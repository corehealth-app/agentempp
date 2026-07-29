import Foundation

enum OnboardingStep: CaseIterable, Codable, Equatable, Sendable {
    case welcome
    case bodyData
    case objective
    case routine
    case persona
    case consent
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
