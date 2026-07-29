import SwiftUI

@MainActor
struct OnboardingCompletionView: View {
    let model: OnboardingFlowModel
    let onComplete: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                title: "Revise suas escolhas",
                message: "Confira o rascunho salvo antes de concluir seu onboarding."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                reviewRow("Nome", value: model.draft.displayName ?? "Não informado")
                reviewRow("País", value: model.draft.countryCode)
                reviewRow("Fuso", value: model.draft.timeZoneIdentifier)
                reviewRow("Objetivo", value: model.draft.objective?.onboardingLabel ?? "Não selecionado")
                reviewRow("Treinos", value: "\(model.draft.trainingFrequency ?? 0) por semana")
                reviewRow("Coach", value: model.draft.persona?.displayName ?? "Não selecionado")
                reviewRow("Consentimento de desenvolvimento", value: model.draft.consent == nil ? "Pendente" : "Confirmado")
            }
            .padding(BodyFlowSpacing.md)
            .background(BodyFlowColor.surface, in: RoundedRectangle(cornerRadius: 16))

            Label(
                "Seu perfil só será concluído depois que todas as escolhas forem salvas com sucesso.",
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
                    Text("Ir para Hoje")
                    Spacer()
                }
                .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            }
            .buttonStyle(.borderedProminent)
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
