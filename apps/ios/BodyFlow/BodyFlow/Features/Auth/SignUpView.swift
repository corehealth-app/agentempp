import SwiftUI

@MainActor
struct SignUpView: View {
    private enum Field: Hashable {
        case email
        case password
        case confirmation
    }

    let model: AppFlowModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validationIssues: [AuthValidationIssue] = []
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    var body: some View {
        AuthScreenLayout(
            title: "Criar conta",
            message: "Cadastre um e-mail e uma senha para começar."
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                AuthOperationMessage(state: model.authOperationState)
                AuthValidationSummary(issues: validationIssues)

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("E-mail").font(BodyFlowTypography.headline)
                    TextField("nome@exemplo.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.email")
                    fieldMessage(for: [.emailRequired, .emailMalformed])
                }

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("Senha").font(BodyFlowTypography.headline)
                    SecureField("Senha", text: $password)
                        .textContentType(.newPassword)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .password)
                        .onSubmit { focusedField = .confirmation }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.password")
                    fieldMessage(for: [.passwordRequired])
                }

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("Confirmar senha").font(BodyFlowTypography.headline)
                    SecureField("Confirmar senha", text: $confirmation)
                        .textContentType(.newPassword)
                        .submitLabel(.join)
                        .focused($focusedField, equals: .confirmation)
                        .onSubmit(submit)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.password-confirmation")
                    fieldMessage(for: [
                        .passwordConfirmationRequired,
                        .passwordsDoNotMatch,
                    ])
                }

                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .accessibilityHidden(true)
                        }
                        Text(isSubmitting ? "Criando conta" : "Criar conta")
                        Spacer()
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.sign-up.submit")

                Button("Já tenho uma conta") {
                    model.showSignIn()
                }
                .frame(maxWidth: .infinity, minHeight: BodyFlowSpacing.minimumTapTarget)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.auth.sign-up")
        .onDisappear(perform: cancelSubmission)
    }

    private var isSubmitting: Bool {
        model.authOperationState == .submitting
    }

    @ViewBuilder
    private func fieldMessage(
        for candidates: [AuthValidationIssue]
    ) -> some View {
        if let issue = candidates.first(where: { validationIssues.contains($0) }) {
            AuthFieldMessage(issue: issue)
        }
    }

    private func submit() {
        guard submissionTask == nil else { return }
        validationIssues = AuthInputValidator.signUp(
            email: email,
            password: password,
            confirmation: confirmation
        )
        guard validationIssues.isEmpty else { return }

        focusedField = nil
        submissionTask = Task {
            await model.signUp(email: email, password: password)
            submissionTask = nil
        }
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
    }
}

#if DEBUG
#Preview("Criar conta · Normal") {
    SignUpView(model: .authPreview(state: .signedOut(.signUp)))
}

#Preview("Criar conta · Loading") {
    SignUpView(model: .authPreview(
        state: .signedOut(.signUp),
        operationState: .submitting
    ))
}

#Preview("Criar conta · Erro recuperável") {
    SignUpView(model: .authPreview(
        state: .signedOut(.signUp),
        operationState: .failed(.serviceUnavailable)
    ))
}
#endif
