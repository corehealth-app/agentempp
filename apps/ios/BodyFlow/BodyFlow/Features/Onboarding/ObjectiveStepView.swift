import SwiftUI

@MainActor
struct ObjectiveStepView: View {
    let model: OnboardingFlowModel
    @State private var explainsGain = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            if model.hasCurrentEligibilityDecision, let decision = model.eligibilityDecision {
                if decision.decision == .assigned {
                    Text(copy("onboarding.objective.assigned.title", fallback: "Seu objetivo inicial"))
                        .font(BodyFlowTypography.screenTitle)
                        .accessibilityAddTraits(.isHeader)
                    paragraphs(decision.notice ?? [])
                        .accessibilityIdentifier("onboarding.objective.notice")
                    if let objective = decision.objective {
                        row(objective, selected: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isSelected)
                            .accessibilityIdentifier(identifier(for: objective))
                    }
                    DisclosureGroup(isExpanded: $explainsGain) {
                        if let gain = decision.options.first(where: { $0.objective == .muscleGain }) {
                            paragraphs(gain.message)
                                .accessibilityIdentifier("onboarding.objective.reason.ganho-massa")
                        }
                    } label: {
                        Text(copy("onboarding.objective.about-gain", fallback: "Sobre o ganho de massa muscular"))
                            .font(BodyFlowTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
                            .accessibilityIdentifier("onboarding.objective.about-gain")
                    }
                } else if decision.decision == .noPlan {
                    Text(copy("onboarding.clinical.no-plan.title",fallback:"Seu acompanhamento"))
                        .font(BodyFlowTypography.screenTitle).accessibilityAddTraits(.isHeader)
                    paragraphs(decision.notice ?? []).accessibilityIdentifier("onboarding.objective.no-plan")
                } else {
                    OnboardingStepHeader(
                        titleKey: "onboarding.objective.title", titleFallback: "Seu objetivo",
                        messageKey: "onboarding.objective.message",
                        messageFallback: "Escolha uma opção para orientar a organização da experiência."
                    )
                    paragraphs(decision.notice ?? [])
                    ForEach(decision.options, id: \.objective) { option in
                        if option.status == .available {
                            Button { model.updateObjective(option.objective) } label: {
                                row(option.objective, selected: model.draft.objective == option.objective)
                            }
                            .buttonStyle(.bodyFlowRow)
                            .accessibilityAddTraits(model.draft.objective == option.objective ? .isSelected : [])
                            .accessibilityHint(model.accessibilityHint(for: [.objectiveRequired]))
                            .accessibilityIdentifier(identifier(for: option.objective))
                        } else {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                                row(option.objective, selected: false)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier(identifier(for: option.objective))
                                BodyFlowStatusLine(copy("onboarding.objective.unavailable", fallback: "Indisponível"), kind: .unavailable)
                                paragraphs(option.message)
                                    .accessibilityIdentifier(reasonIdentifier(for: option.objective))
                            }
                        }
                    }
                }
                OnboardingFieldIssue(model: model, candidates: [.objectiveRequired])
            } else if model.operationState == .saving || model.operationState == .idle {
                BodyFlowStatusLine(copy("onboarding.objective.checking", fallback: "Conferindo os objetivos disponíveis…"), kind: .pending)
                    .accessibilityIdentifier("onboarding.objective.checking")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.objective")
    }

    private func paragraphs(_ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, text in
                Text(verbatim: text).font(BodyFlowTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ value: BodyFlowObjective, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
            Image(symbol: selected ? .selected : .unselected).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                Text(value.onboardingLabel(for: language)).font(BodyFlowTypography.headline)
                Text(value.onboardingDescription(for: language))
                    .font(BodyFlowTypography.callout).foregroundStyle(BodyFlowColor.secondaryText)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget, alignment: .leading)
        .padding(BodyFlowSpacing.sm)
        .background(BodyFlowColor.surface, in: RoundedRectangle(cornerRadius: BodyFlowRadius.card))
        .contentShape(Rectangle())
    }

    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
    private func reasonIdentifier(for objective: BodyFlowObjective) -> String {
        switch objective {
        case .bodyRecomposition: "onboarding.objective.reason.recomposicao"
        case .muscleGain: "onboarding.objective.reason.ganho-massa"
        case .maintenance: "onboarding.objective.reason.manutencao"
        }
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
#Preview("Objetivo · Conferência") {
    OnboardingContainerView(model: .preview(step: .objective))
}
#endif
