import SwiftUI
import UIKit

private enum OnboardingScrollAnchor: Hashable {
    case top
}

@MainActor
struct OnboardingContainerView: View {
    /// The widest the sign-up column gets; the command at the top keeps to
    /// the same column.
    private static let columnMaxWidth: CGFloat = 620

    let model: OnboardingFlowModel
    let photos: SignupBodyPhotoPresentationModel?

    init(model: OnboardingFlowModel, photos: SignupBodyPhotoPresentationModel? = nil) {
        self.model = model
        self.photos = photos
    }
    @State private var submissionTask: Task<Void, Never>?
    @State private var showsPhotoFlow = false
    @State private var photoFlowParentID: ObjectIdentifier?
    @Environment(\.locale) private var locale
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                BodyFlowColor.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Above the scrolling column, never inside it: in reach
                    // on arrival at every step after the first.
                    if model.canGoBack { topBackCommand }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                                BodyFlowBrandIdentityView()
                                if model.pendingProtocolWelcome == nil { progress }
                                OnboardingOperationMessage(state: model.operationState)
                                if model.operationState == .saving && isCheckingEligibility {
                                    BodyFlowStatusLine(copy("onboarding.objective.checking", fallback: "Conferindo os objetivos disponíveis…"), kind: .pending)
                                }
                                OnboardingValidationSummary(issues: model.validationIssues)
                                stepContent
                                    .transition(BodyFlowMotion.stateTransition(reduceMotion: reduceMotion))
                                    .animation(
                                        BodyFlowMotion.animation(.content, reduceMotion: reduceMotion),
                                        value: model.step
                                    )
                                commands
                            }
                            .padding(.horizontal, BodyFlowSpacing.lg)
                            .padding(.vertical, BodyFlowSpacing.lg)
                            .frame(maxWidth: Self.columnMaxWidth)
                            .frame(maxWidth: .infinity)
                            .id(OnboardingScrollAnchor.top)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollDismissesKeyboard(.interactively)
                        // One ScrollView serves every step: without this, the offset
                        // a long step leaves behind carries into the next one.
                        .onChange(of: model.pendingProtocolWelcome != nil) {
                            proxy.scrollTo(OnboardingScrollAnchor.top, anchor: .top)
                        }
                        .onChange(of: model.step) {
                            proxy.scrollTo(OnboardingScrollAnchor.top, anchor: .top)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showsPhotoFlow) {
                photoFlowDestination
            }
        }
        .task(id: model.step) {
            if model.step == .objective { await model.prepareObjectiveIfNeeded() }
        }
        .onChange(of: photos?.route) { _, route in
            if route == nil { closePhotoFlow() }
        }
        .onChange(of: photos.map { ObjectIdentifier($0) }) { _, _ in
            closePhotoFlow()
        }
        .onChange(of: model.step) { _, step in
            if step != .bodyData { closePhotoFlow() }
        }
        .onChange(of: showsPhotoFlow) { _, presented in
            if !presented, !showsPhotoFlow { photoFlowParentID = nil }
        }
        .onDisappear(perform: cancelSubmission)
        .onChange(of: scenePhase) { _, phase in
            keepDraftWhenLeaving(phase)
        }
    }

    @ViewBuilder
    private var photoFlowDestination: some View {
        if let photos, photoFlowParentID == ObjectIdentifier(photos) {
            let expectedParent = ObjectIdentifier(photos)
            SignupBodyPhotoFlowSurface(photos: photos,
                close: { closePhotoFlow(expectedParent: expectedParent) })
                // Surface owns explicit close and its caller cancellation.
                // Do not provide another navigation back command around it.
                .navigationBarBackButtonHidden(true)
        }
    }

    private func openPhotoFlow() {
        guard model.isActive, model.step == .bodyData,
              model.allowsDraftEditing, model.operationState != .saving,
              let photos, photos.isActive, photos.route != nil else { return }
        photoFlowParentID = ObjectIdentifier(photos)
        showsPhotoFlow = true
    }

    private func closePhotoFlow(expectedParent: ObjectIdentifier? = nil) {
        if let expectedParent, photoFlowParentID != expectedParent { return }
        // Confirmation keeps choice/photos proof. Navigation is independent
        // because a valid confirmed Parent can still expose route .result.
        showsPhotoFlow = false
        photoFlowParentID = nil
    }

    /// The person is leaving the app — another app, the camera, Settings, the
    /// lock screen — and the system may end it there. What was typed so far
    /// is kept on this iPhone first (package A4, 2026-10-11).
    private func keepDraftWhenLeaving(_ phase: ScenePhase) {
        guard phase != .active else { return }
        if phase == .background {
            // A number still being typed only reaches the draft when its
            // field stops being edited.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        Task { await model.keepDraftOnDevice() }
    }

    /// P-BACK (reported on 2026-10-10, on "Sua rotina": "Passei pra frente e
    /// ele não deixa voltar", with the top of the screen circled). The only
    /// way back was the last item of the scrolling column and the review had
    /// none. This one is fixed at the top; the one below "Continuar" stays.
    ///
    /// The gutter plus the button's own padding put the glyph on the
    /// column's leading edge (`sm` + `sm` = the column's `lg`).
    private var topBackCommand: some View {
        HStack(spacing: 0) {
            Button {
                Task { await model.back() }
            } label: {
                Label(verbatim: copy("onboarding.back", fallback: "Voltar"), symbol: .back)
            }
            .buttonStyle(BodyFlowButtonStyle(role: .tertiary, isCompact: true))
            .disabled(model.operationState == .saving)
            .accessibilityLabel(copy(
                "onboarding.back.previous-step",
                fallback: "Voltar para a etapa anterior"
            ))
            .accessibilityIdentifier("onboarding.back.top")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BodyFlowSpacing.sm)
        .frame(maxWidth: Self.columnMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var progress: some View {
        let position = (model.visibleSteps.firstIndex(of: model.step) ?? 0) + 1
        return VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(PremiumPresentationCopy.format(
                "onboarding.progress.format",
                locale: locale,
                fallback: "Etapa %lld de %lld",
                position,
                model.visibleSteps.count
            ))
                .font(BodyFlowTypography.callout)
                .fontWeight(.semibold)
            ProgressView(value: Double(position), total: Double(model.visibleSteps.count))
                .frame(height: BodyFlowSpacing.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.progress")
    }

    @ViewBuilder
    private var stepContent: some View {
        if let welcome = model.pendingProtocolWelcome {
            ProtocolMessageView(welcome: welcome, onContinue: model.finishProtocolWelcome)
        } else {
            switch model.stepPresentation {
            case .step(.welcome):
                WelcomeStepView(model: model)
            case .step(.bodyData):
                BodyDataStepView(model: model, photos: photos, openPhotos: openPhotoFlow)
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
    }

    private var commands: some View {
        VStack(spacing: BodyFlowSpacing.sm) {
            if model.step != .completion && model.pendingProtocolWelcome == nil {
                if model.stepPresentation != .developmentConsentUnavailable {
                    Button(action: submit) {
                        Text(continueTitle)
                    }
                    .buttonStyle(BodyFlowButtonStyle(
                        role: .primary,
                        isLoading: model.operationState == .saving
                    ))
                    .disabled(
                        (!model.allowsDraftEditing && !model.canRetryHealthAdmission) || model.operationState == .saving
                            || (model.step == .consent && !model.hasRequiredDevelopmentConsent)
                    )
                    .accessibilityIdentifier("onboarding.continue")
                }

                if model.step != model.visibleSteps.first {
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
                        .disabled(!model.allowsDraftEditing || model.operationState == .saving)
                        .accessibilityIdentifier("onboarding.back")
                }
            }
        }
    }

    private var isCheckingEligibility: Bool {
        !model.isReacceptance && (model.step == .consent || (model.step == .objective && !model.hasCurrentEligibilityDecision))
    }

    private var continueTitle: String {
        switch model.operationState {
        case .idle: copy("onboarding.continue", fallback: "Continuar")
        case .saving: isCheckingEligibility
            ? copy("onboarding.objective.checking", fallback: "Conferindo os objetivos disponíveis…")
            : copy("onboarding.saving", fallback: "Salvando")
        case .failed: model.step == .objective && !model.hasCurrentEligibilityDecision
            ? copy("onboarding.objective.retry", fallback: "Conferir novamente")
            : copy("onboarding.retry", fallback: "Tentar novamente")
        }
    }

    private func submit() {
        guard submissionTask == nil else { return }
        submissionTask = Task {
            if model.step == .objective && !model.hasCurrentEligibilityDecision {
                await model.prepareObjectiveIfNeeded()
            } else {
                await model.continueFromCurrentStep()
            }
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
        case .trainingFrequencyOutOfRange: "Informe de 0 a 7 treinos de musculação por semana."
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
            ), systemImage: BodyFlowSymbol.unavailable.systemName)
        } description: {
            Text(copy(
                "onboarding.documents-unavailable.message",
                fallback: "Não é possível concluir o cadastro sem os documentos oficiais atuais."
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
            BodyFlowStatusLine(
                error.authMessage(for: BodyFlowPresentationLanguage.resolve(locale)),
                kind: .error,
                font: BodyFlowTypography.callout
            )
                .padding(BodyFlowSpacing.md)
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
