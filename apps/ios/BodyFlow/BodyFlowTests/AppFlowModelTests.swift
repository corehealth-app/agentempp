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
            telemetry: InMemoryTelemetryClient(),
            initialAuthOperationState: .failed(.operationUnavailable)
        )

        await model.start()

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
        #expect(model.presentationError == nil)
        #expect(model.authOperationState == .idle)
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
        #expect(model.authOperationState == .failed(.serviceUnavailable))
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

    @Test("authentication destinations are driven by explicit commands")
    func authenticationDestinations() async {
        let model = makeModel()
        await model.start()

        model.showSignUp()
        #expect(model.state == .signedOut(.signUp))

        model.showPasswordRecovery()
        #expect(model.state == .signedOut(.passwordRecovery))

        model.showSignIn()
        #expect(model.state == .signedOut(.signIn))
    }

    @Test("sign in resumes onboarding for an incomplete session")
    func signInResumesOnboarding() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                signedInSession: session
            ),
            onboarding: OnboardingRepositorySpy(
                loadedDraft: BodyFlowTestFixtures.onboardingDraft(
                    currentStep: .routine
                )
            ),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.signIn(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(model.state == .onboarding(userID: "fixture-user", step: .routine))
        #expect(model.currentSession == session)
        #expect(model.authOperationState == .idle)
    }

    @Test("sign in opens the shell for a completed session")
    func signInOpensAuthenticatedShell() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                signedInSession: session
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.signIn(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(model.currentSession == session)
        #expect(model.authOperationState == .idle)
    }

    @Test("sign up success waits for email confirmation")
    func signUpAwaitsConfirmation() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                signUpResult: .confirmationRequired(
                    email: "fixture@example.invalid"
                )
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.signUp(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(
            model.state == .awaitingEmailConfirmation(
                email: "fixture@example.invalid"
            )
        )
        #expect(model.currentSession == nil)
        #expect(model.authOperationState == .idle)
    }

    @Test("development confirmation enters onboarding")
    func developmentConfirmationEntersOnboarding() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                confirmedSession: session
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )

        await model.confirmEmailForDevelopment()

        #expect(model.state == .onboarding(userID: "fixture-user", step: .welcome))
        #expect(model.currentSession == session)
        #expect(model.authOperationState == .idle)
    }

    @Test("recovery success discloses no account state")
    func recoveryUsesNeutralConfirmation() async {
        let model = makeModel()
        await model.start()
        model.showPasswordRecovery()

        await model.requestPasswordRecovery(
            email: "fixture@example.invalid"
        )

        #expect(model.state == .signedOut(.passwordRecovery))
        #expect(model.currentSession == nil)
        #expect(model.presentationError == nil)
        #expect(model.authOperationState == .recoveryConfirmation)
    }

    @Test("a second submit is suppressed while sign in is in flight")
    func suppressesDoubleTap() async {
        let authentication = SuspendedAuthenticationService()
        let model = AppFlowModel(
            authentication: authentication,
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )
        await model.start()

        let firstSubmission = Task {
            await model.signIn(
                email: "fixture@example.invalid",
                password: "local-pass"
            )
        }
        await authentication.waitUntilSignInSuspends()

        await model.signIn(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(await authentication.signInCount() == 1)
        #expect(model.authOperationState == .submitting)

        await authentication.resumeSignIn(returning: .completedFixture)
        await firstSubmission.value

        #expect(model.state == .authenticated(userID: "fixture-user"))
    }

    @Test("cancelled submission ignores a late successful response")
    func cancellationPreventsLateTransition() async {
        let authentication = SuspendedAuthenticationService()
        let model = AppFlowModel(
            authentication: authentication,
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )
        await model.start()

        let submission = Task {
            await model.signIn(
                email: "fixture@example.invalid",
                password: "local-pass"
            )
        }
        await authentication.waitUntilSignInSuspends()

        submission.cancel()
        await authentication.resumeSignIn(returning: .completedFixture)
        await submission.value

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
        #expect(model.authOperationState == .idle)
    }

    private func makeModel() -> AppFlowModel {
        AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: nil),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient()
        )
    }
}

private struct AuthenticationServiceSpy: AuthenticationService {
    let restoredSession: AuthSession?
    let restoreError: AuthenticationError?
    let signedInSession: AuthSession?
    let signUpResult: AuthSignUpResult?
    let confirmedSession: AuthSession?
    let recoveryError: AuthenticationError?

    init(
        restoredSession: AuthSession?,
        restoreError: AuthenticationError? = nil,
        signedInSession: AuthSession? = nil,
        signUpResult: AuthSignUpResult? = nil,
        confirmedSession: AuthSession? = nil,
        recoveryError: AuthenticationError? = nil
    ) {
        self.restoredSession = restoredSession
        self.restoreError = restoreError
        self.signedInSession = signedInSession
        self.signUpResult = signUpResult
        self.confirmedSession = confirmedSession
        self.recoveryError = recoveryError
    }

    func restoreSession() async throws -> AuthSession? {
        if let restoreError {
            throw restoreError
        }
        return restoredSession
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard let signedInSession else {
            throw AuthenticationError.operationUnavailable
        }
        return signedInSession
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        guard let signUpResult else {
            throw AuthenticationError.operationUnavailable
        }
        return signUpResult
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        guard let confirmedSession else {
            throw AuthenticationError.operationUnavailable
        }
        return confirmedSession
    }

    func requestPasswordRecovery(email: String) async throws {
        if let recoveryError {
            throw recoveryError
        }
    }

    func signOut() async throws {}
}

private actor SuspendedAuthenticationService: AuthenticationService {
    private var continuation: CheckedContinuation<AuthSession, any Error>?
    private var count = 0

    func restoreSession() async throws -> AuthSession? {
        nil
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        count += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
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

    func waitUntilSignInSuspends() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func signInCount() -> Int {
        count
    }

    func resumeSignIn(returning session: AuthSession) {
        continuation?.resume(returning: session)
        continuation = nil
    }
}

private extension AuthSession {
    static let completedFixture = AuthSession(
        userID: "fixture-user",
        email: "fixture@example.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: true
    )
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
