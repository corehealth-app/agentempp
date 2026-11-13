import Foundation

/// A complete owned read observation. It conveys no clinical or write authority.
struct TrainingWindowSnapshot: Decodable, Sendable {
  let schema: String
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let timezone: String
  let currentLocalDate: String
  let selectedLocalDate: String
  let weekStart: String
  let weekEnd: String
  let observedAt: String
  let sourceVersion: String
  let completeness: String
  let clinicalPolicy: CurrentClinicalPolicy
  let days: [TrainingWindowDay]
  enum CodingKeys: String, CodingKey {
    case schema, epoch, timezone, completeness, days
    case authUserID = "auth_user_id"
    case ownerID = "owner_id"
    case currentLocalDate = "current_local_date"
    case selectedLocalDate = "selected_local_date"
    case weekStart = "week_start"
    case weekEnd = "week_end"
    case observedAt = "observed_at"
    case sourceVersion = "source_version"
    case clinicalPolicy = "clinical_policy"
  }
  init(data: Data) throws {
    guard data.count <= 750_000 else { throw MobileAPITransportError.invalidResponse }
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schema = try c.decode(String.self, forKey: .schema)
    authUserID = try c.decode(UUID.self, forKey: .authUserID)
    ownerID = try c.decode(UUID.self, forKey: .ownerID)
    epoch = try c.decode(UUID.self, forKey: .epoch)
    timezone = try c.decode(String.self, forKey: .timezone)
    currentLocalDate = try c.decode(String.self, forKey: .currentLocalDate)
    selectedLocalDate = try c.decode(String.self, forKey: .selectedLocalDate)
    weekStart = try c.decode(String.self, forKey: .weekStart)
    weekEnd = try c.decode(String.self, forKey: .weekEnd)
    observedAt = try c.decode(String.self, forKey: .observedAt)
    sourceVersion = try c.decode(String.self, forKey: .sourceVersion)
    completeness = try c.decode(String.self, forKey: .completeness)
    clinicalPolicy = try c.decode(CurrentClinicalPolicy.self, forKey: .clinicalPolicy)
    let policyClock = try c.decode(TrainingPolicyClock.self, forKey: .clinicalPolicy)
    days = try c.decode([TrainingWindowDay].self, forKey: .days)
    guard schema == "training.window.v1", completeness == "complete",
      sourceVersion.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
      let zone = TimeZone(identifier: timezone),
      let observed = ConversationProtocolInstant(observedAt),
      let policyTime = ConversationProtocolInstant(policyClock.observedAt), policyTime <= observed,
      NutritionCivilDate.date(currentLocalDate) != nil,
      let start = NutritionCivilDate.date(weekStart),
      NutritionCivilDate.calendar.component(.weekday, from: start) == 2,
      days.count == 7, weekEnd == NutritionCivilDate.add(weekStart, days: 6),
      days.enumerated().allSatisfy({
        $0.element.localDate == NutritionCivilDate.add(weekStart, days: $0.offset)
      }), days.contains(where: { $0.localDate == selectedLocalDate }),
      days.flatMap(\.workouts).count <= 1000,
      Set(days.flatMap(\.workouts).map(\.id)).count == days.flatMap(\.workouts).count
    else { throw MobileAPITransportError.invalidResponse }
    for day in days {
      for workout in day.workouts {
        guard let instant = ConversationProtocolInstant(workout.performedAt), instant <= observed,
          NutritionCivilDate.string(
            Date(timeIntervalSince1970: Double(instant.seconds)), zone: zone) == day.localDate,
          workout.workoutType.map({ !$0.isEmpty && $0.utf16.count <= 240 }) ?? true,
          workout.intensity.map({ !$0.isEmpty && $0.utf16.count <= 240 }) ?? true,
          workout.durationMin.map({ $0 > 0 && Self.validAmount($0) }) ?? true,
          workout.estimatedKcal.map(Self.validAmount) ?? true
        else { throw MobileAPITransportError.invalidResponse }
      }
    }
  }
  private static func validAmount(_ value: Decimal) -> Bool {
    NSDecimalNumber(decimal: value).doubleValue.isFinite && value >= 0
      && value <= 9_007_199_254_740_991
  }
}
struct TrainingWindowDay: Decodable, Identifiable, Sendable {
  var id: String { localDate }
  let localDate: String
  let workouts: [TrainingWindowActivity]
  enum CodingKeys: String, CodingKey {
    case localDate = "local_date"
    case workouts
  }
}
struct TrainingWindowActivity: Decodable, Identifiable, Sendable {
  let id: UUID
  let workoutType: String?
  let durationMin: Decimal?
  let estimatedKcal: Decimal?
  let intensity: String?
  let performedAt: String
  enum CodingKeys: String, CodingKey {
    case id, intensity
    case workoutType = "workout_type"
    case durationMin = "duration_min"
    case estimatedKcal = "estimated_kcal"
    case performedAt = "performed_at"
  }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    guard
      [.id, .workoutType, .durationMin, .estimatedKcal, .intensity, .performedAt].allSatisfy(
        c.contains)
    else { throw MobileAPITransportError.invalidResponse }
    id = try c.decode(UUID.self, forKey: .id)
    workoutType = try c.decodeIfPresent(String.self, forKey: .workoutType)
    durationMin = try c.decodeIfPresent(Decimal.self, forKey: .durationMin)
    estimatedKcal = try c.decodeIfPresent(Decimal.self, forKey: .estimatedKcal)
    intensity = try c.decodeIfPresent(String.self, forKey: .intensity)
    performedAt = try c.decode(String.self, forKey: .performedAt)
  }
}
private struct TrainingPolicyClock: Decodable {
  let observedAt: String
  enum CodingKeys: String, CodingKey { case observedAt = "observed_at" }
}
