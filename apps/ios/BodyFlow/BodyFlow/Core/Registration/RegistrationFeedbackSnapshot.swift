import Foundation

/// A persisted presentation, never a client-side calculation or phrase selection.
struct RegistrationFeedbackSnapshot: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case meal, workout }
    enum Locale: String, Codable, Sendable { case portuguese = "pt-BR", english = "en" }

    struct Nutrients: Codable, Hashable, Sendable {
        let kcal: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        private enum CodingKeys: String, CodingKey {
            case kcal, proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g"
        }
        var isValid: Bool { [kcal, proteinG, carbsG, fatG].allSatisfy(validNumber) }
    }

    struct Day: Codable, Hashable, Sendable {
        struct Consumed: Codable, Hashable, Sendable {
            let caloriesKcal: Double
            let proteinG: Double
            let carbsG: Double
            let fatG: Double
            private enum CodingKeys: String, CodingKey {
                case caloriesKcal = "calories_kcal", proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g"
            }
            var isValid: Bool { [caloriesKcal, proteinG, carbsG, fatG].allSatisfy(validNumber) }
        }
        struct Targets: Codable, Hashable, Sendable {
            let caloriesKcal: Double?
            let proteinG: Double?
            private enum CodingKeys: String, CodingKey { case caloriesKcal = "calories_kcal", proteinG = "protein_g" }
            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                caloriesKcal = try values.requiredNullable(Double.self, forKey: .caloriesKcal)
                proteinG = try values.requiredNullable(Double.self, forKey: .proteinG)
            }
            func encode(to encoder: any Encoder) throws {
                var values = encoder.container(keyedBy: CodingKeys.self)
                try values.encode(caloriesKcal, forKey: .caloriesKcal)
                try values.encode(proteinG, forKey: .proteinG)
            }
            var isValid: Bool {
                [caloriesKcal, proteinG].allSatisfy { $0.map { validNumber($0) && $0 > 0 } ?? true }
            }
        }
        let localDate: String
        let currentProtocol: String?
        let remainingFoodKcal: Double?
        let foodExcessKcal: Double?
        let exerciseKcal: Double
        let consumed: Consumed
        let targets: Targets
        let caloriePercentage: Double?
        let proteinPercentage: Double?

        private enum CodingKeys: String, CodingKey {
            case localDate = "local_date", currentProtocol = "current_protocol"
            case remainingFoodKcal = "remaining_food_kcal", foodExcessKcal = "food_excess_kcal"
            case exerciseKcal = "exercise_kcal", consumed, targets
            case caloriePercentage = "calorie_percentage", proteinPercentage = "protein_percentage"
        }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            localDate = try values.decode(String.self, forKey: .localDate)
            currentProtocol = try values.requiredNullable(String.self, forKey: .currentProtocol)
            remainingFoodKcal = try values.requiredNullable(Double.self, forKey: .remainingFoodKcal)
            foodExcessKcal = try values.requiredNullable(Double.self, forKey: .foodExcessKcal)
            exerciseKcal = try values.decode(Double.self, forKey: .exerciseKcal)
            consumed = try values.decode(Consumed.self, forKey: .consumed)
            targets = try values.decode(Targets.self, forKey: .targets)
            caloriePercentage = try values.requiredNullable(Double.self, forKey: .caloriePercentage)
            proteinPercentage = try values.requiredNullable(Double.self, forKey: .proteinPercentage)
        }
        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(localDate, forKey: .localDate)
            try values.encode(currentProtocol, forKey: .currentProtocol)
            try values.encode(remainingFoodKcal, forKey: .remainingFoodKcal)
            try values.encode(foodExcessKcal, forKey: .foodExcessKcal)
            try values.encode(exerciseKcal, forKey: .exerciseKcal)
            try values.encode(consumed, forKey: .consumed)
            try values.encode(targets, forKey: .targets)
            try values.encode(caloriePercentage, forKey: .caloriePercentage)
            try values.encode(proteinPercentage, forKey: .proteinPercentage)
        }
        var isValid: Bool {
            validCivilDate(localDate) &&
            (currentProtocol.map { ["recomposicao", "ganho_massa", "manutencao"].contains($0) } ?? true) &&
            validNumber(exerciseKcal) && consumed.isValid && targets.isValid &&
            [remainingFoodKcal, foodExcessKcal, caloriePercentage, proteinPercentage]
                .allSatisfy { $0.map(validNumber) ?? true } &&
            (targets.caloriesKcal == nil) == (caloriePercentage == nil) &&
            (targets.proteinG == nil) == (proteinPercentage == nil)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schema, forKey: .schema)
        try values.encode(registrationID, forKey: .registrationID)
        try values.encode(kind, forKey: .kind)
        try values.encode(locale, forKey: .locale)
        try values.encode(mealTotals, forKey: .mealTotals)
        try values.encode(day, forKey: .day)
        try values.encode(lines, forKey: .lines)
        try values.encode(foodComment, forKey: .foodComment)
        try values.encode(incentive, forKey: .incentive)
    }

    struct Line: Codable, Hashable, Sendable {
        enum Key: String, Codable, Sendable {
            case mealTotals = "meal_totals", dayCalories = "day_calories", dayProtein = "day_protein"
            case foodBudget = "food_budget", dayUnavailable = "day_unavailable"
        }
        let key: Key
        let text: String
    }

    let schema: String
    let registrationID: String
    let kind: Kind
    let locale: Locale
    let mealTotals: Nutrients?
    let day: Day?
    let lines: [Line]
    let foodComment: String?
    let incentive: String?

    private enum CodingKeys: String, CodingKey {
        case schema, registrationID = "registration_id", kind, locale
        case mealTotals = "meal_totals", day, lines, foodComment = "food_comment", incentive
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        registrationID = try values.decode(String.self, forKey: .registrationID)
        kind = try values.decode(Kind.self, forKey: .kind)
        locale = try values.decode(Locale.self, forKey: .locale)
        mealTotals = try values.requiredNullable(Nutrients.self, forKey: .mealTotals)
        day = try values.requiredNullable(Day.self, forKey: .day)
        lines = try values.decode([Line].self, forKey: .lines)
        foodComment = try values.requiredNullable(String.self, forKey: .foodComment)
        incentive = try values.requiredNullable(String.self, forKey: .incentive)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid optional registration feedback"))
        }
    }

    var isValid: Bool {
        let keys = Set(lines.map(\.key))
        return schema == "registration.feedback.v1" && registrationID.utf8.count == 36 &&
            UUID(uuidString: registrationID) != nil &&
            (1...5).contains(lines.count) && keys.count == lines.count &&
            lines.allSatisfy { validText($0.text) } &&
            [foodComment, incentive].allSatisfy { $0.map(validText) ?? true } &&
            (locale != .english || (foodComment == nil && incentive == nil)) &&
            (kind == .meal) == (mealTotals != nil) &&
            (kind == .meal) == keys.contains(.mealTotals) &&
            (mealTotals?.isValid ?? true) && (kind != .workout || foodComment == nil) &&
            (day.map { $0.isValid && !keys.contains(.dayUnavailable) && keys.contains(.dayCalories) && keys.contains(.dayProtein) }
                ?? (keys.contains(.dayUnavailable) && keys.isDisjoint(with: [.dayCalories, .dayProtein, .foodBudget])))
    }

    func bound(to id: String, status: String, proposal: RegistrationProposalSnapshot) -> Self? {
        guard status == "confirmed", registrationID == id, isValid else { return nil }
        switch proposal {
        case .meal: return kind == .meal ? self : nil
        case .workout: return kind == .workout ? self : nil
        case .unknown: return nil
        }
    }
}

private func validNumber(_ value: Double) -> Bool {
    value.isFinite && value >= 0 && value <= 9_007_199_254_740_991
}

private func validText(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 4000
}

private func validCivilDate(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
          bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) })
    else { return false }
    let parts = value.split(separator: "-")
    guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
          (1...12).contains(month) else { return false }
    // Match the server's proleptic Gregorian civil date, without timezone or historical cutover.
    let leapYear = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
    let monthLengths = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return (1...monthLengths[month - 1]).contains(day)
}

private extension KeyedDecodingContainer {
    func requiredNullable<Value: Decodable>(_ type: Value.Type, forKey key: Key) throws -> Value? {
        guard contains(key) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath,
                debugDescription: "Missing nullable feedback field"))
        }
        return try decodeIfPresent(type, forKey: key)
    }
}
