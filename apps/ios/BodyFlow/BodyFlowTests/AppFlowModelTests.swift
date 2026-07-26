import Testing

@testable import BodyFlow

@MainActor
@Suite("App flow model")
struct AppFlowModelTests {
    @Test("fresh launch restores into sign in")
    func freshLaunch() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: nil),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.start()

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
    }

    @Test("confirmed incomplete session resumes its saved onboarding step")
    func resumesOnboarding() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(loadedDraft: draft),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.start()

        #expect(model.state == .onboarding(userID: "fixture-user", step: .objective))
        #expect(model.currentSession == session)
    }

    @Test("confirmed complete session restores into the authenticated shell")
    func restoresAuthenticatedSession() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.start()

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(model.currentSession == session)
    }

    @Test("unconfirmed session awaits email confirmation")
    func awaitsEmailConfirmation() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: AuthSession(
                    userID: "fixture-user",
                    email: "fixture@example.invalid",
                    isEmailConfirmed: false,
                    isOnboardingCompleted: false
                )
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.start()

        #expect(
            model.state == .awaitingEmailConfirmation(
                email: "fixture@example.invalid"
            )
        )
    }

    @Test("restoration failure returns to sign in with a recoverable error")
    func handlesRestorationFailure() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                restoreError: .serviceUnavailable
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.start()

        #expect(model.state == .signedOut(.signIn))
        #expect(model.presentationError == .serviceUnavailable)
        #expect(model.currentSession == nil)
    }

    @Test("sign out returns to sign in")
    func signOutReturnsToSignIn() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: nil),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.signOut()

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
    }

    @Test("cancelled restoration never publishes an authenticated destination")
    func cancelledRestorationDoesNotNavigate() async {
        let cancellation = CancellationCheckSpy()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: AuthSession(
                    userID: "fixture-user",
                    email: "fixture@example.invalid",
                    isEmailConfirmed: true,
                    isOnboardingCompleted: true
                )
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            cancellationCheck: cancellation.isCancelled
        )

        await model.start()

        #expect(model.state == .launching)
        #expect(model.currentSession == nil)
    }
}

private struct AuthenticationServiceSpy: AuthenticationService {
    let restoredSession: AuthSession?
    let restoreError: AuthenticationError?

    init(
        restoredSession: AuthSession?,
        restoreError: AuthenticationError? = nil
    ) {
        self.restoredSession = restoredSession
        self.restoreError = restoreError
    }

    func restoreSession() async throws -> AuthSession? {
        if let restoreError {
            throw restoreError
        }
        return restoredSession
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        throw AuthenticationError.operationUnavailable
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        throw AuthenticationError.operationUnavailable
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        throw AuthenticationError.operationUnavailable
    }

    func requestPasswordRecovery(email: String) async throws {
        throw AuthenticationError.operationUnavailable
    }

    func signOut() async throws {}
}

private struct OnboardingRepositorySpy: OnboardingRepository {
    let loadedDraft: OnboardingDraft?

    init(loadedDraft: OnboardingDraft? = nil) {
        self.loadedDraft = loadedDraft
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        loadedDraft
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}

    func clear(for userID: String) async throws {}
}

private struct CoachPersonaRepositorySpy: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        nil
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}

@MainActor
private final class CancellationCheckSpy {
    private var callCount = 0

    func isCancelled() -> Bool {
        defer { callCount += 1 }
        return callCount > 0
    }
}
