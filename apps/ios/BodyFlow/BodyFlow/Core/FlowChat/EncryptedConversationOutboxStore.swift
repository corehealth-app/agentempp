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
    case unknownOutcome, userCancelled, staleEpoch, reset

    var priority: Int {
        switch self { case .unknownOutcome: 0; case .userCancelled: 1; case .staleEpoch: 2; case .reset: 3 }
    }
}

struct ConversationOutboxEntry: Codable, Sendable, CustomStringConvertible, CustomReflectable {
    let commandID: UUID
    let wireBody: Data
    let inputHash: String
    var state: ConversationOutboxState
    var hold: ConversationOutboxHold?

    init(command: ConversationMealCommand) {
        commandID = command.commandID; wireBody = command.wireBody; inputHash = command.inputHash
        state = .queued; hold = nil
    }

    func validate() throws {
        let command = try ConversationMealCommand(wireBody: wireBody)
        guard command.commandID == commandID, command.wireBody == wireBody, command.inputHash == inputHash,
              (state == .queued || state == .dispatchedUnknown) ? hold == nil : hold != nil
        else { throw ConversationOutboxError.integrityFailure }
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
    private static let header = Data("PCOBX001".utf8)
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
            let result = try mutation(&entries)
            guard entries.count <= Self.capacity else { throw ConversationOutboxError.queueFull }
            try Self.validate(entries)
            let plain = try JSONEncoder().encode(Envelope(version: 1, owner: owner.hash, entries: entries))
            guard plain.count <= Self.maxBytes else { throw ConversationOutboxError.queueFull }
            let box = try AES.GCM.seal(plain, using: key, authenticating: aad(owner))
            guard let combined = box.combined else { throw ConversationOutboxError.storageUnavailable }
            try atomicReplace(Self.header + combined, at: fileURL(owner: owner))
            return result
        }
    }

    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let entries: [ConversationOutboxEntry]
    }

    private func aad(_ owner: ConversationOutboxOwner) -> Data {
        Data("performe.conversation.outbox\0version=1\0owner=\(owner.hash)".utf8)
    }

    private func read(owner: ConversationOutboxOwner, key: SymmetricKey) throws -> [ConversationOutboxEntry] {
        guard let data = try readCiphertext(owner: owner) else { return [] }
        do {
            guard data.starts(with: Self.header) else { throw ConversationOutboxError.integrityFailure }
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.header.count))
            let plain = try AES.GCM.open(box, using: key, authenticating: aad(owner))
            let envelope = try JSONDecoder().decode(Envelope.self, from: plain)
            guard envelope.version == 1, envelope.owner == owner.hash else { throw ConversationOutboxError.integrityFailure }
            try Self.validate(envelope.entries)
            return envelope.entries
        } catch { throw ConversationOutboxError.integrityFailure }
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
