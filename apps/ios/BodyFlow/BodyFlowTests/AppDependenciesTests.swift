import Testing

@testable import BodyFlow

@Suite("App Dependencies")
struct AppDependenciesTests {
    @Test("mock auth exposes its configured fixture session")
    func mockAuthExposesConfiguredState() {
        let provider = MockAuthSessionProvider(
            state: .authenticated(userID: "fixture-user")
        )

        #expect(provider.state == .authenticated(userID: "fixture-user"))
    }

    @Test("scaffold graph decodes the same deterministic Today fixture")
    func scaffoldGraphDecodesTodayFixture() async throws {
        let dependencies = AppDependencies.scaffold()
        let request = APIRequest<TodaySummary>(method: .get, path: "/today")

        #expect(
            dependencies.authSession.state
                == .authenticated(userID: "fixture-user")
        )

        let summary = try await dependencies.apiClient.send(request)
        #expect(summary == AppFixtures.today)
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
        #expect(AppFixtures.profile.coachPreference == "Equilibrado")
        #expect(AppFixtures.profile.notifications == "Ativadas")
    }
}
