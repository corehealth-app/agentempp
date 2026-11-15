import Foundation

/// Explicit additive transport. The old v1 repository remains closed and is
/// reused only for its verified original-login lifecycle, never as a fallback
/// writer when a v2 response is absent, malformed or ambiguous.
protocol TrainingExecutionCompletionProviding: TrainingExecutionProviding {
  func current(_ id: UUID, binding: TrainingExecutionBinding) async throws
    -> TrainingExecutionCurrentV2Snapshot
  func progress(_ operation: TrainingExecutionOperation) async throws
    -> TrainingExecutionProgressV2Snapshot
  func finish(_ operation: TrainingExecutionOperation) async throws
    -> TrainingExecutionCompletionSnapshot
  func completion(_ identity: TrainingExecutionCompletionIdentity) async throws
    -> TrainingExecutionCompletionSnapshot
  func cancel(_ identity: TrainingExecutionCompletionIdentity) async throws
    -> TrainingExecutionCompletionSnapshot
}

struct MobileTrainingExecutionCompletionRepository: TrainingExecutionCompletionProviding {
  let ownerID: UUID, authUserID: UUID
  private let original: MobileTrainingExecutionRepository
  private let transport: MobileAPITransport
  private static let base = "/api/mobile/v1/training/execution-v2"
  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease
  ) async throws -> Self {
    let original = try await MobileTrainingExecutionRepository.scoped(
      transport: transport, lifecycle: lifecycle, lease: lease)
    try await original.validate()
    return .init(
      ownerID: original.ownerID, authUserID: original.authUserID, original: original,
      transport: transport.withResponseBodyLimit(2_097_152).scoped(to: lease))
  }
  func validate() async throws { try await original.validate() }
  func publish(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws {
    try await original.publish(action)
  }
  func completionHome(cursor: TrainingExecutionCursor?) async throws
    -> TrainingExecutionHomeV2Snapshot
  {
    var query: [URLQueryItem] = []
    if let cursor {
      guard cursor.ownerID == ownerID,
        let value = String(data: try cursor.json.data(), encoding: .utf8)
      else { throw TrainingExecutionError.scopeChanged }
      query = [.init(name: "cursor", value: value)]
    }
    let reply = try await execute(
      MobileAPIRequest<TrainingExecutionHomeV2Snapshot>(
        method: .get, path: Self.base, queryItems: query, unauthorizedReplay: .never,
        trainingExecution: .history(ownerID: ownerID, cursor: cursor)))
    try check(reply.data.scope)
    return reply.data
  }
  func current(_ sessionID: UUID, binding: TrainingExecutionBinding) async throws
    -> TrainingExecutionCurrentV2Snapshot
  {
    try check(binding)
    let reply = try await execute(
      MobileAPIRequest<TrainingExecutionCurrentV2Snapshot>(
        method: .get, path: Self.base + "/" + sessionID.uuidString.lowercased(),
        unauthorizedReplay: .never, trainingExecution: .state(binding, sessionID: sessionID)))
    try check(reply.data.scope)
    guard binding.matches(reply.data.scope), reply.data.session.id == sessionID else {
      throw TrainingExecutionError.scopeChanged
    }
    return reply.data
  }
  func progress(_ operation: TrainingExecutionOperation) async throws
    -> TrainingExecutionProgressV2Snapshot
  {
    try check(operation.binding)
    try trainingRequire(operation.kind != "finish")
    let reply = try await execute(
      MobileAPIRequest<TrainingExecutionProgressV2Snapshot>(
        method: .post, path: Self.base + "/" + operation.sessionID.uuidString.lowercased(),
        body: operation.wireBody,
        idempotencyKey: IdempotencyKey(validating: operation.idempotencyKey),
        unauthorizedReplay: .never, trainingExecution: .progressV2(operation)))
    try reply.data.validate(for: operation)
    return reply.data
  }
  func finish(_ operation: TrainingExecutionOperation) async throws
    -> TrainingExecutionCompletionSnapshot
  {
    try check(operation.binding)
    try trainingRequire(operation.kind == "finish")
    let reply = try await execute(
      MobileAPIRequest<TrainingExecutionCompletionSnapshot>(
        method: .post, path: Self.base + "/completions", body: operation.wireBody,
        idempotencyKey: IdempotencyKey(validating: operation.idempotencyKey),
        unauthorizedReplay: .never, trainingExecution: .finish(operation)))
    try reply.data.validate(for: operation)
    try checkStatus(reply)
    return reply.data
  }
  func completion(_ identity: TrainingExecutionCompletionIdentity) async throws
    -> TrainingExecutionCompletionSnapshot
  {
    try check(identity.binding)
    let reply = try await execute(
      MobileAPIRequest<TrainingExecutionCompletionSnapshot>(
        method: .get, path: path(identity), unauthorizedReplay: .never,
        trainingExecution: .completionRead(identity)))
    try reply.data.validate(identity: identity)
    try checkStatus(reply)
    return reply.data
  }
  func cancel(_ identity: TrainingExecutionCompletionIdentity) async throws
    -> TrainingExecutionCompletionSnapshot
  {
    try check(identity.binding)
    let reply = try await execute(
      MobileAPIRequest<TrainingExecutionCompletionSnapshot>(
        method: .post, path: path(identity) + "/cancel", body: identity.cancelBody,
        idempotencyKey: IdempotencyKey(
          validating: "tcancel1:" + identity.completionID.uuidString.lowercased()),
        unauthorizedReplay: .never, trainingExecution: .completionCancel(identity)))
    try reply.data.validate(identity: identity)
    try trainingRequire(reply.data.status != .reserved && reply.statusCode == 200)
    return reply.data
  }
  private func path(_ identity: TrainingExecutionCompletionIdentity) -> String {
    Self.base + "/" + identity.sessionID.uuidString.lowercased() + "/completions/"
      + identity.completionID.uuidString.lowercased()
  }
  private func check(_ scope: TrainingExecutionScope) throws { try check(.init(scope)) }
  private func check(_ binding: TrainingExecutionBinding) throws {
    guard binding.ownerID == ownerID && binding.authUserID == authUserID else {
      throw TrainingExecutionError.scopeChanged
    }
  }
  private func checkStatus(_ reply: MobileAPIHTTPResponse<TrainingExecutionCompletionSnapshot>)
    throws
  {
    try trainingRequire((reply.data.status == .reserved) == (reply.statusCode == 202))
  }
  private func execute<T: Decodable & Sendable>(_ request: MobileAPIRequest<T>) async throws
    -> MobileAPIHTTPResponse<T>
  {
    try await validate()
    do {
      let result = try await transport.executeHTTP(request)
      try await validate()
      return result
    } catch {
      try await validate()
      throw error
    }
  }
}

extension MobileTrainingExecutionCompletionRepository {
  func home(cursor: TrainingExecutionCursor?) async throws -> TrainingExecutionHomeSnapshot {
    try .init(verified: await completionHome(cursor: cursor))
  }
  func read(_ id: UUID) async throws -> TrainingExecutionReadSnapshot {
    let fresh = try await completionHome(cursor: nil)
    return try .init(verified: await current(id, binding: .init(fresh.scope)))
  }
  /// The v2 model must consume its distinct proof/status. Never turn pending or
  /// not_applied into an invented old v1 mutation receipt, even for compatibility.
  func submit(_ operation: TrainingExecutionOperation) async throws
    -> TrainingExecutionMutationSnapshot
  {
    throw TrainingExecutionError.unavailable
  }
  func reconcile(_ rejection: TrainingExecutionRejectedOperation) async throws
    -> TrainingExecutionRejectedResolution
  {
    throw TrainingExecutionError.unavailable
  }
}
