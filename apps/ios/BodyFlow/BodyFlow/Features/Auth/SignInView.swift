import SwiftUI
import UIKit

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
    @Environment(\.locale) private var locale

    var body: some View {
        AuthScreenLayout(
            titleKey: "auth.sign-in.title",
            titleFallback: "Entrar",
            messageKey: "auth.sign-in.message",
            messageFallback: "Use seu e-mail e sua senha para continuar."
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                AuthOperationMessage(state: model.authOperationState)
                AuthValidationSummary(issues: validationIssues)

                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(copy("auth.common.email", fallback: "E-mail"))
                        .font(BodyFlowTypography.headline)
                    TextField(copy("auth.common.email-placeholder", fallback: "nome@exemplo.com"), text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
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
                    Text(copy("auth.common.password", fallback: "Senha"))
                        .font(BodyFlowTypography.headline)
                    SecureField(copy("auth.common.password", fallback: "Senha"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(submit)
                        .bodyFlowField()
                        .accessibilityLabel(copy("auth.common.password", fallback: "Senha"))
                        .accessibilityHint(
                            accessibilityHint(for: [.passwordRequired])
                        )
                        .accessibilityIdentifier("auth.password")
                    fieldMessage(for: [.passwordRequired])
                }

                Button(action: submit) {
                    Text(copy(
                        isSubmitting ? "auth.sign-in.submitting" : "auth.sign-in.submit",
                        fallback: isSubmitting ? "Entrando" : "Entrar"
                    ))
                }
                .buttonStyle(BodyFlowButtonStyle(role: .primary, isLoading: isSubmitting))
                .disabled(isSubmitting)
                .accessibilityIdentifier("auth.sign-in.submit")

                VStack(spacing: BodyFlowSpacing.xs) {
                    Button {
                        Task { await model.showSignUp() }
                    } label: {
                        Text(copy("auth.sign-in.create-account", fallback: "Criar conta"))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .accessibilityIdentifier("auth.open-sign-up")

                    Button {
                        Task { await model.showPasswordRecovery() }
                    } label: {
                        Text(copy("auth.sign-in.recovery", fallback: "Esqueci minha senha"))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
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
        validationIssues = AuthInputValidator.signIn(
            email: email,
            password: password
        )
        guard validationIssues.isEmpty else {
            announceValidationIssues()
            return
        }

        focusedField = nil
        submissionTask = Task {
            await model.signIn(email: email, password: password)
            announceOperationErrorIfNeeded()
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
