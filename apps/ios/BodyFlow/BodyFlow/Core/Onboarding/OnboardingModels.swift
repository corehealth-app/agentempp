import Foundation

enum OnboardingStep: CaseIterable, Codable, Equatable, Sendable {
    case welcome
    case bodyData
    case routine
    case persona
    case consent
    case objective
    case completion
}

enum BiologicalSex: String, CaseIterable, Codable, Sendable {
    case masculine = "masculino"
    case feminine = "feminino"
}

enum BodyFlowObjective: String, CaseIterable, Codable, Sendable {
    case bodyRecomposition = "recomposicao"
    case muscleGain = "ganho_massa"
    case maintenance = "manutencao"
}

enum ActivityLevel: String, CaseIterable, Codable, Sendable {
    case sedentary = "sedentario"
    case light = "leve"
    case moderate = "moderado"
    case high = "alto"
    case athlete = "atleta"
}

enum WaterIntake: String, CaseIterable, Codable, Sendable {
    case low = "pouco"
    case moderate = "moderado"
    case high = "bastante"
}

enum HungerLevel: String, CaseIterable, Codable, Sendable {
    case low = "pouca"
    case moderate = "moderada"
    case high = "muita"
}

enum FoodOrganization: String, CaseIterable, Codable, Sendable {
    case yes = "sim"
    case no = "nao"
}

struct LocalTime: Codable, Equatable, Sendable {
    let hour: Int
    let minute: Int
}

enum OnboardingLocalePolicy {
    static let supportedIdentifiers: Set<String> = ["pt-BR", "en-US"]

    static func isSupported(_ identifier: String) -> Bool {
        supportedIdentifiers.contains(identifier)
    }
}

/// A country is an ISO region written with two letters that groups no other
/// region. The system's list also carries groupings that have a name but are
/// not a country: the numeric ones ("001" is the world, "013" Central
/// America) and a few two-letter ones ("EU", "UN"). The picker and both
/// validations read this one list, so what can be chosen is what is accepted.
enum OnboardingCountryPolicy {
    static let regions: [Locale.Region] = Locale.Region.isoRegions.filter { region in
        region.identifier.count == 2
            && region.identifier.unicodeScalars.allSatisfy { (65...90).contains($0.value) }
            && region.subRegions.isEmpty
    }

    private static let codes = Set(regions.map(\.identifier))

    static func isCountry(_ code: String) -> Bool {
        codes.contains(code)
    }
}

enum OnboardingCivilDate {
    static func date(
        from value: String,
        timeZoneIdentifier: String
    ) -> Date? {
        guard value.utf8.count == 10,
              let formatter = formatter(timeZoneIdentifier: timeZoneIdentifier),
              let date = formatter.date(from: value),
              formatter.string(from: date) == value else {
            return nil
        }
        return date
    }

    static func string(
        from date: Date,
        timeZoneIdentifier: String
    ) -> String? {
        formatter(timeZoneIdentifier: timeZoneIdentifier)?.string(from: date)
    }

    static func timeZone(for identifier: String) -> TimeZone? {
        TimeZone(identifier: identifier)
    }

    private static func formatter(timeZoneIdentifier: String) -> DateFormatter? {
        guard let timeZone = timeZone(for: timeZoneIdentifier) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

enum OnboardingLegalAction: String, Codable, Equatable, Sendable {
    case acceptance
    case acknowledgement
    case consent
}

struct OnboardingDocumentAction: Codable, Equatable, Hashable, Sendable {
    let documentKey: String
    let version: String
    let locale: String
    let contentHash: String
    let action: OnboardingLegalAction

    private enum CodingKeys: String, CodingKey {
        case documentKey = "document_key"
        case version
        case locale
        case contentHash = "content_hash"
        case action
    }
}

struct OnboardingLegalDocument: Codable, Equatable, Sendable {
    let documentKey: String
    let version: String
    let locale: String
    let body: String?
    let contentURL: String?
    let contentHash: String
    let purpose: String
    let action: OnboardingLegalAction
    let required: Bool
    let effectiveAt: String

    var explicitAction: OnboardingDocumentAction {
        OnboardingDocumentAction(
            documentKey: documentKey,
            version: version,
            locale: locale,
            contentHash: contentHash,
            action: action
        )
    }

    private enum CodingKeys: String, CodingKey {
        case documentKey = "document_key"
        case version
        case locale
        case body
        case contentURL = "content_url"
        case contentHash = "content_hash"
        case purpose
        case action
        case required
        case effectiveAt = "effective_at"
    }
}

struct OnboardingAcceptedAction: Codable, Equatable, Sendable {
    let documentKey: String
    let version: String
    let locale: String
    let contentHash: String
    let purpose: String
    let action: OnboardingLegalAction
    let actedAt: String

    private enum CodingKeys: String, CodingKey {
        case documentKey = "document_key"
        case version
        case locale
        case contentHash = "content_hash"
        case purpose
        case action
        case actedAt = "acted_at"
    }
}

struct OnboardingCompletionState: Codable, Equatable, Sendable {
    let completed: Bool
    let completedAt: String?

    private enum CodingKeys: String, CodingKey {
        case completed
        case completedAt = "completed_at"
    }
}

struct OnboardingRequirements: Codable, Equatable, Sendable {
    let available: Bool
    let blockingReason: String?
    let documents: [OnboardingLegalDocument]

    static let unavailable = OnboardingRequirements(
        available: false,
        blockingReason: "documents_unavailable",
        documents: []
    )

    private enum CodingKeys: String, CodingKey {
        case available
        case blockingReason = "blocking_reason"
        case documents
    }
}

struct OnboardingServerState: Codable, Equatable, Sendable {
    let locale: String
    let completion: OnboardingCompletionState
    let requirements: OnboardingRequirements
    let acceptedActions: [OnboardingAcceptedAction]
    let draft: OnboardingDraft?

    init(
        locale: String = "pt-BR",
        completion: OnboardingCompletionState,
        requirements: OnboardingRequirements,
        acceptedActions: [OnboardingAcceptedAction],
        draft: OnboardingDraft? = nil
    ) {
        self.locale = locale
        self.completion = completion
        self.requirements = requirements
        self.acceptedActions = acceptedActions
        self.draft = draft
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        locale = try values.decode(String.self, forKey: .locale)
        completion = try values.decode(OnboardingCompletionState.self, forKey: .completion)
        requirements = try values.decode(OnboardingRequirements.self, forKey: .requirements)
        acceptedActions = try values.decode(
            [OnboardingAcceptedAction].self,
            forKey: .acceptedActions
        )
        draft = try values.decodeIfPresent(
            OnboardingServerDraft.self,
            forKey: .draft
        )?.onboardingDraft()
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(locale, forKey: .locale)
        try values.encode(completion, forKey: .completion)
        try values.encode(requirements, forKey: .requirements)
        try values.encode(acceptedActions, forKey: .acceptedActions)
        if let draft {
            try values.encode(OnboardingServerDraft(draft), forKey: .draft)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case locale
        case completion
        case requirements
        case acceptedActions = "accepted_actions"
        case draft
    }
}

private struct OnboardingServerDraft: Codable {
    let name: String
    let locale: String
    let country: String
    let timezone: String
    let sex: BiologicalSex
    let birthDate: String
    let heightCM: Double
    let weightKG: Double
    let bodyFatPercent: Double?
    let objective: BodyFlowObjective
    let activityLevel: ActivityLevel
    let trainingFrequency: Int
    let waterIntake: WaterIntake
    let hungerLevel: HungerLevel
    let wakeTime: String
    let bedtime: String
    let foodOrganization: FoodOrganization
    let persona: String
    let currentStep: String

    init(_ draft: OnboardingDraft) throws {
        guard let sex = draft.biologicalSex,
              let birthDate = draft.birthDate,
              let heightCM = draft.heightCM,
              let weightKG = draft.weightKG,
              let objective = draft.objective,
              let activityLevel = draft.activityLevel,
              let trainingFrequency = draft.trainingFrequency,
              let waterIntake = draft.waterIntake,
              let hungerLevel = draft.hungerLevel,
              let wakeTime = draft.wakeTime,
              let bedtime = draft.bedtime,
              let foodOrganization = draft.foodOrganization,
              let persona = draft.persona,
              let name = draft.displayName,
              let birthDateString = OnboardingCivilDate.string(
                  from: birthDate,
                  timeZoneIdentifier: draft.timeZoneIdentifier
              ) else {
            throw EncodingError.invalidValue(
                draft,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Authoritative onboarding draft is incomplete"
                )
            )
        }
        self.name = name
        locale = draft.localeIdentifier
        country = draft.countryCode
        timezone = draft.timeZoneIdentifier
        self.sex = sex
        self.birthDate = birthDateString
        self.heightCM = heightCM
        self.weightKG = weightKG
        bodyFatPercent = draft.bodyFatPercent
        self.objective = objective
        self.activityLevel = activityLevel
        self.trainingFrequency = trainingFrequency
        self.waterIntake = waterIntake
        self.hungerLevel = hungerLevel
        self.wakeTime = Self.timeString(wakeTime)
        self.bedtime = Self.timeString(bedtime)
        self.foodOrganization = foodOrganization
        self.persona = switch persona {
        case .focus: "focus"
        case .impulse: "impulse"
        case .zen: "zen"
        }
        currentStep = "consent"
    }

    func onboardingDraft() throws -> OnboardingDraft {
        guard currentStep == "consent",
              OnboardingLocalePolicy.isSupported(locale),
              let birthDate = OnboardingCivilDate.date(
                  from: birthDate,
                  timeZoneIdentifier: timezone
              ),
              let wakeTime = Self.localTime(wakeTime),
              let bedtime = Self.localTime(bedtime),
              let persona = Self.persona(persona) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Invalid authoritative onboarding draft"
                )
            )
        }
        return OnboardingDraft(
            displayName: name,
            localeIdentifier: locale,
            countryCode: country,
            timeZoneIdentifier: timezone,
            biologicalSex: sex,
            birthDate: birthDate,
            heightCM: heightCM,
            weightKG: weightKG,
            bodyFatPercent: bodyFatPercent,
            objective: objective,
            activityLevel: activityLevel,
            trainingFrequency: trainingFrequency,
            waterIntake: waterIntake,
            hungerLevel: hungerLevel,
            wakeTime: wakeTime,
            bedtime: bedtime,
            foodOrganization: foodOrganization,
            persona: persona,
            consent: nil,
            documentActions: nil,
            currentStep: .consent
        )
    }

    private static func localTime(_ value: String) -> LocalTime? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else {
            return nil
        }
        return LocalTime(hour: hour, minute: minute)
    }

    private static func persona(_ value: String) -> CoachPersona? {
        switch value {
        case "focus": .focus
        case "impulse": .impulse
        case "zen": .zen
        default: nil
        }
    }

    private static func timeString(_ value: LocalTime) -> String {
        String(format: "%02d:%02d", value.hour, value.minute)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case locale
        case country
        case timezone
        case sex
        case birthDate = "birth_date"
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bodyFatPercent = "body_fat_percent"
        case objective
        case activityLevel = "activity_level"
        case trainingFrequency = "training_frequency"
        case waterIntake = "water_intake"
        case hungerLevel = "hunger_level"
        case wakeTime = "wake_time"
        case bedtime
        case foodOrganization = "food_organization"
        case persona
        case currentStep = "current_step"
    }
}

struct OnboardingCompletionAcknowledgement: Codable, Equatable, Sendable {
    let onboardingCompleted: Bool
    let completedAt: String
    let objective: BodyFlowObjective
    let persona: CoachPersona
    let documentActions: [OnboardingAcceptedAction]
    let protocolWelcome: ProtocolWelcome?

    private enum CodingKeys: String, CodingKey {
        case onboardingCompleted = "onboarding_completed"
        case completedAt = "completed_at"
        case objective
        case persona
        case documentActions = "document_actions"
        case protocolWelcome = "protocol_welcome"
    }

    init(
        onboardingCompleted: Bool,
        completedAt: String,
        objective: BodyFlowObjective,
        persona: CoachPersona,
        documentActions: [OnboardingAcceptedAction],
        protocolWelcome: ProtocolWelcome? = nil
    ) {
        self.onboardingCompleted = onboardingCompleted
        self.completedAt = completedAt
        self.objective = objective
        self.persona = persona
        self.documentActions = documentActions
        self.protocolWelcome = protocolWelcome
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        onboardingCompleted = try values.decode(Bool.self, forKey: .onboardingCompleted)
        completedAt = try values.decode(String.self, forKey: .completedAt)
        objective = try values.decode(BodyFlowObjective.self, forKey: .objective)
        let personaCode = try values.decode(String.self, forKey: .persona)
        guard let decodedPersona = Self.persona(for: personaCode) else {
            throw DecodingError.dataCorruptedError(
                forKey: .persona,
                in: values,
                debugDescription: "Unsupported coach persona"
            )
        }
        persona = decodedPersona
        protocolWelcome = try values.decodeIfPresent(ProtocolWelcome.self, forKey: .protocolWelcome)
        documentActions = try values.decode(
            [OnboardingAcceptedAction].self,
            forKey: .documentActions
        )
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try values.encode(completedAt, forKey: .completedAt)
        try values.encode(objective, forKey: .objective)
        try values.encode(Self.code(for: persona), forKey: .persona)
        try values.encodeIfPresent(protocolWelcome, forKey: .protocolWelcome)
        try values.encode(documentActions, forKey: .documentActions)
    }

    private static func persona(for code: String) -> CoachPersona? {
        switch code {
        case "focus": .focus
        case "impulse": .impulse
        case "zen": .zen
        default: nil
        }
    }

    private static func code(for persona: CoachPersona) -> String {
        switch persona {
        case .focus: "focus"
        case .impulse: "impulse"
        case .zen: "zen"
        }
    }

    func matches(_ draft: OnboardingDraft) -> Bool {
        guard onboardingCompleted,
              Self.isServerTimestamp(completedAt),
              objective == draft.objective,
              protocolWelcome == nil || protocolWelcome?.protocol == objective,
              persona == draft.persona,
              let submittedActions = draft.documentActions,
              !submittedActions.isEmpty,
              documentActions.allSatisfy({ Self.isServerTimestamp($0.actedAt) }) else {
            return false
        }

        let acknowledgedActions = documentActions.map {
            OnboardingDocumentAction(
                documentKey: $0.documentKey,
                version: $0.version,
                locale: $0.locale,
                contentHash: $0.contentHash,
                action: $0.action
            )
        }
        return acknowledgedActions.count == Set(acknowledgedActions).count
            && Set(acknowledgedActions) == Set(submittedActions)
            && submittedActions.count == Set(submittedActions).count
    }

    private static func isServerTimestamp(_ value: String) -> Bool {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if fractional.date(from: value) != nil { return true }
        return ISO8601DateFormatter().date(from: value) != nil
    }
}

enum DevelopmentConsentDocumentID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case terms = "dev.terms.v1"
    case privacy = "dev.privacy.v1"
}

enum DevelopmentConsentAvailability: Equatable, Sendable {
    case syntheticDevelopment
    case unavailable

    var allowsSyntheticDevelopmentConsent: Bool {
        #if DEBUG
        self == .syntheticDevelopment
        #else
        false
        #endif
    }
}

struct DevelopmentConsentAcceptance: Codable, Equatable, Sendable {
    let documentIDs: [DevelopmentConsentDocumentID]
    let acceptedAt: Date
}

struct OnboardingDraft: Codable, Equatable, Sendable {
    var displayName: String?
    var localeIdentifier: String
    var countryCode: String
    var timeZoneIdentifier: String
    var biologicalSex: BiologicalSex?
    var birthDate: Date?
    var heightCM: Double?
    var weightKG: Double?
    var bodyFatPercent: Double?
    var bodyFatOrigin: OnboardingBodyFatOrigin? = nil
    var bodyPhotoConfirmation: OnboardingBodyPhotoConfirmation? = nil
    var objective: BodyFlowObjective?
    var activityLevel: ActivityLevel?
    var trainingFrequency: Int?
    var waterIntake: WaterIntake?
    var hungerLevel: HungerLevel?
    var wakeTime: LocalTime?
    var bedtime: LocalTime?
    var foodOrganization: FoodOrganization?
    var persona: CoachPersona?
    var consent: DevelopmentConsentAcceptance?
    var documentActions: [OnboardingDocumentAction]? = nil
    var currentStep: OnboardingStep

    static var currentDeviceWelcome: OnboardingDraft {
        let languageCode = Locale.current.language.languageCode?.identifier
        return OnboardingDraft(
            displayName: nil,
            localeIdentifier: languageCode == "pt" ? "pt-BR" : "en-US",
            countryCode: Locale.current.region?.identifier ?? "US",
            timeZoneIdentifier: TimeZone.current.identifier,
            biologicalSex: nil,
            birthDate: nil,
            heightCM: nil,
            weightKG: nil,
            bodyFatPercent: nil,
            objective: nil,
            activityLevel: nil,
            trainingFrequency: nil,
            waterIntake: nil,
            hungerLevel: nil,
            wakeTime: nil,
            bedtime: nil,
            foodOrganization: nil,
            persona: nil,
            consent: nil,
            currentStep: .welcome
        )
    }
}
