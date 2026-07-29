import SwiftUI
import UIKit

enum SignUpField: Hashable, Sendable {
    case email
    case password
    case confirmation
}

enum SignUpSubmitLabel: Equatable, Sendable {
    case next
    case done

    var swiftUIValue: SubmitLabel {
        switch self {
        case .next: .next
        case .done: .done
        }
    }
}

enum SignUpKeyboardAction: Equatable, Sendable {
    case focus(SignUpField)
    case submit
}

struct SignUpKeyboardPresentation: Equatable, Sendable {
    let submitLabel: SignUpSubmitLabel
    let action: SignUpKeyboardAction
}

enum SignUpKeyboardPolicy {
    static var fields: [SignUpField] {
        [.email, .password, .confirmation]
    }

    static func presentation(
        for field: SignUpField
    ) -> SignUpKeyboardPresentation {
        switch field {
        case .email:
            SignUpKeyboardPresentation(
                submitLabel: .next,
                action: .focus(.password)
            )
        case .password:
            SignUpKeyboardPresentation(
                submitLabel: .next,
                action: .focus(.confirmation)
            )
        case .confirmation:
            SignUpKeyboardPresentation(
                submitLabel: .done,
                action: .submit
            )
        }
    }
}

@MainActor
struct SignUpView: View {
    let model: AppFlowModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validationIssues: [AuthValidationIssue] = []
    @State private var submissionTask: Task<Void, Never>?
    @FocusState private var focusedField: SignUpField?

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
                        .submitLabel(
                            SignUpKeyboardPolicy.presentation(for: .email)
                                .submitLabel.swiftUIValue
                        )
                        .focused($focusedField, equals: .email)
                        .onSubmit { handleSubmit(from: .email) }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("E-mail")
                        .accessibilityHint(
                            accessibilityHint(
                                for: [.emailRequired, .emailMalformed]
                            )
                        )
                        .accessibilityIdentifier("auth.email")
                    fieldMessage(for: [.emailRequired, .emailMalformed])
                }

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("Senha").font(BodyFlowTypography.headline)
                    SecureField("Senha", text: $password)
                        .textContentType(.newPassword)
                        .submitLabel(
                            SignUpKeyboardPolicy.presentation(for: .password)
                                .submitLabel.swiftUIValue
                        )
                        .focused($focusedField, equals: .password)
                        .onSubmit { handleSubmit(from: .password) }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Senha")
                        .accessibilityHint(
                            accessibilityHint(for: [.passwordRequired])
                        )
                        .accessibilityIdentifier("auth.password")
                    fieldMessage(for: [.passwordRequired])
                }

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("Confirmar senha").font(BodyFlowTypography.headline)
                    SecureField("Confirmar senha", text: $confirmation)
                        .textContentType(.newPassword)
                        .submitLabel(
                            SignUpKeyboardPolicy.presentation(for: .confirmation)
                                .submitLabel.swiftUIValue
                        )
                        .focused($focusedField, equals: .confirmation)
                        .onSubmit { handleSubmit(from: .confirmation) }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Confirmar senha")
                        .accessibilityHint(
                            accessibilityHint(
                                for: [
                                    .passwordConfirmationRequired,
                                    .passwordsDoNotMatch,
                                ]
                            )
                        )
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

                Button {
                    Task { await model.showSignIn() }
                } label: {
                    Text("Já tenho uma conta")
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
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

    private func accessibilityHint(
        for candidates: [AuthValidationIssue]
    ) -> String {
        FormAccessibilityText.hint(
            for: candidates.first(where: validationIssues.contains)?.message
        )
    }

    private func submit() {
        guard submissionTask == nil else { return }
        validationIssues = AuthInputValidator.signUp(
            email: email,
            password: password,
            confirmation: confirmation
        )
        guard validationIssues.isEmpty else {
            announceValidationIssues()
            return
        }

        focusedField = nil
        submissionTask = Task {
            await model.signUp(email: email, password: password)
            announceOperationErrorIfNeeded()
            submissionTask = nil
        }
    }

    private func handleSubmit(from field: SignUpField) {
        switch SignUpKeyboardPolicy.presentation(for: field).action {
        case .focus(let destination):
            focusedField = destination
        case .submit:
            submit()
        }
    }

    private func announceValidationIssues() {
        guard let message = FormAccessibilityText.validationAnnouncement(
            messages: validationIssues.map(\.message)
        ) else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func announceOperationErrorIfNeeded() {
        guard case .failed(let error) = model.authOperationState else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: error.authMessage
        )
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
