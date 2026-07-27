import SwiftUI

@MainActor
struct SignInView: View {
    private enum Field: Hashable {
        case email
        case password
    }

    let model: AppFlowModel
    @State private var email = ""
    @State private var password = ""
    @State private var validationIssues: [AuthValidationIssue] = []
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    var body: some View {
        AuthScreenLayout(
            title: "Entrar",
            message: "Use seu e-mail e sua senha para continuar."
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                AuthOperationMessage(state: model.authOperationState)
                AuthValidationSummary(issues: validationIssues)

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("E-mail")
                        .font(BodyFlowTypography.headline)
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
                    Text("Senha")
                        .font(BodyFlowTypography.headline)
                    SecureField("Senha", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("auth.password")
                    fieldMessage(for: [.passwordRequired])
                }

                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .accessibilityHidden(true)
                        }
                        Text(isSubmitting ? "Entrando" : "Entrar")
                        Spacer()
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.sign-in.submit")

                VStack(spacing: BodyFlowSpacing.xs) {
                    Button("Criar conta") {
                        model.showSignUp()
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityIdentifier("auth.open-sign-up")

                    Button("Esqueci minha senha") {
                        model.showPasswordRecovery()
                    }
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    .accessibilityIdentifier("auth.open-recovery")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.auth.sign-in")
        .onDisappear(perform: cancelSubmission)
    }

    private var isSubmitting: Bool {
        model.authOperationState == .submitting
    }

    @ViewBuilder
    private func fieldMessage(
        for candidates: [AuthValidationIssue]
    ) -> some View {
        if let issue = candidates.first(where: validationIssues.contains) {
            AuthFieldMessage(issue: issue)
        }
    }

    private func submit() {
        guard submissionTask == nil else { return }
        validationIssues = AuthInputValidator.signIn(
            email: email,
            password: password
        )
        guard validationIssues.isEmpty else { return }

        focusedField = nil
        submissionTask = Task {
            await model.signIn(email: email, password: password)
            submissionTask = nil
        }
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
    }
}

#if DEBUG
#Preview("Entrar · Normal") {
    SignInView(model: .authPreview(state: .signedOut(.signIn)))
}

#Preview("Entrar · Loading") {
    SignInView(model: .authPreview(
        state: .signedOut(.signIn),
        operationState: .submitting
    ))
}

#Preview("Entrar · Erro recuperável") {
    SignInView(model: .authPreview(
        state: .signedOut(.signIn),
        operationState: .failed(.serviceUnavailable)
    ))
}
#endif
