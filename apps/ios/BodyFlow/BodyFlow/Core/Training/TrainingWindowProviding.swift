import Foundation

/// A read constraint from an observed response, never a write or clinical grant.
struct TrainingWindowReadReference: Sendable {
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let timezone: String
  let observedAt: String
  init(_ value: TrainingWindowSnapshot) {
    authUserID = value.authUserID
    ownerID = value.ownerID
    epoch = value.epoch
    timezone = value.timezone
    observedAt = value.observedAt
  }
  func matches(_ value: TrainingWindowSnapshot) -> Bool {
    guard value.authUserID == authUserID, value.ownerID == ownerID, value.epoch == epoch,
      value.timezone == timezone, let expected = ConversationProtocolInstant(observedAt),
      let actual = ConversationProtocolInstant(value.observedAt)
    else { return false }
    return actual >= expected
  }
}
protocol TrainingWindowProviding: Sendable {
  func trainingWindow(date: String?) async throws -> TrainingWindowSnapshot
  func rebindTrainingWindow(_ reference: TrainingWindowReadReference, date: String?) async throws
    -> TrainingWindowSnapshot
}
extension TrainingWindowProviding {
  func rebindTrainingWindow(_ reference: TrainingWindowReadReference, date: String?) async throws
    -> TrainingWindowSnapshot
  {
    throw BodyFlowCapabilityError.serviceUnavailable
  }
}
struct UnavailableTrainingWindowProvider: TrainingWindowProviding {
  func trainingWindow(date: String?) async throws -> TrainingWindowSnapshot {
    throw BodyFlowCapabilityError.serviceUnavailable
  }
}
