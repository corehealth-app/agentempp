import SwiftUI

@MainActor
struct PlanRootView: View {
    let fixture: PlanFixture
    let state: ScreenContentState
    private let retryAction: @MainActor () -> Void

    init(
        fixture: PlanFixture = AppFixtures.plan,
        state: ScreenContentState = .loaded,
        retryAction: @escaping @MainActor () -> Void = {}
    ) {
        self.fixture = fixture
        self.state = state
        self.retryAction = retryAction
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()

            if let screenState = state.screenState {
                ScreenStateView(state: screenState, retryAction: retryAction)
            } else {
                loadedContent
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AppTab.plan.rootAccessibilityIdentifier)
        .navigationTitle("Plano")
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("SUA SEMANA")
                        .font(BodyFlowTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.accent)

                    Text(fixture.title)
                        .font(BodyFlowTypography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Text("Visão local dos valores já fornecidos pelo servidor.")
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }

                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        Label("Sessões", systemImage: "calendar")
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.primaryText)

                        FixtureMetricRow(
                            title: "Planejadas",
                            value: "\(fixture.plannedSessions)"
                        )
                        Divider()
                        FixtureMetricRow(
                            title: "Concluídas",
                            value: "\(fixture.completedSessions)"
                        )
                        Divider()
                        FixtureMetricRow(
                            title: "Próxima sessão",
                            value: fixture.nextItemLabel
                        )
                    }
                }

                NavigationLink(
                    value: AppRoute.detail(tab: .plan, id: "weekly-plan")
                ) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: "Ver detalhes do plano",
                            detail: "Abrir destino local de demonstração",
                            systemImage: "list.clipboard"
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.detail")
            }
            .padding(BodyFlowSpacing.md)
        }
    }
}

#Preview("Plano · Loaded") {
    NavigationStack {
        PlanRootView()
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}

#Preview("Plano · Error") {
    NavigationStack {
        PlanRootView(state: .recoverableError)
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}
