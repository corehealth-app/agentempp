import Foundation

struct OnboardingEligibilityInput: Codable, Equatable, Sendable {
    let locale: String
    let sex: BiologicalSex
    let heightCM: Double
    let weightKG: Double
    let bodyFatPercent: Double?
    let trainingFrequency: Int

    init(draft: OnboardingDraft) throws {
        guard OnboardingLocalePolicy.isSupported(draft.localeIdentifier),
              let sex = draft.biologicalSex, let height = draft.heightCM,
              let weight = draft.weightKG, let frequency = draft.trainingFrequency else {
            throw OnboardingRepositoryError.invalidDraft
        }
        locale = draft.localeIdentifier
        self.sex = sex
        heightCM = height
        weightKG = weight
        bodyFatPercent = draft.bodyFatPercent
        trainingFrequency = frequency
    }

    private enum CodingKeys: String, CodingKey {
        case locale, sex
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bodyFatPercent = "body_fat_percent"
        case trainingFrequency = "training_frequency"
    }
}

struct OnboardingEligibilityDecision: Codable, Equatable, Sendable {
    enum Decision: String, Codable, Sendable { case assigned, choice }
    enum Basis: String, Codable, Sendable { case bodyFat = "body_fat", bmi }
    enum Status: String, Codable, Sendable { case available, blocked, notOffered = "not_offered" }
    enum Reason: String, Codable, Sendable { case composition = "gain_composition", training = "gain_training" }
    struct Option: Codable, Equatable, Sendable {
        let objective: BodyFlowObjective
        let status: Status
        let reasons: [Reason]
        let message: [String]
    }
    let decision: Decision
    let basis: Basis
    let objective: BodyFlowObjective?
    let notice: [String]?
    let options: [Option]
}

struct ProtocolWelcome: Codable, Equatable, Sendable {
    let `protocol`: BodyFlowObjective
    let paragraphs: [String]
}

struct OnboardingOwnerToken: Equatable, Sendable {
    let userID: String
    let restoreGeneration: Int
}


extension OnboardingEligibilityDecision {
    func permits(_ value: BodyFlowObjective?) -> Bool {
        guard let value else { return false }
        return options.first { $0.objective == value }?.status == .available
    }

    /// Contract consistency only; the app never infers clinical availability.
    func validated() throws -> Self {
        guard options.map(\.objective) == [.bodyRecomposition, .muscleGain, .maintenance],
              options.allSatisfy({ option in
                  switch option.status {
                  case .available, .notOffered: return option.reasons.isEmpty && option.message.isEmpty
                  case .blocked: return !option.reasons.isEmpty && !option.message.isEmpty
                  }
              }) else { throw OnboardingRepositoryError.serviceUnavailable }
        switch decision {
        case .choice:
            guard objective == nil, notice == nil else { throw OnboardingRepositoryError.serviceUnavailable }
        case .assigned:
            guard objective == .bodyRecomposition, permits(objective),
                  notice?.isEmpty == false,
                  options[1].status == .blocked, options[2].status == .notOffered else {
                throw OnboardingRepositoryError.serviceUnavailable
            }
        }
        return self
    }
}

enum OnboardingResumePolicy {
    static func normalizedDraft(
        _ draft: OnboardingDraft,
        requirements: OnboardingRequirements,
        developmentConsentAvailability: DevelopmentConsentAvailability,
        historicalCompletedAt: String?,
        now: Date
    ) -> OnboardingDraft {
        var result = draft
        if historicalCompletedAt != nil {
            result.currentStep = .consent
            return result
        }
        guard draft.currentStep == .objective || draft.currentStep == .completion else { return result }
        for step in OnboardingStep.allCases.prefix(while: { $0 != .objective }) {
            if !OnboardingStepValidator.issues(for: step, draft: draft,
                developmentConsentAvailability: developmentConsentAvailability,
                requirements: requirements, now: now).isEmpty {
                result.currentStep = step
                return result
            }
        }
        // No persisted draft can carry a current server decision into this session.
        result.currentStep = .objective
        return result
    }
}
