import Foundation

struct OnboardingEligibilityInput: Codable, Equatable, Sendable {
    let version: Int?
    let timezone: String?
    let birthDate: String?
    let locale: String
    let sex: BiologicalSex
    let heightCM: Double
    let weightKG: Double
    let bodyFatPercent: Double?
    let trainingFrequency: Int

    init(draft: OnboardingDraft, clinicalSignup: OnboardingClinicalSignupCapability? = nil) throws {
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
        if clinicalSignup != nil {
            guard let birth = draft.birthDate, TimeZone(identifier:draft.timeZoneIdentifier) != nil,
                  let date = OnboardingCivilDate.string(from:birth,timeZoneIdentifier:draft.timeZoneIdentifier) else {
                throw OnboardingRepositoryError.invalidDraft
            }
            version = 2; timezone = draft.timeZoneIdentifier; birthDate = date
        } else { version = nil; timezone = nil; birthDate = nil }
    }

    private enum CodingKeys: String, CodingKey {
        case locale, sex, version, timezone
        case birthDate = "birth_date"
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bodyFatPercent = "body_fat_percent"
        case trainingFrequency = "training_frequency"
    }
}

struct OnboardingEligibilityDecision: Codable, Equatable, Sendable {
    enum Decision: String, Codable, Sendable { case assigned, choice, noPlan = "no_plan" }
    enum Basis: String, Codable, Sendable { case bodyFat = "body_fat", bmi }
    enum Status: String, Codable, Sendable { case available, blocked, notOffered = "not_offered" }
    enum Reason: String, Codable, Sendable { case composition = "gain_composition", training = "gain_training", healthReview = "health_review", lossGuard = "loss_guard" }
    struct Option: Codable, Equatable, Sendable {
        let objective: BodyFlowObjective
        let status: Status
        let reasons: [Reason]
        let message: [String]
    }
    let decision: Decision
    let basis: Basis?
    let objective: BodyFlowObjective?
    let notice: [String]?
    let options: [Option]
    let version: Int?
    let professionalAssessmentRecommended: Bool?
    let pauseWeightLossGuidance: Bool?

    init(decision: Decision, basis: Basis?, objective: BodyFlowObjective?, notice: [String]?, options: [Option],
         version: Int? = nil, professionalAssessmentRecommended: Bool? = nil, pauseWeightLossGuidance: Bool? = nil) {
        self.decision=decision;self.basis=basis;self.objective=objective;self.notice=notice;self.options=options
        self.version=version;self.professionalAssessmentRecommended=professionalAssessmentRecommended;self.pauseWeightLossGuidance=pauseWeightLossGuidance
    }
    private enum CodingKeys: String, CodingKey {
        case decision,basis,objective,notice,options,version
        case professionalAssessmentRecommended = "professional_assessment_recommended", pauseWeightLossGuidance = "pause_weight_loss_guidance"
    }
    init(from decoder: any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        version=c.contains(.version) ? try c.decode(Int.self,forKey:.version) : nil
        decision=try c.decode(Decision.self,forKey:.decision)
        basis=try c.decodeIfPresent(Basis.self,forKey:.basis)
        objective=try c.decode(BodyFlowObjective?.self,forKey:.objective)
        notice=try c.decode([String]?.self,forKey:.notice)
        options=try c.decode([Option].self,forKey:.options)
        professionalAssessmentRecommended=c.contains(.professionalAssessmentRecommended) ? try c.decode(Bool.self,forKey:.professionalAssessmentRecommended) : nil
        pauseWeightLossGuidance=c.contains(.pauseWeightLossGuidance) ? try c.decode(Bool.self,forKey:.pauseWeightLossGuidance) : nil
    }
    func encode(to encoder: any Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encodeIfPresent(version,forKey:.version);try c.encode(decision,forKey:.decision);try c.encodeIfPresent(basis,forKey:.basis)
        try c.encode(objective,forKey:.objective);try c.encode(notice,forKey:.notice);try c.encode(options,forKey:.options)
        try c.encodeIfPresent(professionalAssessmentRecommended,forKey:.professionalAssessmentRecommended)
        try c.encodeIfPresent(pauseWeightLossGuidance,forKey:.pauseWeightLossGuidance)
    }
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
        guard let value else { return version == 2 && decision == .noPlan }
        return options.first { $0.objective == value }?.status == .available
    }

    /// Contract consistency only; the app never infers clinical availability.
    func validated() throws -> Self {
        let current = version == 2
        guard (version == nil || version == 1 || current),
              current ? (basis == nil && professionalAssessmentRecommended != nil && pauseWeightLossGuidance != nil)
                : (basis != nil && professionalAssessmentRecommended == nil && pauseWeightLossGuidance == nil),
              current || options.allSatisfy({$0.reasons.allSatisfy{$0 == .composition || $0 == .training}}) else {throw OnboardingRepositoryError.serviceUnavailable}
        if decision == .noPlan {
            guard current, objective == nil, options.isEmpty, notice?.isEmpty == false,
                  professionalAssessmentRecommended == true, pauseWeightLossGuidance == true else {throw OnboardingRepositoryError.serviceUnavailable}
            return self
        }
        guard options.map(\.objective) == [.bodyRecomposition, .muscleGain, .maintenance],
              options.allSatisfy({ option in
                  switch option.status {
                  case .available, .notOffered: return option.reasons.isEmpty && option.message.isEmpty
                  case .blocked: return !option.reasons.isEmpty && !option.message.isEmpty
                  }
              }) else { throw OnboardingRepositoryError.serviceUnavailable }
        switch decision {
        case .choice:
            guard objective == nil else { throw OnboardingRepositoryError.serviceUnavailable }
            if current && pauseWeightLossGuidance == true {
                guard professionalAssessmentRecommended == true, notice?.isEmpty == false,
                      options[0].status == .blocked, options[2].status == .available else {throw OnboardingRepositoryError.serviceUnavailable}
            } else {guard notice == nil, !current || professionalAssessmentRecommended == false else {throw OnboardingRepositoryError.serviceUnavailable}}
        case .assigned:
            guard objective == .bodyRecomposition, permits(objective),
                  notice?.isEmpty == false,
                  options[1].status == .blocked, options[2].status == .notOffered else {
                throw OnboardingRepositoryError.serviceUnavailable
            }
            guard !current || (pauseWeightLossGuidance == false && professionalAssessmentRecommended == false) else {throw OnboardingRepositoryError.serviceUnavailable}
        case .noPlan: throw OnboardingRepositoryError.serviceUnavailable
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
