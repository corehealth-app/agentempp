import SwiftUI

/// Text belongs to the server; paragraph positions preserve repetitions and order.
@MainActor
struct ProtocolMessageView: View {
    enum Context {
        case onboarding, currentObjective
        var prefix: String {
            self == .onboarding ? "onboarding.protocol-welcome" : "current-objective.welcome"
        }
        var actionIdentifier: String { prefix + (self == .onboarding ? ".continue" : ".close") }
        var actionKey: String.LocalizationValue {
            self == .onboarding ? "onboarding.protocol-welcome.continue" : "current-objective.welcome.close"
        }
        var actionFallback: String { self == .onboarding ? "Ir para Hoje" : "Fechar" }
    }
    let welcome: ProtocolWelcome
    let context: Context
    let onContinue: @MainActor () -> Void
    @Environment(\.locale) private var locale

    init(welcome: ProtocolWelcome, context: Context = .onboarding, onContinue: @escaping @MainActor () -> Void) {
        self.welcome = welcome
        self.context = context
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            Text(copy("onboarding.protocol-welcome.title", fallback: "Mensagem do Flow"))
                .font(BodyFlowTypography.screenTitle)
                .accessibilityAddTraits(.isHeader)
            BodyFlowCard(surface: .card) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    Text(verbatim: "Flow").font(BodyFlowTypography.headline)
                        .accessibilityIdentifier(context.prefix + ".sender")
                    ForEach(Array(welcome.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        Text(verbatim: paragraph).font(BodyFlowTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(context.prefix + ".paragraph.\(index)")
                    }
                }
            }
            Button(action: onContinue) {
                Text(copy(context.actionKey, fallback: context.actionFallback))
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary))
            .accessibilityIdentifier(context.actionIdentifier)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen." + context.prefix)
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}
