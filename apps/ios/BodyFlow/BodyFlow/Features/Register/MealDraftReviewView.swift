import SwiftUI

/// The candidates the server read, for the patient to correct and confirm.
/// No calorie appears here: the calculation happens only after this list is
/// sent, on the server.
struct MealDraftReviewView: View {
    @Binding var review: MealDraftReview
    let isSubmitting: Bool
    let submit: @MainActor () -> Void
    let startOver: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("registration.review.title"))
                    .font(BodyFlowTypography.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(copy("registration.review.subtitle"))
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let transcript = review.transcript {
                note(title: copy("registration.review.transcript"), text: transcript)
                    .accessibilityIdentifier("registration.review.transcript")
            }
            if let contextNote = review.contextNote {
                note(title: copy("registration.review.context"), text: contextNote)
                    .accessibilityIdentifier("registration.review.context")
            }
            if let label = review.nutritionLabel {
                BodyFlowStatusLine(
                    [copy("registration.review.label.found"), label.productName]
                        .compactMap { $0 }
                        .joined(separator: ": "),
                    kind: .info
                )
                .accessibilityIdentifier("registration.review.label")
            }

            Picker(copy("registration.review.meal-type"), selection: $review.mealType) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(RegistrationCopy.mealTypeTitle(type, language: language)).tag(type)
                }
            }
            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            .accessibilityIdentifier("registration.review.meal-type")

            ForEach($review.items) { $item in
                itemCard($item)
            }

            if let blocker = review.blocker(language: language) {
                BodyFlowStatusLine(copy(MealCaptureCopy.blockerKey(blocker)), kind: .warning)
                    .accessibilityIdentifier("registration.review.blocker")
            }

            Button(action: submit) {
                Text(copy("registration.review.submit"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: isSubmitting))
            .disabled(isSubmitting || review.blocker(language: language) != nil)
            .accessibilityIdentifier("registration.review.submit")

            Button(action: startOver) {
                Text(copy("registration.live.start-over"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
            .disabled(isSubmitting)
            .accessibilityIdentifier("registration.review.start-over")
        }
    }

    private func itemCard(_ item: Binding<MealDraftReview.Item>) -> some View {
        let value = item.wrappedValue
        return BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                fieldCaption("registration.review.item.name")
                TextField(copy("registration.review.item.name"), text: item.name, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
                    .bodyFlowField()
                    .accessibilityLabel(copy("registration.review.item.name"))
                    .accessibilityIdentifier("registration.review.item.\(value.id).name")

                if value.hasDoubtfulName {
                    BodyFlowStatusLine(
                        copy(value.candidate.reviewReason == "ambiguous"
                            ? "registration.review.reason.ambiguous"
                            : "registration.review.reason.low-confidence"),
                        kind: .warning
                    )
                }

                fieldCaption("registration.review.item.quantity")
                TextField(
                    copy("registration.review.item.quantity"),
                    text: Binding(
                        get: { value.quantityDisplay(language: language) },
                        set: { item.wrappedValue.quantityText = $0 }
                    )
                )
                .keyboardType(.decimalPad)
                .bodyFlowField()
                .accessibilityLabel(copy("registration.review.item.quantity"))
                .accessibilityIdentifier("registration.review.item.\(value.id).quantity")

                BodyFlowStatusLine(
                    [copy(MealCaptureCopy.basisKey(for: value)), portion(of: value)]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    kind: value.quantity(language: language) == nil ? .warning : .info
                )
                .accessibilityIdentifier("registration.review.item.\(value.id).basis")

                if value.requiresConfirmation {
                    Toggle(isOn: item.isConfirmed) {
                        Text(copy("registration.review.confirm-item"))
                            .font(BodyFlowTypography.callout)
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityIdentifier("registration.review.item.\(value.id).confirm")
                }

                if review.offersNutritionLabel {
                    Toggle(isOn: Binding(
                        get: { review.usesNutritionLabel(value.id) },
                        set: { review.setUsesNutritionLabel($0, for: value.id) }
                    )) {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                            Text(copy("registration.review.label.use"))
                                .font(BodyFlowTypography.callout)
                            if review.suggestedLabelItemID == value.id {
                                Text(copy("registration.review.label.suggested"))
                                    .font(BodyFlowTypography.caption)
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                            }
                        }
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityIdentifier("registration.review.item.\(value.id).label")
                }

                Button {
                    review.remove(value.id)
                } label: {
                    Label(verbatim: copy("registration.review.remove"), symbol: .remove)
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
                .disabled(isSubmitting)
                .accessibilityIdentifier("registration.review.item.\(value.id).remove")
            }
        }
    }

    /// The visible name of a field; the field itself carries the same label
    /// for assistive technologies.
    private func fieldCaption(_ key: String.LocalizationValue) -> some View {
        Text(copy(key))
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .accessibilityHidden(true)
    }

    /// "2 × unidade", as the server counted it; nil when it did not count.
    private func portion(of item: MealDraftReview.Item) -> String? {
        guard !item.hasTypedQuantity,
              let count = item.candidate.count,
              let unit = item.candidate.unitLabel
        else {
            return nil
        }
        return "\(MealProposalNumberParser.format(count, language: language)) × \(unit)"
    }

    private func note(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text(title)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
            Text(verbatim: text)
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }
}
