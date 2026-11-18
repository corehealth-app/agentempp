import CryptoKit
import Foundation
import Security

/// Live callers share one actor per canonical origin. No extension/other
/// process owns this namespace; the injectable initializer is for composition
/// tests. An unresolved command can never be overwritten or generically reset.
actor JourneySocialPendingStore {
  private let origin: URL
  private let service: String
  private let security: any KeychainSecurityClient
  private var busy = false
  private static let registry = JourneySocialPendingRegistry()

  static func live(origin: URL) async throws -> JourneySocialPendingStore {
    try await registry.store(origin: origin)
  }
  init(origin: URL, security: any KeychainSecurityClient) throws {
    let canonical = try journeySocialOrigin(origin)
    self.origin = canonical
    self.service = "com.performeai.journey-social.pending.v1." + Self.hash(canonical.absoluteString)
    self.security = security
  }
  func load(authUserID: UUID) async throws -> JourneySocialPendingOperation? {
    try enter()
    defer { busy = false }
    return try await read(authUserID)
  }
  func claim(_ pending: JourneySocialPendingOperation) async throws {
    try enter()
    defer { busy = false }
    guard pending.origin == origin else { throw JourneySocialPendingError.scopeChanged }
    let auth = pending.operation.binding.authUserID
    if let prior = try await read(auth) {
      guard prior == pending else { throw JourneySocialPendingError.pendingOperation }
      return
    }
    let bytes = try pending.storageData()
    switch await security.add(descriptor(auth), data: bytes) {
    case errSecSuccess: return
    case errSecDuplicateItem:
      guard try await read(auth) == pending else {
        throw JourneySocialPendingError.pendingOperation
      }
    default: throw JourneySocialPendingError.storageUnavailable
    }
  }
  func acknowledge(_ pending: JourneySocialPendingOperation, result: JourneySocialMutationSnapshot)
    async throws
  {
    try result.validate(for: pending.operation)
    try await retireExact(pending)
  }
  func acknowledgeResolution(
    _ pending: JourneySocialPendingOperation, result: JourneySocialResolutionSnapshot,
    current: JourneySocialBinding
  ) async throws {
    try result.validate(for: pending, current: current)
    try await retireExact(pending)
  }
  private func retireExact(_ pending: JourneySocialPendingOperation) async throws {
    try enter()
    defer { busy = false }
    guard pending.origin == origin else { throw JourneySocialPendingError.scopeChanged }
    let auth = pending.operation.binding.authUserID
    guard try await read(auth) == pending else { throw JourneySocialPendingError.pendingOperation }
    let result = await security.delete(descriptor(auth))
    guard result == errSecSuccess || result == errSecItemNotFound else {
      throw JourneySocialPendingError.storageUnavailable
    }
  }
  private func enter() throws {
    guard !busy else { throw JourneySocialPendingError.pendingOperation }
    busy = true
  }
  private func read(_ auth: UUID) async throws -> JourneySocialPendingOperation? {
    switch await security.read(descriptor(auth)) {
    case .notFound: return nil
    case .failure: throw JourneySocialPendingError.storageUnavailable
    case .data(let bytes):
      guard bytes.count <= JourneySocialPendingOperation.storageLimit,
        let p = try? JSONDecoder().decode(JourneySocialPendingOperation.self, from: bytes),
        p.origin == origin, p.operation.binding.authUserID == auth,
        let canonical = try? p.storageData(), canonical == bytes
      else { throw JourneySocialPendingError.storageUnavailable }
      return p
    }
  }
  private func descriptor(_ auth: UUID) -> KeychainItemDescriptor {
    .init(
      itemClass: .genericPassword, service: service,
      account: Self.hash(auth.uuidString.lowercased()), accessibility: .whenUnlockedThisDeviceOnly,
      synchronizable: false, accessGroup: nil)
  }
  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

private actor JourneySocialPendingRegistry {
  private var stores: [URL: JourneySocialPendingStore] = [:]
  func store(origin: URL) throws -> JourneySocialPendingStore {
    let canonical = try journeySocialOrigin(origin)
    if let previous = stores[canonical] { return previous }
    let store = try JourneySocialPendingStore(
      origin: canonical, security: SystemKeychainSecurityClient())
    stores[canonical] = store
    return store
  }
}
