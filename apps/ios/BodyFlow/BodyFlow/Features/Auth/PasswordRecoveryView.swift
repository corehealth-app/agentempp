import SwiftUI
import UIKit

@MainActor
struct PasswordRecoveryView: View {
    let model: AppFlowModel
    @State private var email = ""
    @State private var validationIssues: [AuthValidationIssue] = []
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var emailIsFocused: Bool

    var body: some View {
        AuthScreenLayout(
            title: "Recuperar senha",
            message: "Informe seu e-mail para receber as orientações disponíveis."
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                AuthOperationMessage(state: model.authOperationState)
                AuthValidationSummary(issues: validationIssues)

                if model.authOperationState == .recoveryConfirmation {
                    Label(
                        "Se houver uma conta para este e-mail, enviaremos as instruções de recuperação.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .padding(BodyFlowSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        BodyFlowColor.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityIdentifier("auth.recovery.confirmation")
                } else {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        Text("E-mail").font(BodyFlowTypography.headline)
                        TextField("nome@exemplo.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .focused($emailIsFocused)
                            .onSubmit(submit)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("E-mail")
                            .accessibilityHint(accessibilityHint)
                            .accessibilityIdentifier("auth.email")

                        if let issue = validationIssues.first {
                            AuthFieldMessage(issue: issue)
                        }
                    }

                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .accessibilityHidden(true)
                            }
                            Text(isSubmitting ? "Enviando" : "Enviar instruções")
                            Spacer()
                        }
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("auth.recovery.submit")
                }

                Button {
                    model.showSignIn()
                } label: {
                    Text("Voltar para entrar")
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
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
        guard let issue = validationIssues.first else { return "" }
        return "Erro: \(issue.message)"
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
        UIAccessibility.post(
            notification: .announcement,
            argument: "Erros no formulário: "
                + validationIssues.map(\.message).joined(separator: " ")
        )
    }

    private func announceResult() {
        let message: String
        switch model.authOperationState {
        case .recoveryConfirmation:
            message = "Se houver uma conta para este e-mail, enviaremos as instruções de recuperação."
        case .failed(let error):
            message = error.authMessage
        case .idle, .submitting:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
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
