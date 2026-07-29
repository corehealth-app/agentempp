import SwiftUI
import UIKit

@MainActor
struct OnboardingContainerView: View {
    let model: OnboardingFlowModel
    @State private var submissionTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                BodyFlowColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
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
            Text("Etapa \(position) de \(OnboardingStep.allCases.count)")
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
            DevelopmentConsentUnavailableView()
        }
    }

    private var commands: some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            if model.step != .completion {
                if model.stepPresentation != .developmentConsentUnavailable {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if model.operationState == .saving {
                                ProgressView().tint(.white).accessibilityHidden(true)
                            }
                            Text(continueTitle)
                            Spacer()
                        }
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.operationState == .saving
                            || (model.step == .consent && !model.hasRequiredDevelopmentConsent)
                    )
                    .accessibilityIdentifier("onboarding.continue")
                }

                if model.step != .welcome {
                    Button(action: model.back) {
                        Text("Voltar")
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                        .disabled(model.operationState == .saving)
                        .accessibilityIdentifier("onboarding.back")
                }
            }
        }
    }

    private var continueTitle: String {
        switch model.operationState {
        case .idle: "Continuar"
        case .saving: "Salvando"
        case .failed: "Tentar novamente"
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
        if let validationMessage = FormAccessibilityText.validationAnnouncement(
            messages: model.validationIssues.map(\.message)
        ) {
            message = validationMessage
        } else if case .failed(let error) = model.operationState {
            message = error.authMessage
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
        case .consentRequired: "Confirme os documentos de desenvolvimento."
        case .developmentConsentUnavailable: "Esta etapa não está disponível nesta versão."
        }
    }
}

@MainActor
private struct DevelopmentConsentUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Etapa indisponível", systemImage: "lock.fill")
        } description: {
            Text("Esta etapa ainda não está disponível nesta versão.")
        }
        .accessibilityIdentifier("screen.onboarding.consent-unavailable")
    }
}

@MainActor
private struct OnboardingOperationMessage: View {
    let state: OnboardingOperationState

    var body: some View {
        if case .failed(let error) = state {
            Label(error.authMessage, systemImage: "exclamationmark.circle.fill")
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.warning)
                .padding(BodyFlowSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BodyFlowColor.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("onboarding.error")
        }
    }
}

@MainActor
private struct OnboardingValidationSummary: View {
    let issues: [OnboardingValidationIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("Revise os campos indicados.").fontWeight(.semibold)
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text("• \(issue.message)")
                }
            }
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.warning)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Erros no formulário: " + issues.map(\.message).joined(separator: " "))
        }
    }
}
