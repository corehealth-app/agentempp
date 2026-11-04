import CryptoKit
import Darwin
import Foundation

/// Constructed from an authenticated lease, never from composer text. The
/// stable hash deliberately excludes bearer and local session generation so
/// the same account can recover its ciphertext after logout or process death.
struct ConversationOutboxOwner: Sendable {
    let hash: String
    init(lease: SessionLease) throws {
        guard let id = UUID(uuidString: lease.userID) else { throw ConversationOutboxError.invalidOwner }
        hash = ConversationMealCommand.digest(Data("performe.conversation.outbox.v1\0\(id.uuidString.lowercased())".utf8))
    }
}

enum ConversationOutboxState: String, Codable, Sendable {
    case queued
    case dispatchedUnknown = "dispatched-unknown"
    case waitingReconciliation = "waiting-reconciliation"
}

enum ConversationOutboxHold: String, Codable, Sendable {
    case unknownOutcome, userCancelled, originalEpochUnavailable, staleEpoch, reset

    var priority: Int {
        switch self { case .unknownOutcome: 0; case .userCancelled: 1; case .originalEpochUnavailable: 2; case .staleEpoch: 3; case .reset: 4 }
    }
}

struct ConversationOutboxEntry: Codable, Sendable, CustomStringConvertible, CustomReflectable {
    enum EpochProvenance: String, Codable, Sendable {
        case backendObservation = "backend-observation"
        case legacyV1Missing = "legacy-v1-missing"
    }
    let commandID: UUID
    let wireBody: Data
    let inputHash: String
    let originalServerEpoch: UUID?
    let epochProvenance: EpochProvenance
    var state: ConversationOutboxState
    var hold: ConversationOutboxHold?

    init(command: ConversationMealCommand, originalServerEpoch: UUID) {
        commandID = command.commandID; wireBody = command.wireBody; inputHash = command.inputHash
        self.originalServerEpoch = originalServerEpoch; epochProvenance = .backendObservation
        state = .queued; hold = nil
    }

    fileprivate init(legacy command: ConversationMealCommand, state: ConversationOutboxState, hold: ConversationOutboxHold?) {
        commandID = command.commandID; wireBody = command.wireBody; inputHash = command.inputHash
        originalServerEpoch = nil; epochProvenance = .legacyV1Missing
        // Preserve the proof of never-dispatched work; unknown work stays
        // undiscardable, even though no usable dispatch ticket can be issued.
        self.state = state == .queued ? .queued : .waitingReconciliation
        self.hold = hold ?? .originalEpochUnavailable
    }

    private enum CodingKeys: String, CodingKey {
        case commandID, wireBody, inputHash, originalServerEpoch, epochProvenance, state, hold
    }
    init(from decoder: any Decoder) throws {
        try outboxKeys(decoder, required: ["commandID", "wireBody", "inputHash", "originalServerEpoch", "epochProvenance", "state", "hold"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commandID = try c.decode(UUID.self, forKey: .commandID)
        wireBody = try c.decode(Data.self, forKey: .wireBody)
        inputHash = try c.decode(String.self, forKey: .inputHash)
        originalServerEpoch = try c.decodeIfPresent(UUID.self, forKey: .originalServerEpoch)
        epochProvenance = try c.decode(EpochProvenance.self, forKey: .epochProvenance)
        state = try c.decode(ConversationOutboxState.self, forKey: .state)
        hold = try c.decodeIfPresent(ConversationOutboxHold.self, forKey: .hold)
        try validate()
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(commandID, forKey: .commandID); try c.encode(wireBody, forKey: .wireBody)
        try c.encode(inputHash, forKey: .inputHash); try c.encode(originalServerEpoch, forKey: .originalServerEpoch)
        try c.encode(epochProvenance, forKey: .epochProvenance); try c.encode(state, forKey: .state)
        try c.encode(hold, forKey: .hold)
    }
    func validate() throws {
        let command = try ConversationMealCommand(wireBody: wireBody)
        guard command.commandID == commandID, command.wireBody == wireBody, command.inputHash == inputHash else {
            throw ConversationOutboxError.integrityFailure
        }
        switch epochProvenance {
        case .legacyV1Missing:
            guard originalServerEpoch == nil, hold != nil, state != .dispatchedUnknown else { throw ConversationOutboxError.integrityFailure }
        case .backendObservation:
            guard originalServerEpoch != nil, hold != .originalEpochUnavailable else { throw ConversationOutboxError.integrityFailure }
            switch state {
            case .queued:
                guard hold == nil || hold == .reset else { throw ConversationOutboxError.integrityFailure }
            case .dispatchedUnknown:
                guard hold == nil else { throw ConversationOutboxError.integrityFailure }
            case .waitingReconciliation:
                guard hold != nil else { throw ConversationOutboxError.integrityFailure }
            }
        }
    }

    var description: String { "ConversationOutboxEntry(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

/// A synchronous disk transaction is called only inside the lifecycle's
/// patient-state gate. flock also excludes another store instance/process.
/// Ciphertext is retained on corruption, missing key, account change or logout.
struct EncryptedConversationOutboxStore: Sendable {
    // Existing Flow history/accepted-cache horizon is 50. Backpressure never
    // silently evicts a command whose server outcome may still be unknown.
    static let capacity = 50
    private static let maxBytes = capacity * 24_576 + 4_096
    private static let header = Data("PCOBX002".utf8)
    private static let legacyHeader = Data("PCOBX001".utf8)
    private static let directoryCreationLock = NSLock()
    let root: URL

    init(directory: URL) {
        root = directory.appendingPathComponent("performe-conversation-outbox-v1", isDirectory: true)
    }

    static var device: Self { Self(directory: .applicationSupportDirectory) }

    func fileURL(owner: ConversationOutboxOwner) -> URL {
        root.appendingPathComponent(owner.hash + ".sealed", isDirectory: false)
    }

    func containsCiphertext(owner: ConversationOutboxOwner) throws -> Bool {
        try locked { try readCiphertext(owner: owner) != nil }
    }

    func load(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> [ConversationOutboxEntry] {
        try locked { try read(owner: owner, key: key) }
    }

    @discardableResult
    func update<Value: Sendable>(
        owner: ConversationOutboxOwner, key: SymmetricKey,
        _ mutation: (inout [ConversationOutboxEntry]) throws -> Value
    ) throws -> Value {
        try locked {
            var entries = try read(owner: owner, key: key)
            let original = entries
            let result = try mutation(&entries)
            guard entries.count <= Self.capacity else { throw ConversationOutboxError.queueFull }
            try Self.validate(entries)
            try Self.validateTransitions(from: original, to: entries)
            let plain = try JSONEncoder().encode(Envelope(version: 2, owner: owner.hash, entries: entries))
            guard plain.count <= Self.maxBytes else { throw ConversationOutboxError.queueFull }
            let box = try AES.GCM.seal(plain, using: key, authenticating: aad(owner, version: 2))
            guard let combined = box.combined else { throw ConversationOutboxError.storageUnavailable }
            try atomicReplace(Self.header + combined, at: fileURL(owner: owner))
            return result
        }
    }

    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let entries: [ConversationOutboxEntry]
        private enum CodingKeys: String, CodingKey { case version, owner, entries }
        init(version: Int, owner: String, entries: [ConversationOutboxEntry]) {
            self.version = version; self.owner = owner; self.entries = entries
        }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner", "entries"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            entries = try c.decode([ConversationOutboxEntry].self, forKey: .entries)
        }
    }
    private struct LegacyEnvelope: Decodable {
        let version: Int
        let owner: String
        let entries: [LegacyEntry]
        private enum CodingKeys: String, CodingKey { case version, owner, entries }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["version", "owner", "entries"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version); owner = try c.decode(String.self, forKey: .owner)
            entries = try c.decode([LegacyEntry].self, forKey: .entries)
        }
    }
    private struct LegacyEntry: Decodable {
        let value: ConversationOutboxEntry
        private enum CodingKeys: String, CodingKey { case commandID, wireBody, inputHash, state, hold }
        init(from decoder: any Decoder) throws {
            try outboxKeys(decoder, required: ["commandID", "wireBody", "inputHash", "state"], optional: ["hold"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decode(UUID.self, forKey: .commandID), wire = try c.decode(Data.self, forKey: .wireBody)
            let hash = try c.decode(String.self, forKey: .inputHash), state = try c.decode(ConversationOutboxState.self, forKey: .state)
            let hold = try c.decodeIfPresent(ConversationOutboxHold.self, forKey: .hold)
            let command = try ConversationMealCommand(wireBody: wire)
            guard command.commandID == id, command.wireBody == wire, command.inputHash == hash,
                  hold != .originalEpochUnavailable,
                  ((state == .waitingReconciliation) ? hold != nil : hold == nil) else { throw ConversationOutboxError.integrityFailure }
            value = ConversationOutboxEntry(legacy: command, state: state, hold: hold)
        }
    }
    private func aad(_ owner: ConversationOutboxOwner, version: Int) -> Data {
        Data("performe.conversation.outbox\0version=\(version)\0owner=\(owner.hash)".utf8)
    }

    private func read(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> [ConversationOutboxEntry] {
        guard let data = try readCiphertext(owner: owner) else { return [] }
        do {
            let version: Int
            if data.starts(with: Self.header) { version = 2 }
            else if data.starts(with: Self.legacyHeader) { version = 1 }
            else { throw ConversationOutboxError.integrityFailure }
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.header.count))
            let plain = try AES.GCM.open(box, using: key, authenticating: aad(owner, version: version))
            let entries: [ConversationOutboxEntry]
            if version == 1 {
                let envelope = try JSONDecoder().decode(LegacyEnvelope.self, from: plain)
                guard envelope.version == 1, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
                entries = envelope.entries.map(\.value)
            } else {
                let envelope = try JSONDecoder().decode(Envelope.self, from: plain)
                guard envelope.version == 2, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
                entries = envelope.entries
            }
            try Self.validate(entries)
            return entries
        } catch { throw ConversationOutboxError.integrityFailure }
    }

    private static func validateTransitions(from original: [ConversationOutboxEntry], to entries: [ConversationOutboxEntry]) throws {
        for old in original {
            guard let new = entries.first(where: { $0.commandID == old.commandID }) else { continue }
            guard old.wireBody == new.wireBody, old.inputHash == new.inputHash,
                  old.originalServerEpoch == new.originalServerEpoch, old.epochProvenance == new.epochProvenance else {
                // Hold monotonicity is checked explicitly below; identities can
                // never be rebound, including nil legacy epoch becoming current.
                throw ConversationOutboxError.integrityFailure
            }
            if let hold = old.hold {
                guard let next = new.hold, next.priority >= hold.priority else { throw ConversationOutboxError.integrityFailure }
            }
            if old.state != .queued {
                guard new.state != .queued else { throw ConversationOutboxError.integrityFailure }
            }
            if old.state == .waitingReconciliation {
                guard new.state == .waitingReconciliation else { throw ConversationOutboxError.integrityFailure }
            }
        }
    }

    private static func validate(_ entries: [ConversationOutboxEntry]) throws {
        guard entries.count <= capacity, Set(entries.map(\.commandID)).count == entries.count else {
            throw ConversationOutboxError.integrityFailure
        }
        for entry in entries { try entry.validate() }
    }

    private func prepareDirectory() throws {
        // The initial directory must already be private when it becomes
        // visible to another instance. Metadata configuration follows under
        // the process-shared file lock, rather than racing before that lock.
        try Self.directoryCreationLock.withLock {
            try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard mkdir(root.path, 0o700) == 0 || errno == EEXIST else { throw ConversationOutboxError.storageUnavailable }
        }
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw ConversationOutboxError.storageUnavailable }
    }

    private func configureDirectory() throws {
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var directory = root; try directory.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        #endif
    }

    private func locked<Value>(operation: () throws -> Value) throws -> Value {
        do {
            try prepareDirectory()
            // One empty store lock also serializes protection/backup metadata
            // across accounts and processes. Command files remain per account.
            let path = root.appendingPathComponent(".store.lock").path
            let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw ConversationOutboxError.storageUnavailable }
            defer { close(descriptor) }
            while flock(descriptor, LOCK_EX) != 0 {
                guard errno == EINTR else { throw ConversationOutboxError.storageUnavailable }
            }
            defer { flock(descriptor, LOCK_UN) }
            try configureDirectory()
            return try operation()
        } catch let error as ConversationOutboxError { throw error }
        catch { throw ConversationOutboxError.storageUnavailable }
    }

    private func readCiphertext(owner: ConversationOutboxOwner) throws -> Data? {
        let descriptor = open(fileURL(owner: owner).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw ConversationOutboxError.storageUnavailable
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= Self.maxBytes + 128 else {
            throw ConversationOutboxError.integrityFailure
        }
        var data = Data(count: Int(info.st_size))
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ConversationOutboxError.storageUnavailable }
                offset += count
            }
        }
        return data
    }

    /// Only ciphertext touches the temporary file. No throwing operation is
    /// performed after rename, so a reported failure preserves the old queue.
    private func atomicReplace(_ ciphertext: Data, at destination: URL) throws {
        let temporary = root.appendingPathComponent(".\(UUID().uuidString).sealed-tmp")
        let descriptor = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ConversationOutboxError.storageUnavailable }
        defer { close(descriptor); unlink(temporary.path) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path)
        #endif
        try ciphertext.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ConversationOutboxError.storageUnavailable }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, destination.path) == 0 else {
            throw ConversationOutboxError.storageUnavailable
        }
    }
}

private struct OutboxStorageKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func outboxKeys(_ decoder: any Decoder, required: Set<String>, optional: Set<String> = []) throws {
    let keys = Set(try decoder.container(keyedBy: OutboxStorageKey.self).allKeys.map(\.stringValue))
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw ConversationOutboxError.integrityFailure }
}
