import SwiftUI

struct MealDemonstrationSourceView: View {
    let choice: MealCaptureChoice
    let isSubmitting: Bool
    let detect: @MainActor () -> Void

    private var isPhoto: Bool { choice == .photo }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Label(
                isPhoto ? "Amostra fotográfica local" : "Amostra de áudio local",
                systemImage: isPhoto ? "photo" : "waveform"
            )
            .font(BodyFlowTypography.headline)
            .accessibilityIdentifier(
                isPhoto ? "registration.meal.photo" : "registration.meal.audio"
            )

            Text("Demonstração local; não solicita permissão nem acessa mídia.")
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)

            Button("Detectar refeição", action: detect)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting)
                .accessibilityIdentifier("registration.meal.detect")
        }
    }
}
