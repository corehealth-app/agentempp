import SwiftUI

/// The same official document cards serve signup and existing accounts.
/// They do not know anything about profile, health, photos, or completion.
@MainActor
struct OnboardingLegalDocumentsView: View {
    let documents: [OnboardingLegalDocument]
    let selectedActions: Set<OnboardingDocumentAction>
    let allowsEditing: Bool
    var recordedActions: Set<OnboardingDocumentAction> = []
    let onChange: (OnboardingDocumentAction, Bool) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            ForEach(documents, id: \.documentKey) { document in
                let presentation = OnboardingLegalDocumentPresentation(
                    document: document,
                    language: BodyFlowPresentationLanguage.resolve(locale)
                )
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                        Text(presentation.title)
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
                    Text(presentation.body)
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
        let isSelected = selectedActions.contains(action)
        return Button {
            onChange(action, !isSelected)
        } label: {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                Image(symbol: isSelected ? .checkboxOn : .checkboxOff)
                    .accessibilityHidden(true)
                Text(recordedActions.contains(action)
                     ? copy("onboarding.legacy.recorded", fallback: "Já registrado")
                     : actionLabel(document.action))
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
        .buttonStyle(.bodyFlowRow)
        .disabled(!allowsEditing || recordedActions.contains(action))
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
}
