import SwiftUI

struct HistoryWorkoutDetailView: View {
    @Environment(\.locale) private var locale
    let row: HistoryWorkoutLogRow?
    var strengthQuestion: WorkoutStrengthQuestionConfiguration? = nil

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            if let row {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                            Text(values.workoutType(row.workoutType) ?? copy("history.workout.fallback"))
                                .font(BodyFlowTypography.screenTitle)
                                .foregroundStyle(BodyFlowColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            if values.duration(row.durationMin) != nil
                                || values.estimatedEnergy(row.estimatedKcal) != nil {
                                Divider()
                            }
                            if let duration = values.duration(row.durationMin) {
                                metric(duration, identifier: "history.workout.duration")
                            }
                            if let energy = values.estimatedEnergy(row.estimatedKcal) {
                                metric(energy, identifier: "history.workout.energy")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let strengthQuestion {
                        WorkoutStrengthQuestionHost(configuration: strengthQuestion, showsRegistrationFeedback: true)
                    }
                    }
                    .padding(BodyFlowSpacing.md)
                }
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        }
        .bodyFlowScreenChrome(title: copy("history.workout.navigation.title"))
        .accessibilityIdentifier("screen.history.workout-detail")
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

    private func metric(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(BodyFlowTypography.body)
            .foregroundStyle(BodyFlowColor.primaryText)
            .accessibilityIdentifier(identifier)
    }
}
