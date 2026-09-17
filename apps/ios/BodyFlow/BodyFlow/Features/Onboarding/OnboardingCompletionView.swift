import SwiftUI

@MainActor
struct OnboardingCompletionView: View {
    let model: OnboardingFlowModel
    let onComplete: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                titleKey: "onboarding.completion.title",
                titleFallback: "Revise suas escolhas",
                messageKey: "onboarding.completion.message",
                messageFallback: "Confira suas escolhas antes de concluir seu onboarding."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                reviewRow("Nome", value: model.draft.displayName ?? "Não informado")
                reviewRow("País", value: model.draft.countryCode)
                reviewRow("Fuso", value: model.draft.timeZoneIdentifier)
                reviewRow("Objetivo", value: model.draft.objective?.onboardingLabel ?? "Não selecionado")
                reviewRow("Treinos", value: "\(model.draft.trainingFrequency ?? 0) por semana")
                reviewRow("Coach", value: model.draft.persona?.displayName ?? "Não selecionado")
                if let documentActions = model.draft.documentActions,
                   !documentActions.isEmpty {
                    reviewRow(
                        "Documentos oficiais",
                        value: "\(documentActions.count) \(documentActions.count == 1 ? "ação confirmada" : "ações confirmadas")"
                    )
                    ForEach(documentActions, id: \.self) { action in
                        reviewRow(
                            action.documentKey,
                            value: "Versão \(action.version) · \(action.action.reviewLabel)"
                        )
                    }
                } else {
                    reviewRow(
                        "Consentimento de desenvolvimento",
                        value: model.draft.consent == nil ? "Pendente" : "Confirmado"
                    )
                }
            }
            .padding(BodyFlowSpacing.md)
            .background(
                BodyFlowColor.surface,
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.card)
            )

            Label(
                copy(
                    "onboarding.completion.notice",
                    fallback: "Seu perfil só será concluído depois que todas as escolhas forem salvas com sucesso."
                ),
                systemImage: "lock.shield"
            )
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onComplete) {
                HStack {
                    Spacer()
                    if model.operationState == .saving {
                        ProgressView()
                            .tint(.white)
                            .accessibilityHidden(true)
                    }
                    Text(model.operationState.isFailure
                         ? copy("onboarding.retry", fallback: "Tentar novamente")
                         : copy("onboarding.completion.finish", fallback: "Ir para Hoje"))
                    Spacer()
                }
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary))
            .disabled(model.operationState == .saving)
            .accessibilityIdentifier("onboarding.go-to-today")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.completion")
    }

    private func reviewRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            Text(label).font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
            Text(value).font(BodyFlowTypography.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}

private extension OnboardingOperationState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

private extension OnboardingLegalAction {
    var reviewLabel: String {
        switch self {
        case .acceptance: "Aceite"
        case .acknowledgement: "Ciência"
        case .consent: "Consentimento"
        }
    }
}

#if DEBUG
#Preview("Revisão · Válido") {
    OnboardingContainerView(model: .preview(step: .completion))
}

#Preview("Revisão · Salvando") {
    OnboardingContainerView(model: .preview(
        step: .completion,
        operationState: .saving
    ))
}

#Preview("Revisão · Erro recuperável") {
    OnboardingContainerView(model: .preview(
        step: .completion,
        operationState: .failed(.serviceUnavailable)
    ))
}
#endif
