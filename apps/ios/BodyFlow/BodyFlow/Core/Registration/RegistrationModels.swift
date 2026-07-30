import Foundation

typealias RegistrationProposalResponse = MobileResponse<RegistrationSnapshot>
typealias RegistrationCancellationResponse = MobileResponse<RegistrationSnapshot>
typealias RegistrationConfirmationResponse = MobileResponse<RegistrationConfirmationSnapshot>

enum MealType: String, Codable, CaseIterable, Hashable, Sendable {
    case breakfast = "cafe"
    case lunch = "almoco"
    case snack = "lanche"
    case dinner = "jantar"
    case supper = "ceia"
    case other = "outro"
}

enum WorkoutIntensity: String, Codable, CaseIterable, Hashable, Sendable {
    case light = "leve"
    case moderate = "moderada"
    case high = "alta"
}

struct MealProposalItemRequest: Codable, Hashable, Sendable {
    let foodName: String
    let quantityG: Decimal
    let userKcal: Decimal?

    private enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case quantityG = "quantity_g"
        case userKcal = "user_kcal"
    }
}

struct MealProposalRequest: Codable, Hashable, Sendable {
    let mealType: MealType
    let items: [MealProposalItemRequest]
    let consumedAt: APITimestamp?

    private enum CodingKeys: String, CodingKey {
        case mealType = "meal_type"
        case items
        case consumedAt = "consumed_at"
    }
}

struct WorkoutProposalRequest: Codable, Hashable, Sendable {
    let workoutType: String
    let durationMin: Int
    let intensity: WorkoutIntensity?
    let performedAt: APITimestamp?

    private enum CodingKeys: String, CodingKey {
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case intensity
        case performedAt = "performed_at"
    }
}

enum RegistrationProposalRequest: Codable, Hashable, Sendable {
    case meal(MealProposalRequest)
    case workout(WorkoutProposalRequest)

    private enum CodingKeys: String, CodingKey {
        case kind
        case mealType = "meal_type"
        case items
        case consumedAt = "consumed_at"
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case intensity
        case performedAt = "performed_at"
    }

    private enum Kind: String, Codable {
        case meal
        case workout
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .kind) {
        case .meal:
            self = .meal(
                MealProposalRequest(
                    mealType: try container.decode(MealType.self, forKey: .mealType),
                    items: try container.decode(
                        [MealProposalItemRequest].self,
                        forKey: .items
                    ),
                    consumedAt: try container.decodeIfPresent(
                        APITimestamp.self,
                        forKey: .consumedAt
                    )
                )
            )
        case .workout:
            self = .workout(
                WorkoutProposalRequest(
                    workoutType: try container.decode(String.self, forKey: .workoutType),
                    durationMin: try container.decode(Int.self, forKey: .durationMin),
                    intensity: try container.decodeIfPresent(
                        WorkoutIntensity.self,
                        forKey: .intensity
                    ),
                    performedAt: try container.decodeIfPresent(
                        APITimestamp.self,
                        forKey: .performedAt
                    )
                )
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .meal(request):
            try container.encode(Kind.meal, forKey: .kind)
            try container.encode(request.mealType, forKey: .mealType)
            try container.encode(request.items, forKey: .items)
            try container.encodeIfPresent(request.consumedAt, forKey: .consumedAt)
        case let .workout(request):
            try container.encode(Kind.workout, forKey: .kind)
            try container.encode(request.workoutType, forKey: .workoutType)
            try container.encode(request.durationMin, forKey: .durationMin)
            try container.encodeIfPresent(request.intensity, forKey: .intensity)
            try container.encodeIfPresent(request.performedAt, forKey: .performedAt)
        }
    }
}

struct RegistrationEditCommand: Hashable, Sendable {
    let registrationID: String
    let proposal: RegistrationProposalRequest
}

struct RegistrationIDCommand: Hashable, Sendable {
    let registrationID: String
}

struct RegistrationSnapshot: Codable, Hashable, Sendable {
    let id: String
    let status: String
    let createdAt: APITimestamp
    let expiresAt: APITimestamp
    let resolvedAt: APITimestamp?
    let proposal: RegistrationProposalSnapshot

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case resolvedAt = "resolved_at"
        case proposal
    }
}

enum RegistrationProposalSnapshot: Codable, Hashable, Sendable {
    case meal(MealProposalSnapshot)
    case workout(WorkoutProposalSnapshot)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    private enum Kind: String, Codable {
        case meal
        case workout
        case unknown
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .kind) {
        case .meal:
            self = .meal(try MealProposalSnapshot(from: decoder))
        case .workout:
            self = .workout(try WorkoutProposalSnapshot(from: decoder))
        case .unknown:
            self = .unknown
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .meal(proposal):
            try container.encode(Kind.meal, forKey: .kind)
            try proposal.encode(to: encoder)
        case let .workout(proposal):
            try container.encode(Kind.workout, forKey: .kind)
            try proposal.encode(to: encoder)
        case .unknown:
            try container.encode(Kind.unknown, forKey: .kind)
        }
    }
}

struct MealProposalSnapshot: Codable, Hashable, Sendable {
    let mealType: String
    let items: [MealProposalItemSnapshot]
    let totals: MealProposalTotalsSnapshot?
    let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case mealType = "meal_type"
        case items
        case totals
        case warnings
    }
}

struct MealProposalItemSnapshot: Codable, Hashable, Sendable {
    let name: String
    let quantityG: Decimal
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?

    private enum CodingKeys: String, CodingKey {
        case name
        case quantityG = "quantity_g"
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

struct MealProposalTotalsSnapshot: Codable, Hashable, Sendable {
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?

    private enum CodingKeys: String, CodingKey {
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

struct WorkoutProposalSnapshot: Codable, Hashable, Sendable {
    let workoutType: String?
    let durationMin: Decimal?
    let estimatedKcal: Decimal?
    let intensity: String?

    private enum CodingKeys: String, CodingKey {
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case estimatedKcal = "estimated_kcal"
        case intensity
    }
}

struct RegistrationConfirmationSnapshot: Codable, Hashable, Sendable {
    let registration: RegistrationSnapshot
    let alreadyConfirmed: Bool
    let deduped: Bool?

    private enum CodingKeys: String, CodingKey {
        case alreadyConfirmed = "already_confirmed"
        case deduped
    }

    init(from decoder: any Decoder) throws {
        registration = try RegistrationSnapshot(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alreadyConfirmed = try container.decode(Bool.self, forKey: .alreadyConfirmed)
        deduped = try container.decodeIfPresent(Bool.self, forKey: .deduped)
    }

    func encode(to encoder: any Encoder) throws {
        try registration.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alreadyConfirmed, forKey: .alreadyConfirmed)
        try container.encodeIfPresent(deduped, forKey: .deduped)
    }
}
