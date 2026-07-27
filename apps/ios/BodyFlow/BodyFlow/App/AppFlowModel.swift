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
}

@MainActor
@Observable
final class AppFlowModel {
    private let authentication: any AuthenticationService
    private let onboarding: any OnboardingRepository
    private let persona: any CoachPersonaRepository
    private let telemetry: any TelemetryClient
    private let cancellationCheck: @MainActor () -> Bool

    private(set) var state: AppFlowState = .launching
    private(set) var currentSession: AuthSession?
    private(set) var presentationError: AppPresentationError?
    private(set) var authOperationState: AuthOperationState = .idle

    init(
        authentication: any AuthenticationService,
        onboarding: any OnboardingRepository,
        persona: any CoachPersonaRepository,
        telemetry: any TelemetryClient,
        initialState: AppFlowState = .launching,
        initialAuthOperationState: AuthOperationState = .idle,
        cancellationCheck: @escaping @MainActor () -> Bool = { false }
    ) {
        self.authentication = authentication
        self.onboarding = onboarding
        self.persona = persona
        self.telemetry = telemetry
        state = initialState
        authOperationState = initialAuthOperationState
        self.cancellationCheck = cancellationCheck
    }

    func start() async {
        presentationError = nil

        do {
            let restoredSession = try await authentication.restoreSession()
            guard !isCancellationRequested else { return }

            guard let restoredSession else {
                transitionToSignedOut()
                return
            }

            await restore(restoredSession)
        } catch {
            guard !isCancellationRequested else { return }
            transitionToSignedOut(error: presentationError(for: error))
        }
    }

    func signOut() async {
        do {
            try await authentication.signOut()
            guard !isCancellationRequested else { return }
            transitionToSignedOut()
        } catch {
            guard !isCancellationRequested else { return }
            transitionToSignedOut(error: presentationError(for: error))
        }
    }

    func showSignUp() {
        navigate(to: .signUp)
    }

    func showPasswordRecovery() {
        navigate(to: .passwordRecovery)
    }

    func showSignIn() {
        navigate(to: .signIn)
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
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            failAuthOperation(with: error)
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
                currentSession = nil
                state = .awaitingEmailConfirmation(email: email)
            case .authenticated(let session):
                await restore(session)
            }

            guard !isCancellationRequested else {
                finishCancelledAuthOperation()
                return
            }
            authOperationState = .idle
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            failAuthOperation(with: error)
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
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            failAuthOperation(with: error)
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
        } catch is CancellationError {
            finishCancelledAuthOperation()
        } catch {
            failAuthOperation(with: error)
        }
    }

    private func restore(_ session: AuthSession) async {
        guard !isCancellationRequested else { return }

        guard session.isEmailConfirmed else {
            guard !isCancellationRequested else { return }
            currentSession = session
            guard !isCancellationRequested else {
                currentSession = nil
                return
            }
            state = .awaitingEmailConfirmation(email: session.email)
            return
        }

        guard !session.isOnboardingCompleted else {
            guard !isCancellationRequested else { return }
            currentSession = session
            guard !isCancellationRequested else {
                currentSession = nil
                return
            }
            state = .authenticated(userID: session.userID)
            return
        }

        do {
            let draft = try await onboarding.loadDraft(for: session.userID)
            guard !isCancellationRequested else { return }

            currentSession = session
            guard !isCancellationRequested else {
                currentSession = nil
                return
            }
            state = .onboarding(
                userID: session.userID,
                step: draft?.currentStep ?? .welcome
            )
        } catch {
            guard !isCancellationRequested else { return }

            currentSession = session
            guard !isCancellationRequested else {
                currentSession = nil
                return
            }
            state = .onboarding(userID: session.userID, step: .welcome)
            presentationError = presentationError(for: error)
        }
    }

    private func transitionToSignedOut(error: AppPresentationError? = nil) {
        guard !isCancellationRequested else { return }
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

    private func navigate(to destination: AuthDestination) {
        guard authOperationState != .submitting,
              isAuthenticationNavigationAllowed else {
            return
        }
        currentSession = nil
        state = .signedOut(destination)
        presentationError = nil
        authOperationState = .idle
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

    private func failAuthOperation(with error: Error) {
        guard !isCancellationRequested else {
            finishCancelledAuthOperation()
            return
        }
        let error = presentationError(for: error)
        presentationError = error
        authOperationState = .failed(error)
    }

    private var isCancellationRequested: Bool {
        Task.isCancelled || cancellationCheck()
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
             OnboardingRepositoryError.developmentConsentForbidden:
            .operationUnavailable
        case AuthenticationError.serviceUnavailable,
             OnboardingRepositoryError.serviceUnavailable,
             CoachPersonaRepositoryError.serviceUnavailable:
            .serviceUnavailable
        case AuthenticationError.storageUnavailable,
             OnboardingRepositoryError.storageUnavailable,
             CoachPersonaRepositoryError.storageUnavailable:
            .storageUnavailable
        default:
            .operationUnavailable
        }
    }
}
