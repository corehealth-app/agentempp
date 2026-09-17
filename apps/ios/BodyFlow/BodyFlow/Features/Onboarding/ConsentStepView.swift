import SwiftUI

enum OnboardingConsentAccessibilityID {
    static let developmentGroup = "onboarding.development-consent"
    static let developmentTerms = "consent.terms"
    static let developmentPrivacy = "consent.privacy"
    static let officialGroup = "onboarding.legal-documents"

    static func officialDocument(_ key: String) -> String {
        "onboarding.legal-document.\(key)"
    }

    static func officialAction(_ key: String) -> String {
        "onboarding.legal-action.\(key)"
    }
}

@MainActor
struct ConsentStepView: View {
    let model: OnboardingFlowModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            if model.requirements.available {
                OnboardingStepHeader(
                    titleKey: "onboarding.consent.title",
                    titleFallback: "Documentos e confirmações",
                    messageKey: "onboarding.consent.message",
                    messageFallback: "Leia cada documento e registre a ação indicada para continuar."
                )
                officialDocuments
            } else {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    OnboardingStepHeader(
                        titleKey: "onboarding.consent.development.title",
                        titleFallback: "Consentimento de desenvolvimento",
                        messageKey: "onboarding.consent.development.message",
                        messageFallback: "Ambiente de validação. Estes documentos são sintéticos e não representam um aceite jurídico real."
                    )
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        consentButton(
                            for: .terms,
                            accessibilityIdentifier: OnboardingConsentAccessibilityID.developmentTerms
                        )
                        consentButton(
                            for: .privacy,
                            accessibilityIdentifier: OnboardingConsentAccessibilityID.developmentPrivacy
                        )
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(OnboardingConsentAccessibilityID.developmentGroup)
                }
            }

            OnboardingFieldIssue(model: model, candidates: [.consentRequired])
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.consent")
    }

    private var officialDocuments: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            ForEach(model.requirements.documents, id: \.documentKey) { document in
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                        Text(document.documentKey)
                            .font(BodyFlowTypography.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(document.required
                             ? copy("onboarding.consent.required", fallback: "Obrigatório")
                             : copy("onboarding.consent.optional", fallback: "Opcional"))
                            .font(BodyFlowTypography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(BodyFlowColor.color(.brandPrimary))
                    }
                    Text(document.purpose)
                        .font(BodyFlowTypography.callout)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(document.body ?? "")
                        .font(BodyFlowTypography.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PremiumPresentationCopy.format(
                        "onboarding.consent.version-format",
                        locale: locale,
                        fallback: "Versão %@",
                        document.version
                    ))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    officialActionButton(for: document)
                }
                .padding(BodyFlowSpacing.md)
                .background(
                    BodyFlowColor.surface,
                    in: RoundedRectangle(cornerRadius: BodyFlowRadius.card)
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    OnboardingConsentAccessibilityID.officialDocument(document.documentKey)
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OnboardingConsentAccessibilityID.officialGroup)
    }

    private func officialActionButton(
        for document: OnboardingLegalDocument
    ) -> some View {
        let action = document.explicitAction
        let isSelected = model.draft.documentActions?.contains(action) == true
        return Button {
            model.updateDocumentAction(action, selected: !isSelected)
        } label: {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .accessibilityHidden(true)
                Text(actionLabel(document.action))
                    .font(BodyFlowTypography.headline)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .frame(
                maxWidth: .infinity,
                minHeight: BodyFlowSpacing.minimumTapTarget,
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .frame(
            maxWidth: .infinity,
            minHeight: BodyFlowSpacing.minimumTapTarget,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(
            OnboardingConsentAccessibilityID.officialAction(document.documentKey)
        )
    }

    private func actionLabel(_ action: OnboardingLegalAction) -> String {
        switch action {
        case .acceptance: copy("onboarding.consent.accept", fallback: "Aceitar")
        case .acknowledgement: copy("onboarding.consent.acknowledge", fallback: "Confirmar ciência")
        case .consent: copy("onboarding.consent.consent", fallback: "Consentir")
        }
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }

    private func consentButton(
        for documentID: DevelopmentConsentDocumentID,
        accessibilityIdentifier: String
    ) -> some View {
        let acceptance = acceptanceBinding(for: documentID)
        let isAccepted = acceptance.wrappedValue

        return Button {
            acceptance.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                Image(
                    systemName: isAccepted
                        ? "checkmark.square.fill"
                        : "square"
                )
                .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: BodyFlowSpacing.xxs
                ) {
                    Text(title(for: documentID))
                        .font(BodyFlowTypography.headline)
                    Text(isAccepted ? "Selecionado" : "Não selecionado")
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
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.card)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isAccepted ? .isSelected : [])
        .accessibilityHint(
            model.accessibilityHint(for: [.consentRequired])
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func title(
        for documentID: DevelopmentConsentDocumentID
    ) -> String {
        switch documentID {
        case .terms:
            "Confirmo os Termos de desenvolvimento (dev.terms.v1)"
        case .privacy:
            "Confirmo a Privacidade de desenvolvimento (dev.privacy.v1)"
        }
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
