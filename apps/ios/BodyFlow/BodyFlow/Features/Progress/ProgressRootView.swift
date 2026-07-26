import SwiftUI

@MainActor
struct ProgressRootView: View {
    let fixture: ProgressFixture
    let state: ScreenContentState
    private let retryAction: @MainActor () -> Void

    init(
        fixture: ProgressFixture = AppFixtures.progress,
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
        .accessibilityIdentifier(AppTab.progress.rootAccessibilityIdentifier)
        .navigationTitle("Progresso")
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("CONSISTÊNCIA")
                        .font(BodyFlowTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.accent)

                    Text("Seu progresso")
                        .font(BodyFlowTypography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Text(fixture.reevaluationLabel)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }

                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        FixtureMetricRow(
                            title: "Nível",
                            value: "\(fixture.level)",
                            systemImage: "medal"
                        )
                        Divider()
                        FixtureMetricRow(
                            title: "Sequência",
                            value: "\(fixture.streakDays) dias",
                            systemImage: "flame"
                        )
                        Divider()
                        FixtureMetricRow(
                            title: "Blocos concluídos",
                            value: "\(fixture.completedBlocks)",
                            systemImage: "checkmark.seal"
                        )
                    }
                }

                NavigationLink(
                    value: AppRoute.detail(
                        tab: .progress,
                        id: "progress-snapshot"
                    )
                ) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: "Ver resumo do progresso",
                            detail: "Abrir destino local de demonstração",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progress.detail")
            }
            .padding(BodyFlowSpacing.md)
        }
    }
}

#Preview("Progresso · Loaded") {
    NavigationStack {
        ProgressRootView()
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}

#Preview("Progresso · Offline") {
    NavigationStack {
        ProgressRootView(state: .offline)
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}
