import CryptoKit
import Foundation

/// Synchronous RMW only: session-bound callers execute inside the patient-state gate.
/// Separate from draft/session clearers; no photos, asset IDs or body values are stored.
struct SignupBodyPhotoCleanupStore: Sendable {
    static let folderName = "performe-signup-photo-cleanup"
    let root: URL
    #if DEBUG
    private let beforeAtomicWrite: @Sendable () throws -> Void
    init(directory: URL, beforeAtomicWrite: @escaping @Sendable () throws -> Void = {}) {
        root = directory.appendingPathComponent(Self.folderName, isDirectory: true)
        self.beforeAtomicWrite = beforeAtomicWrite
    }
    #else
    init(directory: URL) {
        root = directory.appendingPathComponent(Self.folderName, isDirectory: true)
    }
    #endif

    static var device: Self { Self(directory: URL.applicationSupportDirectory) }

    static func userHash(_ userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func fileURL(for userID: String) -> URL {
        root.appendingPathComponent(Self.userHash(userID) + ".json", isDirectory: false)
    }

    func load(for userID: String) throws -> SignupBodyPhotoCleanupQueue {
        let data: Data
        do { data = try Data(contentsOf: fileURL(for: userID)) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError {
                return SignupBodyPhotoCleanupQueue(userHash: Self.userHash(userID))
            }
            throw error
        }
        guard Self.hasKnownShape(data) else { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
        let queue: SignupBodyPhotoCleanupQueue
        do { queue = try JSONDecoder().decode(SignupBodyPhotoCleanupQueue.self, from: data) }
        catch { throw SignupBodyPhotoCleanupStoreError.invalidFormat }
        try queue.validate()
        guard queue.userHash == Self.userHash(userID) else { throw SignupBodyPhotoCleanupStoreError.ownerMismatch }
        return queue
    }

    /// Codable otherwise ignores new fields and RMW would silently erase them.
    private static func hasKnownShape(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              Set(envelope.keys) == Set(["version", "userHash", "knownScopes", "unboundCreates"]),
              let scopes = envelope["knownScopes"] as? [[String: Any]] else { return false }
        let scopeKeys: Set<String> = ["generation", "revision", "operationID", "pending", "repair"]
        let repairKeys: Set<String> = ["key", "createdAt"]
        for scope in scopes {
            guard Set(scope.keys).isSubset(of: scopeKeys) else { return false }
            if let repair = scope["repair"], !(repair is NSNull) {
                guard let record = repair as? [String: Any],
                      Set(record.keys) == repairKeys else { return false }
            }
        }
        return true
    }

    func mutate<Value: Sendable>(for userID: String,
        _ operation: @Sendable (inout SignupBodyPhotoCleanupQueue) throws -> Value) throws -> Value {
        var current = try load(for: userID)
        let result = try operation(&current)
        try current.validate()
        guard current.userHash == Self.userHash(userID) else { throw SignupBodyPhotoCleanupStoreError.ownerMismatch }
        let data = try JSONEncoder().encode(current)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        #if DEBUG
        try beforeAtomicWrite()
        #endif
        try data.write(to: fileURL(for: userID), options: [.atomic, .completeFileProtection])
        return result
    }
}
