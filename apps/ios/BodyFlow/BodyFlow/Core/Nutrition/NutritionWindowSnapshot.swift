import Foundation

/// A complete owned read observation. It conveys no clinical or write authority.
struct NutritionWindowSnapshot: Decodable, Sendable {
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
  let days: [NutritionWindowDay]
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
    let policyClock = try c.decode(NutritionPolicyClock.self, forKey: .clinicalPolicy)
    days = try c.decode([NutritionWindowDay].self, forKey: .days)
    guard schema == "nutrition.window.v1", completeness == "complete", nutritionHash(sourceVersion),
      let zone = TimeZone(identifier: timezone),
      let observed = ConversationProtocolInstant(observedAt),
      let policyTime = ConversationProtocolInstant(policyClock.observedAt), policyTime <= observed,
      NutritionCivilDate.date(currentLocalDate) != nil,
      let start = NutritionCivilDate.date(weekStart),
      NutritionCivilDate.calendar.component(.weekday, from: start) == 2,
      days.count == 7, weekEnd == NutritionCivilDate.add(weekStart, days: 6),
      days.enumerated().allSatisfy({
        $0.element.localDate == NutritionCivilDate.add(weekStart, days: $0.offset)
      }),
      days.contains(where: { $0.localDate == selectedLocalDate }),
      days.flatMap(\.meals).count <= 1000,
      Set(days.flatMap(\.meals).map(\.id)).count == days.flatMap(\.meals).count
    else { throw MobileAPITransportError.invalidResponse }
    for day in days {
      try day.validate(zone: zone, observed: observed, policy: clinicalPolicy)
    }
  }
}

struct NutritionWindowDay: Decodable, Identifiable, Sendable {
  var id: String { localDate }
  let localDate: String
  let dayClosed: Bool?
  let dayVersion: String?
  let meals: [NutritionWindowMeal]
  let totals: NutritionWindowTotals
  let targets: NutritionWindowTargets
  let planned: NutritionWindowPlanned
  enum CodingKeys: String, CodingKey {
    case meals, totals, targets, planned
    case localDate = "local_date"
    case dayClosed = "day_closed"
    case dayVersion = "day_version"
  }
  fileprivate func validate(
    zone: TimeZone, observed: ConversationProtocolInstant, policy: CurrentClinicalPolicy
  ) throws {
    let amounts = [totals.kcal, totals.proteinG, totals.carbsG, totals.fatG]
    guard amounts.allSatisfy(nutritionAmount), nutritionAmount(targets.caloriesKcal),
      nutritionAmount(targets.proteinG),
      !policy.hide.calories || targets.caloriesKcal == nil,
      !policy.hide.protein || targets.proteinG == nil
    else { throw MobileAPITransportError.invalidResponse }
    if let dayVersion {
      guard let clock = ConversationProtocolInstant(dayVersion), clock <= observed else {
        throw MobileAPITransportError.invalidResponse
      }
    }
    switch totals.source {
    case .unavailable:
      guard amounts.allSatisfy({ $0 == nil }) else { throw MobileAPITransportError.invalidResponse }
    case .emptyConfirmedSet:
      guard meals.isEmpty, dayVersion == nil, dayClosed == nil, amounts.allSatisfy({ $0 == 0 })
      else {
        throw MobileAPITransportError.invalidResponse
      }
    case .dailySnapshot:
      guard dayVersion != nil, dayClosed != nil, amounts.allSatisfy({ $0 != nil }) else {
        throw MobileAPITransportError.invalidResponse
      }
    }
    if targets.source == .unavailable {
      guard targets.caloriesKcal == nil, targets.proteinG == nil else {
        throw MobileAPITransportError.invalidResponse
      }
    } else if dayVersion == nil {
      throw MobileAPITransportError.invalidResponse
    }
    for meal in meals {
      if let display = meal.displayQuantity, display.provenance != .auditedSameFoodScale {
        guard meal.quantityG == display.reference.quantityG,
          display.value == display.reference.value
        else {
          throw MobileAPITransportError.invalidResponse
        }
      }
      guard nutritionHash(meal.registrationKey), !meal.foodName.isEmpty,
        meal.foodName.utf8.count <= 2000,
        [meal.quantityG, meal.kcal, meal.proteinG, meal.carbsG, meal.fatG].allSatisfy(
          nutritionAmount),
        let clock = ConversationProtocolInstant(meal.consumedAt),
        NutritionCivilDate.string(Date(timeIntervalSince1970: Double(clock.seconds)), zone: zone)
          == localDate
      else { throw MobileAPITransportError.invalidResponse }
    }
    try planned.validate(policy: policy)
  }
}
struct NutritionWindowMeal: Decodable, Identifiable, Sendable {
  let id: UUID
  let registrationKey: String
  let displayQuantity: NutritionDisplayQuantity?
  let mealType: String?
  let foodName: String
  let quantityG: Decimal?
  let kcal: Decimal?
  let proteinG: Decimal?
  let carbsG: Decimal?
  let fatG: Decimal?
  let consumedAt: String
  let nutritionSource: String?
  enum CodingKeys: String, CodingKey {
    case id, kcal
    case displayQuantity = "display_quantity"
    case registrationKey = "registration_key"
    case mealType = "meal_type"
    case foodName = "food_name"
    case quantityG = "quantity_g"
    case proteinG = "protein_g"
    case carbsG = "carbs_g"
    case fatG = "fat_g"
    case consumedAt = "consumed_at"
    case nutritionSource = "nutrition_source"
  }
}
struct NutritionWindowTotals: Decodable, Sendable {
  enum Source: String, Decodable, Sendable {
    case dailySnapshot = "daily_snapshot"
    case emptyConfirmedSet = "empty_confirmed_set"
    case unavailable
  }
  let source: Source
  let kcal: Decimal?
  let proteinG: Decimal?
  let carbsG: Decimal?
  let fatG: Decimal?
  enum CodingKeys: String, CodingKey {
    case source, kcal
    case proteinG = "protein_g"
    case carbsG = "carbs_g"
    case fatG = "fat_g"
  }
}
struct NutritionWindowTargets: Decodable, Sendable {
  enum Source: String, Decodable, Sendable {
    case dailySnapshot = "daily_snapshot"
    case unavailable
  }
  let source: Source
  let caloriesKcal: Decimal?
  let proteinG: Decimal?
  enum CodingKeys: String, CodingKey {
    case source
    case caloriesKcal = "calories_kcal"
    case proteinG = "protein_g"
  }
}
struct NutritionWindowPlanned: Decodable, Sendable {
  enum Status: String, Decodable, Sendable { case available, none, partial, unavailable, protected }
  let status: Status
  let meals: [NutritionWindowPlannedMeal]
  let unavailablePrescriptionIDs: [UUID]
  enum CodingKeys: String, CodingKey {
    case status, meals
    case unavailablePrescriptionIDs = "unavailable_prescription_ids"
  }
  fileprivate func validate(policy: CurrentClinicalPolicy) throws {
    guard meals.count <= 840, Set(meals.map(\.id)).count == meals.count,
      Set(unavailablePrescriptionIDs).count == unavailablePrescriptionIDs.count
    else { throw MobileAPITransportError.invalidResponse }
    switch status {
    case .none, .protected:
      guard meals.isEmpty, unavailablePrescriptionIDs.isEmpty else {
        throw MobileAPITransportError.invalidResponse
      }
    case .unavailable:
      guard meals.isEmpty, !unavailablePrescriptionIDs.isEmpty else {
        throw MobileAPITransportError.invalidResponse
      }
    case .partial:
      guard !unavailablePrescriptionIDs.isEmpty else {
        throw MobileAPITransportError.invalidResponse
      }
    case .available:
      guard unavailablePrescriptionIDs.isEmpty else {
        throw MobileAPITransportError.invalidResponse
      }
    }
    if policy.pauseWeightLossGuidance || policy.hide.objective || policy.hide.calories
      || policy.hide.protein
    {
      guard status == .protected else { throw MobileAPITransportError.invalidResponse }
    }
    for meal in meals {
      guard meal.id.hasPrefix(meal.prescriptionID.uuidString.lowercased() + "/"),
        ConversationProtocolInstant(meal.generatedAt) != nil,
        meal.validUntil.map({ ConversationProtocolInstant($0) != nil }) ?? true,
        !meal.items.isEmpty, meal.items.count <= 50,
        [meal.totalKcal, meal.totalProteinG].allSatisfy(nutritionAmount)
      else { throw MobileAPITransportError.invalidResponse }
      for item in meal.items {
        guard !item.foodName.isEmpty,
          [item.quantityG, item.kcal, item.proteinG, item.carbsG, item.fatG].allSatisfy(
            nutritionAmount)
        else {
          throw MobileAPITransportError.invalidResponse
        }
      }
    }
  }
}
struct NutritionWindowPlannedMeal: Decodable, Identifiable, Sendable {
  let id: String
  let prescriptionID: UUID
  let generatedAt: String
  let validUntil: String?
  let mealType: String
  let dayOfWeek: Int?
  let timeSuggestion: String?
  let notes: String?
  let totalKcal: Decimal?
  let totalProteinG: Decimal?
  let items: [NutritionWindowPlannedItem]
  enum CodingKeys: String, CodingKey {
    case id, notes, items
    case prescriptionID = "prescription_id"
    case generatedAt = "generated_at"
    case validUntil = "valid_until"
    case mealType = "meal_type"
    case dayOfWeek = "day_of_week"
    case timeSuggestion = "time_suggestion"
    case totalKcal = "total_kcal"
    case totalProteinG = "total_protein_g"
  }
}
struct NutritionWindowPlannedItem: Decodable, Sendable {
  let foodName: String
  let quantityG: Decimal
  let kcal: Decimal?
  let proteinG: Decimal?
  let carbsG: Decimal?
  let fatG: Decimal?
  let displayQty: Decimal?
  let displayUnit: String?
  enum CodingKeys: String, CodingKey {
    case kcal
    case foodName = "food_name"
    case quantityG = "quantity_g"
    case proteinG = "protein_g"
    case carbsG = "carbs_g"
    case fatG = "fat_g"
    case displayQty = "display_qty"
    case displayUnit = "display_unit"
  }
}
private func nutritionHash(_ value: String) -> Bool {
  value.utf8.count == 64
    && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
private func nutritionAmount(_ value: Decimal?) -> Bool {
  value.map { !$0.isNaN && $0 >= 0 && $0 <= Decimal(9_007_199_254_740_991 as Int64) } ?? true
}
/// Gregorian civil arithmetic only; it never supplies the authoritative today.
enum NutritionCivilDate {
  static var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }
  static func date(_ raw: String) -> Date? {
    guard raw.count == 10, raw.utf8.allSatisfy({ $0 == 45 || (48...57).contains($0) }) else {
      return nil
    }
    let parts = raw.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, parts[0] > 0,
      let value = calendar.date(
        from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), string(value) == raw
    else { return nil }
    return value
  }
  static func string(_ date: Date, zone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> String {
    var cal = calendar
    cal.timeZone = zone
    let parts = cal.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }
  static func add(_ raw: String, days: Int) -> String? {
    guard let date = date(raw), let result = calendar.date(byAdding: .day, value: days, to: date)
    else { return nil }
    return string(result)
  }
}

private struct NutritionPolicyClock: Decodable {
  let observedAt: String
  enum CodingKeys: String, CodingKey { case observedAt = "observed_at" }
}

/// Only the owned server read proves this current fact/reference lineage.
struct NutritionDisplayQuantity: Decodable, Sendable {
  enum Provenance: String, Decodable, Sendable {
    case sealedOriginal = "sealed_original"
    case auditedRestore = "audited_restore"
    case auditedSameFoodScale = "audited_same_food_scale"
  }
  struct Reference: Decodable, Sendable {
    let originalLogID: UUID
    let value: Decimal
    let unit: String
    let quantityG: Decimal
    let quantityBasis: String
    enum CodingKeys: String, CodingKey {
      case value, unit
      case originalLogID = "original_log_id"
      case quantityG = "quantity_g"
      case quantityBasis = "quantity_basis"
    }
  }
  let value: Decimal
  let unit: String
  let estimated: Bool
  let provenance: Provenance
  let reference: Reference
  enum CodingKeys: String, CodingKey { case value, unit, estimated, provenance, reference }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    value = try c.decode(Decimal.self, forKey: .value)
    unit = try c.decode(String.self, forKey: .unit)
    estimated = try c.decode(Bool.self, forKey: .estimated)
    provenance = try c.decode(Provenance.self, forKey: .provenance)
    reference = try c.decode(Reference.self, forKey: .reference)
    guard !value.isNaN, value > 0, value <= 999999,
      !reference.value.isNaN, reference.value > 0, reference.value <= 999999,
      !reference.quantityG.isNaN, reference.quantityG > 0, reference.quantityG <= 9999,
      !unit.isEmpty, unit.utf16.count <= 40,
      unit == unit.trimmingCharacters(in: .whitespacesAndNewlines),
      unit == reference.unit,
      ["stated", "portion_reference", "visual_estimate"].contains(reference.quantityBasis),
      reference.quantityBasis != "visual_estimate" || estimated,
      provenance != .auditedSameFoodScale || estimated
    else { throw MobileAPITransportError.invalidResponse }
  }
}
