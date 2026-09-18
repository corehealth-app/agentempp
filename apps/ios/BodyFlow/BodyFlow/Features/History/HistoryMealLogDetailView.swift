import SwiftUI

struct HistoryMealLogDetailView: View {
    @Environment(\.locale) private var locale
    let row: HistoryMealLogRow?

    var body: some View {
        Group {
            if let row {
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        BodyFlowCard {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                                Text(row.foodName)
                                    .font(BodyFlowTypography.title)
                                    .foregroundStyle(BodyFlowColor.primaryText)
                                if let mealType = row.mealType {
                                    Text(mealType)
                                        .font(BodyFlowTypography.body)
                                        .foregroundStyle(BodyFlowColor.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        BodyFlowCard {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                                if let quantity = values.quantity(row.quantityG) {
                                    metric(quantity, identifier: "history.meal.quantity")
                                }
                                if let energy = values.energy(row.kcal) {
                                    metric(energy, identifier: "history.meal.energy")
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
        .navigationTitle(copy("history.meal.navigation.title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.history.meal-detail")
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
