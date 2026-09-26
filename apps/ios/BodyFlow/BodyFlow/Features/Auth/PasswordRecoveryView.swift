import SwiftUI
import UIKit

@MainActor
struct PasswordRecoveryView: View {
    let model: AppFlowModel
    @State private var email = ""
    @State private var validationIssues: [AuthValidationIssue] = []
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var emailIsFocused: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        AuthScreenLayout(
            titleKey: "auth.recovery.title",
            titleFallback: "Recuperar senha",
            messageKey: "auth.recovery.message",
            messageFallback: "Informe seu e-mail para receber as orientações disponíveis."
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                AuthOperationMessage(state: model.authOperationState)
                AuthValidationSummary(issues: validationIssues)

                if model.authOperationState == .recoveryConfirmation {
                    BodyFlowStatusLine(
                        copy("auth.recovery.confirmation", fallback: "Se houver uma conta para este e-mail, enviaremos as instruções de recuperação."),
                        kind: .success,
                        font: BodyFlowTypography.body
                    )
                    .padding(BodyFlowSpacing.md)
                    .bodyFlowWash(.brandPrimary)
                    .accessibilityIdentifier("auth.recovery.confirmation")
                } else {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        Text(copy("auth.common.email", fallback: "E-mail")).font(BodyFlowTypography.headline)
                        TextField(copy("auth.common.email-placeholder", fallback: "nome@exemplo.com"), text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .focused($emailIsFocused)
                            .onSubmit(submit)
                            .bodyFlowField()
                            .accessibilityLabel(copy("auth.common.email", fallback: "E-mail"))
                            .accessibilityHint(accessibilityHint)
                            .accessibilityIdentifier("auth.email")

                        if let issue = validationIssues.first {
                            AuthFieldMessage(issue: issue)
                        }
                    }

                    Button(action: submit) {
                        Text(copy(
                            isSubmitting ? "auth.recovery.submitting" : "auth.recovery.submit",
                            fallback: isSubmitting ? "Enviando" : "Enviar instruções"
                        ))
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: isSubmitting))
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("auth.recovery.submit")
                }

                Button {
                    Task { await model.showSignIn() }
                } label: {
                    Text(copy("auth.common.back-to-sign-in", fallback: "Voltar para entrar"))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                .accessibilityIdentifier("auth.back-to-sign-in")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.auth.password-recovery")
        .onDisappear(perform: cancelSubmission)
    }

    private var isSubmitting: Bool {
        model.authOperationState == .submitting
    }

    private var accessibilityHint: String {
        FormAccessibilityText.hint(
            for: validationIssues.first?.message(for: language),
            language: language
        )
    }

    private func submit() {
        guard submissionTask == nil else { return }
        validationIssues = AuthInputValidator.recovery(email: email)
        guard validationIssues.isEmpty else {
            announceValidationIssues()
            return
        }

        emailIsFocused = false
        submissionTask = Task {
            await model.requestPasswordRecovery(email: email)
            announceResult()
            submissionTask = nil
        }
    }

    private func announceValidationIssues() {
        guard let message = FormAccessibilityText.validationAnnouncement(
            messages: validationIssues.map { $0.message(for: language) },
            language: language
        ) else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func announceResult() {
        let message: String
        switch model.authOperationState {
        case .recoveryConfirmation:
            message = copy("auth.recovery.confirmation", fallback: "Se houver uma conta para este e-mail, enviaremos as instruções de recuperação.")
        case .failed(let error):
            message = error.authMessage(for: language)
        case .idle, .submitting:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}

#if DEBUG
#Preview("Recuperação · Normal") {
    PasswordRecoveryView(
        model: .authPreview(state: .signedOut(.passwordRecovery))
    )
}

#Preview("Recuperação · Loading") {
    PasswordRecoveryView(
        model: .authPreview(
            state: .signedOut(.passwordRecovery),
            operationState: .submitting
        )
    )
}

#Preview("Recuperação · Erro recuperável") {
    PasswordRecoveryView(
        model: .authPreview(
            state: .signedOut(.passwordRecovery),
            operationState: .failed(.serviceUnavailable)
        )
    )
}

#Preview("Recuperação · Confirmação") {
    PasswordRecoveryView(
        model: .authPreview(
            state: .signedOut(.passwordRecovery),
            operationState: .recoveryConfirmation
        )
    )
}
#endif
