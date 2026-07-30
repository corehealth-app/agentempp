import Foundation

typealias HistoryResponse = MobileResponse<HistorySnapshot>

struct HistorySnapshot: Codable, Equatable, Sendable {
    let meals: [HistoryMealLogRow]
    let workouts: [HistoryWorkoutLogRow]
    let pagination: HistoryPaginationMetadata
}

struct HistoryMealLogRow: Codable, Equatable, Sendable {
    let id: String
    let mealType: String?
    let foodName: String
    let quantityG: Decimal?
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
    let consumedAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case id
        case mealType = "meal_type"
        case foodName = "food_name"
        case quantityG = "quantity_g"
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case consumedAt = "consumed_at"
    }
}

struct HistoryWorkoutLogRow: Codable, Equatable, Sendable {
    let id: String
    let workoutType: String?
    let durationMin: Int?
    let estimatedKcal: Int?
    let intensity: String?
    let performedAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case id
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case estimatedKcal = "estimated_kcal"
        case intensity
        case performedAt = "performed_at"
    }
}

struct HistoryPaginationMetadata: Codable, Equatable, Sendable {
    let limit: Int
    let before: APITimestamp?
}

struct HistoryQuery: Equatable, Sendable {
    let before: APITimestamp?
    let limit: Int

    private init(before: APITimestamp?, limit: Int) {
        self.before = before
        self.limit = limit
    }

    static let firstPage = HistoryQuery(before: nil, limit: 30)
}
