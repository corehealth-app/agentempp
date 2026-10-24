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

/// How the quantity the patient reviewed was obtained. A candidate without a
/// quantity never becomes a request, so "missing" has no case here.
enum MealQuantityBasis: String, Codable, Hashable, Sendable {
    case stated
    case visualEstimate = "visual_estimate"
    case portionReference = "portion_reference"
}

/// Where the meal came from. Media channels carry the asset the patient
/// reviewed; text never does.
enum MealSourceChannel: String, Codable, Hashable, Sendable {
    case text
    case camera
    case gallery
    case audioRecording = "audio_recording"
    case audioImport = "audio_import"

    var isPhoto: Bool { self == .camera || self == .gallery }
    var isAudio: Bool { self == .audioRecording || self == .audioImport }
}

struct MealProposalSource: Codable, Hashable, Sendable {
    let channel: MealSourceChannel
    let mediaAssetID: String?

    /// Fails closed on the pairing the server enforces: a media channel needs
    /// its asset and text must not carry one.
    init?(channel: MealSourceChannel, mediaAssetID: String?) {
        guard (channel == .text) == (mediaAssetID == nil) else { return nil }
        self.channel = channel
        self.mediaAssetID = mediaAssetID
    }

    private enum CodingKeys: String, CodingKey {
        case channel
        case mediaAssetID = "media_asset_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let channel = try container.decode(MealSourceChannel.self, forKey: .channel)
        let mediaAssetID = try container.decodeIfPresent(String.self, forKey: .mediaAssetID)
        guard let source = MealProposalSource(channel: channel, mediaAssetID: mediaAssetID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .mediaAssetID,
                in: container,
                debugDescription: "channel and media asset do not match"
            )
        }
        self = source
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channel, forKey: .channel)
        try container.encodeIfPresent(mediaAssetID, forKey: .mediaAssetID)
    }
}

struct MealProposalItemRequest: Codable, Hashable, Sendable {
    let foodName: String
    let quantityG: Decimal
    let userKcal: Decimal?
    let quantityBasis: MealQuantityBasis?
    let candidateID: String?
    /// The patient tied the photographed nutrition label to this item. Only
    /// the choice travels; the server reads the label again by itself.
    let usesNutritionLabel: Bool

    init(
        foodName: String,
        quantityG: Decimal,
        userKcal: Decimal?,
        quantityBasis: MealQuantityBasis? = nil,
        candidateID: String? = nil,
        usesNutritionLabel: Bool = false
    ) {
        self.foodName = foodName
        self.quantityG = quantityG
        self.userKcal = userKcal
        self.quantityBasis = quantityBasis
        self.candidateID = candidateID
        self.usesNutritionLabel = usesNutritionLabel
    }

    private enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case quantityG = "quantity_g"
        case userKcal = "user_kcal"
        case quantityBasis = "quantity_basis"
        case candidateID = "candidate_id"
        case usesNutritionLabel = "use_nutrition_label"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        foodName = try container.decode(String.self, forKey: .foodName)
        quantityG = try container.decode(Decimal.self, forKey: .quantityG)
        userKcal = try container.decodeIfPresent(Decimal.self, forKey: .userKcal)
        quantityBasis = try container.decodeIfPresent(
            MealQuantityBasis.self,
            forKey: .quantityBasis
        )
        candidateID = try container.decodeIfPresent(String.self, forKey: .candidateID)
        usesNutritionLabel = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesNutritionLabel
        ) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(foodName, forKey: .foodName)
        try container.encode(quantityG, forKey: .quantityG)
        try container.encodeIfPresent(userKcal, forKey: .userKcal)
        try container.encodeIfPresent(quantityBasis, forKey: .quantityBasis)
        try container.encodeIfPresent(candidateID, forKey: .candidateID)
        if usesNutritionLabel {
            try container.encode(true, forKey: .usesNutritionLabel)
        }
    }
}

struct MealProposalRequest: Codable, Hashable, Sendable {
    let mealType: MealType
    let items: [MealProposalItemRequest]
    let consumedAt: APITimestamp?
    let source: MealProposalSource?

    init(
        mealType: MealType,
        items: [MealProposalItemRequest],
        consumedAt: APITimestamp?,
        source: MealProposalSource? = nil
    ) {
        self.mealType = mealType
        self.items = items
        self.consumedAt = consumedAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case mealType = "meal_type"
        case items
        case consumedAt = "consumed_at"
        case source
    }
}

struct WorkoutProposalRequest: Codable, Hashable, Sendable {
    let workoutType: String
    let durationMin: Int
    let intensity: WorkoutIntensity?
    let performedAt: APITimestamp?
    let registrationProtocol: WorkoutRegistrationProtocol?

    init(
        workoutType: String,
        durationMin: Int,
        intensity: WorkoutIntensity?,
        performedAt: APITimestamp?,
        registrationProtocol: WorkoutRegistrationProtocol? = nil
    ) {
        self.workoutType = workoutType
        self.durationMin = durationMin
        self.intensity = intensity
        self.performedAt = performedAt
        self.registrationProtocol = registrationProtocol
    }

    private enum CodingKeys: String, CodingKey {
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case intensity
        case performedAt = "performed_at"
        case registrationProtocol = "workout_protocol"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workoutType = try container.decode(String.self, forKey: .workoutType)
        durationMin = try container.decode(Int.self, forKey: .durationMin)
        intensity = try container.decodeIfPresent(WorkoutIntensity.self, forKey: .intensity)
        performedAt = try container.decodeIfPresent(APITimestamp.self, forKey: .performedAt)
        registrationProtocol = container.contains(.registrationProtocol)
            ? try container.decode(WorkoutRegistrationProtocol.self, forKey: .registrationProtocol)
            : nil
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
        case source
        case workoutType = "workout_type"
        case durationMin = "duration_min"
        case intensity
        case performedAt = "performed_at"
        case workoutProtocol = "workout_protocol"
    }

    private enum Kind: String, Codable {
        case meal
        case workout
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let workoutProtocol = container.contains(.workoutProtocol)
            ? try container.decode(WorkoutRegistrationProtocol.self, forKey: .workoutProtocol)
            : nil

        switch try container.decode(Kind.self, forKey: .kind) {
        case .meal:
            guard workoutProtocol == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .workoutProtocol, in: container,
                    debugDescription: "Workout protocol cannot authorize a meal"
                )
            }
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
                    ),
                    source: try container.decodeIfPresent(
                        MealProposalSource.self,
                        forKey: .source
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
                    ),
                    registrationProtocol: workoutProtocol
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
            try container.encodeIfPresent(request.source, forKey: .source)
        case let .workout(request):
            try container.encode(Kind.workout, forKey: .kind)
            try container.encode(request.workoutType, forKey: .workoutType)
            try container.encode(request.durationMin, forKey: .durationMin)
            try container.encodeIfPresent(request.intensity, forKey: .intensity)
            try container.encodeIfPresent(request.performedAt, forKey: .performedAt)
            try container.encodeIfPresent(request.registrationProtocol, forKey: .workoutProtocol)
        }
    }
}

struct RegistrationEditCommand: Encodable, Hashable, Sendable {
    let registrationID: String
    let proposal: RegistrationProposalRequest
    let workoutVersion: WorkoutRegistrationVersion?

    init(
        registrationID: String,
        proposal: RegistrationProposalRequest,
        workoutVersion: WorkoutRegistrationVersion? = nil
    ) {
        self.registrationID = registrationID
        self.proposal = proposal
        self.workoutVersion = workoutVersion
    }

    func encode(to encoder: any Encoder) throws {
        switch proposal {
        case .meal:
            guard workoutVersion == nil else { throw BodyFlowCapabilityError.invalidInput }
        case let .workout(request):
            guard workoutVersion != nil || request.registrationProtocol == nil else {
                throw BodyFlowCapabilityError.invalidInput
            }
        }
        try proposal.encode(to: encoder)
        try workoutVersion?.encodeSelection(to: encoder)
    }
}

struct RegistrationIDCommand: Hashable, Sendable {
    let registrationID: String
    let workoutVersion: WorkoutRegistrationVersion?

    init(registrationID: String, workoutVersion: WorkoutRegistrationVersion? = nil) {
        self.registrationID = registrationID
        self.workoutVersion = workoutVersion
    }
}

struct RegistrationSnapshot: Codable, Hashable, Sendable {
    let id: String
    let status: String
    let createdAt: APITimestamp
    let expiresAt: APITimestamp
    let resolvedAt: APITimestamp?
    let proposal: RegistrationProposalSnapshot
    let workoutVersion: WorkoutRegistrationVersion?
    let editReceipt: WorkoutRegistrationEditReceipt?
    /// Optional identity of the saved workout, distinct from this proposal ID.
    let confirmedWorkoutID: String?
    let feedback: RegistrationFeedbackSnapshot?

    init(
        id: String,
        status: String,
        createdAt: APITimestamp,
        expiresAt: APITimestamp,
        resolvedAt: APITimestamp?,
        proposal: RegistrationProposalSnapshot,
        workoutVersion: WorkoutRegistrationVersion? = nil,
        editReceipt: WorkoutRegistrationEditReceipt? = nil,
        confirmedWorkoutID: String? = nil,
        feedback: RegistrationFeedbackSnapshot? = nil
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.resolvedAt = resolvedAt
        self.proposal = proposal
        self.workoutVersion = workoutVersion
        self.editReceipt = editReceipt
        self.confirmedWorkoutID = Self.validConfirmedWorkoutID(confirmedWorkoutID, status: status, proposal: proposal)
        self.feedback = feedback?.bound(to: id, status: status, proposal: proposal)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case resolvedAt = "resolved_at"
        case proposal
        case workoutProtocol = "workout_protocol"
        case contentRevision = "content_revision"
        case editReceipt = "receipt"
        case confirmedWorkoutID = "confirmed_workout_id"
        case feedback
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(APITimestamp.self, forKey: .createdAt)
        expiresAt = try container.decode(APITimestamp.self, forKey: .expiresAt)
        resolvedAt = try container.decodeIfPresent(APITimestamp.self, forKey: .resolvedAt)
        proposal = try container.decode(RegistrationProposalSnapshot.self, forKey: .proposal)
        if container.contains(.workoutProtocol) || container.contains(.contentRevision) {
            _ = try container.decode(WorkoutRegistrationProtocol.self, forKey: .workoutProtocol)
            let revision = try container.decode(Int.self, forKey: .contentRevision)
            guard case .workout = proposal,
                  let version = WorkoutRegistrationVersion(contentRevision: revision) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .contentRevision, in: container,
                    debugDescription: "Invalid workout registration version"
                )
            }
            workoutVersion = version
        } else {
            workoutVersion = nil
        }
        editReceipt = container.contains(.editReceipt)
            ? try container.decode(WorkoutRegistrationEditReceipt.self, forKey: .editReceipt)
            : nil
        if let editReceipt {
            guard let workoutVersion,
                  workoutVersion.contentRevision >= editReceipt.resultRevision else {
                throw DecodingError.dataCorruptedError(
                    forKey: .editReceipt, in: container,
                    debugDescription: "Edit receipt is newer than its current projection"
                )
            }
        }
        // This optional enrichment was previously ignored by the decoder.
        // Validate the principal snapshot first; an invalid optional identity
        // disables only clarification, never a valid persisted confirmation.
        let identity = try? container.decode(String.self, forKey: .confirmedWorkoutID)
        confirmedWorkoutID = Self.validConfirmedWorkoutID(identity, status: status, proposal: proposal)
        // Principal authority is decoded above. Invalid enrichment is ignored.
        let optionalFeedback = try? container.decode(RegistrationFeedbackSnapshot.self, forKey: .feedback)
        feedback = optionalFeedback?.bound(to: id, status: status, proposal: proposal)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        try container.encode(proposal, forKey: .proposal)
        if let workoutVersion {
            guard case .workout = proposal else { throw BodyFlowCapabilityError.invalidInput }
            try container.encode(WorkoutRegistrationProtocol.uiV1, forKey: .workoutProtocol)
            try container.encode(workoutVersion.contentRevision, forKey: .contentRevision)
        }
        if let editReceipt {
            guard let workoutVersion,
                  workoutVersion.contentRevision >= editReceipt.resultRevision else {
                throw BodyFlowCapabilityError.invalidInput
            }
            try container.encode(editReceipt, forKey: .editReceipt)
        }
        try container.encodeIfPresent(confirmedWorkoutID, forKey: .confirmedWorkoutID)
        try container.encodeIfPresent(feedback, forKey: .feedback)
    }

    private static func validConfirmedWorkoutID(_ value: String?, status: String,
                                               proposal: RegistrationProposalSnapshot) -> String? {
        guard status == "confirmed", case .workout = proposal, let value else { return nil }
        return WorkoutStrengthWire.uuid(value)
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

/// Origin the server stored with the proposal. The channel stays a string:
/// proposals created elsewhere carry channels the app never sends.
struct MealProposalSourceSnapshot: Codable, Hashable, Sendable {
    let channel: String
    let mediaAssetID: String?

    private enum CodingKeys: String, CodingKey {
        case channel
        case mediaAssetID = "media_asset_id"
    }

    /// The origin as a request can carry it again; nil when the stored
    /// channel is not one the app sends.
    var requestSource: MealProposalSource? {
        MealSourceChannel(rawValue: channel).flatMap {
            MealProposalSource(channel: $0, mediaAssetID: mediaAssetID)
        }
    }
}

struct MealProposalSnapshot: Codable, Hashable, Sendable {
    let mealType: String
    let items: [MealProposalItemSnapshot]
    let totals: MealProposalTotalsSnapshot?
    let warnings: [String]
    let source: MealProposalSourceSnapshot?

    init(
        mealType: String,
        items: [MealProposalItemSnapshot],
        totals: MealProposalTotalsSnapshot?,
        warnings: [String],
        source: MealProposalSourceSnapshot? = nil
    ) {
        self.mealType = mealType
        self.items = items
        self.totals = totals
        self.warnings = warnings
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case mealType = "meal_type"
        case items
        case totals
        case warnings
        case source
    }
}

/// Where an item's calories in a pending proposal came from.
enum MealItemKcalOrigin: Hashable, Sendable {
    /// The server calculated them (no patient value, or one it refused).
    case official
    /// The patient reported this value and the server applied it.
    case patientReported(Decimal)
    /// The response predates the provenance fields; nothing can be assumed.
    case unknown
}

struct MealProposalItemSnapshot: Codable, Hashable, Sendable {
    let name: String
    let quantityG: Decimal
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
    /// `user_kcal`: the patient's value for this item as the server stored it.
    let userKcal: Decimal?
    /// `nutrition_source`: the source the server applied; "user_kcal" means
    /// `kcal` is the patient's value.
    let nutritionSource: String?
    /// False when the response carried neither provenance key (an earlier
    /// server): the origin is unknown, never "calculated" by default.
    let kcalOriginReported: Bool
    /// `resolution`: "needs_clarification" when the server has not calculated
    /// this item yet (it is not a legitimate zero); nil from an earlier server.
    let resolution: String?
    /// `preparation_options`: the preparations to choose from, when that is
    /// the missing information.
    let preparationOptions: [String]?
    /// `quantity_basis`: how the quantity was obtained, when the proposal
    /// recorded it.
    let quantityBasis: String?
    let quantityDisplay: MealQuantityDisplay?

    private static let patientSource = "user_kcal"
    private static let needsClarificationValue = "needs_clarification"

    var needsClarification: Bool { resolution == Self.needsClarificationValue }

    init(
        name: String,
        quantityG: Decimal,
        kcal: Decimal?,
        proteinG: Decimal?,
        carbsG: Decimal?,
        fatG: Decimal?,
        userKcal: Decimal? = nil,
        nutritionSource: String? = nil,
        kcalOriginReported: Bool = true,
        resolution: String? = nil,
        preparationOptions: [String]? = nil,
        quantityBasis: String? = nil,
        quantityDisplay: MealQuantityDisplay? = nil
    ) {
        self.name = name
        self.quantityG = quantityG
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.userKcal = userKcal
        self.nutritionSource = nutritionSource
        self.kcalOriginReported = kcalOriginReported
        self.resolution = resolution
        self.preparationOptions = preparationOptions
        self.quantityBasis = quantityBasis
        self.quantityDisplay = quantityDisplay
    }

    var kcalOrigin: MealItemKcalOrigin {
        guard kcalOriginReported else { return .unknown }
        if nutritionSource == Self.patientSource, let userKcal {
            return .patientReported(userKcal)
        }
        return .official
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case quantityG = "quantity_g"
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case userKcal = "user_kcal"
        case nutritionSource = "nutrition_source"
        case resolution
        case preparationOptions = "preparation_options"
        case quantityBasis = "quantity_basis"
        case quantityDisplay = "quantity_display"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        quantityG = try container.decode(Decimal.self, forKey: .quantityG)
        kcal = try container.decodeIfPresent(Decimal.self, forKey: .kcal)
        proteinG = try container.decodeIfPresent(Decimal.self, forKey: .proteinG)
        carbsG = try container.decodeIfPresent(Decimal.self, forKey: .carbsG)
        fatG = try container.decodeIfPresent(Decimal.self, forKey: .fatG)
        userKcal = try container.decodeIfPresent(Decimal.self, forKey: .userKcal)
        nutritionSource = try container.decodeIfPresent(String.self, forKey: .nutritionSource)
        kcalOriginReported = container.contains(.userKcal)
            && container.contains(.nutritionSource)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        preparationOptions = try container.decodeIfPresent(
            [String].self,
            forKey: .preparationOptions
        )
        quantityBasis = try container.decodeIfPresent(String.self, forKey: .quantityBasis)
        quantityDisplay = try? container.decodeIfPresent(MealQuantityDisplay.self, forKey: .quantityDisplay)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(quantityG, forKey: .quantityG)
        try container.encodeIfPresent(kcal, forKey: .kcal)
        try container.encodeIfPresent(proteinG, forKey: .proteinG)
        try container.encodeIfPresent(carbsG, forKey: .carbsG)
        try container.encodeIfPresent(fatG, forKey: .fatG)
        if kcalOriginReported {
            try container.encode(userKcal, forKey: .userKcal)
            try container.encode(nutritionSource, forKey: .nutritionSource)
        }
        try container.encodeIfPresent(resolution, forKey: .resolution)
        try container.encodeIfPresent(preparationOptions, forKey: .preparationOptions)
        try container.encodeIfPresent(quantityBasis, forKey: .quantityBasis)
        try container.encodeIfPresent(quantityDisplay, forKey: .quantityDisplay)
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
