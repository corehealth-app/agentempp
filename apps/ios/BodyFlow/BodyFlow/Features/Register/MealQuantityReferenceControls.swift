import SwiftUI

/// Shared explanation and explicit grams option for all three meal forms.
struct MealQuantityReferenceControls: View {
    let reference: MealQuantityValue
    let currentGrams: Decimal?
    let showingGrams: Bool
    let canToggle: Bool
    let language: SupportedAppLanguage
    let identifier: String
    let toggle: () -> Void

    var body: some View {
        if reference.usesReference {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy(reference.isVolume ? "meal.quantity.volume-reference" : "meal.quantity.portion-reference"))
                if let currentGrams {
                    Text(copy("meal.quantity.equivalence") + ": ≈ " + MealProposalNumberParser.format(currentGrams, language: language) + " g")
                        .accessibilityIdentifier(identifier + ".equivalence")
                }
                Button(action: toggle) {
                    Text(copy(showingGrams ? referenceModeKey : "meal.quantity.use-grams"))
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(BodyFlowColor.accent)
                .disabled(!canToggle)
                .accessibilityIdentifier(identifier + ".unit-mode")
            }
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var referenceModeKey: String.LocalizationValue {
        switch reference.unit {
        case "mL": "meal.quantity.use-volume"
        case "scoop": "meal.quantity.use-scoops"
        default: "meal.quantity.use-units"
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }
}
