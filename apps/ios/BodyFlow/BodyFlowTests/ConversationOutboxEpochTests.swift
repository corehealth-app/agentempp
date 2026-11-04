import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Immutable backend epoch in encrypted conversation outbox")
struct ConversationOutboxEpochTests {
    @Test func coldRestartKeepsOriginalEpochAndExactReplayWhileTwoNewIntentsDiffer() async throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let lifecycle = OutboxLifecycleFake(lease: f.lease)
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: OutboxKeychainFake())
        let first = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: f.store, keyVault: vault)
        let a = try await first.enqueue(source: .text("arroz200g"), server: f.server)
        let b = try await first.enqueue(source: .text("arroz200g"), server: f.server)
        #expect(a != b)
        let sent = try await first.prepareDispatch(commandID: a, server: f.server)
        #expect(sent.originalServerEpoch == f.epoch)
        await first.invalidate()
        let second = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: f.store, keyVault: vault)
        let retry = try await second.reconciliationTicket(commandID: a)
        #expect(retry.originalServerEpoch == sent.originalServerEpoch)
        #expect(retry.wireBody == sent.wireBody && retry.inputHash == sent.inputHash)
        #expect(retry.idempotencyKey == sent.idempotencyKey)
        let rows = try f.store.load(owner: f.owner, key: await vault.key(owner: f.owner, mayCreate: false))
        #expect(rows.map(\.originalServerEpoch) == [f.epoch, f.epoch])
        #expect(rows.allSatisfy { $0.epochProvenance == .backendObservation })
        await second.invalidate()
    }

    @Test func legacyQueuedAndUnknownStayUnboundReadOnlyAndCannotProduceSendTickets() async throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let queued = try ConversationMealCommand(source: .text("old queued"))
        let unknown = try ConversationMealCommand(source: .text("old unknown"))
        try writeLegacy(f, commands: [(queued, .queued, nil), (unknown, .dispatchedUnknown, nil)])
        let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
        let keychain = OutboxKeychainFake()
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: keychain)
        // Seed only this synthetic keychain item with the exact fixture key.
        try await seed(f, keychain: keychain)
        let session = try await ConversationOutboxSession.open(lifecycle: OutboxLifecycleFake(lease: f.lease), store: f.store, keyVault: vault)
        let rows = try f.store.load(owner: f.owner, key: f.key)
        #expect(rows[0].state == .queued && rows[0].hold == .originalEpochUnavailable)
        #expect(rows[1].state == .waitingReconciliation && rows[1].hold == .originalEpochUnavailable)
        #expect(rows.allSatisfy { $0.originalServerEpoch == nil && $0.epochProvenance == .legacyV1Missing })
        #expect(rows.map(\.wireBody) == [queued.wireBody, unknown.wireBody])
        await #expect(throws: ConversationOutboxError.originalEpochUnavailable) { try await session.prepareDispatch(commandID: queued.commandID, server: f.server) }
        await #expect(throws: ConversationOutboxError.originalEpochUnavailable) { try await session.reconciliationTicket(commandID: unknown.commandID) }
        #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
        try await session.discardUnsent(commandID: queued.commandID)
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await session.discardUnsent(commandID: unknown.commandID) }
        let remaining = try f.store.load(owner: f.owner, key: f.key)
        #expect(remaining.count == 1 && remaining[0].commandID == unknown.commandID)
        #expect(remaining[0].originalServerEpoch == nil)
        await session.invalidate()
    }

    @Test func atomicMigrationPreservesLegacyIdentityAndHoldWithoutFillingEpoch() throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let old = try ConversationMealCommand(source: .text("legacy reset"))
        try writeLegacy(f, commands: [(old, .waitingReconciliation, .reset)])
        let new = try ConversationMealCommand(source: .text("new user intent"))
        try f.store.update(owner: f.owner, key: f.key) { $0.append(.init(command: new, originalServerEpoch: f.epoch)) }
        let bytes = try Data(contentsOf: f.store.fileURL(owner: f.owner))
        #expect(bytes.starts(with: Data("PCOBX002".utf8)))
        let rows = try EncryptedConversationOutboxStore(directory: f.directory).load(owner: f.owner, key: f.key)
        #expect(rows.count == 2)
        #expect(rows[0].commandID == old.commandID && rows[0].wireBody == old.wireBody && rows[0].inputHash == old.inputHash)
        #expect(rows[0].hold == .reset && rows[0].originalServerEpoch == nil && rows[0].epochProvenance == .legacyV1Missing)
        #expect(rows[1].originalServerEpoch == f.epoch && rows[1].epochProvenance == .backendObservation)
    }

    @Test func failedMigrationWritePreservesExactV1Ciphertext() throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        try writeLegacy(f, commands: [(try ConversationMealCommand(source: .text("legacy")), .queued, nil)])
        let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: f.store.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.store.root.path) }
        #expect(throws: ConversationOutboxError.storageUnavailable) {
            try f.store.update(owner: f.owner, key: f.key) { $0.append(.init(command: try ConversationMealCommand(source: .text("new")), originalServerEpoch: f.epoch)) }
        }
        #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
    }

    @Test func concurrentMigrateAndAppendNeverLoseLegacyOrNewIntents() async throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let old = try ConversationMealCommand(source: .text("legacy"))
        try writeLegacy(f, commands: [(old, .queued, nil)])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let store = EncryptedConversationOutboxStore(directory: f.directory)
                    try store.update(owner: f.owner, key: f.key) { $0.append(.init(command: try ConversationMealCommand(source: .text("new")), originalServerEpoch: f.epoch)) }
                }
            }
            try await group.waitForAll()
        }
        let rows = try f.store.load(owner: f.owner, key: f.key)
        #expect(rows.count == 9 && Set(rows.map(\.commandID)).count == 9)
        #expect(rows.first?.commandID == old.commandID && rows.first?.originalServerEpoch == nil)
        #expect(rows.dropFirst().allSatisfy { $0.originalServerEpoch == f.epoch })
    }

    @Test func lateObservationMismatchIsReadOnlyAndNeverHoldsAnotherEpoch() async throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let session = try await ConversationOutboxSession.open(lifecycle: OutboxLifecycleFake(lease: f.lease), store: f.store, keyVault: .init(service: "synthetic", security: OutboxKeychainFake()))
        let newer = ConversationOutboxServerObservation(ownerID: f.server.ownerID, localSessionGeneration: f.lease.generation, epoch: UUID())
        let id = try await session.enqueue(source: .text("new epoch intent"), server: newer)
        let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await session.prepareDispatch(commandID: id, server: f.server) }
        #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
        let decision = try await session.decisionTicket(commandID: id)
        #expect(decision.originalServerEpoch == newer.epoch)
        _ = try await session.prepareDispatch(commandID: id, server: newer)
        await session.invalidate()
    }

    @Test func resetDecisionAndBackendHoldsArePermanentAcrossRestartAndReturningEpoch() async throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let lifecycle = OutboxLifecycleFake(lease: f.lease)
        let vault = ConversationOutboxKeyVault(service: "synthetic", security: OutboxKeychainFake())
        let first = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: f.store, keyVault: vault)
        let queued = try await first.enqueue(source: .text("queued"), server: f.server)
        let decision = try await first.decisionTicket(commandID: queued)
        try await first.holdForLocalReset(ticket: decision)
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await first.prepareDispatch(commandID: queued, server: f.server) }
        let id = try await first.enqueue(source: .text("sent"), server: f.server)
        let sent = try await first.prepareDispatch(commandID: id, server: f.server)
        try await first.markWaiting(ticket: sent, hold: .staleEpoch)
        try await first.markWaiting(ticket: sent, hold: .unknownOutcome)
        await first.invalidate()
        let next = try await ConversationOutboxSession.open(lifecycle: lifecycle, store: f.store, keyVault: vault)
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await next.prepareDispatch(commandID: id, server: f.server) }
        let retry = try await next.reconciliationTicket(commandID: id)
        #expect(retry.originalServerEpoch == f.epoch && retry.inputHash == sent.inputHash)
        let key = try await vault.key(owner: f.owner, mayCreate: false)
        #expect(try f.store.load(owner: f.owner, key: key).map(\.hold) == [.reset, .staleEpoch])
        try await next.discardUnsent(commandID: queued) // Explicit known-unsent user choice.
        await next.invalidate()
    }

    @Test func accountOrLeaseMismatchCannotPersistOrPublishEpochBoundWork() async throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let session = try await ConversationOutboxSession.open(lifecycle: OutboxLifecycleFake(lease: f.lease), store: f.store, keyVault: .init(service: "synthetic", security: OutboxKeychainFake()))
        for observation in [ConversationOutboxServerObservation(ownerID: UUID(), localSessionGeneration: f.lease.generation, epoch: f.epoch), ConversationOutboxServerObservation(ownerID: f.server.ownerID, localSessionGeneration: f.lease.generation + 1, epoch: f.epoch)] {
            await #expect(throws: ConversationOutboxError.invalidServerObservation) { try await session.enqueue(source: .text("private"), server: observation) }
        }
        #expect(!(try f.store.containsCiphertext(owner: f.owner)))
        await session.invalidate()
    }

    @Test func retainedEntryCannotRetagEpochClearHoldOrReturnToQueued() throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        let command = try ConversationMealCommand(source: .text("original"))
        try f.store.update(owner: f.owner, key: f.key) { $0.append(.init(command: command, originalServerEpoch: f.epoch)) }
        let original = try Data(contentsOf: f.store.fileURL(owner: f.owner))
        #expect(throws: ConversationOutboxError.integrityFailure) {
            try f.store.update(owner: f.owner, key: f.key) { $0[0] = .init(command: command, originalServerEpoch: UUID()) }
        }
        #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == original)
        try f.store.update(owner: f.owner, key: f.key) { $0[0].state = .waitingReconciliation; $0[0].hold = .reset }
        let held = try Data(contentsOf: f.store.fileURL(owner: f.owner))
        #expect(throws: ConversationOutboxError.integrityFailure) {
            try f.store.update(owner: f.owner, key: f.key) { $0[0].state = .queued; $0[0].hold = nil }
        }
        #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == held)
    }

    @Test func authenticatedV2MissingEpochWithoutLegacyProvenanceAndAADRetagAreRejected() throws {
        let f = try OutboxDiskFixture(); defer { f.remove() }
        try f.store.update(owner: f.owner, key: f.key) { $0.append(.init(command: try ConversationMealCommand(source: .text("new")), originalServerEpoch: f.epoch)) }
        let path = f.store.fileURL(owner: f.owner), original = try Data(contentsOf: path)
        let aad = Data("performe.conversation.outbox\0version=2\0owner=\(f.owner.hash)".utf8)
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: original.dropFirst(8)), using: f.key, authenticating: aad)
        var envelope = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        var entries = try #require(envelope["entries"] as? [[String: Any]])
        entries[0]["originalServerEpoch"] = NSNull(); envelope["entries"] = entries
        let forged = try #require(AES.GCM.seal(JSONSerialization.data(withJSONObject: envelope), using: f.key, authenticating: aad).combined)
        try (Data("PCOBX002".utf8) + forged).write(to: path)
        #expect(throws: ConversationOutboxError.integrityFailure) { try f.store.load(owner: f.owner, key: f.key) }
        try (Data("PCOBX001".utf8) + original.dropFirst(8)).write(to: path)
        #expect(throws: ConversationOutboxError.integrityFailure) { try f.store.load(owner: f.owner, key: f.key) }
    }

    private func writeLegacy(_ f: OutboxDiskFixture, commands: [(ConversationMealCommand, ConversationOutboxState, ConversationOutboxHold?)]) throws {
        _ = try f.store.containsCiphertext(owner: f.owner)
        let rows: [[String: Any]] = commands.map { command, state, hold in
            var row: [String: Any] = ["commandID": command.commandID.uuidString, "wireBody": command.wireBody.base64EncodedString(), "inputHash": command.inputHash, "state": state.rawValue]
            if let hold { row["hold"] = hold.rawValue }
            return row
        }
        let plain = try JSONSerialization.data(withJSONObject: ["version": 1, "owner": f.owner.hash, "entries": rows])
        let aad = Data("performe.conversation.outbox\0version=1\0owner=\(f.owner.hash)".utf8)
        let box = try #require(AES.GCM.seal(plain, using: f.key, authenticating: aad).combined)
        try (Data("PCOBX001".utf8) + box).write(to: f.store.fileURL(owner: f.owner))
    }
    private func seed(_ f: OutboxDiskFixture, keychain: OutboxKeychainFake) async throws {
        let data = f.key.withUnsafeBytes { Data($0) }
        await keychain.seed(data, owner: f.owner.hash)
    }
}
