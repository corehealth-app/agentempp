import SwiftUI

@MainActor
struct LegacyReconsentView: View {
    let model: LegacyReconsentModel
    let signOut: @MainActor () async -> Void

    var body: some View {
        ScrollView {
            LegacyReconsentContent(model: model, signOut: signOut)
                .padding(BodyFlowSpacing.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
        .background(BodyFlowColor.background)
        .environment(\.locale, Locale(identifier: model.presentation.locale))
        .accessibilityIdentifier("screen.onboarding.legacy-documents")
    }
}

/// The exact scrolling content is also hosted in native rendering tests.
@MainActor
struct LegacyReconsentContent: View {
    let model: LegacyReconsentModel
    let signOut: @MainActor () async -> Void
    @State private var submission: Task<Void, Never>?
    @State private var signingOut = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            BodyFlowBrandIdentityView()
            OnboardingStepHeader(titleKey: "onboarding.consent.title", titleFallback: "Documentos e confirmações",
                messageKey: "onboarding.legacy.message",
                messageFallback: "Revise os documentos atualizados para continuar. Seu cadastro e histórico serão preservados.")
            OnboardingLegalDocumentsView(documents: model.presentation.requirements.documents,
                selectedActions: model.selectedActions, allowsEditing: model.allowsEditing && !signingOut,
                recordedActions: Set(model.presentation.acceptedActions),
                onChange: { model.update($0, selected: $1) })
            if model.hasError {
                BodyFlowStatusLine(copy("onboarding.legacy.error", "Não foi possível confirmar agora. Tente novamente."), kind: .error)
                    .accessibilityIdentifier("onboarding.legacy.error")
            }
            if model.acknowledgement != nil {
                BodyFlowStatusLine(copy("onboarding.legacy.checking", "Conferindo seu acesso…"), kind: .pending)
            }
            Button {
                guard submission == nil else { return }
                submission = Task { await model.submit(); submission = nil }
            } label: {
                Text(model.pending == nil
                     ? copy("onboarding.legacy.continue", "Continuar")
                     : copy("onboarding.legacy.retry", "Tentar novamente"))
            }
            .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: model.isBusy))
            .disabled(!model.canSubmit || signingOut)
            .accessibilityIdentifier("onboarding.legacy.continue")
            Button {
                guard !signingOut else { return }
                signingOut = true
                Task { await signOut(); signingOut = false }
            } label: {
                Text(copy("onboarding.legacy.sign-out", "Sair da conta"))
            }
            .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            .disabled(model.isBusy || signingOut)
            .accessibilityIdentifier("onboarding.legacy.sign-out")
        }
        .onDisappear { submission?.cancel(); submission = nil }
    }

    private func copy(_ key: String.LocalizationValue, _ fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}
