import SwiftUI

struct MealDemonstrationSourceView: View {
    let choice: MealCaptureChoice
    let isSubmitting: Bool
    let detect: @MainActor () -> Void
    @Environment(\.locale) private var locale

    private var isPhoto: Bool { choice == .photo }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Label(
                copy(isPhoto
                    ? "registration.demo.photo-title"
                    : "registration.demo.audio-title"),
                systemImage: isPhoto ? "photo" : "waveform"
            )
            .font(BodyFlowTypography.headline)
            .accessibilityIdentifier(
                isPhoto ? "registration.meal.photo" : "registration.meal.audio"
            )

            Text(copy("registration.capture.demo-notice"))
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)

            Button(action: detect) {
                Text(copy("registration.capture.detect"))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
            }
                .buttonStyle(BodyFlowButtonStyle(role: .primary))
                .disabled(isSubmitting)
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
