#if DEBUG
import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Signup photo cleanup queue and protected store")
struct SignupBodyPhotoCleanupQueueStoreTests {
    @Test("invalid civil dates cannot authorize a cleanup scope or replace its stored bytes",
          arguments: ["2026-02-30T11:22:33.123456Z", "2025-02-29T11:22:33Z", "2026-04-31T11:22:33+00:00"])
    func rejectsImpossibleGenerationDates(_ generation: String) throws {
        var queue = CleanupFixtures.empty()
        #expect(throws: SignupBodyPhotoCleanupStoreError.invalidFormat) {
            try queue.observePending(generation, newRevision: CleanupFixtures.id(90))
        }
        #expect(queue.knownScopes.isEmpty)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-date-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SignupBodyPhotoCleanupStore(directory: folder)
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        let invalid = SignupBodyPhotoCleanupQueue(userHash: SignupBodyPhotoCleanupStore.userHash(CleanupFixtures.user),
            knownScopes: [SignupBodyPhotoCleanupKnownScope(generation: generation, revision: CleanupFixtures.id(91),
                operationID: nil, pending: true, repair: nil)])
        let bytes = try JSONEncoder().encode(invalid)
        try bytes.write(to: store.fileURL(for: CleanupFixtures.user))
        #expect(throws: SignupBodyPhotoCleanupStoreError.invalidFormat) {
            try store.mutate(for: CleanupFixtures.user) { current in current.rememberUnbound(CleanupFixtures.id(92)) }
        }
        #expect(try Data(contentsOf: store.fileURL(for: CleanupFixtures.user)) == bytes)
    }

    @Test("Q01 known G survives ACK and repair identity survives JSON/reprepare")
    func generationsAndRepairAttemptAreRetained() throws {
        let inputs = CleanupQueueInputs()
        var queue = CleanupFixtures.empty()
        #expect(try queue.observePending(CleanupFixtures.g1, newRevision: CleanupFixtures.id(1)))
        #expect(try queue.observePending(CleanupFixtures.g2, newRevision: CleanupFixtures.id(2)))
        let first = try #require(queue.scope(CleanupFixtures.g1))
        let other = try #require(queue.scope(CleanupFixtures.g2))
        let ticket = try #require(try queue.prepareRepair(CleanupFixtures.g1,
            expectedRevision: first.revision, newRevision: CleanupFixtures.id(3), operationID: CleanupFixtures.id(4),
            takeKey: { try inputs.takeKey() }, takeDate: { inputs.takeDate() }))
        #expect(ticket.userHash == queue.userHash)
        #expect(ticket.generation == CleanupFixtures.g1)
        #expect(ticket.revision == CleanupFixtures.id(3))
        let attempt = try ticket.mutationAttempt()
        #expect(attempt.operation == .mediaDelete)
        #expect(attempt.key.value == "cleanup-proof-key-1")
        #expect(attempt.payload.generation == CleanupFixtures.g1)
        #expect(attempt.createdAt == CleanupFixtures.date)
        #expect(try queue.acknowledge(ticket, newRevision: CleanupFixtures.id(5)))
        let acked = try #require(queue.scope(CleanupFixtures.g1))
        #expect(!acked.pending)
        #expect(acked.revision == CleanupFixtures.id(5))
        #expect(queue.scope(CleanupFixtures.g2) == other)
        var restored = try JSONDecoder().decode(SignupBodyPhotoCleanupQueue.self,
            from: JSONEncoder().encode(queue))
        #expect(restored == queue)
        let retry = try #require(try restored.prepareRepair(CleanupFixtures.g1,
            expectedRevision: acked.revision, newRevision: CleanupFixtures.id(6), operationID: CleanupFixtures.id(7),
            takeKey: { try inputs.takeKey() }, takeDate: { inputs.takeDate() }))
        #expect(try retry.mutationAttempt() == attempt)
        #expect(restored.scope(CleanupFixtures.g1)?.pending == true)
        #expect(inputs.counts == CleanupQueueInputs.Counts(keys: 1, dates: 1))
    }

    @Test("Q02 every entry mutation advances CAS; old zero/ACK/owner/ABA cannot win")
    func oldResponsesCannotClearPreparedOrRecreatedScope() throws {
        let inputs = CleanupQueueInputs()
        var queue = CleanupFixtures.seeded()
        let observed = try #require(queue.scope(CleanupFixtures.g1))
        let ticket1 = try #require(try queue.prepareRepair(CleanupFixtures.g1,
            expectedRevision: observed.revision, newRevision: CleanupFixtures.id(10), operationID: CleanupFixtures.id(11),
            takeKey: { try inputs.takeKey() }, takeDate: { inputs.takeDate() }))
        #expect(queue.scope(CleanupFixtures.g1)?.revision == CleanupFixtures.id(10))
        let prepared = queue
        let mutationResult1 = queue.resolveNotRequired(CleanupFixtures.g1, expectedRevision: observed.revision)
        #expect(!mutationResult1)
        let stalePrepare = try queue.prepareRepair(CleanupFixtures.g1,
            expectedRevision: observed.revision, newRevision: CleanupFixtures.id(65), operationID: CleanupFixtures.id(66),
            takeKey: { try inputs.takeKey() }, takeDate: { inputs.takeDate() })
        #expect(stalePrepare == nil)
        #expect(queue == prepared)
        #expect(inputs.counts == CleanupQueueInputs.Counts(keys: 1, dates: 1))
        let ticket2 = try #require(try queue.prepareRepair(CleanupFixtures.g1,
            expectedRevision: ticket1.revision, newRevision: CleanupFixtures.id(12), operationID: CleanupFixtures.id(13),
            takeKey: { try inputs.takeKey() }, takeDate: { inputs.takeDate() }))
        #expect(ticket2.revision != ticket1.revision)
        #expect(try ticket2.mutationAttempt() == ticket1.mutationAttempt())
        let current = queue
        #expect(try !queue.acknowledge(ticket1, newRevision: CleanupFixtures.id(14)))
        #expect(queue == current)
        let wrongOwner = SignupBodyPhotoCleanupTicket(userHash: String(repeating: "b", count: 64),
            generation: ticket2.generation, revision: ticket2.revision, operationID: ticket2.operationID, repair: ticket2.repair)
        #expect(try !queue.acknowledge(wrongOwner, newRevision: CleanupFixtures.id(15)))
        #expect(queue == current)
        let wrongOperation = SignupBodyPhotoCleanupTicket(userHash: ticket2.userHash,
            generation: ticket2.generation, revision: ticket2.revision,
            operationID: CleanupFixtures.id(63), repair: ticket2.repair)
        #expect(try !queue.acknowledge(wrongOperation, newRevision: CleanupFixtures.id(64)))
        #expect(queue == current)
        #expect(try queue.acknowledge(ticket2, newRevision: CleanupFixtures.id(16)))
        #expect(queue.scope(CleanupFixtures.g1)?.revision == CleanupFixtures.id(16))
        #expect(queue.scope(CleanupFixtures.g1)?.pending == false)
        let mutationResult2 = queue.resolveNotRequired(CleanupFixtures.g1, expectedRevision: CleanupFixtures.id(16))
        #expect(mutationResult2)
        #expect(try queue.observePending(CleanupFixtures.g1, newRevision: CleanupFixtures.id(17)))
        let recreated = queue
        #expect(try !queue.acknowledge(ticket2, newRevision: CleanupFixtures.id(18)))
        #expect(queue == recreated)
        let mutationResult3 = queue.resolveNotRequired(CleanupFixtures.g1, expectedRevision: CleanupFixtures.id(16))
        #expect(!mutationResult3)
        #expect(queue == recreated)
    }

    @Test("Q03 unbound marker is idempotent and negative proof resolves only its G")
    func zeroProofNeverResolvesUnboundCreate() throws {
        var queue = CleanupFixtures.seeded()
        let g2 = try #require(queue.scope(CleanupFixtures.g2))
        let g1 = try #require(queue.scope(CleanupFixtures.g1))
        let marker = CleanupFixtures.id(20)
        let mutationResult4 = queue.rememberUnbound(marker)
        #expect(mutationResult4)
        let mutationResult5 = queue.rememberUnbound(marker)
        #expect(!mutationResult5)
        #expect(queue.unboundCreates == [marker])
        let mutationResult6 = queue.resolveNotRequired(CleanupFixtures.g1, expectedRevision: g1.revision)
        #expect(mutationResult6)
        #expect(queue.scope(CleanupFixtures.g1) == nil)
        #expect(queue.scope(CleanupFixtures.g2) == g2)
        #expect(queue.unboundCreates == [marker])
        let restored = try JSONDecoder().decode(SignupBodyPhotoCleanupQueue.self,
            from: JSONEncoder().encode(queue))
        #expect(restored.unboundCreates == [marker])
        #expect(restored.scope(CleanupFixtures.g2) == g2)
    }

    @Test("Q04 real-file RMW merges latest siblings; fault before atomic preserves exact bytes")
    func storeNeverWritesAnOldSnapshotOrLosesFileOnWriteFault() throws {
        let directory = CleanupFiles.makeDirectory()
        defer { CleanupFiles.remove(directory) }
        let store = SignupBodyPhotoCleanupStore(directory: directory)
        let ticket = CleanupFixtures.ticket()
        var queue = CleanupFixtures.seeded(prepared: ticket)
        try CleanupFiles.seed(queue, store: store)
        let stale = try store.load(for: CleanupFixtures.user)
        #expect(stale == queue)
        // A second writer/operation adds a sibling after the old read. The
        // tested operation receives only its ticket, not this stale snapshot.
        queue.unboundCreates = [CleanupFixtures.id(30)]
        queue.knownScopes.append(CleanupFixtures.extraScope())
        try CleanupFiles.seed(queue, store: store)
        let acknowledged = try store.mutate(for: CleanupFixtures.user) { current in
            try current.acknowledge(ticket, newRevision: CleanupFixtures.id(31))
        }
        #expect(acknowledged)
        let merged = try CleanupFiles.raw(store)
        #expect(merged.scope(CleanupFixtures.g1)?.pending == false)
        #expect(merged.scope(CleanupFixtures.g1)?.revision == CleanupFixtures.id(31))
        #expect(merged.scope(CleanupFixtures.g2) == queue.scope(CleanupFixtures.g2))
        #expect(merged.scope(CleanupFixtures.g3) == queue.scope(CleanupFixtures.g3))
        #expect(merged.unboundCreates == queue.unboundCreates)
        let before = try Data(contentsOf: store.fileURL(for: CleanupFixtures.user))
        let fault = CleanupWriteFault()
        let failing = SignupBodyPhotoCleanupStore(directory: directory, beforeAtomicWrite: { try fault.trip() })
        #expect(throws: CleanupInjectedError.beforeAtomic) {
            try failing.mutate(for: CleanupFixtures.user) { (current: inout SignupBodyPhotoCleanupQueue) in current.rememberUnbound(CleanupFixtures.id(32)) }
        }
        #expect(fault.calls == 1)
        #expect(try Data(contentsOf: store.fileURL(for: CleanupFixtures.user)) == before)
        #expect(try CleanupFiles.raw(store) == merged)
        let values = try store.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.fileURL(for: CleanupFixtures.user).path)
        if let protection = attrs[.protectionKey] as? FileProtectionType { #expect(protection == .complete) }
        let text = try String(contentsOf: store.fileURL(for: CleanupFixtures.user), encoding: .utf8)
        #expect(!text.contains(CleanupFixtures.user))
    }

    @Test("Q06 owner files are independent and absent is the only empty state")
    func twoOwnersCannotReplaceEachOthersMarkers() throws {
        let directory = CleanupFiles.makeDirectory()
        defer { CleanupFiles.remove(directory) }
        let store = SignupBodyPhotoCleanupStore(directory: directory)
        let other = "00000000-0000-4000-8000-000000cd0202"
        #expect(store.fileURL(for: CleanupFixtures.user) != store.fileURL(for: other))
        #expect(try store.load(for: CleanupFixtures.user).knownScopes.isEmpty)
        #expect(try store.load(for: CleanupFixtures.user).unboundCreates.isEmpty)
        let wroteA = try store.mutate(for: CleanupFixtures.user) { $0.rememberUnbound(CleanupFixtures.id(60)) }
        #expect(wroteA)
        let wroteB = try store.mutate(for: other) { $0.rememberUnbound(CleanupFixtures.id(61)) }
        #expect(wroteB)
        #expect(try store.load(for: CleanupFixtures.user).unboundCreates == [CleanupFixtures.id(60)])
        #expect(try store.load(for: other).unboundCreates == [CleanupFixtures.id(61)])
        try #require(FileManager.default.fileExists(atPath: store.fileURL(for: CleanupFixtures.user).path))
        try #require(FileManager.default.fileExists(atPath: store.fileURL(for: other).path))
        let a = try Data(contentsOf: store.fileURL(for: CleanupFixtures.user))
        let updatedB = try store.mutate(for: other) { $0.rememberUnbound(CleanupFixtures.id(62)) }
        #expect(updatedB)
        #expect(try Data(contentsOf: store.fileURL(for: CleanupFixtures.user)) == a)
        #expect(try store.load(for: other).unboundCreates == [CleanupFixtures.id(61), CleanupFixtures.id(62)])
    }

    @Test("Q05 invalid existing file is an error and exact bytes survive", arguments: CleanupInvalidFile.allCases)
    func invalidExistingFileIsNeverEmptyOrDeleted(_ invalid: CleanupInvalidFile) throws {
        let directory = CleanupFiles.makeDirectory()
        defer { CleanupFiles.remove(directory) }
        let store = SignupBodyPhotoCleanupStore(directory: directory)
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        let bytes: Data
        let expected: SignupBodyPhotoCleanupStoreError
        switch invalid {
        case .malformed:
            bytes = Data("{not valid json".utf8); expected = .invalidFormat
        case .futureVersion:
            var queue = CleanupFixtures.seeded(); queue.version = 99
            bytes = try JSONEncoder().encode(queue); expected = .unsupportedVersion
        case .otherOwner:
            let queue = SignupBodyPhotoCleanupQueue(userHash: String(repeating: "b", count: 64),
                knownScopes: CleanupFixtures.seeded().knownScopes)
            bytes = try JSONEncoder().encode(queue); expected = .ownerMismatch
        case .unknownEnvelopeField, .unknownScopeField, .unknownRepairField:
            let encoded = try JSONEncoder().encode(CleanupFixtures.seeded(prepared: CleanupFixtures.ticket()))
            var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            if invalid == .unknownEnvelopeField { object["futureTechnicalState"] = 1 }
            else {
                var scopes = try #require(object["knownScopes"] as? [[String: Any]])
                if invalid == .unknownScopeField { scopes[0]["futureTechnicalState"] = 1 }
                else {
                    var repair = try #require(scopes[0]["repair"] as? [String: Any])
                    repair["futureTechnicalState"] = 1
                    scopes[0]["repair"] = repair
                }
                object["knownScopes"] = scopes
            }
            bytes = try JSONSerialization.data(withJSONObject: object)
            expected = .invalidFormat
        case .invalidStoredKey:
            var queue = CleanupFixtures.seeded(prepared: CleanupFixtures.ticket())
            queue.knownScopes[0].repair = SignupBodyPhotoCleanupRepairRecord(key: "invalid key", createdAt: CleanupFixtures.date)
            bytes = try JSONEncoder().encode(queue); expected = .invalidFormat
        }
        try bytes.write(to: store.fileURL(for: CleanupFixtures.user), options: .atomic)
        #expect(throws: expected) { try store.load(for: CleanupFixtures.user) }
        #expect(try Data(contentsOf: store.fileURL(for: CleanupFixtures.user)) == bytes)
        let operationInputs = CleanupQueueInputs()
        #expect(throws: expected) {
            try store.mutate(for: CleanupFixtures.user) { (current: inout SignupBodyPhotoCleanupQueue) in
                _ = try operationInputs.takeKey()
                return current.rememberUnbound(CleanupFixtures.id(40))
            }
        }
        #expect(operationInputs.counts == CleanupQueueInputs.Counts(keys: 0, dates: 0))
        #expect(try Data(contentsOf: store.fileURL(for: CleanupFixtures.user)) == bytes)
    }
}

enum CleanupInvalidFile: String, CaseIterable, Sendable {
    case malformed, futureVersion, otherOwner, invalidStoredKey, unknownEnvelopeField, unknownScopeField, unknownRepairField
}
private enum CleanupInjectedError: Error, Equatable { case beforeAtomic }

private final class CleanupQueueInputs: @unchecked Sendable {
    struct Counts: Equatable { let keys: Int; let dates: Int }
    private let lock = NSLock()
    private var keys = 0, dates = 0
    var counts: Counts { lock.withLock { Counts(keys: keys, dates: dates) } }
    func takeKey() throws -> IdempotencyKey {
        let value = lock.withLock { keys += 1; return keys }
        return try IdempotencyKey(validating: "cleanup-proof-key-\(value)")
    }
    func takeDate() -> Date {
        lock.withLock { dates += 1; return CleanupFixtures.date.addingTimeInterval(Double(dates - 1)) }
    }
}
private final class CleanupWriteFault: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func trip() throws {
        lock.withLock { count += 1 }
        throw CleanupInjectedError.beforeAtomic
    }
}

private enum CleanupFixtures {
    static let user = "00000000-0000-4000-8000-000000cd0201"
    static let g1 = "2026-10-12T12:34:56.123456Z"
    static let g2 = "2026-10-12T12:34:57.654321+00:00"
    static let g3 = "2026-10-12T15:35:00.000001+03:00"
    static let date = Date(timeIntervalSince1970: 1_790_000_000.125)
    static func id(_ suffix: Int) -> UUID {
        // Deterministic UUID from bytes; no force unwrap/parse fixture failure.
        UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, UInt8(suffix)))
    }
    static func empty() -> SignupBodyPhotoCleanupQueue {
        SignupBodyPhotoCleanupQueue(userHash: SignupBodyPhotoCleanupStore.userHash(user))
    }
    static func seeded(prepared: SignupBodyPhotoCleanupTicket? = nil) -> SignupBodyPhotoCleanupQueue {
        let first = SignupBodyPhotoCleanupKnownScope(generation: g1,
            revision: prepared?.revision ?? id(50), operationID: prepared?.operationID,
            pending: true, repair: prepared?.repair)
        let second = SignupBodyPhotoCleanupKnownScope(generation: g2,
            revision: id(51), operationID: nil, pending: true, repair: nil)
        return SignupBodyPhotoCleanupQueue(userHash: SignupBodyPhotoCleanupStore.userHash(user), knownScopes: [first, second])
    }
    static func ticket() -> SignupBodyPhotoCleanupTicket {
        SignupBodyPhotoCleanupTicket(userHash: SignupBodyPhotoCleanupStore.userHash(user), generation: g1,
            revision: id(52), operationID: id(53),
            repair: SignupBodyPhotoCleanupRepairRecord(key: "cleanup-proof-key-file", createdAt: date))
    }
    static func extraScope() -> SignupBodyPhotoCleanupKnownScope {
        SignupBodyPhotoCleanupKnownScope(generation: g3, revision: id(54), operationID: nil, pending: true, repair: nil)
    }
}
private enum CleanupFiles {
    static func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("signup-cleanup-queue-r2-\(UUID().uuidString)", isDirectory: true)
    }
    static func remove(_ directory: URL) { try? FileManager.default.removeItem(at: directory) }
    static func seed(_ queue: SignupBodyPhotoCleanupQueue, store: SignupBodyPhotoCleanupStore) throws {
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(queue).write(to: store.fileURL(for: CleanupFixtures.user), options: .atomic)
    }
    static func raw(_ store: SignupBodyPhotoCleanupStore) throws -> SignupBodyPhotoCleanupQueue {
        try JSONDecoder().decode(SignupBodyPhotoCleanupQueue.self,
            from: Data(contentsOf: store.fileURL(for: CleanupFixtures.user)))
    }
}
#endif
