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
    @Test("persisted-step restore records one viewed event after publishing that step")
    func persistedStepRestoreRecordsViewedAfterStatePublication() async {
        let telemetry = StateObservingTelemetryClient<AppFlowState>()
        let session = AuthSession(
            userID: "fixture-user",
            email: "person@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let model = AppFlowModel(
            authentication: RestoringTelemetryAuthenticationService(
                restoredSession: session
            ),
            onboarding: RestoringTelemetryOnboardingRepository(
                loadResult: .success(
                    BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
                )
            ),
            persona: TelemetryPersonaRepository(),
            telemetry: telemetry
        )
        await telemetry.observe { model.state }

        await model.start()

        let publishedState = AppFlowState.onboarding(
            userID: "fixture-user",
            step: .objective
        )
        #expect(model.state == publishedState)
        #expect(await telemetry.snapshot() == [
            ObservedTelemetryRecord(
                event: TelemetryEvent(
                    name: .onboardingStepViewed,
                    metadata: ["step": "objective"]
                ),
                state: publishedState
            ),
        ])
    }

    @MainActor
    @Test("nil-draft restore records welcome viewed after publishing the fallback")
    func nilDraftRestoreRecordsWelcomeAfterStatePublication() async {
        let telemetry = StateObservingTelemetryClient<AppFlowState>()
        let session = AuthSession(
            userID: "fixture-user",
            email: "person@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let model = AppFlowModel(
            authentication: RestoringTelemetryAuthenticationService(
                restoredSession: session
            ),
            onboarding: RestoringTelemetryOnboardingRepository(
                loadResult: .success(nil)
            ),
            persona: TelemetryPersonaRepository(),
            telemetry: telemetry
        )
        await telemetry.observe { model.state }

        await model.start()

        let publishedState = AppFlowState.onboarding(
            userID: "fixture-user",
            step: .welcome
        )
        #expect(model.state == publishedState)
        #expect(await telemetry.snapshot() == [
            ObservedTelemetryRecord(
                event: TelemetryEvent(
                    name: .onboardingStepViewed,
                    metadata: ["step": "welcome"]
                ),
                state: publishedState
            ),
        ])
    }

    @MainActor
    @Test("failed-draft restore records welcome viewed after publishing the fallback")
    func failedDraftRestoreRecordsWelcomeAfterStatePublication() async {
        let telemetry = StateObservingTelemetryClient<AppFlowState>()
        let session = AuthSession(
            userID: "fixture-user",
            email: "person@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let model = AppFlowModel(
            authentication: RestoringTelemetryAuthenticationService(
                restoredSession: session
            ),
            onboarding: RestoringTelemetryOnboardingRepository(
                loadResult: .failure(.storageUnavailable)
            ),
            persona: TelemetryPersonaRepository(),
            telemetry: telemetry
        )
        await telemetry.observe { model.state }

        await model.start()

        let publishedState = AppFlowState.onboarding(
            userID: "fixture-user",
            step: .welcome
        )
        #expect(model.state == publishedState)
        #expect(model.presentationError == .storageUnavailable)
        #expect(await telemetry.snapshot() == [
            ObservedTelemetryRecord(
                event: TelemetryEvent(
                    name: .onboardingStepViewed,
                    metadata: ["step": "welcome"]
                ),
                state: publishedState
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
    @Test("records every allowed auth navigation after its screen transition")
    func recordsAuthNavigationSequence() async {
        let telemetry = InMemoryTelemetryClient()
        let model = makeAuthModel(
            outcome: .failure(.operationUnavailable),
            telemetry: telemetry
        )

        await model.showSignUp()
        #expect(model.state == .signedOut(.signUp))
        await model.showSignIn()
        #expect(model.state == .signedOut(.signIn))
        await model.showPasswordRecovery()
        #expect(model.state == .signedOut(.passwordRecovery))
        await model.showSignIn()
        #expect(model.state == .signedOut(.signIn))

        #expect(await telemetry.snapshot() == [
            TelemetryEvent(
                name: .authScreenViewed,
                metadata: ["screen": "sign_up"]
            ),
            TelemetryEvent(
                name: .authScreenViewed,
                metadata: ["screen": "sign_in"]
            ),
            TelemetryEvent(
                name: .authScreenViewed,
                metadata: ["screen": "password_recovery"]
            ),
            TelemetryEvent(
                name: .authScreenViewed,
                metadata: ["screen": "sign_in"]
            ),
        ])
    }

    @MainActor
    @Test("records completion and exactly one next view only after the saved transition")
    func recordsOnboardingAdvanceSequence() async {
        let order = TelemetryOrderRecorder()
        let telemetry = OrderedTelemetryClient(order: order)
        let repository = OrderedTelemetryOnboardingRepository(order: order)
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome),
            repository: repository,
            personaRepository: OrderedTelemetryPersonaRepository(order: order),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { step in
                order.append("callback-\(step)")
            },
            onCompleted: {}
        )

        await model.continueFromCurrentStep()

        #expect(model.step == .bodyData)
        #expect(order.values == [
            "draft-saved-bodyData",
            "callback-bodyData",
            "event-onboarding_step_completed-welcome",
            "event-onboarding_step_viewed-body_data",
        ])
    }

    @MainActor
    @Test("successful back records destination viewed after publishing step and draft")
    func successfulBackRecordsViewedAfterStatePublication() async {
        let telemetry = StateObservingTelemetryClient<OnboardingTelemetryState>()
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .objective),
            repository: TelemetryOnboardingRepository(),
            personaRepository: TelemetryPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { _ in },
            onCompleted: {}
        )
        await telemetry.observe {
            OnboardingTelemetryState(
                step: model.step,
                draftStep: model.draft.currentStep
            )
        }

        await model.back()

        let publishedState = OnboardingTelemetryState(
            step: .bodyData,
            draftStep: .bodyData
        )
        #expect(model.step == .bodyData)
        #expect(model.draft.currentStep == .bodyData)
        #expect(await telemetry.snapshot() == [
            ObservedTelemetryRecord(
                event: TelemetryEvent(
                    name: .onboardingStepViewed,
                    metadata: ["step": "body_data"]
                ),
                state: publishedState
            ),
        ])
    }

    @MainActor
    @Test("back at welcome records no viewed event")
    func backAtWelcomeRecordsNoViewedEvent() async {
        let telemetry = InMemoryTelemetryClient()
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome),
            repository: TelemetryOnboardingRepository(),
            personaRepository: TelemetryPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { _ in },
            onCompleted: {}
        )

        await model.back()

        #expect(model.step == .welcome)
        #expect(await telemetry.snapshot().isEmpty)
    }

    @MainActor
    @Test("cancelled back records no viewed event or transition")
    func cancelledBackRecordsNoViewedEvent() async {
        let telemetry = InMemoryTelemetryClient()
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .objective),
            repository: TelemetryOnboardingRepository(),
            personaRepository: TelemetryPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { _ in },
            onCompleted: {},
            cancellationCheck: { true }
        )

        await model.back()

        #expect(model.step == .objective)
        #expect(model.draft.currentStep == .objective)
        #expect(await telemetry.snapshot().isEmpty)
    }

    @MainActor
    @Test("back during a stale saving operation records no viewed event")
    func staleSavingBackRecordsNoViewedEvent() async {
        let telemetry = InMemoryTelemetryClient()
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .objective),
            repository: TelemetryOnboardingRepository(),
            personaRepository: TelemetryPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { _ in },
            onCompleted: {},
            initialOperationState: .saving
        )

        await model.back()

        #expect(model.step == .objective)
        #expect(model.draft.currentStep == .objective)
        #expect(await telemetry.snapshot().isEmpty)
    }

    @MainActor
    @Test("records no onboarding transition event when saving is cancelled")
    func recordsNoOnboardingAdvanceOnCancellation() async {
        let telemetry = InMemoryTelemetryClient()
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome),
            repository: CancelledTelemetryOnboardingRepository(),
            personaRepository: TelemetryPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { _ in },
            onCompleted: {}
        )

        await model.continueFromCurrentStep()

        #expect(model.step == .welcome)
        #expect(await telemetry.snapshot().isEmpty)
    }

    @MainActor
    @Test("records persona and onboarding completion in persisted order")
    func recordsOnboardingCompletionSequence() async {
        let order = TelemetryOrderRecorder()
        let telemetry = OrderedTelemetryClient(order: order)
        let repository = OrderedTelemetryOnboardingRepository(order: order)
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .completion),
            repository: repository,
            personaRepository: OrderedTelemetryPersonaRepository(order: order),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { _ in },
            onCompleted: {
                order.append("callback-completed")
            }
        )

        await model.complete()

        #expect(order.values == [
            "persona-persisted-focus",
            "event-coach_persona_selected-focus",
            "onboarding-persisted",
            "callback-completed",
            "event-onboarding_step_completed-completion",
            "event-onboarding_completed",
        ])
    }

    @MainActor
    @Test("does not record onboarding success when final persistence fails")
    func recordsNoFalseOnboardingCompletionOnFailure() async {
        let order = TelemetryOrderRecorder()
        let telemetry = OrderedTelemetryClient(order: order)
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .completion),
            repository: OrderedTelemetryOnboardingRepository(
                order: order,
                completionError: .storageUnavailable
            ),
            personaRepository: OrderedTelemetryPersonaRepository(order: order),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { step in
                order.append("callback-\(step)")
            },
            onCompleted: {
                order.append("callback-completed")
            }
        )

        await model.complete()

        #expect(model.step == .consent)
        #expect(order.values == [
            "persona-persisted-focus",
            "event-coach_persona_selected-focus",
            "onboarding-persisted",
            "callback-consent",
        ])
    }

    @MainActor
    @Test("records profile persona only after its repository accepts the change")
    func recordsProfilePersonaAfterPersistence() async {
        let order = TelemetryOrderRecorder()
        let telemetry = OrderedTelemetryClient(order: order)
        let model = CoachPersonaEditorModel(
            userID: "fixture-user",
            repository: OrderedTelemetryPersonaRepository(order: order),
            telemetry: telemetry,
            initialSelected: .zen,
            initialPersisted: .focus,
            initialOperationState: .idle
        )

        let didSave = await model.save()

        #expect(didSave)
        #expect(order.values == [
            "persona-persisted-zen",
            "event-coach_persona_selected-zen",
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

private struct RestoringTelemetryAuthenticationService: AuthenticationService {
    let restoredSession: AuthSession?

    func restoreSession() async throws -> AuthSession? { restoredSession }

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

private struct TelemetryOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private struct RestoringTelemetryOnboardingRepository: OnboardingRepository {
    let loadResult: Result<OnboardingDraft?, OnboardingRepositoryError>

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        try loadResult.get()
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private struct TelemetryPersonaRepository: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}

private struct ObservedTelemetryRecord<State: Equatable & Sendable>: Equatable, Sendable {
    let event: TelemetryEvent
    let state: State
}

private actor StateObservingTelemetryClient<State: Equatable & Sendable>: TelemetryClient {
    private var observer: (@MainActor @Sendable () -> State)?
    private var records: [ObservedTelemetryRecord<State>] = []

    func observe(
        _ observer: @escaping @MainActor @Sendable () -> State
    ) {
        self.observer = observer
    }

    func record(_ event: TelemetryEvent) async {
        guard let observer else { return }
        let state = await observer()
        records.append(ObservedTelemetryRecord(event: event, state: state))
    }

    func snapshot() -> [ObservedTelemetryRecord<State>] {
        records
    }
}

private struct OnboardingTelemetryState: Equatable, Sendable {
    let step: OnboardingStep
    let draftStep: OnboardingStep
}

private actor OrderedTelemetryClient: TelemetryClient {
    let order: TelemetryOrderRecorder

    init(order: TelemetryOrderRecorder) {
        self.order = order
    }

    func record(_ event: TelemetryEvent) {
        var value = "event-\(event.name.rawValue)"
        if case .string(let step)? = event.metadata["step"] {
            value += "-\(step)"
        }
        if case .string(let persona)? = event.metadata["persona"] {
            value += "-\(persona)"
        }
        order.append(value)
    }
}

private actor OrderedTelemetryOnboardingRepository: OnboardingRepository {
    let order: TelemetryOrderRecorder
    let completionError: OnboardingRepositoryError?

    init(
        order: TelemetryOrderRecorder,
        completionError: OnboardingRepositoryError? = nil
    ) {
        self.order = order
        self.completionError = completionError
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        order.append("draft-saved-\(draft.currentStep)")
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        order.append("onboarding-persisted")
        if let completionError {
            throw completionError
        }
    }

    func clear(for userID: String) async throws {}
}

private struct CancelledTelemetryOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        throw CancellationError()
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

private actor OrderedTelemetryPersonaRepository: CoachPersonaRepository {
    let order: TelemetryOrderRecorder

    init(order: TelemetryOrderRecorder) {
        self.order = order
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        order.append("persona-persisted-\(persona.telemetryTestValue)")
    }
}

private final class TelemetryOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private extension CoachPersona {
    var telemetryTestValue: String {
        switch self {
        case .focus: "focus"
        case .impulse: "impulse"
        case .zen: "zen"
        }
    }
}

private extension AuthSession {
    static let completedFixture = AuthSession(
        userID: "fixture-user",
        email: "person@example.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: true
    )
}
