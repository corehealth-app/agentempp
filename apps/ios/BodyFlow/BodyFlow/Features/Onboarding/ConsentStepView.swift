import SwiftUI

@MainActor
struct ConsentStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                title: "Consentimento de desenvolvimento",
                message: "Esta demonstração usa documentos técnicos sintéticos. Eles não representam aceite legal."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Label("Termos de desenvolvimento", systemImage: "doc.text")
                Label("Privacidade de desenvolvimento", systemImage: "hand.raised")
            }
            .font(BodyFlowTypography.body)

            Toggle("Confirmo os dois documentos sintéticos para continuar nesta demonstração", isOn: consentAccepted)
                .font(BodyFlowTypography.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.development-consent")

            OnboardingFieldIssue(model: model, candidates: [.consentRequired])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.consent")
    }

    private var consentAccepted: Binding<Bool> {
        Binding(
            get: { model.draft.consent != nil },
            set: { accepted in
                model.updateConsent(accepted ? DevelopmentConsentAcceptance(
                    documentIDs: ["development-privacy", "development-terms"],
                    acceptedAt: Date()
                ) : nil)
            }
        )
    }
}

#if DEBUG
#Preview("Consentimento · Válido") {
    OnboardingContainerView(model: .preview(step: .consent))
}

#Preview("Consentimento · Validação") {
    OnboardingContainerView(model: .preview(
        step: .consent,
        validationIssues: [.consentRequired]
    ))
    .dynamicTypeSize(.accessibility3)
}

#Preview("Consentimento · Erro ao salvar") {
    OnboardingContainerView(model: .preview(
        step: .consent,
        operationState: .failed(.operationUnavailable)
    ))
}
#endif
