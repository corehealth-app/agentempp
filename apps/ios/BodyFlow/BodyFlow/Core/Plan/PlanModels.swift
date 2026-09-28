import Foundation

typealias PlanResponse = MobileResponse<PlanSnapshot>

struct PlanSnapshot: Codable, Equatable, Sendable {
    let training: TrainingPlanSnapshot?
    let nutrition: [NutritionPrescriptionSnapshot]
}

struct TrainingPlanSnapshot: Codable, Equatable, Sendable {
    let id: String
    let planType: String
    let daysPerWeek: Int
    let equipmentSummary: String?
    let generatedAt: APITimestamp
    let validUntil: APITimestamp?
    let version: Int?
    let notes: String?
    /// The days of the plan, when the server sent them and they could be
    /// read. A plan whose schedule cannot be read still shows its summary.
    let weeklySchedule: [TrainingDaySnapshot]?

    init(
        id: String,
        planType: String,
        daysPerWeek: Int,
        equipmentSummary: String?,
        generatedAt: APITimestamp,
        validUntil: APITimestamp?,
        version: Int?,
        notes: String?,
        weeklySchedule: [TrainingDaySnapshot]? = nil
    ) {
        self.id = id
        self.planType = planType
        self.daysPerWeek = daysPerWeek
        self.equipmentSummary = equipmentSummary
        self.generatedAt = generatedAt
        self.validUntil = validUntil
        self.version = version
        self.notes = notes
        self.weeklySchedule = weeklySchedule
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case planType = "plan_type"
        case daysPerWeek = "days_per_week"
        case equipmentSummary = "equipment_summary"
        case generatedAt = "generated_at"
        case validUntil = "valid_until"
        case version
        case notes
        case weeklySchedule = "weekly_schedule"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        planType = try container.decode(String.self, forKey: .planType)
        daysPerWeek = try container.decode(Int.self, forKey: .daysPerWeek)
        equipmentSummary = try container.decodeIfPresent(String.self, forKey: .equipmentSummary)
        generatedAt = try container.decode(APITimestamp.self, forKey: .generatedAt)
        validUntil = try container.decodeIfPresent(APITimestamp.self, forKey: .validUntil)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        weeklySchedule = (try? container.decodeIfPresent(
            [TrainingDaySnapshot].self,
            forKey: .weeklySchedule
        )) ?? nil
    }
}

/// One day of a training plan, as stored. Every field is optional: plans
/// written before the current format, or imported ones, may lack any of them.
struct TrainingDaySnapshot: Codable, Equatable, Sendable {
    let day: String?
    let focus: String?
    let durationMin: Decimal?
    let exercises: [TrainingExerciseSnapshot]

    private enum CodingKeys: String, CodingKey {
        case day, focus, exercises
        case durationMin = "duration_min"
    }

    init(day: String?, focus: String?, durationMin: Decimal?, exercises: [TrainingExerciseSnapshot]) {
        self.day = day
        self.focus = focus
        self.durationMin = durationMin
        self.exercises = exercises
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try? container.decodeIfPresent(String.self, forKey: .day)
        focus = try? container.decodeIfPresent(String.self, forKey: .focus)
        durationMin = try? container.decodeIfPresent(Decimal.self, forKey: .durationMin)
        exercises = ((try? container.decodeIfPresent(
            [TrainingExerciseSnapshot].self,
            forKey: .exercises
        )) ?? nil) ?? []
    }
}

struct TrainingExerciseSnapshot: Codable, Equatable, Sendable {
    let name: String?
    let sets: Decimal?
    let repsRange: String?
    let restSeconds: Decimal?

    private enum CodingKeys: String, CodingKey {
        case name, sets
        case repsRange = "reps_range"
        case restSeconds = "rest_seconds"
    }

    init(name: String?, sets: Decimal?, repsRange: String?, restSeconds: Decimal?) {
        self.name = name
        self.sets = sets
        self.repsRange = repsRange
        self.restSeconds = restSeconds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        sets = try? container.decodeIfPresent(Decimal.self, forKey: .sets)
        repsRange = try? container.decodeIfPresent(String.self, forKey: .repsRange)
        restSeconds = try? container.decodeIfPresent(Decimal.self, forKey: .restSeconds)
    }
}

struct NutritionPrescriptionSnapshot: Codable, Equatable, Sendable {
    let id: String
    let type: String
    let payload: JSONValue?
    let generatedAt: APITimestamp
    let validUntil: APITimestamp?
    let version: Int?
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case payload
        case generatedAt = "generated_at"
        case validUntil = "valid_until"
        case version
        case notes
    }
}
