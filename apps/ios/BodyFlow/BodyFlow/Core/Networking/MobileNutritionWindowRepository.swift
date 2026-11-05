import Foundation

struct MobileNutritionWindowRepository: NutritionWindowProviding {
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let lease: SessionLease
  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(750_000).scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    return .init(transport: scoped, lifecycle: lifecycle, lease: lease)
  }
  func nutritionWindow(date: String?) async throws -> NutritionWindowSnapshot {
    try await validate()
    var query = CurrentClinicalRepresentation.currentV1.queryItems
    if let date {
      guard NutritionCivilDate.date(date) != nil else {
        throw MobileAPITransportError.invalidResponse
      }
      query.append(.init(name: "date", value: date))
    }
    let result = try await transport.executeHTTP(
      MobileAPIRequest<NutritionWindowSnapshot>(
        method: .get, path: "/api/mobile/v1/nutrition/window", queryItems: query))
    try await validate()
    guard result.statusCode == 200, result.data.authUserID == UUID(uuidString: lease.userID),
      result.data.selectedLocalDate == (date ?? result.data.currentLocalDate)
    else {
      throw MobileAPITransportError.invalidResponse
    }
    return result.data
  }
  /// Fresh read capability under the original Auth generation. Neither the
  /// observed reference nor this read acknowledges or revives an old writer.
  func rebindNutritionWindow(_ reference: NutritionWindowReadReference, date: String?) async throws
    -> NutritionWindowSnapshot
  {
    try await validate()
    guard reference.authUserID == UUID(uuidString: lease.userID) else {
      throw MobileAPITransportError.invalidResponse
    }
    let fresh = try await Self.scoped(transport: transport, lifecycle: lifecycle, lease: lease)
    let value = try await fresh.nutritionWindow(date: date)
    try await validate()
    guard reference.matches(value) else { throw MobileAPITransportError.invalidResponse }
    return value
  }
  private func validate() async throws {
    try Task.checkCancellation()
    try await lifecycle.validate(lease)
    try await transport.validateOriginalSession(lease)
    try Task.checkCancellation()
  }
}
