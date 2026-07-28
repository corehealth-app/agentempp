import Foundation
import Testing

@testable import BodyFlow

@Suite("Telemetry")
struct TelemetryTests {
    @Test("allows exactly the approved privacy-safe event names")
    func allowsApprovedEventNames() {
        let approvedNames = [
            "auth_screen_viewed",
            "auth_operation_completed",
            "onboarding_step_viewed",
            "onboarding_step_completed",
            "coach_persona_selected",
            "onboarding_completed",
            "sign_out_completed",
        ]

        for name in approvedNames {
            #expect(
                TelemetryEventName(rawValue: name) != nil,
                "Expected approved event name \(name)"
            )
        }

        for name in ["app_launched", "tab_selected", "retry_requested"] {
            #expect(
                TelemetryEventName(rawValue: name) == nil,
                "Expected legacy event name \(name) to be unavailable"
            )
        }
    }

    @Test("discards every metadata key outside the privacy allowlist")
    func discardsUnsupportedMetadata() throws {
        let metadata: [String: any Sendable] = [
            "screen": "sign_in",
            "outcome": "failure",
            "error_category": "service_unavailable",
            "step": "welcome",
            "persona": "focus",
            "email": "person@example.invalid",
            "password": "local-pass",
            "birth_date": "2000-01-01",
            "height_cm": 170,
            "weight_kg": 65,
            "body_fat_percent": 25,
            "token": "provider-token",
            "raw_error": "provider failure body",
            "message": "free-form input",
        ]
        let eventName = try #require(
            TelemetryEventName(rawValue: "auth_operation_completed")
        )
        let event = TelemetryEvent(name: eventName, metadata: metadata)

        #expect(event.metadata == [
            "screen": .string("sign_in"),
            "outcome": .string("failure"),
            "error_category": .string("service_unavailable"),
            "step": .string("welcome"),
            "persona": .string("focus"),
        ])
    }

    @Test("discards free-form values even when they use approved keys")
    func discardsFreeFormValues() {
        let event = TelemetryEvent(
            name: .authOperationCompleted,
            metadata: [
                "screen": "person@example.invalid",
                "outcome": "deu tudo certo",
                "error_category": "provider said account exists",
                "step": "Pessoa Teste",
                "persona": "custom coach prompt",
            ]
        )

        #expect(event.metadata.isEmpty)
    }

    @MainActor
    @Test("records auth success only after the destination transition")
    func recordsAuthSuccessAfterTransition() async {
        let telemetry = InMemoryTelemetryClient()
        let model = makeAuthModel(
            outcome: .success(.completedFixture),
            telemetry: telemetry
        )

        await model.signIn(
            email: "person@example.invalid",
            password: "local-pass"
        )

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(await telemetry.snapshot() == [
            TelemetryEvent(
                name: .authOperationCompleted,
                metadata: [
                    "screen": "sign_in",
                    "outcome": "success",
                ]
            ),
        ])
    }

    @MainActor
    @Test("records auth failure with a bounded category and no raw text")
    func recordsBoundedAuthFailure() async {
        let telemetry = InMemoryTelemetryClient()
        let model = makeAuthModel(
            outcome: .failure(.serviceUnavailable),
            telemetry: telemetry
        )

        await model.signIn(
            email: "person@example.invalid",
            password: "local-pass"
        )

        #expect(model.state == .signedOut(.signIn))
        #expect(await telemetry.snapshot() == [
            TelemetryEvent(
                name: .authOperationCompleted,
                metadata: [
                    "screen": "sign_in",
                    "outcome": "failure",
                    "error_category": "service_unavailable",
                ]
            ),
        ])
    }

    @MainActor
    @Test("records no auth success when the operation is cancelled")
    func recordsNoAuthSuccessOnCancellation() async {
        let telemetry = InMemoryTelemetryClient()
        let model = makeAuthModel(
            outcome: .cancelled,
            telemetry: telemetry
        )

        await model.signIn(
            email: "person@example.invalid",
            password: "local-pass"
        )

        #expect(model.state == .signedOut(.signIn))
        #expect(await telemetry.snapshot().isEmpty)
    }

    @MainActor
    @Test("records the first auth screen after fresh restoration")
    func recordsFreshAuthScreenAfterTransition() async {
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: TelemetryAuthenticationService(
                signInOutcome: .failure(.operationUnavailable)
            ),
            onboarding: TelemetryOnboardingRepository(),
            persona: TelemetryPersonaRepository(),
            telemetry: telemetry
        )

        await model.start()

        #expect(model.state == .signedOut(.signIn))
        #expect(await telemetry.snapshot() == [
            TelemetryEvent(
                name: .authScreenViewed,
                metadata: ["screen": "sign_in"]
            ),
        ])
    }

    @MainActor
    @Test("records sign out only after returning to sign in")
    func recordsSignOutAfterTransition() async {
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: TelemetryAuthenticationService(
                signInOutcome: .failure(.operationUnavailable)
            ),
            onboarding: TelemetryOnboardingRepository(),
            persona: TelemetryPersonaRepository(),
            telemetry: telemetry,
            initialState: .authenticated(userID: "fixture-user")
        )

        await model.signOut()

        #expect(model.state == .signedOut(.signIn))
        #expect(await telemetry.snapshot() == [
            TelemetryEvent(name: .signOutCompleted),
        ])
    }

    @MainActor
    private func makeAuthModel(
        outcome: TelemetrySignInOutcome,
        telemetry: InMemoryTelemetryClient
    ) -> AppFlowModel {
        AppFlowModel(
            authentication: TelemetryAuthenticationService(
                signInOutcome: outcome
            ),
            onboarding: TelemetryOnboardingRepository(),
            persona: TelemetryPersonaRepository(),
            telemetry: telemetry,
            initialState: .signedOut(.signIn)
        )
    }
}

private enum TelemetrySignInOutcome: Sendable {
    case success(AuthSession)
    case failure(AuthenticationError)
    case cancelled
}

private struct TelemetryAuthenticationService: AuthenticationService {
    let signInOutcome: TelemetrySignInOutcome

    func restoreSession() async throws -> AuthSession? { nil }

    func signIn(email: String, password: String) async throws -> AuthSession {
        switch signInOutcome {
        case .success(let session):
            session
        case .failure(let error):
            throw error
        case .cancelled:
            throw CancellationError()
        }
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        throw AuthenticationError.operationUnavailable
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        throw AuthenticationError.operationUnavailable
    }

    func requestPasswordRecovery(email: String) async throws {}
    func signOut() async throws {}
}

private struct TelemetryOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private struct TelemetryPersonaRepository: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}

private extension AuthSession {
    static let completedFixture = AuthSession(
        userID: "fixture-user",
        email: "person@example.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: true
    )
}
