import SwiftUI

struct MealTextDraftView: View {
    @Binding var draft: String
    let isSubmitting: Bool
    let detect: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text("Descreva a refeição")
                .font(BodyFlowTypography.headline)
            TextField("Ex.: arroz, feijão e frango", text: $draft, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("registration.meal.text")

            Button("Detectar refeição", action: detect)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting || draft.isEmpty)
                .accessibilityIdentifier("registration.meal.detect")
        }
    }
}
