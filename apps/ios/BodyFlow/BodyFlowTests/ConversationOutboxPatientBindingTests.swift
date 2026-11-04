import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Distinct Auth and patient ownership in durable conversation commands")
struct ConversationOutboxPatientBindingTests {
    @Test func distinctAuthenticatedSubjectAndPatientCanPersistAndDispatch() async throws {
        let f = try fixture(); defer { f.disk.remove() }
        let session = try await ConversationOutboxSession.open(lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault, expectedLease: f.lease)
        let id = try await session.enqueue(source: .text("private patient meal"), server: f.server)
        let ticket = try await session.prepareDispatch(commandID: id, server: f.server)
        #expect(ticket.originalPatientOwnerID == f.patient)
        #expect(ticket.ownerHash == f.authOwner.hash)
        let key = try await f.vault.key(owner: f.authOwner, mayCreate: false)
        let rows = try f.disk.store.load(owner: f.authOwner, key: key)
        #expect(rows.first?.originalPatientOwnerID == f.patient)
        #expect(f.server.authUserID != f.server.ownerID)
        let probe = await MainActor.run { PatientOutboxProbe() }
        try await session.publishSnapshot(server: f.server) { probe.snapshot = $0 }
        #expect(await probe.snapshot?.entries.first?.commandID == id)
        #expect(await probe.snapshot?.held.isEmpty == true)
        await session.invalidate()
    }

    @Test func acceptedPatientChangeRevokesOldObservationAndNeverPublishesOldPlaintext() async throws {
        let f = try fixture(); defer { f.disk.remove() }
        let authority = ConversationOutboxObservationAuthority()
        let firstRead = try authority.beginRefresh()
        let a = try authority.accept(refreshID: firstRead, authUserID: f.server.authUserID, ownerID: f.patient, localSessionGeneration: f.lease.generation, epoch: f.server.epoch)
        let session = try await ConversationOutboxSession.open(lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault, expectedLease: f.lease)
        let id = try await session.enqueue(source: .text("PRIVATE PATIENT A"), server: a)
        let ticket = try await session.prepareDispatch(commandID: id, server: a)
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner))
        let nextRead = try authority.beginRefresh()
        let b = try authority.accept(refreshID: nextRead, authUserID: f.server.authUserID, ownerID: UUID(), localSessionGeneration: f.lease.generation, epoch: f.server.epoch)
        let probe = await MainActor.run { PatientOutboxProbe() }
        await #expect(throws: ConversationOutboxError.staleObservation) { try await session.publishSnapshot(server: a) { probe.snapshot = $0 } }
        #expect(await probe.snapshot == nil)
        try await session.publishSnapshot(server: b) { probe.snapshot = $0 }
        let redacted = try #require(await probe.snapshot)
        #expect(redacted.entries.isEmpty)
        #expect(redacted.held.count == 1 && redacted.held[0].commandID == id)
        #expect(!redacted.held[0].canDiscardUnsent)
        await #expect(throws: ConversationOutboxError.invalidServerObservation) { try await session.authorizeResubmission(ticket: ticket, server: b) }
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner)) == original)
        await session.invalidate()
    }

    @Test func lateSessionReadCannotReplaceNewerPatientMapping() throws {
        let f = try fixture(); defer { f.disk.remove() }
        let authority = ConversationOutboxObservationAuthority()
        let old = try authority.beginRefresh(), latest = try authority.beginRefresh()
        _ = try authority.accept(refreshID: latest, authUserID: f.server.authUserID, ownerID: f.patient, localSessionGeneration: f.lease.generation, epoch: f.server.epoch)
        #expect(throws: ConversationOutboxError.staleObservation) {
            try authority.accept(refreshID: old, authUserID: f.server.authUserID, ownerID: UUID(), localSessionGeneration: f.lease.generation, epoch: UUID())
        }
    }

    @Test func v2WithoutPatientBindingRemainsReadOnlyHeldAndNeverAssumesAuthEqualsPatient() async throws {
        let f = try fixture(); defer { f.disk.remove() }
        let command = try ConversationMealCommand(source: .text("OLD PRIVATE BODY"))
        _ = try f.disk.store.containsCiphertext(owner: f.authOwner)
        let row: [String: Any] = ["commandID": command.commandID.uuidString, "wireBody": command.wireBody.base64EncodedString(), "inputHash": command.inputHash, "originalServerEpoch": f.server.epoch.uuidString, "epochProvenance": "backend-observation", "state": "queued", "hold": NSNull()]
        let unknown = try ConversationMealCommand(source: .text("OLD UNKNOWN BODY"))
        var unknownRow = row
        unknownRow["commandID"] = unknown.commandID.uuidString
        unknownRow["wireBody"] = unknown.wireBody.base64EncodedString()
        unknownRow["inputHash"] = unknown.inputHash
        unknownRow["state"] = "dispatched-unknown"
        let plain = try JSONSerialization.data(withJSONObject: ["version": 2, "owner": f.authOwner.hash, "entries": [row, unknownRow]])
        let aad = Data("performe.conversation.outbox\0version=2\0owner=\(f.authOwner.hash)".utf8)
        let box = try #require(AES.GCM.seal(plain, using: f.disk.key, authenticating: aad).combined)
        try (Data("PCOBX002".utf8) + box).write(to: f.disk.store.fileURL(owner: f.authOwner))
        await f.keys.seed(f.disk.key.withUnsafeBytes { Data($0) }, owner: f.authOwner.hash)
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner))
        let session = try await ConversationOutboxSession.open(lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault, expectedLease: f.lease)
        let rows = try f.disk.store.load(owner: f.authOwner, key: f.disk.key)
        #expect(rows[0].originalPatientOwnerID == nil && rows[0].originalServerEpoch == f.server.epoch)
        #expect(rows[0].state == .queued && rows[0].hold == .originalOwnerUnavailable)
        #expect(rows[1].state == .waitingReconciliation && rows[1].hold == .originalOwnerUnavailable)
        #expect(rows[1].wireBody == unknown.wireBody && rows[1].originalPatientOwnerID == nil)
        let probe = await MainActor.run { PatientOutboxProbe() }
        try await session.publishSnapshot(server: f.server) { probe.snapshot = $0 }
        #expect(await probe.snapshot?.entries.isEmpty == true)
        #expect(await probe.snapshot?.held.map(\.canDiscardUnsent) == [true, false])
        await #expect(throws: ConversationOutboxError.originalOwnerUnavailable) { try await session.prepareDispatch(commandID: command.commandID, server: f.server) }
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner)) == original)
        await #expect(throws: ConversationOutboxError.originalOwnerUnavailable) { try await session.reconciliationTicket(commandID: unknown.commandID) }
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await session.discardUnsent(commandID: unknown.commandID) }
        try await session.discardUnsent(commandID: command.commandID)
        let preserved = try f.disk.store.load(owner: f.authOwner, key: f.disk.key)
        #expect(preserved.count == 1 && preserved[0].commandID == unknown.commandID && preserved[0].wireBody == unknown.wireBody)
        await session.invalidate()
    }

    @Test func enqueueOnlyBindingCannotAuthorizeTransportOrRawPublication() async throws {
        let f = try fixture(); defer { f.disk.remove() }
        let authority = ConversationOutboxObservationAuthority(), refresh = try authority.beginRefresh()
        let captured = try authority.accept(refreshID: refresh, authUserID: f.server.authUserID, ownerID: f.patient,
            localSessionGeneration: f.lease.generation, epoch: f.server.epoch, enqueueOnly: true)
        let session = try await ConversationOutboxSession.open(lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault, expectedLease: f.lease)
        let id = try await session.enqueue(source: .text("offline source"), server: captured)
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner))
        await #expect(throws: ConversationOutboxError.invalidServerObservation) { try await session.prepareDispatch(commandID: id, server: captured) }
        let probe = await MainActor.run { PatientOutboxProbe() }
        await #expect(throws: ConversationOutboxError.invalidServerObservation) { try await session.publishSnapshot(server: captured) { probe.snapshot = $0 } }
        #expect(await probe.snapshot == nil)
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner)) == original)
        await session.invalidate()
    }

    @Test func immutablePatientCannotBeRetaggedEvenWhenOriginalEpochMatches() throws {
        let f = try fixture(); defer { f.disk.remove() }
        let command = try ConversationMealCommand(source: .text("original patient source"))
        try f.disk.store.update(owner: f.authOwner, key: f.disk.key) { $0.append(.init(command: command, originalServerEpoch: f.server.epoch, originalPatientOwnerID: f.patient)) }
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner))
        #expect(throws: ConversationOutboxError.integrityFailure) {
            try f.disk.store.update(owner: f.authOwner, key: f.disk.key) { $0[0] = .init(command: command, originalServerEpoch: f.server.epoch, originalPatientOwnerID: UUID()) }
        }
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.authOwner)) == original)
    }

    private struct Fixture {
        let disk: OutboxDiskFixture
        let lease: SessionLease
        let patient: UUID
        let authOwner: ConversationOutboxOwner
        let lifecycle: OutboxLifecycleFake
        let keys: OutboxKeychainFake
        let vault: ConversationOutboxKeyVault
        let server: ConversationOutboxServerObservation
    }
    private func fixture() throws -> Fixture {
        let disk = try OutboxDiskFixture()
        let lease = SessionLease(userID: "90000000-0000-4000-8000-000000000001", generation: 7, bearer: "synthetic-auth-only")
        let patient = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let keys = OutboxKeychainFake()
        return .init(disk: disk, lease: lease, patient: patient, authOwner: try ConversationOutboxOwner(lease: lease), lifecycle: OutboxLifecycleFake(lease: lease), keys: keys, vault: .init(service: "synthetic", security: keys), server: .init(authUserID: UUID(uuidString: lease.userID)!, ownerID: patient, localSessionGeneration: lease.generation, epoch: disk.epoch))
    }
}

@MainActor private final class PatientOutboxProbe { var snapshot: ConversationOutboxViewSnapshot? }
