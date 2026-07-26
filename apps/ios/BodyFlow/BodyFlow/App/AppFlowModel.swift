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

    init(
        authentication: any AuthenticationService,
        onboarding: any OnboardingRepository,
        persona: any CoachPersonaRepository,
        telemetry: any TelemetryClient,
        cancellationCheck: @escaping @MainActor () -> Bool = { false }
    ) {
        self.authentication = authentication
        self.onboarding = onboarding
        self.persona = persona
        self.telemetry = telemetry
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
        presentationError = error
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
