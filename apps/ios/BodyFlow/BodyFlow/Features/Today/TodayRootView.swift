import Foundation
import SwiftUI

@MainActor
struct TodayRootView: View {
    let fixture: TodaySummary
    let state: ScreenContentState
    private let retryAction: @MainActor () -> Void

    init(
        fixture: TodaySummary = AppFixtures.today,
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
        .accessibilityIdentifier(AppTab.today.rootAccessibilityIdentifier)
        .navigationTitle("Hoje")
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("RESUMO DIÁRIO")
                        .font(BodyFlowTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyFlowColor.accent)

                    Text("Um passo de cada vez.")
                        .font(BodyFlowTypography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(BodyFlowColor.primaryText)

                    Text(fixture.localDate)
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }

                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        Label("Energia de hoje", systemImage: "bolt.heart")
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.primaryText)

                        FixtureMetricRow(
                            title: "Consumido",
                            value: kcal(fixture.energy.consumedKcal)
                        )
                        Divider()
                        FixtureMetricRow(
                            title: "Meta",
                            value: kcal(fixture.energy.targetKcal)
                        )
                        Divider()
                        FixtureMetricRow(
                            title: "Restante para alimentos",
                            value: kcal(fixture.energy.remainingFoodKcal)
                        )
                    }
                }

                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Label("Rotina", systemImage: "checklist")
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.primaryText)

                        Text(fixture.routine.statusLabel)
                            .font(BodyFlowTypography.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(BodyFlowColor.achievement)

                        Label(
                            fixture.routine.nextItemLabel,
                            systemImage: "clock"
                        )
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }

                NavigationLink(
                    value: AppRoute.detail(tab: .today, id: "daily-summary")
                ) {
                    BodyFlowCard {
                        FeatureActionLabel(
                            title: fixture.nextAction.title,
                            detail: fixture.nextAction.detail,
                            systemImage: "plus.circle.fill"
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.next-action")
            }
            .padding(BodyFlowSpacing.md)
        }
    }

    private func kcal(_ value: Int) -> String {
        "\(value.formatted(.number.locale(Locale(identifier: "pt_BR")))) kcal"
    }
}

#Preview("Hoje · Loaded") {
    NavigationStack {
        TodayRootView()
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}

#Preview("Hoje · Loading") {
    NavigationStack {
        TodayRootView(state: .loading)
    }
    .environment(AppRouter())
    .installAppDependencies(AppDependencies.scaffold())
}
