import SwiftUI

@MainActor
struct PersonaStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                title: "Escolha seu coach",
                message: "A persona muda o estilo da conversa, não os cálculos ou orientações."
            )

            VStack(spacing: BodyFlowSpacing.sm) {
                ForEach(CoachPersona.allCases, id: \.self) { value in
                    Button {
                        model.updatePersona(value)
                    } label: {
                        HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                            Image(systemName: model.draft.persona == value ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                                Text(value.displayName).fontWeight(.semibold)
                                Text(description(for: value))
                                    .font(BodyFlowTypography.callout)
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
                        .padding(BodyFlowSpacing.sm)
                        .background(BodyFlowColor.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.draft.persona == value ? .isSelected : [])
                }
            }
            OnboardingFieldIssue(model: model, candidates: [.personaRequired])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.persona")
    }

    private func description(for persona: CoachPersona) -> String {
        switch persona {
        case .focus: "Direto, firme, objetivo e respeitoso."
        case .impulse: "Motivador, positivo e energético."
        case .zen: "Calmo, explicativo e acolhedor."
        }
    }
}

#if DEBUG
#Preview("Persona · Válido") {
    OnboardingContainerView(model: .preview(step: .persona))
}

#Preview("Persona · Validação") {
    OnboardingContainerView(model: .preview(
        step: .persona,
        validationIssues: [.personaRequired]
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Persona · Erro ao salvar") {
    OnboardingContainerView(model: .preview(
        step: .persona,
        operationState: .failed(.serviceUnavailable)
    ))
}
#endif
