import Foundation
import Observation

enum OnboardingOperationState: Equatable, Sendable {
    case idle
    case saving
    case failed(AppPresentationError)
}

enum OnboardingValidationIssue: Equatable, Sendable {
    case displayNameRequired
    case countryInvalid
    case timeZoneInvalid
    case biologicalSexRequired
    case birthDateRequired
    case birthDateInFuture
    case heightOutOfRange
    case weightOutOfRange
    case bodyFatOutOfRange
    case objectiveRequired
    case activityLevelRequired
    case trainingFrequencyOutOfRange
    case waterIntakeRequired
    case hungerLevelRequired
    case wakeTimeRequired
    case bedtimeRequired
    case foodOrganizationRequired
    case personaRequired
    case consentRequired
}

enum OnboardingStepValidator {
    static func issues(
        for step: OnboardingStep,
        draft: OnboardingDraft,
        now: Date
    ) -> [OnboardingValidationIssue] {
        switch step {
        case .welcome:
            welcomeIssues(draft)
        case .bodyData:
            bodyDataIssues(draft, now: now)
        case .objective:
            draft.objective == nil ? [.objectiveRequired] : []
        case .routine:
            routineIssues(draft)
        case .persona:
            draft.persona == nil ? [.personaRequired] : []
        case .consent:
            hasRequiredDevelopmentConsent(draft.consent) ? [] : [.consentRequired]
        case .completion:
            []
        }
    }

    static func completionIssues(
        draft: OnboardingDraft,
        now: Date
    ) -> [OnboardingValidationIssue] {
        OnboardingStep.allCases
            .filter { $0 != .completion }
            .flatMap { issues(for: $0, draft: draft, now: now) }
    }

    private static func welcomeIssues(
        _ draft: OnboardingDraft
    ) -> [OnboardingValidationIssue] {
        var issues: [OnboardingValidationIssue] = []
        if draft.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(.displayNameRequired)
        }

        let country = draft.countryCode
        let uppercaseLetters = country.count == 2
            && country == country.uppercased()
            && country.unicodeScalars.allSatisfy { (65...90).contains($0.value) }
        let isoCountryCodes = Set(Locale.Region.isoRegions.map(\.identifier))
        if !uppercaseLetters || !isoCountryCodes.contains(country) {
            issues.append(.countryInvalid)
        }
        if TimeZone(identifier: draft.timeZoneIdentifier) == nil {
            issues.append(.timeZoneInvalid)
        }
        return issues
    }

    private static func bodyDataIssues(
        _ draft: OnboardingDraft,
        now: Date
    ) -> [OnboardingValidationIssue] {
        var issues: [OnboardingValidationIssue] = []
        if draft.biologicalSex == nil {
            issues.append(.biologicalSexRequired)
        }
        if let birthDate = draft.birthDate {
            if birthDate > now {
                issues.append(.birthDateInFuture)
            }
        } else {
            issues.append(.birthDateRequired)
        }
        if !isInRange(draft.heightCM, range: 100...250) {
            issues.append(.heightOutOfRange)
        }
        if !isInRange(draft.weightKG, range: 30...300) {
            issues.append(.weightOutOfRange)
        }
        if let bodyFatPercent = draft.bodyFatPercent,
           !(3...60).contains(bodyFatPercent) {
            issues.append(.bodyFatOutOfRange)
        }
        return issues
    }

    private static func routineIssues(
        _ draft: OnboardingDraft
    ) -> [OnboardingValidationIssue] {
        var issues: [OnboardingValidationIssue] = []
        if draft.activityLevel == nil {
            issues.append(.activityLevelRequired)
        }
        if !(0...7).contains(draft.trainingFrequency ?? -1) {
            issues.append(.trainingFrequencyOutOfRange)
        }
        if draft.waterIntake == nil {
            issues.append(.waterIntakeRequired)
        }
        if draft.hungerLevel == nil {
            issues.append(.hungerLevelRequired)
        }
        if !isValid(draft.wakeTime) {
            issues.append(.wakeTimeRequired)
        }
        if !isValid(draft.bedtime) {
            issues.append(.bedtimeRequired)
        }
        if draft.foodOrganization == nil {
            issues.append(.foodOrganizationRequired)
        }
        return issues
    }

    private static func isInRange(
        _ value: Double?,
        range: ClosedRange<Double>
    ) -> Bool {
        guard let value else { return false }
        return range.contains(value)
    }

    private static func isValid(_ time: LocalTime?) -> Bool {
        guard let time else { return false }
        return (0..<24).contains(time.hour) && (0..<60).contains(time.minute)
    }

    private static func hasRequiredDevelopmentConsent(
        _ acceptance: DevelopmentConsentAcceptance?
    ) -> Bool {
        let acceptedIDs = Set(acceptance?.documentIDs ?? [])
        return Set(DevelopmentConsentDocumentID.allCases).isSubset(of: acceptedIDs)
    }
}

@MainActor
@Observable
final class OnboardingFlowModel {
    let userID: String
    private let repository: any OnboardingRepository
    private let personaRepository: any CoachPersonaRepository
    private let now: @MainActor () -> Date
    private let cancellationCheck: @MainActor () -> Bool
    private var activeSubmissionID: UUID?
    private var didComplete = false

    private(set) var draft: OnboardingDraft
    private(set) var step: OnboardingStep
    private(set) var operationState: OnboardingOperationState
    private(set) var validationIssues: [OnboardingValidationIssue]
    let onStepChanged: @MainActor (OnboardingStep) -> Void
    let onCompleted: @MainActor () -> Void

    init(
        userID: String,
        initialDraft: OnboardingDraft,
        repository: any OnboardingRepository,
        personaRepository: any CoachPersonaRepository,
        onStepChanged: @escaping @MainActor (OnboardingStep) -> Void,
        onCompleted: @escaping @MainActor () -> Void,
        initialOperationState: OnboardingOperationState = .idle,
        initialValidationIssues: [OnboardingValidationIssue] = [],
        now: @escaping @MainActor () -> Date = Date.init,
        cancellationCheck: @escaping @MainActor () -> Bool = { false }
    ) {
        self.userID = userID
        self.repository = repository
        self.personaRepository = personaRepository
        draft = initialDraft
        step = initialDraft.currentStep
        operationState = initialOperationState
        validationIssues = initialValidationIssues
        self.onStepChanged = onStepChanged
        self.onCompleted = onCompleted
        self.now = now
        self.cancellationCheck = cancellationCheck
    }

    func back() {
        guard operationState != .saving,
              let index = OnboardingStep.allCases.firstIndex(of: step),
              index > OnboardingStep.allCases.startIndex else {
            return
        }
        validationIssues = []
        operationState = .idle
        let previousStep = OnboardingStep.allCases[index - 1]
        step = previousStep
        draft.currentStep = previousStep
        onStepChanged(previousStep)
    }

    func continueFromCurrentStep() async {
        guard operationState != .saving else { return }

        let issues = OnboardingStepValidator.issues(
            for: step,
            draft: draft,
            now: now()
        )
        validationIssues = issues
        guard issues.isEmpty else {
            operationState = .idle
            return
        }

        guard let index = OnboardingStep.allCases.firstIndex(of: step),
              index < OnboardingStep.allCases.index(before: OnboardingStep.allCases.endIndex) else {
            return
        }

        let nextStep = OnboardingStep.allCases[index + 1]
        var advancedDraft = draft
        advancedDraft.currentStep = nextStep
        let submissionID = UUID()
        activeSubmissionID = submissionID
        operationState = .saving

        do {
            try await repository.saveDraft(advancedDraft, for: userID)
            guard activeSubmissionID == submissionID,
                  !isCancellationRequested else {
                finishCancelledSubmission(submissionID)
                return
            }
            draft = advancedDraft
            step = nextStep
            operationState = .idle
            activeSubmissionID = nil
            onStepChanged(nextStep)
        } catch is CancellationError {
            finishCancelledSubmission(submissionID)
        } catch {
            guard activeSubmissionID == submissionID else { return }
            guard !isCancellationRequested else {
                finishCancelledSubmission(submissionID)
                return
            }
            activeSubmissionID = nil
            operationState = .failed(presentationError(for: error))
        }
    }

    func complete() async {
        guard step == .completion,
              draft.currentStep == .completion,
              operationState != .saving,
              !didComplete else {
            return
        }

        let issues = OnboardingStepValidator.completionIssues(
            draft: draft,
            now: now()
        )
        validationIssues = issues
        guard issues.isEmpty, let selectedPersona = draft.persona else {
            operationState = .idle
            return
        }

        let submittedDraft = draft
        let submissionID = UUID()
        activeSubmissionID = submissionID
        operationState = .saving

        do {
            try await personaRepository.setPersona(selectedPersona, for: userID)
            guard canPublish(submissionID) else {
                finishCancelledSubmission(submissionID)
                return
            }

            try await repository.complete(submittedDraft, for: userID)
            guard canPublish(submissionID) else {
                finishCancelledSubmission(submissionID)
                return
            }

            didComplete = true
            activeSubmissionID = nil
            operationState = .idle
            onCompleted()
        } catch is CancellationError {
            finishCancelledSubmission(submissionID)
        } catch {
            guard activeSubmissionID == submissionID else { return }
            guard !isCancellationRequested else {
                finishCancelledSubmission(submissionID)
                return
            }
            activeSubmissionID = nil
            operationState = .failed(presentationError(for: error))
        }
    }

    func cancelActiveSubmission() {
        guard activeSubmissionID != nil else { return }
        activeSubmissionID = nil
        operationState = .idle
    }

    func updateDisplayName(_ value: String?) { draft.displayName = value }
    func updateLocaleIdentifier(_ value: String) { draft.localeIdentifier = value }
    func updateCountryCode(_ value: String) { draft.countryCode = value.uppercased() }
    func updateTimeZoneIdentifier(_ value: String) { draft.timeZoneIdentifier = value }
    func updateBiologicalSex(_ value: BiologicalSex?) { draft.biologicalSex = value }
    func updateBirthDate(_ value: Date?) { draft.birthDate = value }
    func updateHeightCM(_ value: Double?) { draft.heightCM = value }
    func updateWeightKG(_ value: Double?) { draft.weightKG = value }
    func updateBodyFatPercent(_ value: Double?) { draft.bodyFatPercent = value }
    func updateObjective(_ value: BodyFlowObjective?) { draft.objective = value }
    func updateActivityLevel(_ value: ActivityLevel?) { draft.activityLevel = value }
    func updateTrainingFrequency(_ value: Int?) { draft.trainingFrequency = value }
    func updateWaterIntake(_ value: WaterIntake?) { draft.waterIntake = value }
    func updateHungerLevel(_ value: HungerLevel?) { draft.hungerLevel = value }
    func updateWakeTime(_ value: LocalTime?) { draft.wakeTime = value }
    func updateBedtime(_ value: LocalTime?) { draft.bedtime = value }
    func updateFoodOrganization(_ value: FoodOrganization?) { draft.foodOrganization = value }
    func updatePersona(_ value: CoachPersona?) { draft.persona = value }
    func updateConsent(_ value: DevelopmentConsentAcceptance?) { draft.consent = value }

    var hasRequiredDevelopmentConsent: Bool {
        OnboardingStepValidator.issues(
            for: .consent,
            draft: draft,
            now: now()
        ).isEmpty
    }

    private var isCancellationRequested: Bool {
        Task.isCancelled || cancellationCheck()
    }

    private func canPublish(_ submissionID: UUID) -> Bool {
        activeSubmissionID == submissionID && !isCancellationRequested
    }

    private func finishCancelledSubmission(_ submissionID: UUID) {
        guard activeSubmissionID == submissionID else { return }
        activeSubmissionID = nil
        operationState = .idle
    }

    private func presentationError(for error: Error) -> AppPresentationError {
        switch error {
        case OnboardingRepositoryError.invalidDraft:
            .invalidInput
        case OnboardingRepositoryError.developmentConsentForbidden:
            .operationUnavailable
        case OnboardingRepositoryError.serviceUnavailable:
            .serviceUnavailable
        case OnboardingRepositoryError.storageUnavailable:
            .storageUnavailable
        case CoachPersonaRepositoryError.serviceUnavailable:
            .serviceUnavailable
        case CoachPersonaRepositoryError.storageUnavailable:
            .storageUnavailable
        default:
            .operationUnavailable
        }
    }
}
