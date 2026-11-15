import CryptoKit
import Foundation
import Security

/// A private, non-synchronizing Keychain slot per origin and Auth account.
/// Live callers share the registry actor; no extension or second process owns
/// this namespace. No update/upsert can overwrite an unresolved operation.
actor TrainingExecutionPendingStore {
  private let service: String
  private let security: any KeychainSecurityClient
  private var busy = false
  private static let registry = TrainingExecutionPendingStoreRegistry()

  static func live(origin: URL) async throws -> TrainingExecutionPendingStore {
    try await registry.store(origin: origin)
  }
  init(origin: URL, security: any KeychainSecurityClient) throws {
    let configuration = try MobileAPIConfiguration(originString: origin.absoluteString)
    service =
      "com.performeai.training-execution.pending.v1."
      + Self.hash(configuration.origin.absoluteString)
    self.security = security
  }

  func load(authUserID: UUID) async throws -> TrainingExecutionOperation? {
    try enter()
    defer { busy = false }
    return try await read(authUserID)
  }
  func claim(_ operation: TrainingExecutionOperation) async throws {
    try enter()
    defer { busy = false }
    let auth = operation.binding.authUserID
    if let previous = try await read(auth) {
      guard previous == operation else { throw TrainingExecutionError.pendingOperation }
      return
    }
    let bytes = try JSONEncoder().encode(operation)
    guard bytes.count <= 32_768 else { throw TrainingExecutionError.storageUnavailable }
    switch await security.add(descriptor(auth), data: bytes) {
    case errSecSuccess: return
    case errSecDuplicateItem:
      guard try await read(auth) == operation else { throw TrainingExecutionError.pendingOperation }
    default: throw TrainingExecutionError.storageUnavailable
    }
  }

  /// This is deliberately not a generic delete or reset. A validated original
  /// receipt may retire only the exact slot that produced that receipt.
  func acknowledge(
    _ operation: TrainingExecutionOperation, result: TrainingExecutionMutationSnapshot
  ) async throws {
    try result.validate(for: operation)
    try await retireExact(operation)
  }

  func acknowledgeProgress(
    _ operation: TrainingExecutionOperation, result: TrainingExecutionProgressV2Snapshot
  ) async throws {
    try result.validate(for: operation)
    guard result.status != .pending else { throw TrainingExecutionError.pendingOperation }
    try await retireExact(operation)
  }

  func acknowledgeCompletion(
    _ operation: TrainingExecutionOperation, result: TrainingExecutionCompletionSnapshot
  ) async throws {
    try result.validate(for: operation)
    guard result.status != .reserved, result.receipt != nil else {
      throw TrainingExecutionError.pendingOperation
    }
    try await retireExact(operation)
  }

  /// Retires only an exact future-denial proof, never a borrowed workout ACK.
  func retireFinish(
    _ operation: TrainingExecutionOperation, resolution: TrainingExecutionFinishResolutionSnapshot
  ) async throws {
    try resolution.validate(for: operation, mode: resolution.mode)
    guard resolution.status == .withdrawn || resolution.status == .fenced else {
      throw TrainingExecutionError.pendingOperation
    }
    try await retireExact(operation)
  }

  private func retireExact(_ operation: TrainingExecutionOperation) async throws {
    try enter()
    defer { busy = false }
    let auth = operation.binding.authUserID
    guard try await read(auth) == operation else { throw TrainingExecutionError.pendingOperation }
    let status = await security.delete(descriptor(auth))
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw TrainingExecutionError.storageUnavailable
    }
  }

  /// A sealed original-session pre-write rejection is not a receipt and never
  /// credits a workout. It resolves only this exact proven-unaccepted command.
  func retireRejected(_ proof: TrainingExecutionRejectedResolution) async throws {
    try enter()
    defer { busy = false }
    let operation = proof.operation
    let auth = operation.binding.authUserID
    guard operation.binding.matches(proof.home.scope), try await read(auth) == operation else {
      throw TrainingExecutionError.pendingOperation
    }
    let status = await security.delete(descriptor(auth))
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw TrainingExecutionError.storageUnavailable
    }
  }

  private func enter() throws {
    guard !busy else { throw TrainingExecutionError.pendingOperation }
    busy = true
  }
  private func read(_ auth: UUID) async throws -> TrainingExecutionOperation? {
    switch await security.read(descriptor(auth)) {
    case .notFound: return nil
    case .failure: throw TrainingExecutionError.storageUnavailable
    case .data(let bytes):
      guard bytes.count <= 32_768,
        let operation = try? JSONDecoder().decode(TrainingExecutionOperation.self, from: bytes),
        operation.binding.authUserID == auth
      else { throw TrainingExecutionError.storageUnavailable }
      return operation
    }
  }
  private func descriptor(_ auth: UUID) -> KeychainItemDescriptor {
    .init(
      itemClass: .genericPassword, service: service,
      account: Self.hash(auth.uuidString.lowercased()),
      accessibility: .whenUnlockedThisDeviceOnly, synchronizable: false, accessGroup: nil)
  }
  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

private actor TrainingExecutionPendingStoreRegistry {
  private var stores: [URL: TrainingExecutionPendingStore] = [:]
  func store(origin: URL) throws -> TrainingExecutionPendingStore {
    let normalized = try MobileAPIConfiguration(originString: origin.absoluteString).origin
    if let previous = stores[normalized] { return previous }
    let store = try TrainingExecutionPendingStore(
      origin: normalized, security: SystemKeychainSecurityClient())
    stores[normalized] = store
    return store
  }
}
