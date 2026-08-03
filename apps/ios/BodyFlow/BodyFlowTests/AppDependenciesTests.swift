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
            try await dependencies.mealDetection.detect(
                BodyFlowTestFixtures.textMealDetectionInput
            )
        }
    }

    @Test("Release registration mutations fail closed")
    func releaseRegistrationMutationsFailClosed() async throws {
        let dependencies = releaseDependencies()

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.propose(
                BodyFlowTestFixtures.registrationProposalAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.edit(
                BodyFlowTestFixtures.registrationEditAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.confirm(
                BodyFlowTestFixtures.registrationConfirmAttempt()
            )
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await dependencies.registration.cancel(
                BodyFlowTestFixtures.registrationCancelAttempt()
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

    @Test("Release Prompt 14 factories expose only fail-closed capabilities")
    func releasePrompt14FactoriesFailClosed() async throws {
        let dependencies = releaseDependencies()
        let content = dependencies.publishedContentSessions.makeSession(
            userID: "release-user"
        )
        let coach = dependencies.coachExperienceSessions.makeCoachExperience(
            userID: "release-user"
        )
        let cover = dependencies.contentCoverSessions.makeLoader(
            userID: "release-user"
        )
        let query = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await content.listing.content(query)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await coach.coachExperience()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await cover.image(
                publicationID: "publication-1",
                version: 4,
                cover: PublishedContentCover(
                    url: "/api/mobile/v1/content/covers/AbC_123-xyz",
                    expiresAt: APITimestamp(value: .distantFuture)
                ),
                target: ContentCoverTargetSize(
                    widthPixels: 240,
                    heightPixels: 160
                )
            )
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

    @Test("Debug Prompt 14 factories remain unavailable before fixture composition")
    func debugPrompt14FactoriesRemainUnavailable() async throws {
        let dependencies = AppDependencies.make(
            configuration: AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: true,
                startsWithCompletedFixture: true,
                preloadsSyntheticOnboardingValues: true,
                authBehavior: .succeed(after: nil)
            )
        )
        let content = dependencies.publishedContentSessions.makeSession(
            userID: "demo-user-v1"
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await content.detail.contentDetail(
                publicationID: "publication-1"
            )
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
        let mealDetection = try #require(
            dependencies.mealDetection as? DemoBodyFlowRepository
        )
        let registration = try #require(
            dependencies.registration as? DemoBodyFlowRepository
        )
        let hydration = try #require(
            dependencies.hydration as? DemoBodyFlowRepository
        )
        let weight = try #require(
            dependencies.weight as? DemoBodyFlowRepository
        )

        #expect(today === history)
        #expect(today === plan)
        #expect(today === progress)
        #expect(today === routine)
        #expect(today === mealDetection)
        #expect(today === registration)
        #expect(today === hydration)
        #expect(today === weight)
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

    @Test("Prompt 13 hydration weight and routine ports share coherent actor behavior")
    func prompt13Task11MutationPortsUseSharedActor() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )

        let beforeToday = try await dependencies.today.today()
        let beforeProgress = try await dependencies.progress.progress()
        let beforeHistory = try await dependencies.history.history(.firstPage)

        let hydration = try await dependencies.hydration.record(
            dependencyHydrationAttempt()
        )
        #expect(hydration == DemoBodyFlowFixtures.hydrationReceipt)
        #expect(
            try await dependencies.today.today()
                == DemoBodyFlowFixtures.postHydrationToday
        )

        let beforeWeightToday = try await dependencies.today.today()
        let weight = try await dependencies.weight.record(
            dependencyWeightAttempt()
        )
        #expect(weight == DemoBodyFlowFixtures.weightReceipt)
        #expect(try await dependencies.today.today() == beforeWeightToday)
        #expect(try await dependencies.progress.progress() == beforeProgress)
        #expect(try await dependencies.history.history(.firstPage) == beforeHistory)

        let routine = try await dependencies.routine.record(
            dependencyRoutineAttempt()
        )
        #expect(routine == DemoBodyFlowFixtures.routineTakenReceipt)
        #expect(
            try await dependencies.today.today()
                == DemoBodyFlowFixtures.today(
                    confirmation: .none,
                    hydrationRecorded: true,
                    routine: .taken
                )
        )
        #expect(
            try await dependencies.routine.list(
                kind: .supplement,
                includeArchived: false
            ) == DemoBodyFlowFixtures.postRoutineTakenSupplementList
        )
        #expect(
            try await dependencies.routine.history(
                kind: .supplement,
                itemID: "supplement-1",
                cursor: nil,
                limit: 20
            ) == DemoBodyFlowFixtures.postRoutineTakenSupplementHistory
        )
        #expect(beforeToday == DemoBodyFlowFixtures.loadedToday)
    }

    @Test("Prompt 13 registration existential mutates the shared Today and History actor")
    func prompt13RegistrationUsesSharedActorSnapshots() async throws {
        let dependencies = AppDependencies.make(
            configuration: .resolve(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                buildFlavor: .debug
            )
        )
        let registration: any RegistrationProviding = dependencies.registration
        let createdAt = Date(timeIntervalSince1970: 1_784_589_300)
        let detected = try await dependencies.mealDetection.detect(
            .text("texto que não será interpretado")
        )
        let proposed = try await registration.propose(MutationAttempt(
            operation: .proposalCreate,
            key: try IdempotencyKey(validating: "dependency-propose-0001"),
            payload: detected,
            createdAt: createdAt
        ))
        #expect(proposed == DemoBodyFlowFixtures.pendingMealRegistration)

        let confirmed = try await registration.confirm(MutationAttempt(
            operation: .proposalConfirm,
            key: try IdempotencyKey(validating: "dependency-confirm-0001"),
            payload: RegistrationIDCommand(registrationID: proposed.data.id),
            createdAt: createdAt
        ))

        #expect(confirmed == DemoBodyFlowFixtures.confirmedMealRegistration)
        #expect(
            try await dependencies.today.today()
                == DemoBodyFlowFixtures.postMealConfirmationToday
        )
        #expect(
            try await dependencies.history.history(.firstPage)
                == DemoBodyFlowFixtures.postMealConfirmationHistory
        )
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

#if DEBUG
private let dependencyActionDate = Date(timeIntervalSince1970: 1_784_589_300)

private func dependencyHydrationAttempt() throws -> MutationAttempt<HydrationCommand> {
    MutationAttempt(
        operation: .hydration,
        key: try IdempotencyKey(validating: "dependency-hydration-0001"),
        payload: try HydrationCommand(
            amountML: 250,
            occurredAt: APITimestamp(value: dependencyActionDate)
        ),
        createdAt: dependencyActionDate
    )
}

private func dependencyWeightAttempt() throws -> MutationAttempt<WeightCommand> {
    MutationAttempt(
        operation: .weight,
        key: try IdempotencyKey(validating: "dependency-weight-0001"),
        payload: try WeightCommand(
            weightKG: 78.4,
            recordedAt: dependencyActionDate
        ),
        createdAt: dependencyActionDate
    )
}

private func dependencyRoutineAttempt() throws
    -> MutationAttempt<RoutineActionCommand> {
    MutationAttempt(
        operation: .routineAction,
        key: try IdempotencyKey(validating: "dependency-routine-0001"),
        payload: try RoutineActionCommand(
            kind: .supplement,
            itemID: "supplement-1",
            status: .taken,
            reminderRuleID: "rule-08",
            scheduledFor: APITimestamp(
                value: Date(timeIntervalSince1970: 1_784_545_200)
            ),
            occurredAt: APITimestamp(value: dependencyActionDate),
            snoozedUntil: nil
        ),
        createdAt: dependencyActionDate
    )
}
#endif
