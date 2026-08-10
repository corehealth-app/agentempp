import Foundation

typealias TodayResponse = MobileResponse<TodaySnapshot>

struct TodaySnapshot: Codable, Equatable, Sendable {
    let localDate: String
    let protocolName: String?
    let targets: TodayTargets
    let consumed: TodayConsumed
    let remainingFoodKcal: Int
    let foodExcessKcal: Int
    let exerciseKcal: Int
    let dailyBalanceKcal: Int
    let dailyBalanceStatus: String
    let proteinStatus: TodayProteinStatus
    let meals: [TodayMeal]
    let workouts: [TodayWorkout]
    let hydration: TodayHydration
    let supplements: TodayRoutineSection
    let medications: TodayRoutineSection
    let pendingActions: TodayPendingActions
    let block7700: TodayBlock7700?
    let completionStatus: TodayCompletionStatus
    let sources: TodaySources
    let calculationVersion: String
    let updatedAt: APITimestamp?
    let generatedAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case protocolName = "protocol"
        case targets
        case consumed
        case remainingFoodKcal = "remaining_food_kcal"
        case foodExcessKcal = "food_excess_kcal"
        case exerciseKcal = "exercise_kcal"
        case dailyBalanceKcal = "daily_balance_kcal"
        case dailyBalanceStatus = "daily_balance_status"
        case proteinStatus = "protein_status"
        case meals
        case workouts
        case hydration
        case supplements
        case medications
        case pendingActions = "pending_actions"
        case block7700 = "block_7700"
        case completionStatus = "completion_status"
        case sources
        case calculationVersion = "calculation_version"
        case updatedAt = "updated_at"
        case generatedAt = "generated_at"
    }
}

struct TodayTargets: Codable, Equatable, Sendable {
    let caloriesKcal: Int?
    let proteinG: Decimal?
    let source: String
    let caloriesSource: String?
    let proteinSource: String?

    private enum CodingKeys: String, CodingKey {
        case caloriesKcal = "calories_kcal"
        case proteinG = "protein_g"
        case source
        case caloriesSource = "calories_source"
        case proteinSource = "protein_source"
    }
}

struct TodayConsumed: Codable, Equatable, Sendable {
    let caloriesKcal: Int
    let proteinG: Decimal
    let carbsG: Decimal
    let fatG: Decimal
    let source: String

    private enum CodingKeys: String, CodingKey {
        case caloriesKcal = "calories_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case source
    }
}

struct TodayProteinStatus: Codable, Equatable, Sendable {
    let consumedG: Decimal
    let targetG: Decimal?
    let remainingG: Decimal?
    let percentage: Int?
    let status: String

    private enum CodingKeys: String, CodingKey {
        case consumedG = "consumed_g"
        case targetG = "target_g"
        case remainingG = "remaining_g"
        case percentage
        case status
    }
}

struct TodayMeal: Codable, Equatable, Sendable {
    let id: String
    let mealType: String
    let foodName: String
    let quantityG: Decimal
    let kcal: Int
    let proteinG: Decimal
    let carbsG: Decimal
    let fatG: Decimal
    let consumedAt: APITimestamp
    let nutritionSource: String?

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
        case nutritionSource = "nutrition_source"
    }
}

struct TodayWorkout: Codable, Equatable, Sendable {
    let id: String
    let workoutType: String
    let durationMin: Int
    let estimatedKcal: Int
    let intensity: String
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

struct TodayHydration: Codable, Equatable, Sendable {
    let consumedML: Int
    let targetML: Int?
    let remainingML: Int?
    let percentage: Int?
    let status: String

    private enum CodingKeys: String, CodingKey {
        case consumedML = "consumed_ml"
        case targetML = "target_ml"
        case remainingML = "remaining_ml"
        case percentage
        case status
    }
}

struct TodayRoutineSection: Codable, Equatable, Sendable {
    let availability: String
    let items: [TodayRoutineItem]

    private enum CodingKeys: String, CodingKey {
        case availability
        case items
    }
}

struct TodayRoutineItem: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let doseText: String?
    let origin: String?
    let remindersEnabled: Bool
    let schedules: [TodayRoutineSchedule]
    let occurrences: [TodayRoutineOccurrence]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case doseText = "dose_text"
        case origin
        case remindersEnabled = "reminders_enabled"
        case schedules
        case occurrences
    }
}

struct TodayRoutineSchedule: Codable, Equatable, Sendable {
    let id: String
    let localTime: String
    let weekdays: [Int]

    private enum CodingKeys: String, CodingKey {
        case id
        case localTime = "local_time"
        case weekdays
    }
}

struct TodayRoutineOccurrence: Codable, Equatable, Sendable {
    let reminderRuleID: String
    let scheduledFor: APITimestamp
    let status: String
    let lastActionAt: APITimestamp?
    let snoozedUntil: APITimestamp?

    private enum CodingKeys: String, CodingKey {
        case reminderRuleID = "reminder_rule_id"
        case scheduledFor = "scheduled_for"
        case status
        case lastActionAt = "last_action_at"
        case snoozedUntil = "snoozed_until"
    }
}

struct TodayPendingActions: Codable, Equatable, Sendable {
    let registrations: [TodayPendingRegistration]
    let mealGaps: TodayMealGaps

    private enum CodingKeys: String, CodingKey {
        case registrations
        case mealGaps = "meal_gaps"
    }
}

struct TodayPendingRegistration: Codable, Equatable, Sendable {
    let id: String
    let kind: String
    let mealType: String?
    let createdAt: APITimestamp
    let expiresAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case mealType = "meal_type"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct TodayMealGaps: Codable, Equatable, Sendable {
    let expected: [String]
    let registered: [String]
    let skipped: [String]
    let open: [String]
    let reliable: Bool
    let source: String
    let activeDays: Int

    private enum CodingKeys: String, CodingKey {
        case expected
        case registered
        case skipped
        case open
        case reliable
        case source
        case activeDays = "active_days"
    }
}

struct TodayBlock7700: Codable, Equatable, Sendable {
    let enabled: Bool
    let availability: String
    let targetKcal: Int?
    let currentKcal: Int?
    let percentage: Int?
    let completedBlocks: Int?
    let totalCreditedKcal: Int?
    let source: String

    private enum CodingKeys: String, CodingKey {
        case enabled
        case availability
        case targetKcal = "target_kcal"
        case currentKcal = "current_kcal"
        case percentage
        case completedBlocks = "completed_blocks"
        case totalCreditedKcal = "total_credited_kcal"
        case source
    }
}

struct TodayCompletionStatus: Codable, Equatable, Sendable {
    let status: String
    let dayClosed: Bool
    let hasSufficientData: Bool?

    private enum CodingKeys: String, CodingKey {
        case status
        case dayClosed = "day_closed"
        case hasSufficientData = "has_sufficient_data"
    }
}

struct TodaySources: Codable, Equatable, Sendable {
    let targets: String
    let consumed: String
    let exercise: String
    let meals: String
    let workouts: String
    let hydration: String
    let hydrationTarget: String
    let supplements: String
    let medications: String
    let pendingActions: String
    let block7700: String

    private enum CodingKeys: String, CodingKey {
        case targets
        case consumed
        case exercise
        case meals
        case workouts
        case hydration
        case hydrationTarget = "hydration_target"
        case supplements
        case medications
        case pendingActions = "pending_actions"
        case block7700 = "block_7700"
    }
}
