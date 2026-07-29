import Foundation

struct RegistrationCommandFixture: Identifiable, Equatable, Sendable {
    let id: String
    let kindID: String
    let title: String
    let systemImage: String
}

struct RegistrationFixture: Identifiable, Equatable, Sendable {
    let id: String
    let commands: [RegistrationCommandFixture]
    let disclaimer: String
}

struct PlanFixture: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let plannedSessions: Int
    let completedSessions: Int
    let nextItemLabel: String
}

struct ProgressFixture: Identifiable, Equatable, Sendable {
    let id: String
    let level: Int
    let streakDays: Int
    let completedBlocks: Int
    let reevaluationLabel: String
}

struct ProfileFixture: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let notifications: String
}

enum AppFixtures {
    static let today = TodaySummary(
        localDate: "2026-07-26",
        energy: .init(
            consumedKcal: 1_200,
            targetKcal: 1_935,
            remainingFoodKcal: 735
        ),
        routine: .init(
            statusLabel: "3 de 5 concluídos",
            nextItemLabel: "Hidratação às 16:00"
        ),
        nextAction: .init(
            id: "fixture-today-register-lunch",
            title: "Registrar almoço",
            detail: "Adicione o que você consumiu."
        ),
        calculationVersion: "bodyflow.daily-state.v2"
    )

    static let registration = RegistrationFixture(
        id: "fixture-registration",
        commands: [
            RegistrationCommandFixture(
                id: "fixture-register-meal",
                kindID: "meal",
                title: "Refeição",
                systemImage: "fork.knife"
            ),
            RegistrationCommandFixture(
                id: "fixture-register-training",
                kindID: "training",
                title: "Treino",
                systemImage: "figure.run"
            ),
            RegistrationCommandFixture(
                id: "fixture-register-weight",
                kindID: "weight",
                title: "Peso",
                systemImage: "scalemass"
            ),
            RegistrationCommandFixture(
                id: "fixture-register-hydration",
                kindID: "hydration",
                title: "Hidratação",
                systemImage: "drop"
            ),
        ],
        disclaimer: "Demonstração local. Nenhum registro foi salvo."
    )

    static let plan = PlanFixture(
        id: "fixture-plan",
        title: "Plano semanal",
        plannedSessions: 4,
        completedSessions: 3,
        nextItemLabel: "Mobilidade · 20 min"
    )

    static let progress = ProgressFixture(
        id: "fixture-progress",
        level: 7,
        streakDays: 12,
        completedBlocks: 2,
        reevaluationLabel: "Próxima reavaliação em 9 dias"
    )

    static let profile = ProfileFixture(
        id: "fixture-profile",
        title: "Perfil de demonstração",
        notifications: "Ativadas"
    )

    static let todayPayload = Data(
        """
        {
          "local_date": "2026-07-26",
          "energy": {
            "consumed_kcal": 1200,
            "target_kcal": 1935,
            "remaining_food_kcal": 735
          },
          "routine": {
            "status_label": "3 de 5 concluídos",
            "next_item_label": "Hidratação às 16:00"
          },
          "next_action": {
            "id": "fixture-today-register-lunch",
            "title": "Registrar almoço",
            "detail": "Adicione o que você consumiu."
          },
          "calculation_version": "bodyflow.daily-state.v2"
        }
        """.utf8
    )
}
