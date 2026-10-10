import SwiftUI

struct MealTextDraftView: View {
    @Binding var draft: String
    let isSubmitting: Bool
    var presentsLocalDemonstration: Bool = true
    /// True when the field should take the keyboard by itself (the direct
    /// entry, once the sheet has finished arriving).
    var takesKeyboard: Bool = false
    let detect: @MainActor () -> Void
    @Environment(\.locale) private var locale
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("registration.text.title"))
                .font(BodyFlowTypography.headline)
            TextField(
                copy(presentsLocalDemonstration
                    ? "registration.text.placeholder"
                    : "registration.text.placeholder.live"),
                text: $draft,
                axis: .vertical
            )
                .lineLimit(3...6)
                .textInputAutocapitalization(.sentences)
                .focused($fieldFocused)
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
        .onChange(of: takesKeyboard, initial: true) { _, takes in
            if takes { fieldFocused = true }
        }
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(
            key,
            language: BodyFlowPresentationLanguage.resolve(locale)
        )
    }
}
