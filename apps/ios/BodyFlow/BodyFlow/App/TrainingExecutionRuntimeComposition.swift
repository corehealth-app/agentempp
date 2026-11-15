import Foundation

/// Bundled protocol selection. This is never a login, permission or launch-argument grant.
enum TrainingExecutionRuntimeSelection: Equatable, Sendable {
  case progressV1, completionV1, unavailable
  static let infoKey = "PERFORME_TRAINING_EXECUTION_RUNTIME"
  static func load(_ raw: Any?) -> Self {
    guard let raw else { return .progressV1 }
    guard let value = raw as? String else { return .unavailable }
    switch value {
    case "progress_v1": return .progressV1
    case "completion_v1": return .completionV1
    default: return .unavailable
    }
  }
}

/// Only the existing qualified real conversational family installs this inert
/// source. Construction does not read Keychain, authenticate or create a workout.
struct TrainingExecutionSessionSource: Sendable {
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let pendingStore: TrainingExecutionPendingStore?
  private let completionEnabled: Bool
  init(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    pendingStore: TrainingExecutionPendingStore? = nil, completionEnabled: Bool = false
  ) {
    self.transport = transport
    self.lifecycle = lifecycle
    self.pendingStore = pendingStore
    self.completionEnabled = completionEnabled
  }
  @MainActor func open(expectedUserID: String) async throws -> TrainingExecutionModel {
    try Task.checkCancellation()
    let lease = try await lifecycle.leaseForRequest()
    guard let expected = UUID(uuidString: expectedUserID),
      UUID(uuidString: lease.userID) == expected,
      let origin = transport.configuredOrigin
    else { throw SessionLifecycleError.sessionSuperseded }
    try await lifecycle.validate(lease)
    let repository: any TrainingExecutionProviding
    if completionEnabled {
      repository = try await MobileTrainingExecutionCompletionRepository.scoped(
        transport: transport, lifecycle: lifecycle, lease: lease)
    } else {
      repository = try await MobileTrainingExecutionRepository.scoped(
        transport: transport, lifecycle: lifecycle, lease: lease)
    }
    let store: TrainingExecutionPendingStore
    if let pendingStore { store = pendingStore } else { store = try await .live(origin: origin) }
    try await repository.validate()
    let model = TrainingExecutionModel(provider: repository, store: store)
    do {
      try await model.publishIfCurrent {}
      return model
    } catch {
      await model.close()
      throw error
    }
  }
}
