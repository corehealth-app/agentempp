import Testing

@testable import BodyFlow

@Suite("App Dependencies")
struct AppDependenciesTests {
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
}
