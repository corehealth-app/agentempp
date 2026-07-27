import SwiftUI

@MainActor
struct ObjectiveStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                title: "Seu objetivo",
                message: "Escolha uma opção para orientar a organização da experiência."
            )

            Picker("Objetivo", selection: objective) {
                ForEach(BodyFlowObjective.allCases, id: \.self) { value in
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                        Text(value.onboardingLabel).fontWeight(.semibold)
                        Text(value.onboardingDescription)
                            .font(BodyFlowTypography.callout)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .tag(value as BodyFlowObjective?)
                    .accessibilityIdentifier(identifier(for: value))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            OnboardingFieldIssue(model: model, candidates: [.objectiveRequired])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.objective")
    }

    private var objective: Binding<BodyFlowObjective?> {
        Binding(get: { model.draft.objective }, set: { model.updateObjective($0) })
    }

    private func identifier(for objective: BodyFlowObjective) -> String {
        switch objective {
        case .bodyRecomposition: "onboarding.objective.recomposicao"
        case .muscleGain: "onboarding.objective.ganho-massa"
        case .maintenance: "onboarding.objective.manutencao"
        }
    }
}

#if DEBUG
#Preview("Objetivo · Válido") {
    OnboardingContainerView(model: .preview(step: .objective))
}

#Preview("Objetivo · Validação") {
    OnboardingContainerView(model: .preview(
        step: .objective,
        validationIssues: [.objectiveRequired]
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Objetivo · Erro ao salvar") {
    OnboardingContainerView(model: .preview(
        step: .objective,
        operationState: .failed(.serviceUnavailable)
    ))
}
#endif
