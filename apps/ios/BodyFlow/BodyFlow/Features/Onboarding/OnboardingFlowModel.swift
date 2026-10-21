import Foundation
import Observation

enum OnboardingOperationState: Equatable, Sendable {
    case idle
    case saving
    case failed(AppPresentationError)
}

enum OnboardingCompletionStatus: Equatable, Sendable {
    case preparation
    case submission
    case reconciliation
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

        if !OnboardingCountryPolicy.isCountry(draft.countryCode) {
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
    private var signupCompletion: OnboardingCompletionCapability?
    private let preparationIDProvider: @MainActor () -> UUID
    private var activeSubmissionID: UUID?
    private struct CompletionPreparation {
        let preparationID: UUID
        let submittedDraft: OnboardingDraft
    }
    private enum CompletionTransport {
        case legacy(IdempotencyKey)
        case versioned(OnboardingCompletionIntent)
    }
    private struct CompletionSubmission {
        let submittedDraft: OnboardingDraft
        let transport: CompletionTransport
    }
    private enum CompletionAttempt {
        case preparation(CompletionPreparation)
        case submission(CompletionSubmission)
    }
    private enum PendingCompletion {
        case preparing(CompletionPreparation)
        case preparationUncertain(CompletionPreparation)
        case submission(CompletionSubmission)
        case reconciling(CompletionAttempt, OnboardingServerState?)

        var attempt: CompletionAttempt {
            switch self {
            case .preparing(let value), .preparationUncertain(let value): .preparation(value)
            case .submission(let value): .submission(value)
            case .reconciling(let value, _): value
            }
        }
    }
    private struct EligibilitySnapshot: Equatable {
        let input: OnboardingEligibilityInput
        let actions: Set<OnboardingDocumentAction>
        let developmentConsent: DevelopmentConsentAcceptance?
    }
    private var pendingCompletion: PendingCompletion?
    private var bodyPhotoDeletionIntent: OnboardingBodyPhotoDeletionIntent?
    private var verifiedPhotoConfirmation: OnboardingBodyPhotoConfirmation?
    private var eligibilitySnapshot: EligibilitySnapshot?
    private var didComplete = false
    private var didNotifyRoot = false
    private(set) var isActive = true
    private(set) var historicalCompletedAt: String?
    private(set) var eligibilityDecision: OnboardingEligibilityDecision?
    private(set) var pendingProtocolWelcome: ProtocolWelcome?
    private(set) var draft: OnboardingDraft
    private(set) var step: OnboardingStep
    private(set) var operationState: OnboardingOperationState
    private(set) var validationIssues: [OnboardingValidationIssue]
    private(set) var requirements: OnboardingRequirements
    let onStepChanged: @MainActor (OnboardingStep) -> Void
    let onCompleted: @MainActor () -> Void
    let onOfficialCleanupObserved: @MainActor (OnboardingBodyPhotoCleanupScope?) async -> Void

    init(
        userID: String, initialDraft: OnboardingDraft,
        repository: any OnboardingRepository,
        personaRepository: any CoachPersonaRepository,
        developmentConsentAvailability: DevelopmentConsentAvailability,
        requirements: OnboardingRequirements = .unavailable,
        historicalCompletedAt: String? = nil,
        signupCompletion: OnboardingCompletionCapability? = nil,
        preparationIDProvider: @escaping @MainActor () -> UUID = UUID.init,
        idempotencyKeyProvider: any IdempotencyKeyProviding = RandomIdempotencyKeyProvider(),
        telemetry: any TelemetryClient = DisabledTelemetryClient(),
        onStepChanged: @escaping @MainActor (OnboardingStep) -> Void,
        onCompleted: @escaping @MainActor () -> Void,
        onOfficialCleanupObserved: @escaping @MainActor (OnboardingBodyPhotoCleanupScope?) async -> Void = { _ in },
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
        self.historicalCompletedAt = historicalCompletedAt
        self.signupCompletion = signupCompletion
        self.preparationIDProvider = preparationIDProvider
        self.idempotencyKeyProvider = idempotencyKeyProvider
        self.telemetry = telemetry
        let normalized = OnboardingResumePolicy.normalizedDraft(initialDraft, requirements: requirements,
            developmentConsentAvailability: developmentConsentAvailability,
            historicalCompletedAt: historicalCompletedAt, now: now())
        draft = normalized
        step = normalized.currentStep
        operationState = initialOperationState
        validationIssues = initialValidationIssues
        if normalized.currentStep != initialDraft.currentStep {
            validationIssues = OnboardingStepValidator.issues(for: normalized.currentStep, draft: normalized,
                developmentConsentAvailability: developmentConsentAvailability, requirements: requirements, now: now())
        }
        self.onStepChanged = onStepChanged
        self.onCompleted = onCompleted
        self.onOfficialCleanupObserved = onOfficialCleanupObserved
        self.now = now
        self.cancellationCheck = cancellationCheck
    }

    #if DEBUG
    /// Only the local preview factory uses this explicit, validated fixture.
    /// Normal initialization and the repository default retain fail-closed behavior.
    func installDecisionForPreview(_ decision: OnboardingEligibilityDecision, requestedStep: OnboardingStep) {
        guard requestedStep == .objective || requestedStep == .completion,
              prerequisiteIssues().isEmpty, let snapshot = currentEligibilitySnapshot(),
              let validated = try? decision.validated() else { return }
        var candidate = draft
        apply(validated, to: &candidate)
        guard validated.permits(candidate.objective),
              OnboardingStepValidator.issues(for: requestedStep, draft: candidate,
                developmentConsentAvailability: developmentConsentAvailability,
                requirements: requirements, now: now()).isEmpty else { return }
        candidate.currentStep = requestedStep
        draft = candidate
        eligibilityDecision = validated
        eligibilitySnapshot = snapshot
        step = requestedStep
    }
    #endif

    var isReacceptance: Bool { historicalCompletedAt != nil }
    var visibleSteps: [OnboardingStep] { isReacceptance ? [.consent, .completion] : OnboardingStep.allCases }
    var unresolvedCompletion: Bool { pendingCompletion != nil }
    var allowsDraftEditing: Bool { isActive && !didComplete && pendingCompletion == nil }
    var completionStatus: OnboardingCompletionStatus? {
        switch pendingCompletion {
        case .preparing, .preparationUncertain: .preparation
        case .submission: .submission
        case .reconciling: .reconciliation
        case nil: nil
        }
    }
    var checksCompletionOnly: Bool {
        completionStatus == .preparation || completionStatus == .reconciliation
    }
    var canReviewCompletion: Bool {
        guard !isCancellationRequested, !didComplete, operationState != .saving else { return false }
        switch pendingCompletion {
        case .preparationUncertain, .reconciling(_, .some): return true
        default: return false
        }
    }

    /// This abandons only preparation, or a conflict already read as incomplete.
    /// An uncertain completion POST must retain its original receipt and draft.
    func reviewCompletionBeforeRetry() {
        guard canReviewCompletion else { return }
        let officialState: OnboardingServerState?
        switch pendingCompletion {
        case .preparationUncertain: officialState = nil
        case .reconciling(_, let state): officialState = state
        default: return
        }
        activeSubmissionID = nil
        pendingCompletion = nil
        operationState = .idle
        validationIssues = []
        if let state = officialState {
            requirements = state.requirements
            historicalCompletedAt = state.completion.completedAt
            signupCompletion = state.signupCompletion
            if let authoritativeDraft = state.draft { draft = authoritativeDraft }
            draft.localeIdentifier = state.locale
            draft.documentActions = nil
            invalidateBodyPhotoConfirmation()
            clearEligibility()
            draft.currentStep = isReacceptance ? .consent : .bodyData
            draft = OnboardingResumePolicy.normalizedDraft(draft, requirements: requirements,
                developmentConsentAvailability: developmentConsentAvailability,
                historicalCompletedAt: historicalCompletedAt, now: now())
            step = draft.currentStep
            onStepChanged(step)
        }
    }

    var hasPendingBodyPhotoDeletion: Bool { bodyPhotoDeletionIntent != nil }

    /// The pending operation is independent of the editable body-fat value.
    /// A later intent supersedes the previous one without letting it finish us.
    func beginBodyPhotoDeletion(for owner: OnboardingOwnerToken) -> OnboardingBodyPhotoDeletionIntent? {
        guard allowsDraftEditing, !isReacceptance, !isCancellationRequested,
              operationState != .saving, owner.userID == userID else { return nil }
        let intent = OnboardingBodyPhotoDeletionIntent(owner: owner)
        bodyPhotoDeletionIntent = intent
        invalidateBodyPhotoConfirmation()
        return intent
    }

    @discardableResult
    func finishBodyPhotoDeletion(_ intent: OnboardingBodyPhotoDeletionIntent) -> Bool {
        guard allowsDraftEditing, !isCancellationRequested,
              bodyPhotoDeletionIntent == intent else { return false }
        bodyPhotoDeletionIntent = nil
        return true
    }
    var requiresBodyPhotoRevalidation: Bool {
        draft.bodyFatOrigin == .photos && (draft.bodyPhotoConfirmation == nil
            || verifiedPhotoConfirmation != draft.bodyPhotoConfirmation
            || draft.bodyPhotoConfirmation?.matches(draft) != true)
    }

    @discardableResult
    func confirmBodyPhotoEstimate(_ state: SignupBodyPhotoState) -> Bool {
        guard allowsDraftEditing, !isReacceptance, !isCancellationRequested, !hasPendingBodyPhotoDeletion,
              let sex = draft.biologicalSex,
              let confirmation = OnboardingBodyPhotoConfirmation.candidate(from: state, sex: sex),
              let canonicalValue = Double(NSDecimalNumber(decimal: confirmation.value).stringValue) else { return false }
        draft.bodyFatPercent = canonicalValue
        draft.bodyFatOrigin = .photos
        draft.bodyPhotoConfirmation = confirmation
        verifiedPhotoConfirmation = confirmation
        clearEligibility()
        return true
    }

    func reconcileBodyPhotoState(_ state: SignupBodyPhotoState?) {
        guard allowsDraftEditing, !isReacceptance, !isCancellationRequested,
              !hasPendingBodyPhotoDeletion, draft.bodyFatOrigin == .photos else { return }
        guard let state, let sex = draft.biologicalSex,
              let current = OnboardingBodyPhotoConfirmation.candidate(from: state, sex: sex),
              current == draft.bodyPhotoConfirmation, current.matches(draft) else {
            invalidateBodyPhotoConfirmation()
            return
        }
        verifiedPhotoConfirmation = current
    }

    private func invalidateBodyPhotoConfirmation() {
        verifiedPhotoConfirmation = nil
        draft.bodyPhotoConfirmation = nil
        if draft.bodyFatOrigin == .photos {
            draft.bodyFatOrigin = nil
            draft.bodyFatPercent = nil
            clearEligibility()
        }
    }
    /// Whether a step before this one can be returned to. There is none on
    /// the first step (of the sign-up, or of a new acceptance of the
    /// documents), while a completion is pending, and once the sign-up was
    /// accepted (the entry message).
    var canGoBack: Bool {
        guard allowsDraftEditing, let index = visibleSteps.firstIndex(of: step) else { return false }
        return index > 0
    }
    var hasCurrentEligibilityDecision: Bool {
        !requiresBodyPhotoRevalidation && eligibilityDecision != nil && eligibilitySnapshot == currentEligibilitySnapshot()
    }

    /// Teardown affects local ownership only. It cannot undo a server request.
    func invalidate() {
        isActive = false
        activeSubmissionID = nil
        eligibilitySnapshot = nil
        eligibilityDecision = nil
        pendingProtocolWelcome = nil
        verifiedPhotoConfirmation = nil
        operationState = .idle
    }

    func back() async {
        guard allowsDraftEditing, !isCancellationRequested, operationState != .saving,
              let index = visibleSteps.firstIndex(of: step), index > 0 else { return }
        validationIssues = []
        operationState = .idle
        let previous = visibleSteps[index - 1]
        step = previous
        draft.currentStep = previous
        onStepChanged(previous)
        await telemetry.record(.onboardingStepViewed(previous.telemetryValue))
        await keepDraftOnDevice()
    }

    /// Keeps the unfinished sign-up on this iPhone (a real account; see
    /// `OnboardingDeviceDraftStore`). It runs when the step changes and when
    /// the person is about to leave the app — another app, the camera, the
    /// photo library, Settings, the lock screen — so that an app ended in the
    /// middle reopens where the person was, with what was typed.
    ///
    /// Nothing is kept for a new acceptance of the documents (that account's
    /// data is the server's), while a completion is pending, or after it.
    func keepDraftOnDevice() async {
        guard allowsDraftEditing, !isReacceptance else { return }
        await repository.keepDraftOnDevice(draft, for: userID)
    }

    func continueFromCurrentStep() async {
        guard allowsDraftEditing, operationState != .saving, !isCancellationRequested,
              !requiresBodyPhotoRevalidation, !hasPendingBodyPhotoDeletion else { return }
        let issues = issues(for: step)
        validationIssues = issues
        guard issues.isEmpty else { operationState = .idle; return }
        guard let index = visibleSteps.firstIndex(of: step), index + 1 < visibleSteps.count else { return }
        if step == .objective, !isReacceptance {
            guard hasCurrentEligibilityDecision else {
                await prepareObjectiveIfNeeded()
                return
            }
            guard eligibilityDecision?.permits(draft.objective) == true else {
                validationIssues = [.objectiveRequired]
                return
            }
        }
        let completedStep = step
        let nextStep = visibleSteps[index + 1]
        var advancedDraft = draft
        advancedDraft.currentStep = nextStep
        let id = UUID()
        activeSubmissionID = id
        operationState = .saving
        do {
            var freshDecision: OnboardingEligibilityDecision?
            var snapshot: EligibilitySnapshot?
            if completedStep == .consent, !isReacceptance {
                guard let captured = currentEligibilitySnapshot() else {
                    throw OnboardingRepositoryError.invalidDraft
                }
                snapshot = captured
                let answer = try await repository.checkEligibility(captured.input, for: userID,
                    idempotencyKey: idempotencyKeyProvider.nextKey())
                guard canPublish(id), currentEligibilitySnapshot() == captured else {
                    finishCancelledSubmission(id); return
                }
                freshDecision = try answer.validated()
                apply(answer, to: &advancedDraft)
            }
            try await repository.saveDraft(advancedDraft, for: userID)
            guard canPublish(id), snapshot == nil || snapshot == currentEligibilitySnapshot() else {
                finishCancelledSubmission(id); return
            }
            draft = advancedDraft
            if let freshDecision { eligibilityDecision = freshDecision; eligibilitySnapshot = snapshot }
            step = nextStep
            operationState = .idle
            activeSubmissionID = nil
            onStepChanged(nextStep)
            await telemetry.record(.onboardingStepCompleted(completedStep.telemetryValue))
            await telemetry.record(.onboardingStepViewed(nextStep.telemetryValue))
            await keepDraftOnDevice()
        } catch is CancellationError {
            finishCancelledSubmission(id)
        } catch {
            publishFailure(error, for: id)
        }
    }

    /// Called on objective appearance after a resumed draft or a definitive refusal.
    func prepareObjectiveIfNeeded() async {
        guard step == .objective, !isReacceptance, allowsDraftEditing,
              operationState != .saving, !isCancellationRequested, !hasCurrentEligibilityDecision,
              !requiresBodyPhotoRevalidation, !hasPendingBodyPhotoDeletion else { return }
        let prerequisite = prerequisiteIssues()
        guard prerequisite.isEmpty, let captured = currentEligibilitySnapshot() else {
            validationIssues = prerequisite
            return
        }
        let id = UUID()
        activeSubmissionID = id
        operationState = .saving
        do {
            let answer = try await repository.checkEligibility(captured.input, for: userID,
                idempotencyKey: idempotencyKeyProvider.nextKey()).validated()
            guard canPublish(id), currentEligibilitySnapshot() == captured else {
                finishCancelledSubmission(id); return
            }
            apply(answer, to: &draft)
            eligibilityDecision = answer
            eligibilitySnapshot = captured
            validationIssues = []
            activeSubmissionID = nil
            operationState = .idle
        } catch is CancellationError {
            finishCancelledSubmission(id)
        } catch {
            publishFailure(error, for: id)
        }
    }

    func complete() async {
        guard isActive, step == .completion, draft.currentStep == .completion,
              operationState != .saving, !didComplete, !isCancellationRequested,
              !hasPendingBodyPhotoDeletion else { return }
        if pendingCompletion == nil {
            guard !requiresBodyPhotoRevalidation else { return }
            validationIssues = OnboardingStepValidator.completionIssues(draft: draft,
                developmentConsentAvailability: developmentConsentAvailability, requirements: requirements, now: now())
            guard validationIssues.isEmpty else { operationState = .idle; return }
            if !isReacceptance, !hasCurrentEligibilityDecision || eligibilityDecision?.permits(draft.objective) != true {
                moveToObjective()
                await prepareObjectiveIfNeeded()
                return
            }
            if signupCompletion != nil {
                pendingCompletion = .preparing(CompletionPreparation(
                    preparationID: preparationIDProvider(), submittedDraft: draft))
            } else {
                do {
                    pendingCompletion = .submission(CompletionSubmission(submittedDraft: draft,
                        transport: .legacy(try idempotencyKeyProvider.nextKey())))
                } catch { operationState = .failed(presentationError(for: error)); return }
            }
        }
        guard let pending = pendingCompletion else { return }
        let id = UUID()
        activeSubmissionID = id
        operationState = .saving
        if case .reconciling(let attempt, _) = pending {
            await reconcileCompletionIntent(attempt, for: id)
            return
        }
        let submittedDraft: OnboardingDraft
        let acknowledgement: OnboardingCompletionAcknowledgement
        do {
            let submission: CompletionSubmission
            switch pending {
            case .preparing(let preparation), .preparationUncertain(let preparation):
                let receipt: OnboardingCompletionIntent?
                if case .preparing = pending {
                    receipt = try await repository.beginCompletionIntent(for: userID,
                        preparationID: preparation.preparationID)
                } else {
                    receipt = try await repository.resolveCompletionIntent(for: userID,
                        preparationID: preparation.preparationID)
                }
                guard canPublish(id) else { finishCancelledSubmission(id); return }
                guard let receipt, receipt.matches(preparationID: preparation.preparationID) else {
                    throw OnboardingRepositoryError.serviceUnavailable
                }
                submission = CompletionSubmission(submittedDraft: preparation.submittedDraft,
                    transport: .versioned(receipt))
                // Freeze the positive tuple before dispatch, including an uncertain wait.
                pendingCompletion = .submission(submission)
            case .submission(let value): submission = value
            case .reconciling: return // Handled above; never dispatch a stale completion.
            }
            submittedDraft = submission.submittedDraft
            switch submission.transport {
            case .legacy(let key):
                acknowledgement = try await repository.completeOfficial(submittedDraft, for: userID, idempotencyKey: key)
            case .versioned(let receipt):
                acknowledgement = try await repository.completeOfficial(submittedDraft, for: userID, completionIntent: receipt)
            }
            guard acknowledgement.matches(submittedDraft) else { throw OnboardingRepositoryError.serviceUnavailable }
        } catch is CancellationError {
            finishCancelledSubmission(id); return
        } catch {
            guard canPublish(id) else { finishCancelledSubmission(id); return }
            if error as? OnboardingRepositoryError == .completionIntentChanged,
               let attempt = pendingCompletion?.attempt {
                await reconcileCompletionIntent(attempt, for: id)
                return
            }
            if case .preparing(let preparation) = pendingCompletion {
                pendingCompletion = .preparationUncertain(preparation)
                publishFailure(error, for: id)
                return
            }
            if case .preparationUncertain = pendingCompletion {
                publishFailure(error, for: id)
                return
            }
            if error as? OnboardingRepositoryError == .objectiveNotEligible, !isReacceptance {
                pendingCompletion = nil
                activeSubmissionID = nil
                operationState = .idle
                moveToObjective()
                await prepareObjectiveIfNeeded()
                return
            }
            if error as? OnboardingRepositoryError == .requirementsChanged
                || error as? OnboardingRepositoryError == .alreadyCompleted
                || error as? OnboardingRepositoryError == .bodyPhotoConfirmationChanged {
                do {
                    let state = try await repository.loadState(for: userID)
                    guard canPublish(id) else { finishCancelledSubmission(id); return }
                    if state.completion.completed {
                        pendingCompletion = nil
                        didComplete = true
                        let cleanup = state.bodyPhotoCleanup.flatMap { scope in
                            scope.generation == state.completion.completedAt ? scope : nil
                        }
                        await onOfficialCleanupObserved(cleanup)
                        guard canPublish(id) else { finishCancelledSubmission(id); return }
                        activeSubmissionID = nil
                        operationState = .idle
                        notifyRootOnce()
                        return
                    }
                    if state.completion.completedAt != nil, state.draft == nil {
                        throw OnboardingRepositoryError.serviceUnavailable
                    }
                    pendingCompletion = nil
                    requirements = state.requirements
                    historicalCompletedAt = state.completion.completedAt
                    signupCompletion = state.signupCompletion
                    if error as? OnboardingRepositoryError == .bodyPhotoConfirmationChanged, !isReacceptance {
                        activeSubmissionID = nil
                        operationState = .idle
                        invalidateBodyPhotoConfirmation()
                        clearEligibility()
                        draft.currentStep = .bodyData
                        step = .bodyData
                        validationIssues = []
                        onStepChanged(.bodyData)
                        operationState = .failed(presentationError(for: error))
                        return
                    }
                    if isReacceptance, let authoritativeDraft = state.draft { draft = authoritativeDraft }
                    draft.localeIdentifier = state.locale
                    draft.documentActions = nil
                    eligibilityDecision = nil
                    eligibilitySnapshot = nil
                    draft.currentStep = .consent
                    step = .consent
                    onStepChanged(.consent)
                } catch {
                    publishFailure(error, for: id)
                    return
                }
            }
            publishFailure(error, for: id)
            return
        }
        guard canPublish(id) else { finishCancelledSubmission(id); return }
        // Acceptance survives a cancelled wait or a failed local cleanup write.
        // Neither may rearm the already acknowledged completion POST.
        didComplete = true
        pendingCompletion = nil
        await onOfficialCleanupObserved(acknowledgement.bodyPhotoCleanup)
        if canPublish(id) {
            activeSubmissionID = nil
            operationState = .idle
            if !isReacceptance, let welcome = acknowledgement.protocolWelcome {
                pendingProtocolWelcome = welcome
            } else {
                notifyRootOnce()
            }
        } else {
            finishCancelledSubmission(id)
        }
        if let selectedPersona = submittedDraft.persona {
            await telemetry.record(.coachPersonaSelected(selectedPersona.telemetryValue))
        }
        // The accepted record keeps its success telemetry even when its callback
        // tears down this owner. Late, unaccepted responses are guarded above.
        await telemetry.record(.onboardingStepCompleted(.completion))
        await telemetry.record(.onboardingCompleted)
    }

    private func reconcileCompletionIntent(_ attempt: CompletionAttempt, for id: UUID) async {
        guard canPublish(id) else { finishCancelledSubmission(id); return }
        // A failed read retains this phase. The next gesture repeats GET only.
        pendingCompletion = .reconciling(attempt, nil)
        do {
            let state = try await repository.loadState(for: userID)
            guard canPublish(id) else { finishCancelledSubmission(id); return }
            if state.completion.completed {
                pendingCompletion = nil
                didComplete = true
                let cleanup = state.bodyPhotoCleanup.flatMap { scope in
                    scope.generation == state.completion.completedAt ? scope : nil
                }
                await onOfficialCleanupObserved(cleanup)
                guard canPublish(id) else { finishCancelledSubmission(id); return }
                activeSubmissionID = nil
                operationState = .idle
                notifyRootOnce()
                return
            }
            guard state.completion.completedAt == nil || state.draft != nil else {
                throw OnboardingRepositoryError.serviceUnavailable
            }
            pendingCompletion = .reconciling(attempt, state)
            publishFailure(OnboardingRepositoryError.completionIntentChanged, for: id)
        } catch is CancellationError {
            finishCancelledSubmission(id)
        } catch {
            publishFailure(error, for: id)
        }
    }

    func finishProtocolWelcome() {
        guard isActive, !isCancellationRequested, didComplete, pendingProtocolWelcome != nil else { return }
        pendingProtocolWelcome = nil
        notifyRootOnce()
    }

    func cancelActiveSubmission() {
        guard activeSubmissionID != nil else { return }
        makePreparationUncertain()
        activeSubmissionID = nil
        operationState = .idle
    }

    func updateDisplayName(_ value: String?) { guard allowsDraftEditing else { return }; draft.displayName = value }
    func updateLocaleIdentifier(_ value: String) { guard allowsDraftEditing else { return }; if draft.localeIdentifier != value { invalidateBodyPhotoConfirmation() }; draft.localeIdentifier = value; clearEligibility() }
    func updateCountryCode(_ value: String) { guard allowsDraftEditing else { return }; draft.countryCode = value.uppercased() }
    func updateTimeZoneIdentifier(_ value: String) {
        guard allowsDraftEditing else { return }
        let civil = draft.birthDate.flatMap { OnboardingCivilDate.string(from: $0, timeZoneIdentifier: draft.timeZoneIdentifier) }
        draft.timeZoneIdentifier = value
        if let civil, let date = OnboardingCivilDate.date(from: civil, timeZoneIdentifier: value) { draft.birthDate = date }
    }
    func updateBiologicalSex(_ value: BiologicalSex?) { guard allowsDraftEditing else { return }; if draft.biologicalSex != value { invalidateBodyPhotoConfirmation() }; draft.biologicalSex = value; clearEligibility() }
    func updateBirthDate(_ value: Date?) { guard allowsDraftEditing else { return }; if draft.birthDate != value { invalidateBodyPhotoConfirmation() }; draft.birthDate = value }
    func updateHeightCM(_ value: Double?) { guard allowsDraftEditing else { return }; draft.heightCM = value; clearEligibility() }
    func updateWeightKG(_ value: Double?) { guard allowsDraftEditing else { return }; draft.weightKG = value; clearEligibility() }
    func updateBodyFatPercent(_ value: Double?) {
        guard allowsDraftEditing else { return }
        draft.bodyFatPercent = value
        draft.bodyFatOrigin = value == nil ? nil : .typed
        draft.bodyPhotoConfirmation = nil
        verifiedPhotoConfirmation = nil
        clearEligibility()
    }
    func updateObjective(_ value: BodyFlowObjective?) {
        guard allowsDraftEditing, !isReacceptance, hasCurrentEligibilityDecision,
              value == nil || eligibilityDecision?.permits(value) == true else { return }
        draft.objective = value
    }
    func updateActivityLevel(_ value: ActivityLevel?) { guard allowsDraftEditing else { return }; draft.activityLevel = value }
    func updateTrainingFrequency(_ value: Int?) { guard allowsDraftEditing else { return }; draft.trainingFrequency = value; clearEligibility() }
    func updateWaterIntake(_ value: WaterIntake?) { guard allowsDraftEditing else { return }; draft.waterIntake = value }
    func updateHungerLevel(_ value: HungerLevel?) { guard allowsDraftEditing else { return }; draft.hungerLevel = value }
    func updateWakeTime(_ value: LocalTime?) { guard allowsDraftEditing else { return }; draft.wakeTime = value }
    func updateBedtime(_ value: LocalTime?) { guard allowsDraftEditing else { return }; draft.bedtime = value }
    func updateFoodOrganization(_ value: FoodOrganization?) { guard allowsDraftEditing else { return }; draft.foodOrganization = value }
    func updatePersona(_ value: CoachPersona?) { guard allowsDraftEditing else { return }; draft.persona = value }
    func updateConsent(_ value: DevelopmentConsentAcceptance?) { guard allowsDraftEditing else { return }; draft.consent = value; clearEligibility() }
    func updateDocumentAction(_ action: OnboardingDocumentAction, selected: Bool) {
        guard allowsDraftEditing else { return }
        var actions = Set(draft.documentActions ?? [])
        if selected { actions.insert(action) } else { actions.remove(action) }
        draft.documentActions = actions.isEmpty ? nil : requirements.documents.map(\.explicitAction).filter(actions.contains)
        clearEligibility()
    }

    var hasRequiredDevelopmentConsent: Bool { issues(for: .consent).isEmpty }
    var stepPresentation: OnboardingStepPresentation {
        if !requirements.available, !developmentConsentAvailability.allowsSyntheticDevelopmentConsent,
           step == .consent || step == .objective || step == .completion { return .developmentConsentUnavailable }
        return .step(step)
    }

    private func issues(for step: OnboardingStep) -> [OnboardingValidationIssue] {
        OnboardingStepValidator.issues(for: step, draft: draft,
            developmentConsentAvailability: developmentConsentAvailability, requirements: requirements, now: now())
    }
    private func prerequisiteIssues() -> [OnboardingValidationIssue] {
        OnboardingStep.allCases.prefix(while: { $0 != .objective }).flatMap { issues(for: $0) }
    }
    private func currentEligibilitySnapshot() -> EligibilitySnapshot? {
        guard prerequisiteIssues().isEmpty, let input = try? OnboardingEligibilityInput(draft: draft) else { return nil }
        return EligibilitySnapshot(input: input, actions: Set(draft.documentActions ?? []), developmentConsent: draft.consent)
    }
    private func apply(_ answer: OnboardingEligibilityDecision, to draft: inout OnboardingDraft) {
        if answer.decision == .assigned { draft.objective = answer.objective }
        else if !answer.permits(draft.objective) { draft.objective = nil }
    }
    private func clearEligibility() {
        eligibilityDecision = nil
        eligibilitySnapshot = nil
        if pendingCompletion == nil, activeSubmissionID != nil { cancelActiveSubmission() }
    }
    private func moveToObjective() {
        clearEligibility()
        step = .objective
        draft.currentStep = .objective
        validationIssues = []
        onStepChanged(.objective)
    }
    private func notifyRootOnce() {
        guard isActive, !isCancellationRequested, !didNotifyRoot else { return }
        didNotifyRoot = true
        onCompleted()
    }
    private var isCancellationRequested: Bool { !isActive || Task.isCancelled || cancellationCheck() }
    private func canPublish(_ id: UUID) -> Bool { activeSubmissionID == id && !isCancellationRequested }
    private func finishCancelledSubmission(_ id: UUID) {
        guard activeSubmissionID == id else { return }
        makePreparationUncertain()
        activeSubmissionID = nil
        operationState = .idle
    }
    private func makePreparationUncertain() {
        if case .preparing(let preparation) = pendingCompletion {
            pendingCompletion = .preparationUncertain(preparation)
        }
    }
    private func publishFailure(_ error: Error, for id: UUID) {
        guard canPublish(id) else { finishCancelledSubmission(id); return }
        activeSubmissionID = nil
        operationState = .failed(presentationError(for: error))
    }
    private func presentationError(for error: Error) -> AppPresentationError {
        switch error {
        case OnboardingRepositoryError.invalidDraft: .invalidInput
        case OnboardingRepositoryError.objectiveNotEligible,
             OnboardingRepositoryError.documentsUnavailable,
             OnboardingRepositoryError.requirementsChanged,
             OnboardingRepositoryError.alreadyCompleted,
             OnboardingRepositoryError.bodyPhotoConfirmationChanged,
             OnboardingRepositoryError.completionIntentChanged,
             OnboardingRepositoryError.developmentConsentForbidden: .operationUnavailable
        case OnboardingRepositoryError.serviceUnavailable, CoachPersonaRepositoryError.serviceUnavailable: .serviceUnavailable
        case OnboardingRepositoryError.storageUnavailable, CoachPersonaRepositoryError.storageUnavailable: .storageUnavailable
        default: .operationUnavailable
        }
    }
}
