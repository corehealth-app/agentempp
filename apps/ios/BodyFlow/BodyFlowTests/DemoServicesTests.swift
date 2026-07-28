import Foundation
import Testing

@testable import BodyFlow

@Suite("Deterministic demo services")
struct DemoServicesTests {
    @Test("late generation A failure cannot replace in-flight generation B")
    func lateGenerationFailureCannotReplaceNewerGeneration() {
        var gate = DemoInitialResetGate()
        let generationA = gate.begin()

        gate.fail(generationA)
        let generationB = gate.begin()
        gate.fail(generationA)

        #expect(gate.phase == .inFlight(generationB))
    }

    @Test("fresh restore returns no session")
    func freshRestoreReturnsNoSession() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: .resolve(arguments: [], buildFlavor: .debug)
        )

        #expect(try await service.restoreSession() == nil)
    }

    @Test("sign up requires confirmation without creating a session")
    func signUpRequiresConfirmationWithoutCreatingSession() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: .resolve(arguments: [], buildFlavor: .debug)
        )

        let result = try await service.signUp(
            email: "demo-user@fixture.invalid",
            password: "not-persisted"
        )

        #expect(result == .confirmationRequired(email: "demo-user@fixture.invalid"))
        #expect(try await store.loadSession() == nil)
    }

    @Test("cancelled sign up without delay does not retain a pending email")
    func cancelledSignUpWithoutDelayDoesNotRetainPendingEmail() async {
        let service = DemoAuthenticationService(
            stateStore: DemoStateStore(secureStore: InMemorySecureStore()),
            configuration: .resolve(arguments: [], buildFlavor: .debug)
        )
        let cancelledSignUp = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.signUp(
                email: "Demo-User@fixture.invalid",
                password: "not-persisted"
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await cancelledSignUp.value
        }
        await #expect(throws: AuthenticationError.invalidInput) {
            _ = try await service.confirmEmailForDevelopment()
        }
    }

    @Test("development confirmation creates an incomplete confirmed session")
    func developmentConfirmationCreatesIncompleteConfirmedSession() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: .resolve(arguments: [], buildFlavor: .debug)
        )

        _ = try await service.signUp(
            email: "Demo-User@fixture.invalid",
            password: "not-persisted"
        )
        let session = try await service.confirmEmailForDevelopment()

        #expect(session == AuthSession(
            userID: "demo-user-v1",
            email: "Demo-User@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        ))
        #expect(try await store.loadSession() == session)
    }

    @Test("structurally empty sign in leaves demo state untouched")
    func emptySignInLeavesDemoStateUntouched() async {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: .resolve(arguments: [], buildFlavor: .debug)
        )

        await #expect(throws: AuthenticationError.invalidInput) {
            _ = try await service.signIn(email: " ", password: "")
        }

        #expect((try? await store.loadSession()) == nil)
    }

    @Test("recovery has the same public result for plausible emails")
    func recoveryHasSamePublicResultForPlausibleEmails() async throws {
        let service = DemoAuthenticationService(
            stateStore: DemoStateStore(secureStore: InMemorySecureStore()),
            configuration: .resolve(arguments: [], buildFlavor: .debug)
        )

        try await service.requestPasswordRecovery(email: "member@fixture.invalid")
        try await service.requestPasswordRecovery(email: "another@fixture.invalid")
    }

    @Test("sign out removes the session and keeps onboarding data")
    func signOutRemovesOnlySession() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let existingSession = AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)

        try await store.saveSession(existingSession)
        try await store.saveOnboardingDraft(draft)
        try await store.saveCoachPersona(.zen, for: "demo-user-v1")

        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: .resolve(arguments: [], buildFlavor: .debug)
        )
        try await service.signOut()

        #expect(try await store.loadSession() == nil)
        #expect(try await store.loadOnboardingDraft() == draft)
        #expect(try await store.loadCoachPersona(for: "demo-user-v1") == .zen)
    }

    @Test("configured delay can be cancelled before a session write")
    func delayedSignInCanBeCancelledBeforeSessionWrite() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let configuration = AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: false,
            startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .succeed(after: .seconds(5))
        )
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: configuration
        )
        let signIn = Task {
            try await service.signIn(
                email: "demo-user@fixture.invalid",
                password: "not-persisted"
            )
        }

        signIn.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await signIn.value
        }
        #expect(try await store.loadSession() == nil)
    }

    @Test("configured authentication failure writes no session")
    func configuredFailureWritesNoSession() async {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let configuration = AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: false,
            startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .fail(.serviceUnavailable, after: nil)
        )
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: configuration
        )

        await #expect(throws: AuthenticationError.serviceUnavailable) {
            _ = try await service.signIn(
                email: "demo-user@fixture.invalid",
                password: "not-persisted"
            )
        }
        #expect((try? await store.loadSession()) == nil)
    }

    @Test("first restore resets state exactly once")
    func firstRestoreResetsStateExactlyOnce() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        try await store.saveSession(AuthSession(
            userID: "previous-user",
            email: "previous@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        ))
        let configuration = AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: true,
            startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .succeed(after: nil)
        )
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: configuration
        )

        #expect(try await service.restoreSession() == nil)
        let replacement = AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        try await store.saveSession(replacement)

        #expect(try await service.restoreSession() == replacement)
    }

    @Test("cancelled initial restore does not consume the pending reset")
    func cancelledInitialRestoreDoesNotConsumePendingReset() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let staleSession = AuthSession(
            userID: "previous-user",
            email: "previous@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        try await store.saveSession(staleSession)
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: true,
                startsWithCompletedFixture: false,
                preloadsSyntheticOnboardingValues: false,
                authBehavior: .succeed(after: nil)
            )
        )
        let cancelledRestore = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.restoreSession()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await cancelledRestore.value
        }
        #expect(try await store.loadSession() == staleSession)
        #expect(try await service.restoreSession() == nil)
    }

    @Test("initial reset also removes the scoped demo persona")
    func initialResetRemovesScopedDemoPersona() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let repository = DemoCoachPersonaRepository(stateStore: store)
        try await repository.setPersona(.zen, for: "demo-user-v1")
        let service = DemoAuthenticationService(
            stateStore: store,
            configuration: AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: true,
                startsWithCompletedFixture: false,
                preloadsSyntheticOnboardingValues: false,
                authBehavior: .succeed(after: nil)
            )
        )

        _ = try await service.restoreSession()

        #expect(try await repository.selectedPersona(for: "demo-user-v1") == nil)
    }

    @Test("onboarding draft saves and loads for the demo user")
    func onboardingDraftSavesAndLoads() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let repository = DemoOnboardingRepository(
            stateStore: store,
            buildFlavor: .debug
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)

        try await repository.saveDraft(draft, for: "demo-user-v1")

        #expect(try await repository.loadDraft(for: "demo-user-v1") == draft)
    }

    @Test("regular debug launch supplies only injected locale suggestions")
    func regularDebugLaunchSuppliesOnlyInjectedLocaleSuggestions() async throws {
        let repository = DemoOnboardingRepository(
            stateStore: DemoStateStore(secureStore: InMemorySecureStore()),
            buildFlavor: .debug,
            suggestions: DemoOnboardingSuggestions(
                localeIdentifier: "en-US",
                countryCode: "CA",
                timeZoneIdentifier: "America/Toronto"
            )
        )

        let draft = try #require(
            try await repository.loadDraft(for: "demo-user-v1")
        )

        #expect(draft.localeIdentifier == "en-US")
        #expect(draft.countryCode == "CA")
        #expect(draft.timeZoneIdentifier == "America/Toronto")
        #expect(draft.displayName == nil)
        #expect(draft.biologicalSex == nil)
        #expect(draft.objective == nil)
        #expect(draft.persona == nil)
        #expect(draft.consent == nil)
        #expect(draft.currentStep == .welcome)
    }

    @Test("UI-test onboarding preload appears only after email confirmation")
    func uiTestingOnboardingPreloadRequiresConfirmedSession() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let repository = DemoOnboardingRepository(
            stateStore: store,
            buildFlavor: .debug,
            preloadsSyntheticOnboardingValues: true
        )

        let initialDraft = try #require(
            try await repository.loadDraft(for: "demo-user-v1")
        )
        #expect(initialDraft.biologicalSex == nil)
        #expect(initialDraft.activityLevel == nil)
        #expect(initialDraft.objective == nil)

        try await store.saveSession(AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        ))

        let draft = try #require(
            try await repository.loadDraft(for: "demo-user-v1")
        )
        #expect(draft.countryCode == "BR")
        #expect(draft.timeZoneIdentifier == "America/Sao_Paulo")
        #expect(draft.biologicalSex == .feminine)
        #expect(draft.activityLevel == .moderate)
        #expect(draft.objective == nil)
        #expect(draft.persona == nil)
        #expect(draft.consent == nil)
        #expect(draft.currentStep == .welcome)
    }

    @Test("repeated valid onboarding completion is idempotent")
    func repeatedOnboardingCompletionIsIdempotent() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        try await store.saveSession(AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        ))
        let repository = DemoOnboardingRepository(
            stateStore: store,
            buildFlavor: .debug
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)

        try await repository.complete(draft, for: "demo-user-v1")
        try await repository.complete(draft, for: "demo-user-v1")

        #expect(try await store.loadSession() == AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        ))
        #expect(try await repository.loadDraft(for: "demo-user-v1") == draft)
    }

    @Test("persona is saved and read for the demo user")
    func personaIsSavedAndRead() async throws {
        let secureStore = InMemorySecureStore()
        let repository = DemoCoachPersonaRepository(
            stateStore: DemoStateStore(secureStore: secureStore)
        )

        try await repository.setPersona(.focus, for: "demo-user-v1")

        #expect(try await repository.selectedPersona(for: "demo-user-v1") == .focus)
        #expect(try await secureStore.data(
            forKey: "bodyflow.demo.coach-persona.v1.demo-user-v1"
        ) != nil)
    }

    @Test("persona failure preserves the prior selection")
    func personaFailurePreservesPriorSelection() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let successfulRepository = DemoCoachPersonaRepository(stateStore: store)
        try await successfulRepository.setPersona(.focus, for: "demo-user-v1")
        let failingRepository = DemoCoachPersonaRepository(
            stateStore: store,
            behavior: .fail(.serviceUnavailable, after: nil)
        )

        await #expect(throws: CoachPersonaRepositoryError.serviceUnavailable) {
            try await failingRepository.setPersona(.impulse, for: "demo-user-v1")
        }

        #expect(try await successfulRepository.selectedPersona(for: "demo-user-v1") == .focus)
    }

    @Test("release policy rejects development consent without mutating session")
    func releasePolicyRejectsDevelopmentConsent() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let originalSession = AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        try await store.saveSession(originalSession)
        let releaseRepository = DemoOnboardingRepository(
            stateStore: store,
            buildFlavor: .release
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)

        await #expect(throws: OnboardingRepositoryError.developmentConsentForbidden) {
            try await releaseRepository.complete(draft, for: "demo-user-v1")
        }
        #expect(try await store.loadSession() == originalSession)
    }

    @Test("debug launch scenarios resolve to the documented modes")
    func debugLaunchScenariosResolveToDocumentedModes() {
        #expect(AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing"],
            buildFlavor: .debug
        ).scenarioID == "demo/reset/completed/preloaded/succeed")
        #expect(AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing-fresh-auth"],
            buildFlavor: .debug
        ).scenarioID == "demo/reset/fresh/preloaded/succeed")
        #expect(AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing-auth-error"],
            buildFlavor: .debug
        ).scenarioID == "demo/reset/fresh/preloaded/fail-serviceUnavailable")
        #expect(AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing-recovery"],
            buildFlavor: .debug
        ).scenarioID == "demo/reset/fresh/preloaded/succeed")
    }

    @Test("unknown and release arguments cannot enable demo mode")
    func unknownAndReleaseArgumentsCannotEnableDemoMode() {
        #expect(AppLaunchConfiguration.resolve(
            arguments: ["--not-a-demo-switch"],
            buildFlavor: .debug
        ).scenarioID == "demo/keep/fresh/empty/succeed")
        #expect(AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing"],
            buildFlavor: .release
        ).scenarioID == "release/keep/fresh/empty/fail-operationUnavailable")
    }
}

private extension AppLaunchConfiguration {
    var scenarioID: String {
        let modeID = switch mode {
        case .demo: "demo"
        case .releaseUnavailable: "release"
        }
        let resetID = shouldResetDemoState ? "reset" : "keep"
        let fixtureID = startsWithCompletedFixture ? "completed" : "fresh"
        let preloadID = preloadsSyntheticOnboardingValues ? "preloaded" : "empty"
        let behaviorID = switch authBehavior {
        case .succeed: "succeed"
        case .fail(let error, _): "fail-\(String(describing: error))"
        }

        return "\(modeID)/\(resetID)/\(fixtureID)/\(preloadID)/\(behaviorID)"
    }
}
