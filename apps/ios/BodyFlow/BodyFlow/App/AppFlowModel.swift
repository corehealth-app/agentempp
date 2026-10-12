import Foundation
import Observation

enum AuthDestination: Equatable, Sendable {
    case signIn
    case signUp
    case passwordRecovery
}

enum AppFlowState: Equatable, Sendable {
    case launching
    case signedOut(AuthDestination)
    case awaitingEmailConfirmation(email: String)
    case onboarding(userID: String, step: OnboardingStep)
    case authenticated(userID: String)
}

enum AppPresentationError: Equatable, Sendable {
    case invalidInput
    case invalidCredentials
    case confirmationRequired
    case operationUnavailable
    case serviceUnavailable
    case storageUnavailable
    /// Sign-up refused: the e-mail already has an account.
    case emailAlreadyRegistered
    /// Sign-up refused: the password is too weak for the auth server.
    case weakPassword
    /// Sign-up refused for another reason in what was sent.
    case signUpRejected
    /// Sign-up refused: too many attempts in a short time.
    case tooManyAttempts
}

/// Why the sign-up of the signed-in account could not be loaded, as far as
/// the screen needs to tell the cases apart.
enum OnboardingLoadFailure: Equatable, Sendable {
    /// The e-mail belongs to the team's panel: trying again cannot help.
    case teamPanelAccount
    /// Anything else: trying again may work.
    case temporary
}

@MainActor
@Observable
final class AppFlowModel {
    private let authentication: any AuthenticationService
    private let onboarding: any OnboardingRepository
    private let persona: any CoachPersonaRepository
    private let telemetry: any TelemetryClient
    private let developmentConsentAvailability: DevelopmentConsentAvailability
    private let now: @MainActor () -> Date
    private let cancellationCheck: @MainActor () -> Bool
    private var activeOnboardingRestoreID: UUID?
    private var publishedOnboardingActivationID: UUID?
    private let cleanupCoordinator: SignupBodyPhotoCleanupRootCoordinator

    private(set) var cleanupOwnerToken: SignupBodyPhotoCleanupOwnerToken?
    @ObservationIgnored private(set) var cleanupEventTask: Task<Void, Never>?

    private(set) var state: AppFlowState = .launching
    private(set) var currentSession: AuthSession?
    private(set) var presentationError: AppPresentationError?
    private(set) var authOperationState: AuthOperationState = .idle
    private(set) var restoredOnboardingDraft: OnboardingDraft?
    private(set) var restoredOnboardingRequirements: OnboardingRequirements = .unavailable
    private(set) var onboardingRestoreGeneration = 0
    private(set) var restoredHistoricalCompletedAt: String?
    /// Set while the root shows the sign-up load error; `nil` everywhere else.
    private(set) var onboardingLoadFailure: OnboardingLoadFailure?

    private var restoredOnboardingRepository: (any OnboardingRepository)?

    /// The immutable scope used by the restore is also the model's repository.
    var onboardingRepositoryForCurrentOwner: any OnboardingRepository {
        restoredOnboardingRepository ?? onboarding
    }

    var onboardingOwnerToken: OnboardingOwnerToken? {
        guard activeOnboardingRestoreID == nil,
              publishedOnboardingActivationID == cleanupOwnerToken?.activationID,
              case .onboarding(let userID, _) = state else { return nil }
        return OnboardingOwnerToken(userID: userID, restoreGeneration: onboardingRestoreGeneration)
    }

    init(
        authentication: any AuthenticationService,
        onboarding: any OnboardingRepository,
        persona: any CoachPersonaRepository,
        telemetry: any TelemetryClient,
        signupBodyPhotoCleanup: SignupBodyPhotoCleanupCapability? = nil,
        initialState: AppFlowState = .launching,
        initialAuthOperationState: AuthOperationState = .idle,
        developmentConsentAvailability: DevelopmentConsentAvailability = .unavailable,
        now: @escaping @MainActor () -> Date = Date.init,
        cancellationCheck: @escaping @MainActor () -> Bool = { false }
    ) {
        self.authentication = authentication
        self.onboarding = onboarding
        self.persona = persona
        self.telemetry = telemetry
        cleanupCoordinator = SignupBodyPhotoCleanupRootCoordinator(capability: signupBodyPhotoCleanup)
        self.developmentConsentAvailability = developmentConsentAvailability
        self.now = now
        state = initialState
        authOperationState = initialAuthOperationState
        self.cancellationCheck = cancellationCheck
    }

    @discardableResult
    func setCleanupActive(_ active: Bool) -> Task<Void, Never>? {
        retainCleanupEvent(cleanupCoordinator.setActive(active))
    }

    @discardableResult
    func observeOnboardingCleanup(_ observation: OnboardingBodyPhotoCleanupScope?,
        ownerToken: OnboardingOwnerToken) async -> Task<Void, Never>? {
        guard !isCancellationRequested, onboardingOwnerToken == ownerToken,
              let activation = cleanupOwnerToken, activation.userID == ownerToken.userID else { return nil }
        await cleanupCoordinator.observeOfficial(observation, owner: activation)
        guard !isCancellationRequested, onboardingOwnerToken == ownerToken,
              cleanupOwnerToken == activation else { return nil }
        return retainCleanupEvent(cleanupCoordinator.completionObserved(owner: activation,
            freshObservation: .init(currentScope: observation)))
    }

    @discardableResult
    private func retainCleanupEvent(_ task: Task<Void, Never>?) -> Task<Void, Never>? {
        if let task { cleanupEventTask = task }
        return task
    }

    private func invalidateCleanupActivation() {
        cleanupOwnerToken = nil
        cleanupEventTask = nil
        cleanupCoordinator.invalidate()
    }

    func start() async {
        presentationError = nil

        do {
            let restoredSession = try await authentication.restoreSession()
            guard !isCancellationRequested else { return }

            guard let restoredSession else {
                transitionToSignedOut()
                await telemetry.record(.authScreenViewed(.signIn))
                return
            }

            await restore(restoredSession)
        } catch {
            guard !isCancellationRequested else { return }
            transitionToSignedOut(error: presentationError(for: error))
            await telemetry.record(.authScreenViewed(.signIn))
        }
    }

    func signOut() async {
        do {
            try await authentication.signOut()
            guard !isCancellationRequested else { return }
            transitionToSignedOut()
            await telemetry.record(TelemetryEvent(name: .signOutCompleted))
        } catch {
            guard !isCancellationRequested else { return }
            let error = presentationError(for: error)
            presentationError = error
            authOperationState = .failed(error)
        }
    }

    func retryOnboardingRestore() async {
        guard let session = currentSession,
              session.isEmailConfirmed,
              case .onboarding(let userID, _) = state,
              userID == session.userID else {
            return
        }

        presentationError = nil
        guard let activation = cleanupOwnerToken, activation.userID == session.userID else { return }
        let restoreID = beginOnboardingRestore()
        await cleanupCoordinator.transition(to: activation)
        guard canPublishOnboardingRestore(restoreID, activation: activation) else {
            finishOnboardingRestoreIfCurrent(restoreID)
            return
        }
        await restoreOnboarding(session, activation: activation, restoreID: restoreID)
    }

    func showSignUp() async {
        guard navigate(to: .signUp) else { return }
        await telemetry.record(.authScreenViewed(.signUp))
    }

    func showPasswordRecovery() async {
        guard navigate(to: .passwordRecovery) else { return }
        await telemetry.record(.authScreenViewed(.passwordRecovery))
    }

    func showSignIn() async {
        guard navigate(to: .signIn) else { return }
        await telemetry.record(.authScreenViewed(.signIn))
    }

    func updateOnboardingStep(_ step: OnboardingStep, ownerToken: OnboardingOwnerToken) {
        guard onboardingOwnerToken == ownerToken else { return }
        updateOnboardingStep(step)
    }

    func completeOnboarding(ownerToken: OnboardingOwnerToken) {
        guard onboardingOwnerToken == ownerToken else { return }
        completeOnboarding(for: ownerToken.userID)
    }

    func updateOnboardingStep(_ step: OnboardingStep) {
        guard case .onboarding(let userID, _) = state else { return }
        state = .onboarding(userID: userID, step: step)
    }

    func completeOnboarding(for userID: String) {
        guard !isCancellationRequested,
              case .onboarding(let activeUserID, _) = state,
              activeUserID == userID,
              let session = currentSession,
              session.userID == userID,
              session.isEmailConfirmed,
              !session.isOnboardingCompleted else {
            return
        }

        currentSession = AuthSession(
            userID: session.userID,
            email: session.email,
            isEmailConfirmed: session.isEmailConfirmed,
            isOnboardingCompleted: true
        )
        invalidateOnboardingRestore()
        restoredOnboardingDraft = nil
        restoredOnboardingRequirements = .unavailable
        restoredHistoricalCompletedAt = nil
        onboardingLoadFailure = nil
        state = .authenticated(userID: userID)
    }

    func signIn(email: String, password: String) async {
        guard beginAuthOperation() else { return }

        do {
            let session = try await authentication.signIn(
                email: email,
                password: password
            )
            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }

            await restore(session)
            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }
            authOperationState = .idle
            await telemetry.record(.authOperationCompleted(
                screen: .signIn,
                outcome: .success
            ))
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            await failAuthOperation(with: error, screen: .signIn)
        }
    }

    func signUp(email: String, password: String) async {
        guard beginAuthOperation() else { return }

        do {
            let result = try await authentication.signUp(
                email: email,
                password: password
            )
            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }

            switch result {
            case .confirmationRequired(let email):
                invalidateCleanupActivation()
                currentSession = nil
                state = .awaitingEmailConfirmation(email: email)
                await telemetry.record(.authScreenViewed(.emailConfirmation))
            case .authenticated(let session):
                await restore(session)
            }

            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }
            authOperationState = .idle
            await telemetry.record(.authOperationCompleted(
                screen: .signUp,
                outcome: .success
            ))
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            await failAuthOperation(with: error, screen: .signUp)
        }
    }

    func confirmEmailForDevelopment() async {
        guard beginAuthOperation() else { return }

        do {
            let session = try await authentication.confirmEmailForDevelopment()
            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }

            await restore(session)
            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }
            authOperationState = .idle
            await telemetry.record(.authOperationCompleted(
                screen: .emailConfirmation,
                outcome: .success
            ))
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            await failAuthOperation(with: error, screen: .emailConfirmation)
        }
    }

    func requestPasswordRecovery(email: String) async {
        guard beginAuthOperation() else { return }

        do {
            try await authentication.requestPasswordRecovery(email: email)
            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }
            authOperationState = .recoveryConfirmation
            await telemetry.record(.authOperationCompleted(
                screen: .passwordRecovery,
                outcome: .success
            ))
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            await failAuthOperation(with: error, screen: .passwordRecovery)
        }
    }

    private func restore(_ session: AuthSession) async {
        guard !isCancellationRequested else { return }

        guard session.isEmailConfirmed else {
            guard !isCancellationRequested else { return }
            invalidateOnboardingRestore()
            invalidateCleanupActivation()
            restoredOnboardingDraft = nil
            restoredOnboardingRequirements = .unavailable
            restoredHistoricalCompletedAt = nil
            onboardingLoadFailure = nil
            currentSession = session
            guard !isCancellationRequested else {
                currentSession = nil
                return
            }
            state = .awaitingEmailConfirmation(email: session.email)
            await telemetry.record(.authScreenViewed(.emailConfirmation))
            return
        }

        // A new confirmed authentication activation must not reuse authority
        // from an earlier restore, even when the user ID happens to match.
        invalidateOnboardingRestore()
        let activation = SignupBodyPhotoCleanupOwnerToken(userID: session.userID, activationID: UUID())
        cleanupOwnerToken = activation
        cleanupEventTask = nil
        let restoreID = beginOnboardingRestore()
        await cleanupCoordinator.transition(to: activation)
        guard canPublishOnboardingRestore(restoreID, activation: activation) else {
            finishOnboardingRestoreIfCurrent(restoreID)
            return
        }
        await restoreOnboarding(session, activation: activation, restoreID: restoreID)
    }

    private func restoreOnboarding(_ session: AuthSession,
        activation: SignupBodyPhotoCleanupOwnerToken, restoreID: UUID) async {
        var freshObservation: SignupBodyPhotoCleanupFreshObservation?
        do {
            let scopedOnboarding = try await onboarding.scoped(for: session.userID)
            guard canPublishOnboardingRestore(restoreID, activation: activation) else {
                finishOnboardingRestoreIfCurrent(restoreID)
                return
            }
            let serverState = try await scopedOnboarding.loadState(for: session.userID)
            guard canPublishOnboardingRestore(restoreID, activation: activation) else {
                finishOnboardingRestoreIfCurrent(restoreID)
                return
            }
            let cleanup = serverState.bodyPhotoCleanup.flatMap { scope in
                scope.generation == serverState.completion.completedAt ? scope : nil
            }
            freshObservation = .init(currentScope: cleanup)
            await cleanupCoordinator.observeOfficial(cleanup, owner: activation)
            guard canPublishOnboardingRestore(restoreID, activation: activation) else {
                finishOnboardingRestoreIfCurrent(restoreID)
                return
            }

            if serverState.completion.completed {
                retainCleanupEvent(cleanupCoordinator.finishRestore(owner: activation,
                    freshObservation: freshObservation))
                publishCompletedOnboardingRestore(session: session)
                finishOnboardingRestoreIfCurrent(restoreID)
                return
            }

            var draft: OnboardingDraft
            if serverState.completion.completedAt != nil {
                guard let authoritativeDraft = serverState.draft else {
                    throw OnboardingRepositoryError.serviceUnavailable
                }
                draft = authoritativeDraft
                draft.currentStep = .consent
                draft.documentActions = nil
            } else {
                draft = serverState.draft ?? .currentDeviceWelcome
            }
            draft.localeIdentifier = serverState.locale
            draft = OnboardingResumePolicy.normalizedDraft(draft, requirements: serverState.requirements,
                developmentConsentAvailability: developmentConsentAvailability,
                historicalCompletedAt: serverState.completion.completedAt, now: now())
            retainCleanupEvent(cleanupCoordinator.finishRestore(owner: activation,
                freshObservation: freshObservation))
            restoredOnboardingRepository = scopedOnboarding
            publishOnboardingRestore(
                session: session,
                draft: draft,
                requirements: serverState.requirements,
                historicalCompletedAt: serverState.completion.completedAt
            )
            finishOnboardingRestoreIfCurrent(restoreID)
            let step = draft.currentStep
            await telemetry.record(.onboardingStepViewed(step.telemetryValue))
        } catch {
            guard canPublishOnboardingRestore(restoreID, activation: activation) else {
                finishOnboardingRestoreIfCurrent(restoreID)
                return
            }

            // A failed GET leaves the ordinary sweep available. Only an
            // actually received normal response can supply a fresh observation.
            retainCleanupEvent(cleanupCoordinator.finishRestore(owner: activation,
                freshObservation: freshObservation))
            publishOnboardingRestore(
                session: session,
                draft: nil,
                error: presentationError(for: error),
                loadFailure: onboardingLoadFailure(for: error)
            )
            finishOnboardingRestoreIfCurrent(restoreID)
        }
    }

    private func beginOnboardingRestore() -> UUID {
        restoredOnboardingRepository = nil
        let restoreID = UUID()
        activeOnboardingRestoreID = restoreID
        return restoreID
    }

    private func canPublishOnboardingRestore(_ restoreID: UUID,
        activation: SignupBodyPhotoCleanupOwnerToken) -> Bool {
        activeOnboardingRestoreID == restoreID && cleanupOwnerToken == activation && !isCancellationRequested
    }

    private func finishOnboardingRestoreIfCurrent(_ restoreID: UUID) {
        guard activeOnboardingRestoreID == restoreID else { return }
        activeOnboardingRestoreID = nil
    }

    private func invalidateOnboardingRestore() {
        activeOnboardingRestoreID = nil
        restoredOnboardingRepository = nil
    }

    private func publishOnboardingRestore(
        session: AuthSession,
        draft: OnboardingDraft?,
        requirements: OnboardingRequirements = .unavailable,
        historicalCompletedAt: String? = nil,
        error: AppPresentationError? = nil,
        loadFailure: OnboardingLoadFailure? = nil
    ) {
        currentSession = AuthSession(
            userID: session.userID,
            email: session.email,
            isEmailConfirmed: session.isEmailConfirmed,
            isOnboardingCompleted: false
        )
        guard !isCancellationRequested else {
            currentSession = nil
            return
        }

        restoredOnboardingDraft = draft
        restoredOnboardingRequirements = requirements
        restoredHistoricalCompletedAt = historicalCompletedAt
        presentationError = error
        onboardingLoadFailure = loadFailure
        onboardingRestoreGeneration += 1
        // Ending a canceled restore must not grant a new activation authority
        // over the preceding snapshot. Only a guarded publication binds them.
        publishedOnboardingActivationID = cleanupOwnerToken?.activationID
        state = .onboarding(
            userID: session.userID,
            step: draft?.currentStep ?? .welcome
        )
    }

    private func publishCompletedOnboardingRestore(session: AuthSession) {
        restoredOnboardingRepository = nil
        currentSession = AuthSession(
            userID: session.userID,
            email: session.email,
            isEmailConfirmed: session.isEmailConfirmed,
            isOnboardingCompleted: true
        )
        restoredOnboardingDraft = nil
        restoredOnboardingRequirements = .unavailable
        restoredHistoricalCompletedAt = nil
        presentationError = nil
        onboardingLoadFailure = nil
        state = .authenticated(userID: session.userID)
    }

    private func transitionToSignedOut(error: AppPresentationError? = nil) {
        guard !isCancellationRequested else { return }
        invalidateOnboardingRestore()
        invalidateCleanupActivation()
        restoredOnboardingDraft = nil
        restoredOnboardingRequirements = .unavailable
        restoredHistoricalCompletedAt = nil
        onboardingLoadFailure = nil
        currentSession = nil
        state = .signedOut(.signIn)
        if let error {
            presentationError = error
            authOperationState = .failed(error)
        } else {
            presentationError = nil
            authOperationState = .idle
        }
    }

    @discardableResult
    private func navigate(to destination: AuthDestination) -> Bool {
        guard authOperationState != .submitting,
              isAuthenticationNavigationAllowed else {
            return false
        }
        invalidateOnboardingRestore()
        invalidateCleanupActivation()
        restoredOnboardingDraft = nil
        restoredOnboardingRequirements = .unavailable
        restoredHistoricalCompletedAt = nil
        onboardingLoadFailure = nil
        currentSession = nil
        state = .signedOut(destination)
        presentationError = nil
        authOperationState = .idle
        return true
    }

    private var isAuthenticationNavigationAllowed: Bool {
        switch state {
        case .signedOut, .awaitingEmailConfirmation:
            true
        case .launching, .onboarding, .authenticated:
            false
        }
    }

    private func beginAuthOperation() -> Bool {
        guard authOperationState != .submitting else {
            return false
        }
        presentationError = nil
        authOperationState = .submitting
        return true
    }

    private func finishCancelledAuthOperation() {
        authOperationState = .idle
    }

    private func failAuthOperation(
        with error: Error,
        screen: TelemetryAuthScreen
    ) async {
        guard !isCancellationRequested else {
            finishCancelledAuthOperation()
            return
        }
        let error = presentationError(for: error)
        presentationError = error
        authOperationState = .failed(error)
        await telemetry.record(.authOperationCompleted(
            screen: screen,
            outcome: .failure,
            errorCategory: error.telemetryCategory
        ))
    }

    private var isCancellationRequested: Bool {
        Task.isCancelled || cancellationCheck()
    }

    /// What the load-error screen needs to know about a failed read of the
    /// sign-up: only the team-panel conflict is told apart.
    private func onboardingLoadFailure(for error: Error) -> OnboardingLoadFailure {
        switch error {
        case OnboardingRepositoryError.adminAccountConflict: .teamPanelAccount
        default: .temporary
        }
    }

    private func presentationError(for error: Error) -> AppPresentationError {
        switch error {
        case AuthenticationError.invalidInput, OnboardingRepositoryError.invalidDraft:
            .invalidInput
        case AuthenticationError.invalidCredentials:
            .invalidCredentials
        case AuthenticationError.confirmationRequired:
            .confirmationRequired
        case AuthenticationError.operationUnavailable,
             OnboardingRepositoryError.developmentConsentForbidden,
             OnboardingRepositoryError.documentsUnavailable,
             OnboardingRepositoryError.requirementsChanged,
             OnboardingRepositoryError.alreadyCompleted,
             OnboardingRepositoryError.adminAccountConflict:
            .operationUnavailable
        case AuthenticationError.serviceUnavailable,
             OnboardingRepositoryError.serviceUnavailable,
             CoachPersonaRepositoryError.serviceUnavailable:
            .serviceUnavailable
        case AuthenticationError.storageUnavailable,
             OnboardingRepositoryError.storageUnavailable,
             CoachPersonaRepositoryError.storageUnavailable:
            .storageUnavailable
        // A refused sign-up keeps its own reason all the way to the banner.
        case AuthenticationError.emailAlreadyRegistered:
            .emailAlreadyRegistered
        case AuthenticationError.weakPassword:
            .weakPassword
        case AuthenticationError.signUpRejected:
            .signUpRejected
        case AuthenticationError.tooManyAttempts:
            .tooManyAttempts
        default:
            .operationUnavailable
        }
    }
}

private extension AppPresentationError {
    var telemetryCategory: TelemetryErrorCategory {
        switch self {
        case .invalidInput:
            .invalidInput
        case .invalidCredentials:
            .invalidCredentials
        case .confirmationRequired:
            .confirmationRequired
        case .operationUnavailable:
            .operationUnavailable
        case .serviceUnavailable:
            .serviceUnavailable
        case .storageUnavailable:
            .storageUnavailable
        // A refused sign-up adds no telemetry value, and none that says an
        // account exists: what was sent was not accepted, or the service is
        // limiting attempts.
        case .emailAlreadyRegistered, .weakPassword, .signUpRejected:
            .invalidInput
        case .tooManyAttempts:
            .serviceUnavailable
        }
    }
}
