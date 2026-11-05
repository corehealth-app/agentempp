import Foundation

/// A read constraint from an observed response, never a write or clinical grant.
struct NutritionWindowReadReference: Sendable {
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let timezone: String
  let observedAt: String
  init(_ value: NutritionWindowSnapshot) {
    authUserID = value.authUserID
    ownerID = value.ownerID
    epoch = value.epoch
    timezone = value.timezone
    observedAt = value.observedAt
  }
  func matches(_ value: NutritionWindowSnapshot) -> Bool {
    guard value.authUserID == authUserID, value.ownerID == ownerID, value.epoch == epoch,
      value.timezone == timezone, let expected = ConversationProtocolInstant(observedAt),
      let actual = ConversationProtocolInstant(value.observedAt)
    else { return false }
    return actual >= expected
  }
}
protocol NutritionWindowProviding: Sendable {
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot
  func rebindNutritionWindow(_ reference: NutritionWindowReadReference, date: String?) async throws
    -> NutritionWindowSnapshot
}
extension NutritionWindowProviding {
  func rebindNutritionWindow(_ reference: NutritionWindowReadReference, date: String?) async throws
    -> NutritionWindowSnapshot
  {
    throw BodyFlowCapabilityError.serviceUnavailable
  }
}
struct UnavailableNutritionWindowProvider: NutritionWindowProviding {
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot {
    throw BodyFlowCapabilityError.serviceUnavailable
  }
}
