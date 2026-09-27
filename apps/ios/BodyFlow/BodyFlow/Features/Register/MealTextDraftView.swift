import SwiftUI

struct MealTextDraftView: View {
    @Binding var draft: String
    let isSubmitting: Bool
    var presentsLocalDemonstration: Bool = true
    let detect: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("registration.text.title"))
                .font(BodyFlowTypography.headline)
            TextField(copy("registration.text.placeholder"), text: $draft, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("registration.meal.text")

            Button(action: detect) {
                Text(copy("registration.capture.detect"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .disabled(isSubmitting || draft.isEmpty)
                .accessibilityIdentifier("registration.meal.detect")
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}
