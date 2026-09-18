import SwiftUI

struct HistoryWorkoutDetailView: View {
    @Environment(\.locale) private var locale
    let row: HistoryWorkoutLogRow?

    var body: some View {
        Group {
            if let row {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        BodyFlowCard {
                            Text(row.workoutType ?? copy("history.workout.fallback"))
                                .font(BodyFlowTypography.title)
                                .foregroundStyle(BodyFlowColor.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        BodyFlowCard {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                                if let duration = values.duration(row.durationMin) {
                                    metric(duration, identifier: "history.workout.duration")
                                }
                                if let energy = values.estimatedEnergy(row.estimatedKcal) {
                                    metric(energy, identifier: "history.workout.energy")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BodyFlowSpacing.md)
                }
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        }
        .navigationTitle(copy("history.workout.navigation.title"))
        .navigationBarTitleDisplayMode(.inline)
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
