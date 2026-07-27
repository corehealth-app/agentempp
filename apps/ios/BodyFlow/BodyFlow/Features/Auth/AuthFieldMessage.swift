import SwiftUI

extension AuthValidationIssue {
    var message: String {
        switch self {
        case .emailRequired:
            "Informe seu e-mail."
        case .emailMalformed:
            "Informe um e-mail válido."
        case .passwordRequired:
            "Informe sua senha."
        case .passwordConfirmationRequired:
            "Confirme sua senha."
        case .passwordsDoNotMatch:
            "As senhas não coincidem."
        }
    }
}

extension AppPresentationError {
    var authMessage: String {
        switch self {
        case .invalidInput:
            "Revise os dados informados."
        case .invalidCredentials:
            "E-mail ou senha inválidos."
        case .confirmationRequired:
            "Confirme seu e-mail antes de continuar."
        case .operationUnavailable:
            "Esta operação não está disponível agora."
        case .serviceUnavailable:
            "O serviço está temporariamente indisponível. Tente novamente."
        case .storageUnavailable:
            "Não foi possível acessar os dados locais. Tente novamente."
        }
    }
}

@MainActor
struct AuthFieldMessage: View {
    let message: String

    init(issue: AuthValidationIssue) {
        message = issue.message
    }

    init(error: AppPresentationError) {
        message = error.authMessage
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(BodyFlowTypography.callout)
            .foregroundStyle(BodyFlowColor.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

@MainActor
struct AuthScreenLayout<Content: View>: View {
    let title: String
    let message: String
    @ViewBuilder let content: Content

    init(
        title: String,
        message: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.message = message
        self.content = content()
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        Text(title)
                            .font(BodyFlowTypography.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(BodyFlowColor.primaryText)

                        Text(message)
                            .font(BodyFlowTypography.body)
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }

                    content
                }
                .padding(.horizontal, BodyFlowSpacing.lg)
                .padding(.vertical, BodyFlowSpacing.xl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

@MainActor
struct AuthOperationMessage: View {
    let state: AuthOperationState

    var body: some View {
        if case .failed(let error) = state {
            AuthFieldMessage(error: error)
                .padding(BodyFlowSpacing.md)
                .background(
                    BodyFlowColor.warning.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityIdentifier("auth.error")
        }
    }
}

@MainActor
struct AuthValidationSummary: View {
    let issues: [AuthValidationIssue]

    var body: some View {
        if !issues.isEmpty {
            Text("Revise os campos indicados.")
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.warning)
                .accessibilityLabel(
                    "Erros no formulário: "
                        + issues.map(\.message).joined(separator: " ")
                )
        }
    }
}

extension AppFlowModel {
    #if DEBUG
    @MainActor
    static func authPreview(
        state: AppFlowState,
        operationState: AuthOperationState = .idle
    ) -> AppFlowModel {
        let dependencies = AppDependencies.scaffold()
        return AppFlowModel(
            authentication: dependencies.authentication,
            onboarding: dependencies.onboarding,
            persona: dependencies.coachPersona,
            telemetry: dependencies.telemetry,
            initialState: state,
            initialAuthOperationState: operationState
        )
    }
    #endif
}
