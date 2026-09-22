import SwiftUI
import UIKit

@MainActor
struct OnboardingContainerView: View {
    let model: OnboardingFlowModel
    @State private var submissionTask: Task<Void, Never>?
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ZStack {
                BodyFlowColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                        BodyFlowBrandIdentityView()
                        progress
                        OnboardingOperationMessage(state: model.operationState)
                        OnboardingValidationSummary(issues: model.validationIssues)
                        stepContent
                        commands
                    }
                    .padding(.horizontal, BodyFlowSpacing.lg)
                    .padding(.vertical, BodyFlowSpacing.lg)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onDisappear(perform: cancelSubmission)
    }

    private var progress: some View {
        let position = (OnboardingStep.allCases.firstIndex(of: model.step) ?? 0) + 1
        return VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(PremiumPresentationCopy.format(
                "onboarding.progress.format",
                locale: locale,
                fallback: "Etapa %lld de %lld",
                position,
                OnboardingStep.allCases.count
            ))
                .font(BodyFlowTypography.callout)
                .fontWeight(.semibold)
            ProgressView(value: Double(position), total: Double(OnboardingStep.allCases.count))
                .frame(height: BodyFlowSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.progress")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.stepPresentation {
        case .step(.welcome):
            WelcomeStepView(model: model)
        case .step(.bodyData):
            BodyDataStepView(model: model)
        case .step(.objective):
            ObjectiveStepView(model: model)
        case .step(.routine):
            RoutineStepView(model: model)
        case .step(.persona):
            PersonaStepView(model: model)
        case .step(.consent):
            ConsentStepView(model: model)
        case .step(.completion):
            OnboardingCompletionView(model: model, onComplete: submitCompletion)
        case .developmentConsentUnavailable:
            OnboardingDocumentsUnavailableView()
        }
    }

    private var commands: some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            if model.step != .completion {
                if model.stepPresentation != .developmentConsentUnavailable {
                    Button(action: submit) {
                        Text(continueTitle)
                    }
                    .buttonStyle(BodyFlowButtonStyle(
                        role: .primary,
                        isLoading: model.operationState == .saving
                    ))
                    .disabled(
                        model.operationState == .saving
                            || (model.step == .consent && !model.hasRequiredDevelopmentConsent)
                    )
                    .accessibilityIdentifier("onboarding.continue")
                }

                if model.step != .welcome {
                    Button {
                        Task { await model.back() }
                    } label: {
                        Text(copy("onboarding.back", fallback: "Voltar"))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                        .disabled(model.operationState == .saving)
                        .accessibilityIdentifier("onboarding.back")
                }
            }
        }
    }

    private var continueTitle: String {
        switch model.operationState {
        case .idle: copy("onboarding.continue", fallback: "Continuar")
        case .saving: copy("onboarding.saving", fallback: "Salvando")
        case .failed: copy("onboarding.retry", fallback: "Tentar novamente")
        }
    }

    private func submit() {
        guard submissionTask == nil else { return }
        submissionTask = Task {
            await model.continueFromCurrentStep()
            announceOperationResultIfNeeded()
            submissionTask = nil
        }
    }

    private func submitCompletion() {
        guard submissionTask == nil else { return }
        submissionTask = Task {
            await model.complete()
            announceOperationResultIfNeeded()
            submissionTask = nil
        }
    }

    private func announceOperationResultIfNeeded() {
        let message: String
        let language = BodyFlowPresentationLanguage.resolve(locale)
        if let validationMessage = FormAccessibilityText.validationAnnouncement(
            messages: model.validationIssues.map { $0.message(for: language) },
            language: language
        ) {
            message = validationMessage
        } else if case .failed(let error) = model.operationState {
            message = error.authMessage(for: language)
        } else {
            return
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
        model.cancelActiveSubmission()
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}

extension OnboardingValidationIssue {
    var message: String {
        switch self {
        case .displayNameRequired: "Informe como você quer ser chamado."
        case .localeUnsupported: "Confirme um idioma compatível."
        case .countryInvalid: "Confirme um país válido."
        case .timeZoneInvalid: "Confirme um fuso horário válido."
        case .biologicalSexRequired: "Selecione o sexo biológico."
        case .birthDateRequired: "Informe a data de nascimento."
        case .birthDateInFuture: "A data de nascimento não pode estar no futuro."
        case .heightOutOfRange: "Informe uma altura entre 100 e 250 cm."
        case .weightOutOfRange: "Informe um peso entre 30 e 300 kg."
        case .bodyFatOutOfRange: "Informe gordura corporal entre 3% e 60%, ou deixe em branco."
        case .objectiveRequired: "Selecione um objetivo."
        case .activityLevelRequired: "Selecione seu nível de atividade."
        case .trainingFrequencyOutOfRange: "Informe de 0 a 7 treinos por semana."
        case .waterIntakeRequired: "Selecione seu consumo de água."
        case .hungerLevelRequired: "Selecione seu nível de fome."
        case .wakeTimeRequired: "Informe um horário válido para acordar."
        case .bedtimeRequired: "Informe um horário válido para dormir."
        case .foodOrganizationRequired: "Confirme como você organiza as refeições."
        case .personaRequired: "Selecione uma persona de coach."
        case .consentRequired: "Confirme as ações exigidas para todos os documentos atuais."
        case .developmentConsentUnavailable: "Os documentos necessários não estão disponíveis."
        }
    }

    func message(for language: SupportedAppLanguage) -> String {
        let key: String.LocalizationValue = switch self {
        case .displayNameRequired: "onboarding.validation.display-name-required"
        case .localeUnsupported: "onboarding.validation.locale-unsupported"
        case .countryInvalid: "onboarding.validation.country-invalid"
        case .timeZoneInvalid: "onboarding.validation.time-zone-invalid"
        case .biologicalSexRequired: "onboarding.validation.biological-sex-required"
        case .birthDateRequired: "onboarding.validation.birth-date-required"
        case .birthDateInFuture: "onboarding.validation.birth-date-in-future"
        case .heightOutOfRange: "onboarding.validation.height-out-of-range"
        case .weightOutOfRange: "onboarding.validation.weight-out-of-range"
        case .bodyFatOutOfRange: "onboarding.validation.body-fat-out-of-range"
        case .objectiveRequired: "onboarding.validation.objective-required"
        case .activityLevelRequired: "onboarding.validation.activity-level-required"
        case .trainingFrequencyOutOfRange: "onboarding.validation.training-frequency-out-of-range"
        case .waterIntakeRequired: "onboarding.validation.water-intake-required"
        case .hungerLevelRequired: "onboarding.validation.hunger-level-required"
        case .wakeTimeRequired: "onboarding.validation.wake-time-required"
        case .bedtimeRequired: "onboarding.validation.bedtime-required"
        case .foodOrganizationRequired: "onboarding.validation.food-organization-required"
        case .personaRequired: "onboarding.validation.persona-required"
        case .consentRequired: "onboarding.validation.consent-required"
        case .developmentConsentUnavailable: "onboarding.validation.development-consent-unavailable"
        }
        return (try? AppLocalization.string(key, for: language)) ?? message
    }
}

@MainActor
private struct OnboardingDocumentsUnavailableView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        ContentUnavailableView {
            Label(copy(
                "onboarding.documents-unavailable.title",
                fallback: "Documentos indisponíveis"
            ), systemImage: "lock.fill")
        } description: {
            Text(copy(
                "onboarding.documents-unavailable.message",
                fallback: "Não é possível concluir o onboarding sem os documentos oficiais atuais."
            ))
        }
        .accessibilityIdentifier("screen.onboarding.consent-unavailable")
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}

@MainActor
private struct OnboardingOperationMessage: View {
    let state: OnboardingOperationState
    @Environment(\.locale) private var locale

    var body: some View {
        if case .failed(let error) = state {
            Label(
                error.authMessage(
                    for: BodyFlowPresentationLanguage.resolve(locale)
                ),
                systemImage: "exclamationmark.circle.fill"
            )
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.color(.feedbackDestructive))
                .padding(BodyFlowSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .bodyFlowWash(.feedbackDestructive)
                .accessibilityIdentifier("onboarding.error")
        }
    }
}

@MainActor
private struct OnboardingValidationSummary: View {
    let issues: [OnboardingValidationIssue]
    @Environment(\.locale) private var locale

    var body: some View {
        if !issues.isEmpty {
            let language = BodyFlowPresentationLanguage.resolve(locale)
            let messages = issues.map { $0.message(for: language) }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(PremiumPresentationCopy.string(
                    "onboarding.validation.review",
                    locale: locale,
                    fallback: "Revise os campos indicados."
                )).fontWeight(.semibold)
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Text("• \(message)")
                }
            }
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.color(.feedbackDestructive))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                FormAccessibilityText.validationAnnouncement(
                    messages: messages,
                    language: language
                ) ?? ""
            )
        }
    }
}
