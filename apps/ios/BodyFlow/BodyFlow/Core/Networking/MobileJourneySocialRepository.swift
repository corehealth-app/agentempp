import Foundation

protocol JourneySocialProviding: Sendable {
  var binding: JourneySocialBinding { get }
  func validate() async throws
  func publish(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws
  func profile() async throws -> JourneySocialProfile
  func ranking(cursor: JourneySocialRankingCursor?, limit: Int) async throws
    -> JourneySocialRankingPage
  func blocks(cursor: JourneySocialBlocksCursor?, limit: Int) async throws
    -> JourneySocialBlocksPage
  func submit(_ operation: JourneySocialOperation) async throws -> JourneySocialMutationSnapshot
}

/// Original-account privacy controls use the existing BFF only. Construction
/// reads /me; no patient bootstrap, consent, reward or clinical writer exists
/// in this repository. Lost responses retain the caller's immutable operation.
struct MobileJourneySocialRepository: JourneySocialProviding {
  let binding: JourneySocialBinding
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let lease: SessionLease

  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(128 * 1024).scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    try await lifecycle.validate(lease)
    guard let auth = UUID(uuidString: lease.userID) else {
      throw SessionLifecycleError.sessionSuperseded
    }
    let login = try JourneySocialBinding.originalLogin(lease)
    let me = try await scoped.executeHTTP(
      MobileAPIRequest<MeSnapshot>(
        method: .get, path: "/api/mobile/v1/me", unauthorizedReplay: .never))
    try await scoped.validateOriginalSession(lease)
    guard me.statusCode == 200, let owner = UUID(uuidString: me.data.id) else {
      throw MobileAPITransportError.invalidResponse
    }
    let repository = Self(
      binding: .init(ownerID: owner, authUserID: auth, loginID: login), transport: scoped,
      lifecycle: lifecycle, lease: lease)
    try await repository.validate()
    return repository
  }

  func validate() async throws {
    try Task.checkCancellation()
    try await lifecycle.validate(lease)
    let current = try await lifecycle.leaseForRequest()
    guard current.userID == lease.userID, current.generation == lease.generation else {
      throw SessionLifecycleError.sessionSuperseded
    }
    try binding.validate(lease: current)
    try await transport.validateOriginalSession(current)
    try Task.checkCancellation()
  }
  func publish(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws {
    try await validate()
    try await lifecycle.performVisiblePatientStateOperation(lease: lease, operation: action)
  }
  func profile() async throws -> JourneySocialProfile {
    let value: JourneySocialProfile = try await execute(
      MobileAPIRequest(
        method: .get, path: "/api/mobile/v1/profile/journey-social", unauthorizedReplay: .never,
        journeySocial: .profile(binding)))
    try value.validate(binding: binding)
    return value
  }
  func ranking(cursor: JourneySocialRankingCursor?, limit: Int) async throws
    -> JourneySocialRankingPage
  {
    let value: JourneySocialRankingPage = try await execute(
      MobileAPIRequest(
        method: .get, path: "/api/mobile/v1/journey/ranking",
        queryItems: MobileJourneySocialRequestHeaders.pageQuery(cursor: cursor?.json, limit: limit),
        unauthorizedReplay: .never, journeySocial: .ranking(binding, cursor: cursor, limit: limit)))
    try value.validate(binding: binding, cursor: cursor, limit: limit)
    return value
  }
  func blocks(cursor: JourneySocialBlocksCursor?, limit: Int) async throws
    -> JourneySocialBlocksPage
  {
    let value: JourneySocialBlocksPage = try await execute(
      MobileAPIRequest(
        method: .get, path: "/api/mobile/v1/profile/journey-social/blocks",
        queryItems: MobileJourneySocialRequestHeaders.pageQuery(cursor: cursor?.json, limit: limit),
        unauthorizedReplay: .never, journeySocial: .blocks(binding, cursor: cursor, limit: limit)))
    try value.validate(binding: binding, cursor: cursor, limit: limit)
    return value
  }
  /// An explicit reconciliation repeats THIS operation and its key. It never
  /// fabricates another intent, accepts an old profile as current, or retries
  /// automatically after a lost response.
  func submit(_ operation: JourneySocialOperation) async throws -> JourneySocialMutationSnapshot {
    try await validate()
    guard operation.binding == binding else { throw SessionLifecycleError.sessionSuperseded }
    let value: JourneySocialMutationSnapshot = try await execute(
      MobileAPIRequest(
        method: operation.method, path: operation.path, body: operation.wireBody,
        idempotencyKey: IdempotencyKey(validating: operation.idempotencyKey),
        unauthorizedReplay: .never, journeySocial: .mutation(operation)))
    try value.validate(for: operation)
    return value
  }
  private func execute<T: Decodable & Sendable>(_ request: MobileAPIRequest<T>) async throws -> T {
    try await validate()
    do {
      let result = try await transport.executeHTTP(request)
      try await validate()
      guard result.statusCode == 200 else { throw MobileAPITransportError.invalidResponse }
      return result.data
    } catch {
      try await validate()
      throw error
    }
  }
}
