import SwiftUI

@MainActor
struct ConsentStepView: View {
    let model: OnboardingFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            OnboardingStepHeader(
                title: "Consentimento de desenvolvimento",
                message: "Ambiente de validação. Estes documentos são sintéticos e não representam um aceite jurídico real."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Toggle(
                    "Confirmo os Termos de desenvolvimento (dev.terms.v1)",
                    isOn: acceptanceBinding(for: .terms)
                )
                .accessibilityIdentifier("consent.terms")

                Toggle(
                    "Confirmo a Privacidade de desenvolvimento (dev.privacy.v1)",
                    isOn: acceptanceBinding(for: .privacy)
                )
                .accessibilityIdentifier("consent.privacy")
            }
            .font(BodyFlowTypography.headline)
            .fixedSize(horizontal: false, vertical: true)

            OnboardingFieldIssue(model: model, candidates: [.consentRequired])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.consent")
    }

    private func acceptanceBinding(
        for documentID: DevelopmentConsentDocumentID
    ) -> Binding<Bool> {
        Binding(
            get: { model.draft.consent?.documentIDs.contains(documentID) == true },
            set: { accepted in
                var acceptedIDs = Set(model.draft.consent?.documentIDs ?? [])
                if accepted {
                    acceptedIDs.insert(documentID)
                } else {
                    acceptedIDs.remove(documentID)
                }

                guard !acceptedIDs.isEmpty else {
                    model.updateConsent(nil)
                    return
                }
                model.updateConsent(DevelopmentConsentAcceptance(
                    documentIDs: DevelopmentConsentDocumentID.allCases.filter(
                        acceptedIDs.contains
                    ),
                    acceptedAt: model.draft.consent?.acceptedAt ?? Date()
                ))
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
