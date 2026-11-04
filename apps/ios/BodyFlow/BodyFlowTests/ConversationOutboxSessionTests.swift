import Foundation
import Testing
@testable import BodyFlow

@Suite("Conversation outbox authenticated lifecycle")
struct ConversationOutboxSessionTests {
    @Test func newIntentGetsNewIDButRestartReconciliationReusesExactIdentity() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let lifecycle = OutboxLifecycleFake(lease: fixture.lease)
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: OutboxKeychainFake())
        let first = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        let a = try await first.enqueue(source: .text("same body"), server: fixture.server)
        let b = try await first.enqueue(source: .text("same body"), server: fixture.server)
        #expect(a != b)
        let ticket = try await first.prepareDispatch(commandID: a, server: fixture.server)
        await first.invalidate()
        let reopened = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        let retry = try await reopened.reconciliationTicket(commandID: a)
        #expect(retry.commandID == ticket.commandID)
        #expect(retry.inputHash == ticket.inputHash)
        #expect(retry.wireBody == ticket.wireBody)
        #expect(retry.idempotencyKey == "cmsg1:\(a.uuidString.lowercased())")
        #expect(try await snapshot(reopened, server: fixture.server).map(\.commandID) == [a, b])
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await reopened.prepareDispatch(commandID: a, server: fixture.server) }
        await #expect(throws: ConversationOutboxError.invalidTransition) { try await reopened.markWaiting(ticket: ticket, hold: .unknownOutcome) }
        await reopened.invalidate()
    }

    @Test func persistBeforeFlightAndUnknownCannotBeDiscardedOrRetagged() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let lifecycle = OutboxLifecycleFake(lease: fixture.lease)
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: OutboxKeychainFake())
        let session = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        let id = try await session.enqueue(source: .text("meal"), server: fixture.server)
        let ticket = try await session.prepareDispatch(commandID: id, server: fixture.server)
        // A second instance sees unknown before any transport could consume the ticket.
        let diskReader = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        #expect(try await snapshot(diskReader, server: fixture.server).first?.state == .dispatchedUnknown)
        try await session.markWaiting(ticket: ticket, hold: .staleEpoch)
        try await session.markWaiting(ticket: ticket, hold: .unknownOutcome)
        #expect(try await snapshot(session, server: fixture.server).first?.hold == .staleEpoch)
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await session.discardUnsent(commandID: id) }
        #expect(try await session.reconciliationTicket(commandID: id).wireBody == ticket.wireBody)
        await session.invalidate(); await diskReader.invalidate()
    }

    @Test func failedDispatchPersistenceReturnsNoTicketAndLeavesQueued() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let session = try await ConversationOutboxSession.open(lifecycle: OutboxLifecycleFake(lease: fixture.lease), store: fixture.store, keyVault: .init(service: "synthetic", security: OutboxKeychainFake()))
        let id = try await session.enqueue(source: .text("meal"), server: fixture.server)
        let original = try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.store.root.path)
        await #expect(throws: ConversationOutboxError.storageUnavailable) { try await session.prepareDispatch(commandID: id, server: fixture.server) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.store.root.path)
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner)) == original)
        #expect(try await snapshot(session, server: fixture.server).first?.state == .queued)
        await session.invalidate()
    }

    @Test func onlyNeverDispatchedIntentCanBeDiscarded() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let session = try await ConversationOutboxSession.open(lifecycle: OutboxLifecycleFake(lease: fixture.lease), store: fixture.store, keyVault: .init(service: "synthetic", security: OutboxKeychainFake()))
        let id = try await session.enqueue(source: .text("meal"), server: fixture.server)
        try await session.discardUnsent(commandID: id)
        #expect(try await snapshot(session, server: fixture.server).isEmpty)
        await session.invalidate()
        #expect(try fixture.store.containsCiphertext(owner: fixture.owner)) // Logout is not delete-account.
    }

    @Test func accountSwapBlocksLateCallbackPublicationAndLeavesOwnerCiphertext() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let lifecycle = OutboxLifecycleFake(lease: fixture.lease)
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: OutboxKeychainFake())
        let old = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        let id = try await old.enqueue(source: .text("private A"), server: fixture.server)
        let ticket = try await old.prepareDispatch(commandID: id, server: fixture.server)
        let original = try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner))
        await lifecycle.replace(lease: .init(userID: "00000000-0000-0000-0000-000000000002", generation: 8, bearer: "synthetic-B"))
        await #expect(throws: (any Error).self) { try await old.markWaiting(ticket: ticket, hold: .unknownOutcome) }
        let probe = await MainActor.run { OutboxSnapshotProbe() }
        await #expect(throws: (any Error).self) { try await old.publishSnapshot(server: fixture.server) { probe.entries = $0.entries } }
        #expect(await probe.entries == nil)
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner)) == original)
        let other = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        #expect(try await snapshot(other, server: .init(authUserID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, ownerID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, localSessionGeneration: 8, epoch: fixture.epoch)).isEmpty)
        await old.invalidate(); await other.invalidate()
        await lifecycle.replace(lease: .init(userID: fixture.lease.userID, generation: 9, bearer: "synthetic-A-again"))
        let restored = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: vault)
        #expect(try await restored.reconciliationTicket(commandID: id).wireBody == ticket.wireBody)
        await restored.invalidate()
    }

    @Test func existingCiphertextWithLostKeyFailsWithoutReplacingOrDropping() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let lifecycle = OutboxLifecycleFake(lease: fixture.lease)
        let first = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: .init(service: "synthetic", security: OutboxKeychainFake()))
        _ = try await first.enqueue(source: .text("preserve me"), server: fixture.server); await first.invalidate()
        let original = try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner))
        let emptyKeys = OutboxKeychainFake()
        await #expect(throws: ConversationOutboxError.keyUnavailable) {
            try await ConversationOutboxSession.open(lifecycle: lifecycle, store: fixture.store, keyVault: .init(service: "synthetic", security: emptyKeys))
        }
        #expect(await emptyKeys.addCount == 0)
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner)) == original)
    }

    private func snapshot(_ session: ConversationOutboxSession, server: ConversationOutboxServerObservation) async throws -> [ConversationOutboxEntry] {
        let probe = await MainActor.run { OutboxSnapshotProbe() }
        try await session.publishSnapshot(server: server) { probe.entries = $0.entries }
        return try #require(await probe.entries)
    }
}

@MainActor final class OutboxSnapshotProbe { var entries: [ConversationOutboxEntry]? }

actor OutboxLifecycleFake: SessionLifecycleProviding {
    private var lease: SessionLease
    private var work: [UUID: @Sendable () -> Void] = [:]
    private var nextVisibleLease: SessionLease?
    init(lease: SessionLease) { self.lease = lease }
    func replace(lease: SessionLease) {
        self.lease = lease
        let callbacks = work.values; work.removeAll(); for callback in callbacks { callback() }
    }
    func replaceBeforeNextVisible(lease: SessionLease) { nextVisibleLease = lease }
    func currentBearerToken() -> String? { lease.bearer }
    func leaseForRequest() -> SessionLease { lease }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease { try validate(lease); return self.lease }
    func validate(_ candidate: SessionLease) throws {
        guard lease.userID == candidate.userID, lease.generation == candidate.generation else { throw SessionLifecycleError.sessionSuperseded }
    }
    func signOut() -> RemoteRevocationOutcome { .confirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) throws -> UUID {
        try validate(lease); let id = UUID(); work[id] = cancel; return id
    }
    func finishPatientWork(_ id: UUID) { work.removeValue(forKey: id) }
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease, operation: @Sendable () throws -> Value) throws -> Value {
        try validate(lease); return try operation()
    }
    func performVisiblePatientStateOperation<Value: Sendable>(lease: SessionLease, operation: @MainActor @Sendable () throws -> Value) async throws -> Value {
        if let next = nextVisibleLease { nextVisibleLease = nil; replace(lease: next) }
        try validate(lease)
        return try await MainActor.run(body: operation)
    }
}
