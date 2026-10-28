import Foundation

typealias TodayResponse = MobileResponse<TodaySnapshot>

struct TodaySnapshot: Codable, Equatable, Sendable {
    let localDate: String
    let protocolName: String?
    /// Official current objective, independent of the historical day's protocol.
    var currentProtocol: String? = nil
    var clinicalPolicy: CurrentClinicalPolicy? = nil
    /// Optional on older/OFF servers; its official calendar is independent of the day.
    var strengthTrainingWeek: TodayStrengthTrainingWeek? = nil
    let targets: TodayTargets
    let consumed: TodayConsumed
    /// Null when the day has no calorie target (contract); never shown as 0.
    let remainingFoodKcal: Int?
    let foodExcessKcal: Int?
    let exerciseKcal: Int
    /// Consumed minus the day's expenditure for the patient's protocol
    /// (negative = deficit, positive = surplus), as the server computed it.
    let dailyBalanceKcal: Int?
    let dailyBalanceStatus: String
    /// Whether `dailyBalanceKcal` already subtracts the day's exercise. An
    /// older server does not send it; read `dailyBalanceCountsExercise`.
    var dailyBalanceIncludesExercise: Bool? = nil
    /// The expenditure the balance was measured against, when the server
    /// sends it. Additive and optional; an older server sends nothing.
    var dailyBalanceReferenceKcal: Int? = nil
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
        case currentProtocol = "current_protocol"
        case clinicalPolicy = "clinical_policy"
        case strengthTrainingWeek = "strength_training_week"
        case targets
        case consumed
        case remainingFoodKcal = "remaining_food_kcal"
        case foodExcessKcal = "food_excess_kcal"
        case exerciseKcal = "exercise_kcal"
        case dailyBalanceKcal = "daily_balance_kcal"
        case dailyBalanceStatus = "daily_balance_status"
        case dailyBalanceIncludesExercise = "daily_balance_includes_exercise"
        case dailyBalanceReferenceKcal = "daily_balance_reference_kcal"
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

enum TodayStrengthTrainingWeek: Codable, Equatable, Sendable {
    case available(Available)
    case unavailable(reason: String)
    case conflict(reason: String)
    case unsupported(status: String)

    private enum CodingKeys: String, CodingKey { case status, reason }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "available": self = .available(try Available(from: decoder))
        case "unavailable": self = .unavailable(reason: try container.decode(String.self, forKey: .reason))
        case "conflict": self = .conflict(reason: try container.decode(String.self, forKey: .reason))
        default: self = .unsupported(status: status)
        }
    }

    func encode(to encoder: any Encoder) throws {
        if case let .available(value) = self {
            try value.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .available: break
        case let .unavailable(reason):
            try container.encode("unavailable", forKey: .status)
            try container.encode(reason, forKey: .reason)
        case let .conflict(reason):
            try container.encode("conflict", forKey: .status)
            try container.encode(reason, forKey: .reason)
        case let .unsupported(status):
            try container.encode(status, forKey: .status)
        }
    }

    struct Available: Codable, Equatable, Sendable {
        enum TargetSource: String, Codable, Sendable {
            case acceptedPlan = "accepted_plan"
            case informedFrequency = "informed_frequency"
            case absent
        }
        enum TargetAvailability: String, Codable, Sendable { case available, zero, absent }

        let weekStart: String
        let asOfLocalDate: String
        let timeZone: String
        /// Keep all six fractional digits; APITimestamp converts to Date.
        let observedAt: String
        let completedStrengthDays: Int
        let plannedDays: Int?
        let targetSource: TargetSource
        let targetAvailability: TargetAvailability
        let percentage: Int?

        private enum CodingKeys: String, CodingKey {
            case status
            case weekStart = "week_start", asOfLocalDate = "as_of_local_date"
            case timeZone = "time_zone", observedAt = "observed_at"
            case completedStrengthDays = "completed_strength_days", plannedDays = "planned_days"
            case targetSource = "target_source", targetAvailability = "target_availability"
            case percentage
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            weekStart = try container.decode(String.self, forKey: .weekStart)
            asOfLocalDate = try container.decode(String.self, forKey: .asOfLocalDate)
            timeZone = try container.decode(String.self, forKey: .timeZone)
            observedAt = try container.decode(String.self, forKey: .observedAt)
            completedStrengthDays = try container.decode(Int.self, forKey: .completedStrengthDays)
            targetSource = try container.decode(TargetSource.self, forKey: .targetSource)
            targetAvailability = try container.decode(TargetAvailability.self, forKey: .targetAvailability)
            // These keys are required even when their official value is null.
            guard container.contains(.plannedDays), container.contains(.percentage) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing nullable weekly values"
                ))
            }
            plannedDays = try container.decodeIfPresent(Int.self, forKey: .plannedDays)
            percentage = try container.decodeIfPresent(Int.self, forKey: .percentage)
            let validTarget: Bool
            switch targetAvailability {
            case .available:
                validTarget = plannedDays.map { (1...7).contains($0) } == true
                    && targetSource != .absent
                    && percentage.map { (0...100).contains($0) } == true
            case .zero:
                validTarget = plannedDays == 0 && targetSource == .informedFrequency && percentage == nil
            case .absent:
                validTarget = plannedDays == nil && targetSource == .absent && percentage == nil
            }
            guard (0...7).contains(completedStrengthDays), validTarget,
                  TimeZone(identifier: timeZone) != nil,
                  Self.validCalendar(weekStart: weekStart, asOf: asOfLocalDate),
                  Self.validObservation(observedAt) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid official strength week"
                ))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("available", forKey: .status)
            try container.encode(weekStart, forKey: .weekStart)
            try container.encode(asOfLocalDate, forKey: .asOfLocalDate)
            try container.encode(timeZone, forKey: .timeZone)
            try container.encode(observedAt, forKey: .observedAt)
            try container.encode(completedStrengthDays, forKey: .completedStrengthDays)
            try container.encode(plannedDays, forKey: .plannedDays)
            try container.encode(targetSource, forKey: .targetSource)
            try container.encode(targetAvailability, forKey: .targetAvailability)
            try container.encode(percentage, forKey: .percentage)
        }

        /// Validates the supplied civil scope; never chooses a week or reads a device clock.
        private static func validCalendar(weekStart: String, asOf: String) -> Bool {
            guard let start = civilDate(weekStart), let end = civilDate(asOf),
                  let utc = TimeZone(secondsFromGMT: 0) else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = utc
            guard calendar.component(.weekday, from: start) == 2,
                  let days = calendar.dateComponents([.day], from: start, to: end).day else { return false }
            return (0...6).contains(days)
        }

        private static func civilDate(_ value: String) -> Date? {
            guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) == (value.startIndex..<value.endIndex),
                  let utc = TimeZone(secondsFromGMT: 0) else { return nil }
            let parts = value.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, parts[0] > 0 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = utc
            let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
            guard let date = calendar.date(from: components) else { return nil }
            let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
            guard roundTrip.year == parts[0], roundTrip.month == parts[1], roundTrip.day == parts[2] else { return nil }
            return date
        }

        private static func validObservation(_ value: String) -> Bool {
            guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$"#, options: .regularExpression) == (value.startIndex..<value.endIndex),
                  civilDate(String(value.prefix(10))) != nil else { return false }
            let bytes = Array(value.utf8)
            func component(_ offset: Int) -> Int { Int(bytes[offset] - 48) * 10 + Int(bytes[offset + 1] - 48) }
            return component(11) < 24 && component(14) < 60 && component(17) < 60
        }
    }
}

extension TodaySnapshot {
    var blockPresentationPolicy: Block7700PresentationPolicy {
        if clinicalPolicy?.hide.block == true { return .unknown }
        return Block7700PresentationPolicy(currentProtocol: currentProtocol, enabled: block7700?.enabled)
    }

    /// A response without `daily_balance_includes_exercise` comes from a
    /// server that always subtracted exercise from the balance.
    var dailyBalanceCountsExercise: Bool {
        dailyBalanceIncludesExercise ?? true
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

/// One confirmed `meal_logs` row as the server sends it (`DailyStateMeal`):
/// energy, quantity and macros are numbers with up to two decimals and may be
/// null, like in History. They are shown as received, never rounded or
/// replaced by zero here.
struct TodayMeal: Codable, Equatable, Sendable {
    let id: String
    let mealType: String?
    let foodName: String
    let quantityG: Decimal?
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
    let consumedAt: APITimestamp
    let nutritionSource: String?

    var quantityDisplay: MealQuantityDisplay? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case mealType = "meal_type"
        case foodName = "food_name"
        case quantityG = "quantity_g"
        case quantityDisplay = "quantity_display"
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case consumedAt = "consumed_at"
        case nutritionSource = "nutrition_source"
    }
}

/// One confirmed `workout_logs` row (`DailyStateWorkout`): type, duration,
/// energy and intensity may be null (e.g. a workout logged without intensity).
/// Nothing is inferred for an absent value.
struct TodayWorkout: Codable, Equatable, Sendable {
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
