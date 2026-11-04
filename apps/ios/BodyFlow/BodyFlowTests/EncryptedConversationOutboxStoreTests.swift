import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Encrypted conversation outbox disk state")
struct EncryptedConversationOutboxStoreTests {
    @Test func restartRetainsExactBodyHashAndUnknownStateWithoutPlaintext() throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        let command = try ConversationMealCommand(source: .text("PRIVATE MEAL arroz 😀 e\u{301}"))
        try fixture.store.update(owner: fixture.owner, key: fixture.key) { $0.append(.init(command: command, originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID)) }
        try fixture.store.update(owner: fixture.owner, key: fixture.key) { $0[0].state = .dispatchedUnknown }
        let reopened = EncryptedConversationOutboxStore(directory: fixture.directory)
        let entries = try reopened.load(owner: fixture.owner, key: fixture.key)
        #expect(entries.count == 1)
        #expect(entries[0].commandID == command.commandID)
        #expect(entries[0].wireBody == command.wireBody)
        #expect(entries[0].inputHash == command.inputHash)
        #expect(entries[0].state == .dispatchedUnknown)
        let files = try FileManager.default.contentsOfDirectory(at: fixture.store.root, includingPropertiesForKeys: nil)
        for file in files {
            let data = try Data(contentsOf: file)
            #expect(data.range(of: Data("PRIVATE MEAL".utf8)) == nil)
            #expect(data.range(of: Data(fixture.lease.userID.utf8)) == nil)
            #expect(!file.lastPathComponent.contains(fixture.lease.userID))
        }
    }

    @Test func wrongKeyAccountAndTamperingFailClosedAndPreserveCiphertext() throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        try fixture.store.update(owner: fixture.owner, key: fixture.key) {
            $0.append(.init(command: try ConversationMealCommand(source: .text("private")), originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID))
        }
        let path = fixture.store.fileURL(owner: fixture.owner)
        let original = try Data(contentsOf: path)
        #expect(throws: ConversationOutboxError.integrityFailure) {
            try fixture.store.load(owner: fixture.owner, key: SymmetricKey(size: .bits256))
        }
        let other = try ConversationOutboxOwner(lease: SessionLease(userID: "00000000-0000-0000-0000-000000000002", generation: 0, bearer: "synthetic"))
        try original.write(to: fixture.store.fileURL(owner: other))
        #expect(throws: ConversationOutboxError.integrityFailure) {
            try fixture.store.load(owner: other, key: fixture.key) // Even the same key cannot cross AAD owners.
        }
        var changed = original; changed[changed.count - 1] ^= 1; try changed.write(to: path)
        #expect(throws: ConversationOutboxError.integrityFailure) { try fixture.store.load(owner: fixture.owner, key: fixture.key) }
        #expect(try Data(contentsOf: path) == changed)
    }

    @Test func realAtomicWriteFailureLeavesPreviousQueueByteIdentical() throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        try fixture.store.update(owner: fixture.owner, key: fixture.key) {
            $0.append(.init(command: try ConversationMealCommand(source: .text("first")), originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID))
        }
        let original = try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.store.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.store.root.path) }
        #expect(throws: ConversationOutboxError.storageUnavailable) {
            try fixture.store.update(owner: fixture.owner, key: fixture.key) {
                $0.append(.init(command: try ConversationMealCommand(source: .text("second")), originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID))
            }
        }
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner)) == original)
        // Restore the injected fault before exercising normal store access;
        // iOS also applies complete-protection metadata at that boundary.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.store.root.path)
        #expect(try fixture.store.load(owner: fixture.owner, key: fixture.key).count == 1)
    }

    @Test func capacityDoesNotEvictOrPartiallyWrite() throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        try fixture.store.update(owner: fixture.owner, key: fixture.key) { entries in
            for _ in 0..<EncryptedConversationOutboxStore.capacity {
                entries.append(.init(command: try ConversationMealCommand(source: .text("same body")), originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID))
            }
        }
        let original = try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner))
        #expect(throws: ConversationOutboxError.queueFull) {
            try fixture.store.update(owner: fixture.owner, key: fixture.key) {
                $0.append(.init(command: try ConversationMealCommand(source: .text("overflow")), originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID))
            }
        }
        #expect(try Data(contentsOf: fixture.store.fileURL(owner: fixture.owner)) == original)
    }

    @Test func separateConcurrentStoresDoNotLoseIntents() async throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let store = EncryptedConversationOutboxStore(directory: fixture.directory)
                    try store.update(owner: fixture.owner, key: fixture.key) {
                        $0.append(.init(command: try ConversationMealCommand(source: .text("independent intent")), originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID))
                    }
                }
            }
            try await group.waitForAll()
        }
        let entries = try fixture.store.load(owner: fixture.owner, key: fixture.key)
        #expect(entries.count == 20)
        #expect(Set(entries.map(\.commandID)).count == 20)
    }

    @Test func authenticatedButInconsistentFrozenHashIsRejected() throws {
        let fixture = try OutboxDiskFixture(); defer { fixture.remove() }
        try fixture.store.update(owner: fixture.owner, key: fixture.key) {
            $0.append(.init(command: try ConversationMealCommand(source: .text("original source")), originalServerEpoch: fixture.epoch, originalPatientOwnerID: fixture.server.ownerID))
        }
        let path = fixture.store.fileURL(owner: fixture.owner)
        let sealed = try Data(contentsOf: path)
        let aad = Data("performe.conversation.outbox\0version=3\0owner=\(fixture.owner.hash)".utf8)
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed.dropFirst(8)), using: fixture.key, authenticating: aad)
        var envelope = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        var entries = try #require(envelope["entries"] as? [[String: Any]])
        entries[0]["inputHash"] = String(repeating: "0", count: 64); envelope["entries"] = entries
        let changed = try JSONSerialization.data(withJSONObject: envelope)
        let forged = try #require(AES.GCM.seal(changed, using: fixture.key, authenticating: aad).combined)
        try (Data("PCOBX003".utf8) + forged).write(to: path)
        #expect(throws: ConversationOutboxError.integrityFailure) { try fixture.store.load(owner: fixture.owner, key: fixture.key) }
    }
}

struct OutboxDiskFixture {
    let directory: URL
    let store: EncryptedConversationOutboxStore
    let key = SymmetricKey(size: .bits256)
    let lease = SessionLease(userID: "00000000-0000-0000-0000-000000000001", generation: 7, bearer: "synthetic-not-persisted")
    let owner: ConversationOutboxOwner
    let epoch = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    var server: ConversationOutboxServerObservation {
        ConversationOutboxServerObservation(authUserID: UUID(uuidString: lease.userID)!, ownerID: UUID(uuidString: lease.userID)!, localSessionGeneration: lease.generation, epoch: epoch)
    }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-test-\(UUID())", isDirectory: true)
        store = EncryptedConversationOutboxStore(directory: directory)
        owner = try ConversationOutboxOwner(lease: lease)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
