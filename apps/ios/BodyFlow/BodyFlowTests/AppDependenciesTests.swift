import Foundation
import Testing

@testable import BodyFlow

@Suite("App Dependencies")
struct AppDependenciesTests {
    @Test("Release graph installs fail-closed support dependencies")
    func releaseGraphInstallsFailClosedSupportDependencies() {
        let dependencies = releaseDependencies()

        #expect(dependencies.timeProvider is SystemTimeProvider)
        #expect(dependencies.patientTimeZone.documentedIANAIdentifier == nil)
        #expect(dependencies.apiClient is UnavailableAPIClient)
        #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try dependencies.idempotencyKeyProvider.nextKey()
        }
        #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try dependencies.patientTimeZone.requireTimeZone()
        }
    }

    @Test("Release read capabilities fail closed")
    func releaseReadCapabilitiesFailClosed() async {
        let dependencies = releaseDependencies()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.today.today()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.history.history(.firstPage)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.plan.plan()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.progress.progress()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.routine.list(
                kind: .supplement,
                includeArchived: false
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.routine.history(
                kind: .supplement,
                itemID: "release-unavailable-supplement",
                cursor: nil,
                limit: 20
            )
        }
    }

    @Test("Release meal detection fails closed")
    func releaseDetectionIsUnavailable() async {
        let dependencies = releaseDependencies()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.mealDetection.detectMeal(
                from: BodyFlowTestFixtures.textMealDetectionInput
            )
        }
    }

    @Test("Release registration mutations fail closed")
    func releaseRegistrationMutationsFailClosed() async {
        let dependencies = releaseDependencies()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.propose(
                BodyFlowTestFixtures.registrationProposal
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.edit(
                BodyFlowTestFixtures.registrationEdit
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.confirm(
                BodyFlowTestFixtures.registrationID
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.cancel(
                BodyFlowTestFixtures.registrationID
            )
        }
    }

    @Test("Release routine mutations fail closed")
    func releaseRoutineMutationsFailClosed() async throws {
        let dependencies = releaseDependencies()
        let hydrationAttempt = try BodyFlowTestFixtures.hydrationAttempt()
        let weightAttempt = try BodyFlowTestFixtures.weightAttempt()
        let routineAttempt = try BodyFlowTestFixtures.routineAttempt()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.hydration.record(hydrationAttempt)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.weight.record(weightAttempt)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.routine.record(routineAttempt)
        }
    }

    @Test("Release legacy API client fails closed without reaching Today fixture")
    func releaseLegacyAPIClientFailsClosed() async {
        let dependencies = releaseDependencies()
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")

        await #expect(throws: APIClientError.operationUnavailable) {
            try await dependencies.apiClient.send(request)
        }
    }

    #if DEBUG
    @Test("Debug make graph preserves Prompt 12 while Prompt 13 is unavailable")
    func debugMakePreservesPrompt12AndFailsPrompt13Closed() async throws {
        let dependencies = AppDependencies.make(
            configuration: AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: true,
                startsWithCompletedFixture: true,
                preloadsSyntheticOnboardingValues: true,
                authBehavior: .succeed(after: nil)
            )
        )
        let legacyRequest = APIRequest<TodaySummary>(method: .get, path: "/today")

        #expect(try await dependencies.authentication.restoreSession()?.userID == "demo-user-v1")
        #expect(try await dependencies.apiClient.send(legacyRequest) == AppFixtures.today)
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.today.today()
        }
    }

    @Test("scaffold graph has a completed deterministic demo session")
    func scaffoldGraphDecodesTodayFixture() async throws {
        let dependencies = AppDependencies.scaffold()
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")

        #expect(try await dependencies.authentication.restoreSession() == AuthSession(
            userID: "demo-user-v1",
            email: "demo-user@fixture.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        ))

        let summary = try await dependencies.apiClient.send(request)
        #expect(summary == AppFixtures.today)
    }

    @Test("UI relaunch seed and preserve modes use the durable Keychain boundary")
    func uiRelaunchUsesDurableBoundary() {
        let seed = AppDependencies.demo(
            configuration: .resolve(
                arguments: ["--ui-testing"],
                buildFlavor: .debug
            )
        )
        let preserveConfiguration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing-preserve-state"],
            buildFlavor: .debug
        )
        let preserve = AppDependencies.demo(
            configuration: preserveConfiguration
        )

        #expect(seed.secureStore is KeychainSecureStore)
        #expect(preserve.secureStore is KeychainSecureStore)
        #expect(!preserveConfiguration.shouldResetDemoState)
        #expect(!preserveConfiguration.startsWithCompletedFixture)
        #expect(!preserveConfiguration.preloadsSyntheticOnboardingValues)
    }

    @Test("normal Debug relaunch uses the durable development boundary")
    func normalDebugRelaunchUsesDurableBoundary() {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: [],
            buildFlavor: .debug
        )
        let dependencies = AppDependencies.demo(configuration: configuration)

        #expect(configuration.demoStorageBoundary == .keychain)
        #expect(dependencies.secureStore is KeychainSecureStore)
        #expect(!configuration.shouldResetDemoState)
    }

    @Test("normal Debug relaunch restores partial onboarding without a password")
    func normalDebugRelaunchRestoresPartialOnboarding() async throws {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: [],
            buildFlavor: .debug
        )
        let first = AppDependencies.demo(configuration: configuration)
        try? await first.authentication.signOut()
        try? await first.onboarding.clear(for: DemoUser.id)

        let password = "local-pass"
        _ = try await first.authentication.signUp(
            email: "person@example.invalid",
            password: password
        )
        let session = try await first.authentication.confirmEmailForDevelopment()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.displayName = "Pessoa Persistida"
        draft.heightCM = 171
        try await first.onboarding.saveDraft(draft, for: session.userID)

        let relaunched = AppDependencies.demo(configuration: configuration)
        #expect(try await relaunched.authentication.restoreSession() == session)
        #expect(
            try await relaunched.onboarding.loadDraft(for: session.userID)
                == draft
        )

        let persistedKeys = [
            "bodyflow.demo.session.v1",
            "bodyflow.demo.onboarding-draft.v1",
        ]
        for key in persistedKeys {
            let data = try await relaunched.secureStore.data(forKey: key)
            #expect(
                data.flatMap { String(data: $0, encoding: .utf8) }?
                    .contains(password) != true
            )
        }

        try await relaunched.authentication.signOut()
        try await relaunched.onboarding.clear(for: session.userID)
    }

    @Test("fixture catalog exposes the approved server-provided values")
    func fixtureCatalogExposesApprovedValues() {
        #expect(AppFixtures.today.energy.consumedKcal == 1_200)
        #expect(AppFixtures.today.energy.targetKcal == 1_935)
        #expect(AppFixtures.today.energy.remainingFoodKcal == 735)
        #expect(AppFixtures.today.routine.statusLabel == "3 de 5 concluídos")
        #expect(AppFixtures.today.nextAction.title == "Registrar almoço")

        #expect(
            AppFixtures.registration.commands.map(\.title)
                == ["Refeição", "Treino", "Peso", "Hidratação"]
        )
        #expect(
            AppFixtures.registration.commands.map(\.systemImage)
                == ["fork.knife", "figure.run", "scalemass", "drop"]
        )
        #expect(
            AppFixtures.registration.commands.map(\.kindID)
                == ["meal", "training", "weight", "hydration"]
        )
        #expect(
            AppFixtures.registration.disclaimer
                == "Demonstração local. Nenhum registro foi salvo."
        )

        #expect(AppFixtures.plan.title == "Plano semanal")
        #expect(AppFixtures.plan.plannedSessions == 4)
        #expect(AppFixtures.plan.completedSessions == 3)
        #expect(AppFixtures.plan.nextItemLabel == "Mobilidade · 20 min")

        #expect(AppFixtures.progress.level == 7)
        #expect(AppFixtures.progress.streakDays == 12)
        #expect(AppFixtures.progress.completedBlocks == 2)
        #expect(
            AppFixtures.progress.reevaluationLabel
                == "Próxima reavaliação em 9 dias"
        )

        #expect(AppFixtures.profile.title == "Perfil de demonstração")
        #expect(AppFixtures.profile.notifications == "Ativadas")
    }

    @Test("Prompt 13 Debug reads share exactly one repository actor")
    func prompt13DebugReadsShareOneActor() throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )

        let today = try #require(dependencies.today as? DemoBodyFlowRepository)
        let history = try #require(dependencies.history as? DemoBodyFlowRepository)
        let plan = try #require(dependencies.plan as? DemoBodyFlowRepository)
        let progress = try #require(dependencies.progress as? DemoBodyFlowRepository)
        let routine = try #require(dependencies.routine as? DemoBodyFlowRepository)

        #expect(today === history)
        #expect(today === plan)
        #expect(today === progress)
        #expect(today === routine)
    }

    @Test("Prompt 13 Debug graph exposes coherent shared read behavior")
    func prompt13DebugGraphReturnsCoherentReads() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )

        #expect(try await dependencies.today.today() == DemoBodyFlowFixtures.loadedToday)
        #expect(try await dependencies.plan.plan() == DemoBodyFlowFixtures.loadedPlan)
        #expect(try await dependencies.progress.progress() == DemoBodyFlowFixtures.loadedProgress)
        #expect(try await dependencies.history.history(.firstPage) == DemoBodyFlowFixtures.loadedHistory)
        #expect(
            try await dependencies.routine.list(
                kind: .supplement,
                includeArchived: false
            ) == DemoBodyFlowFixtures.loadedSupplementList
        )
    }

    @Test("Prompt 13 mutation and detection ports remain unavailable at Task 9")
    func prompt13MutationAndDetectionPortsRemainUnavailable() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.mealDetection.detectMeal(
                from: BodyFlowTestFixtures.textMealDetectionInput
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.propose(
                BodyFlowTestFixtures.registrationProposal
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.hydration.record(
                BodyFlowTestFixtures.hydrationAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.weight.record(
                BodyFlowTestFixtures.weightAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.routine.record(
                BodyFlowTestFixtures.routineAttempt()
            )
        }
    }
    #endif
}

private func releaseDependencies() -> AppDependencies {
    AppDependencies.make(
        configuration: .resolve(
            arguments: ["--ui-testing-prompt13-loaded"],
            buildFlavor: .release
        )
    )
}
