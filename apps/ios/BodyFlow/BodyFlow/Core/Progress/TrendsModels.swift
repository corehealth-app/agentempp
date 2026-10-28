import Foundation

/// Series for the charts, exactly as the server stored them: one entry per
/// day that has a snapshot (gaps stay gaps) and the dated weights from the
/// reevaluations. Nothing here is estimated or filled in.
struct TrendsDay: Codable, Equatable, Sendable, Identifiable {
    let date: String
    let caloriesConsumed: Int
    let caloriesTarget: Int?
    let exerciseCalories: Int
    let proteinG: Decimal
    let proteinTarget: Decimal?
    let waterConsumedML: Int
    let deficitAccumulated: Int?
    let xpEarned: Int
    let dayClosed: Bool

    var id: String { date }

    private enum CodingKeys: String, CodingKey {
        case date
        case caloriesConsumed = "calories_consumed"
        case caloriesTarget = "calories_target"
        case exerciseCalories = "exercise_calories"
        case proteinG = "protein_g"
        case proteinTarget = "protein_target"
        case waterConsumedML = "water_consumed_ml"
        case deficitAccumulated = "deficit_accumulated"
        case xpEarned = "xp_earned"
        case dayClosed = "day_closed"
    }
}

struct TrendsWeight: Codable, Equatable, Sendable, Identifiable {
    let date: String
    let weightKG: Decimal

    var id: String { date }

    private enum CodingKeys: String, CodingKey {
        case date
        case weightKG = "weight_kg"
    }
}

struct TrendsSnapshot: Codable, Equatable, Sendable {
    let days: Int
    let daily: [TrendsDay]
    let weights: [TrendsWeight]
    var clinicalPolicy: CurrentClinicalPolicy? = nil

    private enum CodingKeys: String, CodingKey {
        case days, daily, weights
        case clinicalPolicy = "clinical_policy"
    }

    static func empty(days: Int) -> TrendsSnapshot {
        TrendsSnapshot(days: days, daily: [], weights: [])
    }
}

typealias TrendsResponse = MobileResponse<TrendsSnapshot>
