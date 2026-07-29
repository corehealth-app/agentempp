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

            VStack(spacing: BodyFlowSpacing.sm) {
                ForEach(BodyFlowObjective.allCases, id: \.self) { value in
                    Button {
                        model.updateObjective(value)
                    } label: {
                        HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                            Image(
                                systemName: model.draft.objective == value
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .accessibilityHidden(true)

                            VStack(
                                alignment: .leading,
                                spacing: BodyFlowSpacing.xxs
                            ) {
                                Text(value.onboardingLabel)
                                    .fontWeight(.semibold)
                                Text(value.onboardingDescription)
                                    .font(BodyFlowTypography.callout)
                                    .foregroundStyle(BodyFlowColor.secondaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget,
                            alignment: .leading
                        )
                        .padding(BodyFlowSpacing.sm)
                        .background(
                            BodyFlowColor.surface,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        model.draft.objective == value ? .isSelected : []
                    )
                    .accessibilityHint(
                        model.accessibilityHint(for: [.objectiveRequired])
                    )
                    .accessibilityIdentifier(identifier(for: value))
                }
            }

            OnboardingFieldIssue(model: model, candidates: [.objectiveRequired])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.objective")
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
