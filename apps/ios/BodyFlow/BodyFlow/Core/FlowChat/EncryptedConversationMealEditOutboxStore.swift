import CryptoKit
import Darwin
import Foundation

struct ConversationMealEditOutboxID: Hashable, Sendable {
  let commandID: UUID
  let operationID: UUID
  init(commandID: UUID, operationID: UUID) {
    self.commandID = commandID
    self.operationID = operationID
  }
  init(operation: ConversationMealEditOperation) {
    self.init(commandID: operation.commandID, operationID: operation.operationID)
  }
}
enum ConversationMealEditOutboxHold: String, Codable, Sendable {
  case unknownOutcome, userCancelled, staleEpoch, serverChanged, reset
  var priority: Int {
    switch self {
    case .unknownOutcome: 0
    case .userCancelled: 1
    case .staleEpoch, .serverChanged: 2
    case .reset: 3
    }
  }
}
struct ConversationMealEditOutboxEntry: Codable, Sendable, CustomStringConvertible,
  CustomReflectable
{
  let operation: ConversationMealEditOperation
  var state: ConversationOutboxState
  var hold: ConversationMealEditOutboxHold?
  var id: ConversationMealEditOutboxID { .init(operation: operation) }
  init(operation: ConversationMealEditOperation) {
    self.operation = operation
    state = .queued
    hold = nil
  }
  private enum CodingKeys: String, CodingKey {
    case ownerID, commandID, originalInputHash, epoch, operationID, operationInputHash, wireBody,
      state, hold
  }
  init(from decoder: any Decoder) throws {
    try editOutboxKeys(
      decoder,
      [
        "ownerID", "commandID", "originalInputHash", "epoch", "operationID", "operationInputHash",
        "wireBody", "state", "hold",
      ])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    operation = try .init(
      ownerID: c.decode(UUID.self, forKey: .ownerID),
      commandID: c.decode(UUID.self, forKey: .commandID),
      originalInputHash: c.decode(String.self, forKey: .originalInputHash),
      epoch: c.decode(UUID.self, forKey: .epoch),
      operationID: c.decode(UUID.self, forKey: .operationID),
      wireBody: c.decode(Data.self, forKey: .wireBody))
    guard operation.operationInputHash == (try c.decode(String.self, forKey: .operationInputHash))
    else { throw ConversationOutboxError.integrityFailure }
    state = try c.decode(ConversationOutboxState.self, forKey: .state)
    hold = try c.decodeIfPresent(ConversationMealEditOutboxHold.self, forKey: .hold)
    try validate()
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(operation.ownerID, forKey: .ownerID)
    try c.encode(operation.commandID, forKey: .commandID)
    try c.encode(operation.originalInputHash, forKey: .originalInputHash)
    try c.encode(operation.epoch, forKey: .epoch)
    try c.encode(operation.operationID, forKey: .operationID)
    try c.encode(operation.operationInputHash, forKey: .operationInputHash)
    try c.encode(operation.wireBody, forKey: .wireBody)
    try c.encode(state, forKey: .state)
    try c.encode(hold, forKey: .hold)
  }
  func validate() throws {
    let parsed = try ConversationMealEditOperation(
      ownerID: operation.ownerID, commandID: operation.commandID,
      originalInputHash: operation.originalInputHash, epoch: operation.epoch,
      operationID: operation.operationID, wireBody: operation.wireBody)
    guard parsed.operationInputHash == operation.operationInputHash,
      parsed.expectedRevision == operation.expectedRevision,
      parsed.expectedVersion == operation.expectedVersion
    else { throw ConversationOutboxError.integrityFailure }
    switch state {
    case .queued:
      guard hold == nil || hold == .reset else { throw ConversationOutboxError.integrityFailure }
    case .dispatchedUnknown:
      guard hold == nil else { throw ConversationOutboxError.integrityFailure }
    case .waitingReconciliation:
      guard hold != nil else { throw ConversationOutboxError.integrityFailure }
    }
  }
  var description: String { "ConversationMealEditOutboxEntry(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

/// Separate encrypted edit namespace. Only ciphertext reaches disk; read or
/// failed mutation never discards prior work. Auth lease/gates belong to session.
struct EncryptedConversationMealEditOutboxStore: Sendable {
  static let capacity = 50
  private static let maxBytes = capacity * 24_576 + 4_096
  private static let header = Data("PCEDX001".utf8)
  private static let directoryCreationLock = NSLock()
  let root: URL
  init(directory: URL) {
    root = directory.appendingPathComponent(
      "performe-conversation-meal-edit-outbox-v1", isDirectory: true)
  }
  static var device: Self { Self(directory: .applicationSupportDirectory) }
  func fileURL(owner: ConversationOutboxOwner) -> URL {
    root.appendingPathComponent(owner.hash + ".sealed", isDirectory: false)
  }
  func containsCiphertext(owner: ConversationOutboxOwner) throws -> Bool {
    try locked { try readCiphertext(owner: owner) != nil }
  }
  func load(owner: ConversationOutboxOwner, key: SymmetricKey) throws
    -> [ConversationMealEditOutboxEntry]
  { try locked { try read(owner: owner, key: key) } }
  @discardableResult func update<Value: Sendable>(
    owner: ConversationOutboxOwner, key: SymmetricKey,
    _ mutation: (inout [ConversationMealEditOutboxEntry]) throws -> Value
  ) throws -> Value {
    try locked {
      var entries = try read(owner: owner, key: key)
      let original = entries
      let result = try mutation(&entries)
      guard entries.count <= Self.capacity else { throw ConversationOutboxError.queueFull }
      try Self.validate(entries)
      try Self.validateTransitions(from: original, to: entries)
      let plain = try JSONEncoder().encode(
        Envelope(version: 1, owner: owner.hash, entries: entries))
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
    let entries: [ConversationMealEditOutboxEntry]
    private enum CodingKeys: String, CodingKey { case version, owner, entries }
    init(version: Int, owner: String, entries: [ConversationMealEditOutboxEntry]) {
      self.version = version
      self.owner = owner
      self.entries = entries
    }
    init(from decoder: any Decoder) throws {
      try editOutboxKeys(decoder, ["version", "owner", "entries"])
      let c = try decoder.container(keyedBy: CodingKeys.self)
      version = try c.decode(Int.self, forKey: .version)
      owner = try c.decode(String.self, forKey: .owner)
      entries = try c.decode([ConversationMealEditOutboxEntry].self, forKey: .entries)
    }
  }
  private func aad(_ owner: ConversationOutboxOwner) -> Data {
    Data("performe.conversation.meal-edit.outbox\0version=1\0owner=\(owner.hash)".utf8)
  }
  private func read(owner: ConversationOutboxOwner, key: SymmetricKey) throws
    -> [ConversationMealEditOutboxEntry]
  {
    guard let data = try readCiphertext(owner: owner) else { return [] }
    do {
      guard data.starts(with: Self.header) else { throw ConversationOutboxError.integrityFailure }
      let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.header.count))
      let plain = try AES.GCM.open(box, using: key, authenticating: aad(owner))
      let envelope = try JSONDecoder().decode(Envelope.self, from: plain)
      guard envelope.version == 1, envelope.owner == owner.hash else {
        throw ConversationOutboxError.integrityFailure
      }
      try Self.validate(envelope.entries)
      return envelope.entries
    } catch { throw ConversationOutboxError.integrityFailure }
  }
  private static func validate(_ entries: [ConversationMealEditOutboxEntry]) throws {
    guard entries.count <= capacity, Set(entries.map(\.id)).count == entries.count else {
      throw ConversationOutboxError.integrityFailure
    }
    for entry in entries { try entry.validate() }
  }
  private static func validateTransitions(
    from original: [ConversationMealEditOutboxEntry], to entries: [ConversationMealEditOutboxEntry]
  ) throws {
    for old in original {
      guard let new = entries.first(where: { $0.id == old.id }) else { continue }
      let a = old.operation
      let b = new.operation
      guard a.ownerID == b.ownerID, a.commandID == b.commandID,
        a.originalInputHash == b.originalInputHash, a.epoch == b.epoch,
        a.operationID == b.operationID, a.operationInputHash == b.operationInputHash,
        a.wireBody == b.wireBody, a.expectedRevision == b.expectedRevision,
        a.expectedVersion == b.expectedVersion
      else { throw ConversationOutboxError.integrityFailure }
      if let hold = old.hold {
        guard let next = new.hold, next.priority >= hold.priority else {
          throw ConversationOutboxError.integrityFailure
        }
      }
      if old.state != .queued {
        guard new.state != .queued else { throw ConversationOutboxError.integrityFailure }
      }
      if old.state == .waitingReconciliation {
        guard new.state == .waitingReconciliation else {
          throw ConversationOutboxError.integrityFailure
        }
      }
    }
  }
  private func prepareDirectory() throws {
    // The initial directory must already be private when it becomes
    // visible to another instance. Metadata configuration follows under
    // the process-shared file lock, rather than racing before that lock.
    try Self.directoryCreationLock.withLock {
      try FileManager.default.createDirectory(
        at: root.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      guard mkdir(root.path, 0o700) == 0 || errno == EEXIST else {
        throw ConversationOutboxError.storageUnavailable
      }
    }
    var info = stat()
    guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
      info.st_mode & 0o077 == 0
    else { throw ConversationOutboxError.storageUnavailable }
  }

  private func configureDirectory() throws {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var directory = root
    try directory.setResourceValues(values)
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
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
    } catch let error as ConversationOutboxError { throw error } catch {
      throw ConversationOutboxError.storageUnavailable
    }
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
      info.st_size > 0, info.st_size <= Self.maxBytes + 128
    else {
      throw ConversationOutboxError.integrityFailure
    }
    var data = Data(count: Int(info.st_size))
    try data.withUnsafeMutableBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.read(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
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
    let descriptor = open(
      temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw ConversationOutboxError.storageUnavailable }
    defer {
      close(descriptor)
      unlink(temporary.path)
    }
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path)
    #endif
    try ciphertext.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
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

private struct EditOutboxStorageKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func editOutboxKeys(_ decoder: any Decoder, _ required: Set<String>) throws {
  let keys = Set(
    try decoder.container(keyedBy: EditOutboxStorageKey.self).allKeys.map(\.stringValue))
  guard keys == required else { throw ConversationOutboxError.integrityFailure }
}
