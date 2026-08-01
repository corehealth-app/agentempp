import SwiftUI

enum MealCaptureChoice: Equatable {
    case text
    case photo
    case audio
}

struct MealCaptureSourceView: View {
    let select: @MainActor (MealCaptureChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text("Como deseja adicionar a refeição?")
                .font(BodyFlowTypography.headline)
                .foregroundStyle(BodyFlowColor.primaryText)

            sourceButton(
                "Descrever em texto",
                systemImage: "text.alignleft",
                identifier: "registration.meal.source.text"
            ) {
                select(.text)
            }
            sourceButton(
                "Usar amostra de foto",
                systemImage: "photo",
                identifier: "registration.meal.source.photo"
            ) {
                select(.photo)
            }
            sourceButton(
                "Usar amostra de áudio",
                systemImage: "waveform",
                identifier: "registration.meal.source.audio"
            ) {
                select(.audio)
            }
        }
    }

    private func sourceButton(
        _ title: String,
        systemImage: String,
        identifier: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
    }
}
