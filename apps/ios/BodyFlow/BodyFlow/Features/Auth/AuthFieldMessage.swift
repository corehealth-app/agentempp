import Foundation
import SwiftUI

enum PremiumPresentationCopy {
    static func string(
        _ key: String.LocalizationValue,
        locale: Locale,
        fallback: String
    ) -> String {
        (try? AppLocalization.string(
            key,
            for: BodyFlowPresentationLanguage.resolve(locale)
        )) ?? fallback
    }

    static func format(
        _ key: String.LocalizationValue,
        locale: Locale,
        fallback: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, locale: locale, fallback: fallback),
            locale: locale,
            arguments: arguments
        )
    }
}

extension AuthValidationIssue {
    var message: String {
        return switch self {
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

    func message(for language: SupportedAppLanguage) -> String {
        let key: String.LocalizationValue
        switch self {
        case .emailRequired: key = "auth.validation.email-required"
        case .emailMalformed: key = "auth.validation.email-malformed"
        case .passwordRequired: key = "auth.validation.password-required"
        case .passwordConfirmationRequired: key = "auth.validation.confirmation-required"
        case .passwordsDoNotMatch: key = "auth.validation.passwords-mismatch"
        }
        return (try? AppLocalization.string(key, for: language)) ?? message
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

    func authMessage(for language: SupportedAppLanguage) -> String {
        let key: String.LocalizationValue = switch self {
        case .invalidInput: "auth.error.invalid-input"
        case .invalidCredentials: "auth.error.invalid-credentials"
        case .confirmationRequired: "auth.error.confirmation-required"
        case .operationUnavailable: "auth.error.operation-unavailable"
        case .serviceUnavailable: "auth.error.service-unavailable"
        case .storageUnavailable: "auth.error.storage-unavailable"
        }
        return (try? AppLocalization.string(key, for: language)) ?? authMessage
    }
}

enum FormAccessibilityText {
    static func hint(for message: String?) -> String {
        guard let message else { return "" }
        return "Erro: \(message)"
    }

    static func validationAnnouncement(messages: [String]) -> String? {
        guard !messages.isEmpty else { return nil }
        return "Erros no formulário: " + messages.joined(separator: " ")
    }

    static func hint(for message: String?, language: SupportedAppLanguage) -> String {
        guard let message else { return "" }
        let format = (try? AppLocalization.string(
            "auth.accessibility.error-format",
            for: language
        )) ?? "Erro: %@"
        return String(format: format, locale: language.formattingLocale, message)
    }

    static func validationAnnouncement(
        messages: [String],
        language: SupportedAppLanguage
    ) -> String? {
        guard !messages.isEmpty else { return nil }
        let format = (try? AppLocalization.string(
            "auth.accessibility.errors-format",
            for: language
        )) ?? "Erros no formulário: %@"
        return String(
            format: format,
            locale: language.formattingLocale,
            messages.joined(separator: " ")
        )
    }
}

@MainActor
struct AuthFieldMessage: View {
    private enum Source {
        case issue(AuthValidationIssue)
        case error(AppPresentationError)
    }

    private let source: Source
    @Environment(\.locale) private var locale

    init(issue: AuthValidationIssue) {
        source = .issue(issue)
    }

    init(error: AppPresentationError) {
        source = .error(error)
    }

    var body: some View {
        BodyFlowStatusLine(message, kind: .error, font: BodyFlowTypography.callout)
    }

    private var message: String {
        let language = BodyFlowPresentationLanguage.resolve(locale)
        return switch source {
        case .issue(let issue): issue.message(for: language)
        case .error(let error): error.authMessage(for: language)
        }
    }
}

@MainActor
struct AuthScreenLayout<Content: View>: View {
    let titleKey: String.LocalizationValue
    let titleFallback: String
    let messageKey: String.LocalizationValue
    let messageFallback: String
    let messageOverride: String?
    let compact: Bool
    @ViewBuilder let content: Content
    @Environment(\.locale) private var locale
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion

    init(
        titleKey: String.LocalizationValue,
        titleFallback: String,
        messageKey: String.LocalizationValue,
        messageFallback: String,
        messageOverride: String? = nil,
        compact: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.titleKey = titleKey
        self.titleFallback = titleFallback
        self.messageKey = messageKey
        self.messageFallback = messageFallback
        self.messageOverride = messageOverride
        self.compact = compact
        self.content = content()
    }

    var body: some View {
        ZStack {
            BodyFlowColor.background.ignoresSafeArea()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: compact ? BodyFlowSpacing.md : BodyFlowSpacing.lg
                ) {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        if !compact {
                            BodyFlowBrandIdentityView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(BodyFlowMotion.stateTransition(reduceMotion: reduceMotion))
                        }

                        Text(PremiumPresentationCopy.string(
                            titleKey,
                            locale: locale,
                            fallback: titleFallback
                        ))
                        .font(BodyFlowTypography.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("auth.screen-title")

                        if !compact {
                            Text(messageOverride ?? PremiumPresentationCopy.string(
                                messageKey,
                                locale: locale,
                                fallback: messageFallback
                            ))
                                .font(BodyFlowTypography.body)
                                .foregroundStyle(BodyFlowColor.secondaryText)
                                .accessibilityIdentifier("auth.supporting-copy")
                                .transition(BodyFlowMotion.stateTransition(reduceMotion: reduceMotion))
                        }
                    }
                    .animation(
                        BodyFlowMotion.animation(.content, reduceMotion: reduceMotion),
                        value: compact
                    )

                    content
                }
                .padding(.horizontal, BodyFlowSpacing.lg)
                .padding(
                    .vertical,
                    compact ? BodyFlowSpacing.md : BodyFlowSpacing.xl
                )
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
                .bodyFlowWash(.feedbackDestructive)
                .accessibilityIdentifier("auth.error")
        }
    }
}

@MainActor
struct AuthValidationSummary: View {
    let issues: [AuthValidationIssue]
    @Environment(\.locale) private var locale

    var body: some View {
        if !issues.isEmpty {
            Text(PremiumPresentationCopy.string(
                "auth.validation.review",
                locale: locale,
                fallback: "Revise os campos indicados."
            ))
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.color(.feedbackDestructive))
                .accessibilityLabel(
                    FormAccessibilityText.validationAnnouncement(
                        messages: issues.map { $0.message(for: language) },
                        language: language
                    ) ?? ""
                )
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
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
