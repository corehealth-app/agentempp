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
                messageFallback: "Confira suas escolhas antes de concluir seu cadastro."
            )

            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                reviewRow(
                    copy("onboarding.completion.name", fallback: "Nome"),
                    value: model.draft.displayName
                        ?? copy("onboarding.completion.not-provided", fallback: "Não informado")
                )
                reviewRow(
                    copy("onboarding.completion.country", fallback: "País"),
                    value: OnboardingCountryPresentation.name(
                        for: model.draft.countryCode,
                        language: language
                    )
                )
                reviewRow(
                    copy("onboarding.completion.time-zone", fallback: "Fuso"),
                    value: OnboardingTimeZonePresentation(
                        identifier: model.draft.timeZoneIdentifier,
                        language: language
                    ).summary
                )
                reviewRow(
                    copy("onboarding.completion.objective", fallback: "Objetivo"),
                    value: model.draft.objective?.onboardingLabel(for: language)
                        ?? copy("onboarding.completion.not-selected", fallback: "Não selecionado")
                )
                reviewRow(
                    copy("onboarding.completion.training", fallback: "Musculação"),
                    value: OnboardingCopy.format(
                        "onboarding.routine.training-frequency.format",
                        language: language,
                        model.draft.trainingFrequency ?? 0
                    )
                )
                reviewRow(
                    copy("onboarding.completion.flow-style", fallback: "Estilo do Flow"),
                    value: model.draft.persona.map(personaTitle)
                        ?? copy("onboarding.completion.not-selected", fallback: "Não selecionado")
                )
                if let documentActions = model.draft.documentActions,
                   !documentActions.isEmpty {
                    reviewRow(
                        copy("onboarding.completion.official-documents", fallback: "Documentos oficiais"),
                        value: OnboardingCopy.format(
                            documentActions.count == 1
                                ? "onboarding.completion.action-count.one"
                                : "onboarding.completion.action-count.other",
                            language: language,
                            documentActions.count
                        )
                    )
                    ForEach(documentActions, id: \.self) { action in
                        reviewRow(
                            OnboardingLegalDocumentKind.title(
                                forDocumentKey: action.documentKey,
                                language: language
                            ),
                            value: OnboardingCopy.format(
                                "onboarding.completion.version-action-format",
                                language: language,
                                action.version,
                                actionLabel(action.action)
                            )
                        )
                    }
                } else {
                    reviewRow(
                        copy(
                            "onboarding.completion.development-consent",
                            fallback: "Consentimento de desenvolvimento"
                        ),
                        value: model.draft.consent == nil
                            ? copy("onboarding.completion.pending", fallback: "Pendente")
                            : copy("onboarding.completion.confirmed", fallback: "Confirmado")
                    )
                }
            }
            .padding(BodyFlowSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                BodyFlowColor.surface,
                in: RoundedRectangle(cornerRadius: BodyFlowRadius.card)
            )

            Label(
                verbatim: copy(
                    "onboarding.completion.notice",
                    fallback: "Seu perfil só será concluído depois que todas as escolhas forem salvas com sucesso."
                ),
                symbol: .privacy
            )
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            if model.unresolvedCompletion {
                BodyFlowStatusLine(completionStatusMessage, kind: .pending)
                    .accessibilityIdentifier("onboarding.completion.unresolved")
            }

            OnboardingCompletionCommands(model: model, onComplete: onComplete)

        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.completion")
    }

    private var completionStatusMessage: String {
        switch model.completionStatus {
        case .preparation:
            copy("onboarding.completion.preparation-uncertain",
                fallback: "A preparação do cadastro ainda precisa ser conferida. Confira novamente ou revise os dados antes de iniciar outra tentativa.")
        case .reconciliation:
            copy("onboarding.completion.reconciling",
                fallback: "O cadastro precisa ser conferido com o servidor antes de continuar. Conferir novamente apenas consulta o resultado.")
        default:
            copy("onboarding.completion.unresolved",
                fallback: "O envio anterior ainda precisa ser confirmado. Tente novamente para conferir o resultado.")
        }
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

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func personaTitle(_ persona: CoachPersona) -> String {
        switch persona {
        case .focus:
            OnboardingCopy.string("onboarding.persona.focus.title", language: language)
        case .impulse:
            OnboardingCopy.string("onboarding.persona.impulse.title", language: language)
        case .zen:
            OnboardingCopy.string("onboarding.persona.zen.title", language: language)
        }
    }

    private func actionLabel(_ action: OnboardingLegalAction) -> String {
        switch action {
        case .acceptance:
            OnboardingCopy.string("onboarding.completion.action.acceptance", language: language)
        case .acknowledgement:
            OnboardingCopy.string("onboarding.completion.action.acknowledgement", language: language)
        case .consent:
            OnboardingCopy.string("onboarding.completion.action.consent", language: language)
        }
    }
}

/// The actual review commands, also hosted by the accessibility geometry tests.
@MainActor
struct OnboardingCompletionCommands: View {
    let model: OnboardingFlowModel
    let onComplete: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            Button(action: onComplete) {
                Text(model.checksCompletionOnly
                     ? copy("onboarding.completion.check-again", fallback: "Conferir novamente")
                     : (model.operationState.isFailure
                        ? copy("onboarding.retry", fallback: "Tentar novamente")
                        : copy("onboarding.completion.finish", fallback: "Concluir cadastro")))
            }
            .buttonStyle(BodyFlowButtonStyle(
                role: .primary,
                isLoading: model.operationState == .saving
            ))
            .disabled(model.operationState == .saving)
            .accessibilityIdentifier("onboarding.go-to-today")

            if model.canReviewCompletion {
                Button {
                    model.reviewCompletionBeforeRetry()
                } label: {
                    Text(copy("onboarding.completion.review-before-retry", fallback: "Revisar cadastro"))
                        .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget)
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .accessibilityIdentifier("onboarding.completion.review-before-retry")
            }
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
