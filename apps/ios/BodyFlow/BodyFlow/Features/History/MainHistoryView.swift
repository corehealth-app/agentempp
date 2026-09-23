import SwiftUI

@MainActor
struct MainHistoryView: View {
    @Environment(\.locale) private var locale
    let model: HistoryViewModel
    let invalidationCenter: FeatureInvalidationCenter

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            content
        }
        .accessibilityElement(children: .contain)
        .bodyFlowScreenChrome(title: copy("history.navigation.title"))
        .accessibilityIdentifier("screen.history")
        .task(id: invalidationCenter.revision(for: .history)) {
            let revision = invalidationCenter.revision(for: .history)
            await model.load(revision: revision)
        }
    }

    @ViewBuilder
    private var content: some View {
        let presentation = model.state.presentation
        if let state = presentation.fullScreenState {
            if state == .empty {
                ScreenStateView(
                    state: state,
                    retryAction: retry,
                    accessibilityIdentifier: "history.empty",
                    titleAccessibilityIdentifier: "history.empty"
                )
            } else {
                ScreenStateView(state: state, retryAction: retry)
            }
        } else if let snapshot = presentation.value {
            let history = HistoryPresentation(snapshot: snapshot, language: language)
            if history.isGloballyEmpty {
                ScreenStateView(state: .empty, retryAction: retry)
                    .accessibilityIdentifier("history.empty")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        if presentation.showsStaleBanner {
                            FeatureStaleRecovery(retry: retry)
                        }
                        if !history.meals.isEmpty { mealSection(history.meals) }
                        if !history.workouts.isEmpty { workoutSection(history.workouts) }
                    }
                    .padding(BodyFlowSpacing.md)
                }
            }
        }
    }

    private func mealSection(_ rows: [HistoryMealLogRow]) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("history.meals.title"))
                .font(BodyFlowTypography.title)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("history.meals")
            ForEach(rows, id: \.id) { row in
                NavigationLink(value: AppRoute.historyMealLog(rowID: row.id)) {
                    HistoryMealLogRowView(row: row)
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("history.meal.\(row.id)")
            }
        }
    }

    private func workoutSection(_ rows: [HistoryWorkoutLogRow]) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("history.workouts.title"))
                .font(BodyFlowTypography.title)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("history.workouts")
            ForEach(rows, id: \.id) { row in
                NavigationLink(value: AppRoute.historyWorkout(logID: row.id)) {
                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                            Text(row.workoutType ?? copy("history.workout.fallback"))
                                .font(BodyFlowTypography.headline)
                                .foregroundStyle(BodyFlowColor.primaryText)
                            if let duration = values.duration(row.durationMin) {
                                Text(duration)
                                    .font(BodyFlowTypography.callout)
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.bodyFlowRow)
                .accessibilityIdentifier("history.workout.\(row.id)")
            }
        }
    }

    private func retry() {
        Task { await model.retry() }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var values: HistoryValuePresentation {
        HistoryValuePresentation(language: language)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        HistoryCopy.string(key, language: language)
    }
}
