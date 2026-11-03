import Foundation

/// Closed, immutable v2 receipt. Only the authenticated server establishes ownership and facts.
/// The client validates consistency and formats saved facts; it never supplies goals or credits.
struct RegistrationFeedbackV2Snapshot: Codable, Hashable, Sendable {
    typealias Kind = RegistrationFeedbackSnapshot.Kind
    typealias Locale = RegistrationFeedbackSnapshot.Locale
    typealias Nutrients = RegistrationFeedbackSnapshot.Nutrients

    struct Quantity: Hashable, Sendable {
        let value: Double
        let unit: String
        let estimated: Bool
        let referenceID: String?
    }
    struct MealItem: Hashable, Sendable {
        let logID: String
        let foodName: String
        let quantityG: Double
        let quantity: Quantity
        let nutritionSource: String
        let nutrients: Nutrients
    }
    struct Meal: Hashable, Sendable {
        let mealKind: String
        let items: [MealItem]
        let totals: Nutrients
    }
    struct Workout: Hashable, Sendable {
        let logID: String
        let workoutType: String
        let durationMin: Double?
        let intensity: String?
        let estimatedKcal: Double?
    }
    enum Registration: Hashable, Sendable { case meal(Meal), workout(Workout) }
    struct Day: Hashable, Sendable {
        let localDate: String
        let currentProtocol: String?
        let consumed: Nutrients
        let caloriesTarget: Double?
        let proteinTarget: Double?
        let caloriePercentage: Double?
        let proteinPercentage: Double?
        let remainingFoodKcal: Double?
        let foodExcessKcal: Double?
        let exerciseKcal: Double
    }
    struct AvailableBlock: Hashable, Sendable {
        let targetKcal: Double
        let currentKcal: Double
        let percentage: Double
        let completedBlocks: Double
        let totalCreditedKcal: Double
    }
    enum Block: Hashable, Sendable {
        case available(AvailableBlock), unavailable, notApplicable, protected
    }
    enum Guidance: String, Hashable, Sendable { case available, paused, unavailable }
    struct Education: Hashable, Sendable {
        let text: String
        let templateID: String
        let preferencesKnown: Bool
    }

    let registrationID: String
    let localDate: String
    let locale: Locale
    let registration: Registration
    let day: Day?
    let block: Block
    let guidance: Guidance
    let education: Education?
    // Retain explicit nulls and the exact closed wire shape for historical round trips.
    private let wire: FeedbackV2Value

    var kind: Kind { if case .meal = registration { .meal } else { .workout } }

    init(from decoder: any Decoder) throws {
        let wire = try FeedbackV2Value(from: decoder)
        do { self = try Self(wire: wire) }
        catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid optional registration feedback v2"))
        }
    }
    func encode(to encoder: any Encoder) throws { try wire.encode(to: encoder) }

    private init(wire: FeedbackV2Value) throws {
        let o = try wire.object(["schema", "registration_id", "local_date", "locale", "assistant",
                                "registration", "day", "block", "guidance", "education"])
        try require(o["schema"]?.string() == "registration.feedback.v2")
        try require(o["assistant"]?.string() == "Flow AI")
        registrationID = try o.value("registration_id").uuid()
        localDate = try o.value("local_date").date()
        guard let locale = Locale(rawValue: try o.value("locale").string()),
              let guidance = Guidance(rawValue: try o.value("guidance").string()) else { throw InvalidReceipt.value }
        self.locale = locale
        self.guidance = guidance
        registration = try Self.registration(o.value("registration"))
        day = try o.value("day").nullable(Self.day)
        block = try Self.block(o.value("block"))
        education = try Self.education(o.value("education"))
        self.wire = try Self.normalizingText(wire, registration: registration)
        try validateRelations()
    }

    private static func registration(_ raw: FeedbackV2Value) throws -> Registration {
        let kind = try raw.member("kind").string()
        if kind == "meal" {
            let o = try raw.object(["kind", "meal_kind", "items", "totals"])
            let mealKind = try o.value("meal_kind").oneOf(["cafe", "almoco", "lanche", "jantar", "ceia", "outro"])
            let items = try o.value("items").array().map(item)
            try require((1...30).contains(items.count) && Set(items.map(\.logID)).count == items.count)
            return .meal(Meal(mealKind: mealKind, items: items, totals: try nutrients(o.value("totals"))))
        }
        try require(kind == "workout")
        let o = try raw.object(["kind", "log_id", "workout_type", "duration_min", "intensity", "estimated_kcal"])
        return .workout(Workout(logID: try o.value("log_id").uuid(),
            workoutType: try o.value("workout_type").text(),
            durationMin: try o.value("duration_min").nullable { try $0.amount(positive: true, max: 1440) },
            intensity: try o.value("intensity").nullable { try $0.text() },
            estimatedKcal: try o.value("estimated_kcal").nullable { try $0.amount() }))
    }
    private static func nutrients(_ raw: FeedbackV2Value) throws -> Nutrients {
        let o = try raw.object(["kcal", "protein_g", "carbs_g", "fat_g"])
        return Nutrients(kcal: try o.value("kcal").amount(), proteinG: try o.value("protein_g").amount(),
                         carbsG: try o.value("carbs_g").amount(), fatG: try o.value("fat_g").amount())
    }
    private static func item(_ raw: FeedbackV2Value) throws -> MealItem {
        let o = try raw.object(["log_id", "food_name", "quantity_g", "quantity", "nutrition_source",
                                "kcal", "protein_g", "carbs_g", "fat_g"])
        let mass = try o.value("quantity_g").amount(positive: true, max: 9999)
        let q = try o.value("quantity").object(["value", "unit", "estimated", "reference_id"])
        let quantity = Quantity(value: try q.value("value").amount(positive: true, max: 999999),
            unit: try q.value("unit").oneOf(["g", "mL", "unit", "scoop"]),
            estimated: try q.value("estimated").bool(),
            referenceID: try q.value("reference_id").nullable { try $0.text() })
        try require(quantity.unit != "g" || close(quantity.value, mass))
        try require(!quantity.estimated || quantity.unit == "g" || quantity.referenceID != nil)
        return MealItem(logID: try o.value("log_id").uuid(), foodName: try o.value("food_name").text(),
            quantityG: mass, quantity: quantity,
            nutritionSource: try o.value("nutrition_source").oneOf(["taco", "canonical_exact", "canonical_fuzzy",
                "canonical_composite", "canonical_composite_partial", "rule_based", "user_correction", "history",
                "user_kcal", "product_label", "pending_approved", "llm_estimate"]),
            nutrients: Nutrients(kcal: try o.value("kcal").amount(), proteinG: try o.value("protein_g").amount(),
                carbsG: try o.value("carbs_g").amount(), fatG: try o.value("fat_g").amount()))
    }
    private static func day(_ raw: FeedbackV2Value) throws -> Day {
        let o = try raw.object(["local_date", "current_protocol", "consumed", "targets", "calorie_percentage",
            "protein_percentage", "remaining_food_kcal", "food_excess_kcal", "exercise_kcal"])
        let c = try o.value("consumed").object(["calories_kcal", "protein_g", "carbs_g", "fat_g"])
        let t = try o.value("targets").object(["calories_kcal", "protein_g"])
        return Day(localDate: try o.value("local_date").date(),
            currentProtocol: try o.value("current_protocol").nullable { try $0.oneOf(["recomposicao", "ganho_massa", "manutencao"]) },
            consumed: Nutrients(kcal: try c.value("calories_kcal").amount(), proteinG: try c.value("protein_g").amount(),
                                carbsG: try c.value("carbs_g").amount(), fatG: try c.value("fat_g").amount()),
            caloriesTarget: try t.value("calories_kcal").nullable { try $0.amount(positive: true) },
            proteinTarget: try t.value("protein_g").nullable { try $0.amount(positive: true) },
            caloriePercentage: try o.value("calorie_percentage").nullable { try $0.amount() },
            proteinPercentage: try o.value("protein_percentage").nullable { try $0.amount() },
            remainingFoodKcal: try o.value("remaining_food_kcal").nullable { try $0.amount() },
            foodExcessKcal: try o.value("food_excess_kcal").nullable { try $0.amount() },
            exerciseKcal: try o.value("exercise_kcal").amount())
    }
    private static func block(_ raw: FeedbackV2Value) throws -> Block {
        let status = try raw.member("status").string()
        if status == "available" {
            let o = try raw.object(["status", "target_kcal", "current_kcal", "percentage", "completed_blocks", "total_credited_kcal"])
            let b = AvailableBlock(targetKcal: try o.value("target_kcal").amount(),
                currentKcal: try o.value("current_kcal").amount(), percentage: try o.value("percentage").amount(),
                completedBlocks: try o.value("completed_blocks").amount(), totalCreditedKcal: try o.value("total_credited_kcal").amount())
            try require(b.targetKcal == 7700 && b.completedBlocks.rounded(.towardZero) == b.completedBlocks)
            try require(b.percentage == (b.currentKcal / b.targetKcal * 100).rounded(.toNearestOrAwayFromZero))
            try require(close(b.totalCreditedKcal, b.completedBlocks * b.targetKcal + b.currentKcal))
            return .available(b)
        }
        _ = try raw.object(["status"])
        switch status {
        case "unavailable": return .unavailable
        case "not_applicable": return .notApplicable
        case "protected": return .protected
        default: throw InvalidReceipt.value
        }
    }
    private static func education(_ raw: FeedbackV2Value) throws -> Education? {
        let status = try raw.member("status").string()
        if status == "unavailable" { _ = try raw.object(["status"]); return nil }
        try require(status == "available")
        let o = try raw.object(["status", "text", "provenance"])
        let p = try o.value("provenance").object(["source", "catalog_version", "template_id", "preferences_known"])
        try require(p["source"]?.string() == "reviewed_template" && p["catalog_version"]?.string() == "registration.education.v1")
        let text = try o.value("text").string()
        try require((1...1600).contains(text.utf16.count))
        return Education(text: text, templateID: try p.value("template_id").string(),
                         preferencesKnown: try p.value("preferences_known").bool())
    }
    private func validateRelations() throws {
        if let d = day {
            try require(d.localDate == localDate)
            try require(d.caloriePercentage == Self.percentage(d.consumed.kcal, d.caloriesTarget))
            try require(d.proteinPercentage == Self.percentage(d.consumed.proteinG, d.proteinTarget))
            try require(d.caloriesTarget != nil || (d.remainingFoodKcal == nil && d.foodExcessKcal == nil))
            try require(!(d.remainingFoodKcal.map { $0 > 0 } == true && d.foodExcessKcal.map { $0 > 0 } == true))
            try require(guidance != .unavailable)
            if guidance == .paused { try require(d.currentProtocol == nil && d.caloriesTarget == nil && d.proteinTarget == nil) }
        }
        switch block {
        case .available: try require(day?.currentProtocol == "recomposicao" && guidance == .available)
        case .notApplicable: try require(day?.currentProtocol != nil && day?.currentProtocol != "recomposicao")
        case .unavailable, .protected: break
        }
        if let education {
            let expected = expectedEducation(preferencesKnown: education.preferencesKnown)
            // Swift String equality normalizes Unicode; the pinned server catalog compares code units.
            try require(education.text.utf16.elementsEqual(expected.text.utf16) && education.templateID == expected.templateID)
        }
    }
    // The server parser trims only its bounded text fields. Keep the same canonical
    // representation without changing quantities, nutrition or saved educational text.
    private static func normalizingText(_ wire: FeedbackV2Value, registration: Registration) throws -> FeedbackV2Value {
        var result = wire
        switch registration {
        case let .meal(meal):
            for (index, item) in meal.items.enumerated() {
                let path = ["registration", "items", String(index)]
                result = try result.setting(path + ["food_name"], to: .string(item.foodName))
                result = try result.setting(path + ["quantity", "reference_id"], to: item.quantity.referenceID.map(FeedbackV2Value.string) ?? .null)
            }
        case let .workout(workout):
            result = try result.setting(["registration", "workout_type"], to: .string(workout.workoutType))
            result = try result.setting(["registration", "intensity"], to: workout.intensity.map(FeedbackV2Value.string) ?? .null)
        }
        return result
    }

    /// ECMAScript trim characters; Foundation also trims NEL, which the server preserves.
    static func trimmedText(_ value: String) -> String {
        let whitespace = CharacterSet(charactersIn:
            "\u{9}\u{a}\u{b}\u{c}\u{d}\u{20}\u{a0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200a}\u{2028}\u{2029}\u{202f}\u{205f}\u{3000}\u{feff}")
        return value.trimmingCharacters(in: whitespace)
    }

    private static func percentage(_ value: Double, _ target: Double?) -> Double? {
        target.map { (value / $0 * 1000).rounded(.toNearestOrAwayFromZero) / 10 }
    }
}

private enum InvalidReceipt: Error { case value }
private func require(_ condition: Bool) throws { if !condition { throw InvalidReceipt.value } }
private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000001 }

/// A private decoder value preserves explicit nulls; exact object keys are checked at every level.
private indirect enum FeedbackV2Value: Codable, Hashable, Sendable {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([Self].self) { self = .array(a) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .object(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .bool(v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    func object(_ keys: [String]) throws -> [String: Self] {
        guard case let .object(value) = self, Set(value.keys) == Set(keys) else { throw InvalidReceipt.value }
        return value
    }
    func member(_ key: String) throws -> Self {
        guard case let .object(value) = self else { throw InvalidReceipt.value }
        return try value.value(key)
    }
    func array() throws -> [Self] { guard case let .array(v) = self else { throw InvalidReceipt.value }; return v }
    func string() throws -> String { guard case let .string(v) = self else { throw InvalidReceipt.value }; return v }
    func bool() throws -> Bool { guard case let .bool(v) = self else { throw InvalidReceipt.value }; return v }
    func oneOf(_ allowed: [String]) throws -> String { let s = try string(); try require(allowed.contains(s)); return s }
    func amount(positive: Bool = false, max: Double = 9_007_199_254_740_991) throws -> Double {
        guard case let .number(v) = self else { throw InvalidReceipt.value }
        try require(v.isFinite && (positive ? v > 0 : v >= 0) && v <= max)
        return v
    }
    func text() throws -> String {
        let value = RegistrationFeedbackV2Snapshot.trimmedText(try string())
        try require((1...240).contains(value.utf16.count)); return value
    }
    func uuid() throws -> String {
        let s = try string(); try require(s.utf8.count == 36 && UUID(uuidString: s) != nil); return s
    }
    func date() throws -> String {
        let s = try string(), b = Array(s.utf8)
        try require(b.count == 10)
        try require(b[4] == 45 && b[7] == 45 && b.enumerated().allSatisfy { $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) })
        let parts = s.split(separator: "-")
        guard let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { throw InvalidReceipt.value }
        let leap = y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)
        try require((1...[31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]).contains(d))
        return s
    }
    func setting(_ path: [String], to value: Self) throws -> Self {
        guard let key = path.first else { return value }
        switch self {
        case var .object(o):
            o[key] = try o.value(key).setting(Array(path.dropFirst()), to: value)
            return .object(o)
        case var .array(a):
            guard let index = Int(key), a.indices.contains(index) else { throw InvalidReceipt.value }
            a[index] = try a[index].setting(Array(path.dropFirst()), to: value)
            return .array(a)
        default: throw InvalidReceipt.value
        }
    }
    func nullable<T>(_ parse: (Self) throws -> T) throws -> T? { if case .null = self { nil } else { try parse(self) } }
}
private extension Dictionary where Key == String, Value == FeedbackV2Value {
    func value(_ key: String) throws -> Value { guard let v = self[key] else { throw InvalidReceipt.value }; return v }
}
