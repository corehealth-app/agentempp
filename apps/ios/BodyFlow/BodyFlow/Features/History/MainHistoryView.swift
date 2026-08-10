import SwiftUI

@MainActor
struct MainHistoryView: View {
    let model: HistoryViewModel
    let invalidationCenter: FeatureInvalidationCenter

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            content
        }
        .accessibilityElement(children: .contain)
        .navigationTitle("Histórico")
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
            let history = HistoryPresentation(snapshot: snapshot)
            if history.isGloballyEmpty {
                ScreenStateView(state: .empty, retryAction: retry)
                    .accessibilityIdentifier("history.empty")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        if presentation.showsStaleBanner {
                            StaleDataBanner()
                            Button(action: retry) {
                                Text("Tentar novamente")
                                    .font(BodyFlowTypography.headline)
                                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("state.retry")
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
            Text("Registros de alimentos")
                .font(BodyFlowTypography.title)
                .accessibilityIdentifier("history.meals")
            ForEach(rows, id: \.id) { row in
                NavigationLink(value: AppRoute.historyMealLog(rowID: row.id)) {
                    HistoryMealLogRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("history.meal.\(row.id)")
            }
        }
    }

    private func workoutSection(_ rows: [HistoryWorkoutLogRow]) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text("Treinos")
                .font(BodyFlowTypography.title)
                .accessibilityIdentifier("history.workouts")
            ForEach(rows, id: \.id) { row in
                NavigationLink(value: AppRoute.historyWorkout(logID: row.id)) {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        Text(row.workoutType ?? "Treino")
                        if let duration = row.durationMin { Text("\(duration) min") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BodyFlowSpacing.md)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("history.workout.\(row.id)")
            }
        }
    }

    private func retry() {
        Task { await model.retry() }
    }
}
