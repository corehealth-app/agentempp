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

enum DevelopmentConsentDocumentID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case terms = "dev.terms.v1"
    case privacy = "dev.privacy.v1"
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
}
