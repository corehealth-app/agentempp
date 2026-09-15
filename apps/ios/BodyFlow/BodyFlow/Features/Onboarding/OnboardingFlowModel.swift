import Foundation
import Observation

enum OnboardingOperationState: Equatable, Sendable {
    case idle
    case saving
    case failed(AppPresentationError)
}

enum OnboardingValidationIssue: Equatable, Sendable {
    case displayNameRequired
    case localeUnsupported
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
    case developmentConsentUnavailable
}

enum OnboardingStepPresentation: Equatable, Sendable {
    case step(OnboardingStep)
    case developmentConsentUnavailable
}

enum OnboardingStepValidator {
    static func issues(
        for step: OnboardingStep,
        draft: OnboardingDraft,
        developmentConsentAvailability: DevelopmentConsentAvailability,
        requirements: OnboardingRequirements = .unavailable,
        now: Date
    ) -> [OnboardingValidationIssue] {
        switch step {
        case .welcome:
            return welcomeIssues(draft)
        case .bodyData:
            return bodyDataIssues(draft, now: now)
        case .objective:
            return draft.objective == nil ? [.objectiveRequired] : []
        case .routine:
            return routineIssues(draft)
        case .persona:
            return draft.persona == nil ? [.personaRequired] : []
        case .consent:
            if requirements.available, !requirements.documents.isEmpty {
                return hasExactRequiredDocumentActions(
                    draft.documentActions,
                    requirements: requirements
                ) ? [] : [.consentRequired]
            }
            if developmentConsentAvailability.allowsSyntheticDevelopmentConsent {
                return hasRequiredDevelopmentConsent(draft.consent) ? [] : [.consentRequired]
            }
            return [.developmentConsentUnavailable]
        case .completion:
            return []
        }
    }

    static func completionIssues(
        draft: OnboardingDraft,
        developmentConsentAvailability: DevelopmentConsentAvailability,
        requirements: OnboardingRequirements = .unavailable,
        now: Date
    ) -> [OnboardingValidationIssue] {
        OnboardingStep.allCases
            .filter { $0 != .completion }
            .flatMap {
                issues(
                    for: $0,
                    draft: draft,
                    developmentConsentAvailability: developmentConsentAvailability,
                    requirements: requirements,
                    now: now
                )
            }
    }

    private static func welcomeIssues(
        _ draft: OnboardingDraft
    ) -> [OnboardingValidationIssue] {
        var issues: [OnboardingValidationIssue] = []
        if draft.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            issues.append(.displayNameRequired)
        }
        if !OnboardingLocalePolicy.isSupported(draft.localeIdentifier) {
            issues.append(.localeUnsupported)
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

    private static func hasExactRequiredDocumentActions(
        _ actions: [OnboardingDocumentAction]?,
        requirements: OnboardingRequirements
    ) -> Bool {
        let required = Set(
            requirements.documents
                .filter(\.required)
                .map(\.explicitAction)
        )
        guard !required.isEmpty else { return false }
        let supplied = actions ?? []
        let selected = Set(supplied)
        let current = Set(requirements.documents.map(\.explicitAction))
        return supplied.count == selected.count
            && required.isSubset(of: selected)
            && selected.isSubset(of: current)
    }
}

@MainActor
@Observable
final class OnboardingFlowModel {
    let userID: String
    private let repository: any OnboardingRepository
    private let personaRepository: any CoachPersonaRepository
    private let developmentConsentAvailability: DevelopmentConsentAvailability
    private let idempotencyKeyProvider: any IdempotencyKeyProviding
    private let telemetry: any TelemetryClient
    private let now: @MainActor () -> Date
    private let cancellationCheck: @MainActor () -> Bool
    private var activeSubmissionID: UUID?
    private var pendingCompletionKey: IdempotencyKey?
    private var didComplete = false

    private(set) var draft: OnboardingDraft
    private(set) var step: OnboardingStep
    private(set) var operationState: OnboardingOperationState
    private(set) var validationIssues: [OnboardingValidationIssue]
    private(set) var requirements: OnboardingRequirements
    let onStepChanged: @MainActor (OnboardingStep) -> Void
    let onCompleted: @MainActor () -> Void

    init(
        userID: String,
        initialDraft: OnboardingDraft,
        repository: any OnboardingRepository,
        personaRepository: any CoachPersonaRepository,
        developmentConsentAvailability: DevelopmentConsentAvailability,
        requirements: OnboardingRequirements = .unavailable,
        idempotencyKeyProvider: any IdempotencyKeyProviding = RandomIdempotencyKeyProvider(),
        telemetry: any TelemetryClient = DisabledTelemetryClient(),
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
        self.developmentConsentAvailability = developmentConsentAvailability
        self.requirements = requirements
        self.idempotencyKeyProvider = idempotencyKeyProvider
        self.telemetry = telemetry
        draft = initialDraft
        step = initialDraft.currentStep
        operationState = initialOperationState
        validationIssues = initialValidationIssues
        self.onStepChanged = onStepChanged
        self.onCompleted = onCompleted
        self.now = now
        self.cancellationCheck = cancellationCheck
    }

    func back() async {
        guard !isCancellationRequested,
              operationState != .saving,
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
        await telemetry.record(.onboardingStepViewed(previousStep.telemetryValue))
    }

    func continueFromCurrentStep() async {
        guard operationState != .saving else { return }

        let issues = OnboardingStepValidator.issues(
            for: step,
            draft: draft,
            developmentConsentAvailability: developmentConsentAvailability,
            requirements: requirements,
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

        let completedStep = step
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
            await telemetry.record(.onboardingStepCompleted(completedStep.telemetryValue))
            await telemetry.record(.onboardingStepViewed(nextStep.telemetryValue))
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
            developmentConsentAvailability: developmentConsentAvailability,
            requirements: requirements,
            now: now()
        )
        validationIssues = issues
        guard issues.isEmpty, let selectedPersona = draft.persona else {
            operationState = .idle
            return
        }

        let idempotencyKey: IdempotencyKey
        do {
            if let pendingCompletionKey {
                idempotencyKey = pendingCompletionKey
            } else {
                let generated = try idempotencyKeyProvider.nextKey()
                pendingCompletionKey = generated
                idempotencyKey = generated
            }
        } catch {
            operationState = .failed(presentationError(for: error))
            return
        }

        let submittedDraft = draft
        let submissionID = UUID()
        activeSubmissionID = submissionID
        operationState = .saving

        do {
            let acknowledgement = try await repository.completeOfficial(
                submittedDraft,
                for: userID,
                idempotencyKey: idempotencyKey
            )
            guard acknowledgement.matches(submittedDraft) else {
                throw OnboardingRepositoryError.serviceUnavailable
            }
        } catch is CancellationError {
            finishCancelledSubmission(submissionID)
            return
        } catch {
            guard activeSubmissionID == submissionID else { return }
            guard !isCancellationRequested else {
                finishCancelledSubmission(submissionID)
                return
            }
            let repositoryError = error as? OnboardingRepositoryError
            if repositoryError == .requirementsChanged || repositoryError == .alreadyCompleted {
                let completedElsewhere: Bool
                do {
                    completedElsewhere = try await reloadRequirementsAfterConflict()
                } catch {
                    guard activeSubmissionID == submissionID else { return }
                    activeSubmissionID = nil
                    operationState = .failed(presentationError(for: error))
                    return
                }
                guard activeSubmissionID == submissionID else { return }
                pendingCompletionKey = nil
                if completedElsewhere {
                    didComplete = true
                    activeSubmissionID = nil
                    operationState = .idle
                    onCompleted()
                    return
                }
            }
            activeSubmissionID = nil
            operationState = .failed(presentationError(for: error))
            return
        }

        guard canPublish(submissionID) else {
            finishCancelledSubmission(submissionID)
            return
        }

        didComplete = true
        pendingCompletionKey = nil
        activeSubmissionID = nil
        operationState = .idle
        onCompleted()
        await telemetry.record(.coachPersonaSelected(selectedPersona.telemetryValue))
        await telemetry.record(.onboardingStepCompleted(.completion))
        await telemetry.record(.onboardingCompleted)
    }

    func cancelActiveSubmission() {
        guard activeSubmissionID != nil else { return }
        activeSubmissionID = nil
        operationState = .idle
    }

    func updateDisplayName(_ value: String?) { draft.displayName = value }
    func updateLocaleIdentifier(_ value: String) { draft.localeIdentifier = value }
    func updateCountryCode(_ value: String) { draft.countryCode = value.uppercased() }
    func updateTimeZoneIdentifier(_ value: String) {
        let civilBirthDate = draft.birthDate.flatMap {
            OnboardingCivilDate.string(
                from: $0,
                timeZoneIdentifier: draft.timeZoneIdentifier
            )
        }
        draft.timeZoneIdentifier = value
        if let civilBirthDate,
           let rebasedBirthDate = OnboardingCivilDate.date(
               from: civilBirthDate,
               timeZoneIdentifier: value
           ) {
            draft.birthDate = rebasedBirthDate
        }
    }
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
    func updateDocumentAction(_ action: OnboardingDocumentAction, selected: Bool) {
        var actions = Set(draft.documentActions ?? [])
        if selected {
            actions.insert(action)
        } else {
            actions.remove(action)
        }
        draft.documentActions = actions.isEmpty
            ? nil
            : requirements.documents
                .map(\.explicitAction)
                .filter(actions.contains)
    }

    var hasRequiredDevelopmentConsent: Bool {
        OnboardingStepValidator.issues(
            for: .consent,
            draft: draft,
            developmentConsentAvailability: developmentConsentAvailability,
            requirements: requirements,
            now: now()
        ).isEmpty
    }

    var stepPresentation: OnboardingStepPresentation {
        if !requirements.available,
           !developmentConsentAvailability.allowsSyntheticDevelopmentConsent,
           step == .consent || step == .completion {
            return .developmentConsentUnavailable
        }
        return .step(step)
    }

    private func reloadRequirementsAfterConflict() async throws -> Bool {
        let state = try await repository.loadState(for: userID)
        if state.completion.completed {
            return true
        }
        requirements = state.requirements
        if state.completion.completedAt != nil {
            guard let authoritativeDraft = state.draft else {
                throw OnboardingRepositoryError.serviceUnavailable
            }
            draft = authoritativeDraft
        }
        draft.localeIdentifier = state.locale
        draft.documentActions = nil
        draft.currentStep = .consent
        step = .consent
        onStepChanged(.consent)
        return false
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
        case OnboardingRepositoryError.documentsUnavailable,
             OnboardingRepositoryError.requirementsChanged,
             OnboardingRepositoryError.alreadyCompleted:
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
