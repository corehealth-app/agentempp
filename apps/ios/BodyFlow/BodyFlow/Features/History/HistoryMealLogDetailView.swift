import SwiftUI

struct HistoryMealLogDetailView: View {
    @Environment(\.locale) private var locale
    let row: HistoryMealLogRow?

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()
            if let row {
                ScrollView {
                    // One card: the record's name and type, then its figures.
                    BodyFlowCard {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                            Text(row.foodName)
                                .font(BodyFlowTypography.screenTitle)
                                .foregroundStyle(BodyFlowColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            if let mealType = row.mealType {
                                Text(RegistrationCopy.mealTypeTitle(code: mealType, language: language))
                                    .font(BodyFlowTypography.body)
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                            }
                            if values.quantity(row.quantityG) != nil
                                || values.energy(row.kcal) != nil {
                                Divider()
                            }
                            if let quantity = values.quantity(row.quantityG) {
                                metric(quantity, identifier: "history.meal.quantity")
                            }
                            if let energy = values.energy(row.kcal) {
                                metric(energy, identifier: "history.meal.energy")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(BodyFlowSpacing.md)
                }
            } else {
                ScreenStateView(state: .unavailable, retryAction: {})
            }
        }
        .bodyFlowScreenChrome(title: copy("history.meal.navigation.title"))
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
