import SwiftUI

/// Text belongs to the server; paragraph positions preserve repetitions and order.
@MainActor
struct ProtocolMessageView: View {
    let welcome: ProtocolWelcome
    let onContinue: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            Text(copy("onboarding.protocol-welcome.title", fallback: "Mensagem do Flow"))
                .font(BodyFlowTypography.screenTitle)
                .accessibilityAddTraits(.isHeader)
            BodyFlowCard(surface: .card) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    Text(verbatim: "Flow").font(BodyFlowTypography.headline)
                        .accessibilityIdentifier("onboarding.protocol-welcome.sender")
                    ForEach(Array(welcome.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        Text(verbatim: paragraph).font(BodyFlowTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboarding.protocol-welcome.paragraph.\(index)")
                    }
                }
            }
            Button(action: onContinue) {
                Text(copy("onboarding.protocol-welcome.continue", fallback: "Ir para Hoje"))
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary))
            .accessibilityIdentifier("onboarding.protocol-welcome.continue")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.protocol-welcome")
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}
