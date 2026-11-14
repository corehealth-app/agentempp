import Foundation

protocol TrainingExecutionProviding: Sendable {
  var ownerID: UUID { get }
  var authUserID: UUID { get }
  func validate() async throws
  func publish(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws
  func home(cursor: TrainingExecutionCursor?) async throws -> TrainingExecutionHomeSnapshot
  func read(_ id: UUID) async throws -> TrainingExecutionReadSnapshot
  func submit(_ operation: TrainingExecutionOperation) async throws
    -> TrainingExecutionMutationSnapshot
  func reconcile(_ rejection: TrainingExecutionRejectedOperation) async throws
    -> TrainingExecutionRejectedResolution
}

/// Only this original-session repository can issue a definitive rejection.
/// Unknown/post-commit scope errors never construct this capability.
struct TrainingExecutionRejectedOperation: Error, Sendable, CustomStringConvertible {
  let operation: TrainingExecutionOperation
  let code: String
  fileprivate init(_ operation: TrainingExecutionOperation, code: String) {
    self.operation = operation
    self.code = code
  }
  var description: String { "TrainingExecutionRejectedOperation(redacted)" }
}
struct TrainingExecutionRejectedResolution: Sendable {
  let operation: TrainingExecutionOperation
  let home: TrainingExecutionHomeSnapshot
  let session: TrainingExecutionSession?
  fileprivate init(
    operation: TrainingExecutionOperation, home: TrainingExecutionHomeSnapshot,
    session: TrainingExecutionSession?
  ) {
    self.operation = operation
    self.home = home
    self.session = session
  }
}

struct MobileTrainingExecutionRepository: TrainingExecutionProviding {
  let ownerID: UUID, authUserID: UUID
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let lease: SessionLease
  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(750_000).scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    guard let auth = UUID(uuidString: lease.userID) else {
      throw SessionLifecycleError.sessionSuperseded
    }
    let me = try await scoped.executeHTTP(
      MobileAPIRequest<MeSnapshot>(
        method: .get, path: "/api/mobile/v1/me", unauthorizedReplay: .never))
    try await scoped.validateOriginalSession(lease)
    guard me.statusCode == 200, let owner = UUID(uuidString: me.data.id) else {
      throw TrainingExecutionError.unavailable
    }
    return .init(
      ownerID: owner, authUserID: auth, transport: scoped, lifecycle: lifecycle, lease: lease)
  }
  func validate() async throws {
    try Task.checkCancellation()
    try await lifecycle.validate(lease)
    try await transport.validateOriginalSession(lease)
    try Task.checkCancellation()
  }
  func publish(_ action: @escaping @MainActor @Sendable () throws -> Void) async throws {
    try await validate()
    try await lifecycle.performVisiblePatientStateOperation(lease: lease, operation: action)
  }
  func home(cursor: TrainingExecutionCursor?) async throws -> TrainingExecutionHomeSnapshot {
    try await validate()
    let query: [URLQueryItem]
    if let cursor {
      guard cursor.ownerID == ownerID,
        let string = String(data: try cursor.json.data(), encoding: .utf8)
      else { throw TrainingExecutionError.scopeChanged }
      query = [.init(name: "cursor", value: string)]
    } else {
      query = []
    }
    do {
      let result = try await transport.executeHTTP(
        MobileAPIRequest<TrainingExecutionHomeSnapshot>(
          method: .get, path: "/api/mobile/v1/training/execution", queryItems: query,
          unauthorizedReplay: .never, trainingExecution: .home(ownerID: ownerID, cursor: cursor)))
      try await validate()
      try scope(result.data.scope)
      return result.data
    } catch {
      try await validate()
      throw error
    }
  }
  func read(_ id: UUID) async throws -> TrainingExecutionReadSnapshot {
    try await validate()
    do {
      let result = try await transport.executeHTTP(
        MobileAPIRequest<TrainingExecutionReadSnapshot>(
          method: .get, path: "/api/mobile/v1/training/execution/" + id.uuidString.lowercased(),
          unauthorizedReplay: .never, trainingExecution: .read(ownerID: ownerID, sessionID: id)))
      try await validate()
      try scope(result.data.scope)
      guard result.data.session.id == id else { throw TrainingExecutionError.invalidResponse }
      return result.data
    } catch {
      try await validate()
      throw error
    }
  }
  func submit(_ operation: TrainingExecutionOperation) async throws
    -> TrainingExecutionMutationSnapshot
  {
    try await validate()
    guard operation.binding.ownerID == ownerID, operation.binding.authUserID == authUserID else {
      throw TrainingExecutionError.scopeChanged
    }
    do {
      let result = try await transport.executeHTTP(
        MobileAPIRequest<TrainingExecutionMutationSnapshot>(
          method: .post, path: "/api/mobile/v1/training/execution/commands",
          body: operation.wireBody,
          idempotencyKey: IdempotencyKey(validating: operation.idempotencyKey),
          unauthorizedReplay: .never, trainingExecution: .mutation(operation)))
      try await validate()
      try result.data.validate(for: operation)
      return result.data
    } catch {
      try await validate()
      if case MobileAPITransportError.conflict(let code, _) = error,
        Self.prewriteRejections.contains(code)
      {
        throw TrainingExecutionRejectedOperation(operation, code: code)
      }
      throw error
    }
  }
  func reconcile(_ rejection: TrainingExecutionRejectedOperation) async throws
    -> TrainingExecutionRejectedResolution
  {
    try await validate()
    guard Self.prewriteRejections.contains(rejection.code),
      rejection.operation.binding.ownerID == ownerID,
      rejection.operation.binding.authUserID == authUserID
    else { throw TrainingExecutionError.scopeChanged }
    let fresh = try await home(cursor: nil)
    guard rejection.operation.binding.matches(fresh.scope) else {
      throw TrainingExecutionError.scopeChanged
    }
    let session: TrainingExecutionSession?
    do {
      let current = try await read(rejection.operation.sessionID)
      guard rejection.operation.binding.matches(current.scope) else {
        throw TrainingExecutionError.scopeChanged
      }
      session = current.session
    } catch MobileAPITransportError.http(status: 404, code: _, requestID: _) {
      try await validate()
      session = nil
    }
    try await validate()
    return .init(operation: rejection.operation, home: fresh, session: session)
  }
  private func scope(_ value: TrainingExecutionScope) throws {
    guard value.ownerID == ownerID, value.authUserID == authUserID else {
      throw TrainingExecutionError.scopeChanged
    }
  }
  private static let prewriteRejections: Set<String> = [
    "training_execution_revision_conflict", "training_execution_plan_changed",
    "training_execution_day_closed",
    "training_execution_terminal", "training_execution_recording_blocked",
    "training_execution_day_unavailable",
    "training_execution_state_unavailable", "training_execution_revision_exhausted",
    "training_execution_set_conflict", "training_execution_set_limit",
  ]
}
