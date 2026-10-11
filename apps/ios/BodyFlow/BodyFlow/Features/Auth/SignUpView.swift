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
    /// Which of the two passwords are shown as typed (the "eye").
    @State private var passwordVisibility = AuthPasswordVisibility()
    @FocusState private var focusedField: SignUpField?
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AuthScreenLayout(
            titleKey: "auth.sign-up.title",
            titleFallback: "Criar conta",
            messageKey: "auth.sign-up.message",
            messageFallback: "Cadastre um e-mail e uma senha para começar.",
            compact: focusedField != nil
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                AuthOperationMessage(state: model.authOperationState)
                AuthValidationSummary(issues: validationIssues)

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(copy("auth.common.email", fallback: "E-mail")).font(BodyFlowTypography.headline)
                    TextField(copy("auth.common.email-placeholder", fallback: "nome@exemplo.com"), text: $email)
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
                        .bodyFlowField()
                        .accessibilityLabel(copy("auth.common.email", fallback: "E-mail"))
                        .accessibilityHint(
                            accessibilityHint(
                                for: [.emailRequired, .emailMalformed]
                            )
                        )
                        .accessibilityIdentifier("auth.email")
                    fieldMessage(for: [.emailRequired, .emailMalformed])
                }

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(copy("auth.common.password", fallback: "Senha")).font(BodyFlowTypography.headline)
                    AuthPasswordField(
                        slot: .password,
                        title: copy("auth.common.password", fallback: "Senha"),
                        text: $password,
                        visibility: $passwordVisibility,
                        contentType: .newPassword,
                        submitLabel: SignUpKeyboardPolicy.presentation(for: .password)
                            .submitLabel.swiftUIValue,
                        focus: $focusedField,
                        focusValue: .password,
                        hint: accessibilityHint(for: [.passwordRequired]),
                        identifier: "auth.password",
                        onSubmit: { handleSubmit(from: .password) }
                    )
                    fieldMessage(for: [.passwordRequired])
                }

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(copy("auth.common.password-confirmation", fallback: "Confirmar senha")).font(BodyFlowTypography.headline)
                    AuthPasswordField(
                        slot: .confirmation,
                        title: copy("auth.common.password-confirmation", fallback: "Confirmar senha"),
                        text: $confirmation,
                        visibility: $passwordVisibility,
                        contentType: .newPassword,
                        submitLabel: SignUpKeyboardPolicy.presentation(for: .confirmation)
                            .submitLabel.swiftUIValue,
                        focus: $focusedField,
                        focusValue: .confirmation,
                        hint: accessibilityHint(
                            for: [
                                .passwordConfirmationRequired,
                                .passwordsDoNotMatch,
                            ]
                        ),
                        identifier: "auth.password-confirmation",
                        onSubmit: { handleSubmit(from: .confirmation) }
                    )
                    fieldMessage(for: [
                        .passwordConfirmationRequired,
                        .passwordsDoNotMatch,
                    ])
                }

                Button(action: submit) {
                    Text(copy(
                        isSubmitting ? "auth.sign-up.submitting" : "auth.sign-up.submit",
                        fallback: isSubmitting ? "Criando conta" : "Criar conta"
                    ))
                }
                .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: isSubmitting))
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.sign-up.submit")

                Button {
                    Task { await model.showSignIn() }
                } label: {
                    Text(copy("auth.sign-up.existing-account", fallback: "Já tenho uma conta"))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: BodyFlowSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(BodyFlowButtonStyle(role: .secondary))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.auth.sign-up")
        .onDisappear {
            cancelSubmission()
            passwordVisibility.hideAll()
        }
        // No password stays readable once the app leaves the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { passwordVisibility.hideAll() }
        }
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
            for: candidates.first(where: validationIssues.contains)?.message(for: language),
            language: language
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

        // Sending: the passwords are hidden again. Their text is untouched.
        passwordVisibility.hideAll()
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
            messages: validationIssues.map { $0.message(for: language) },
            language: language
        ) else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func announceOperationErrorIfNeeded() {
        guard case .failed(let error) = model.authOperationState else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: error.authMessage(for: language)
        )
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
