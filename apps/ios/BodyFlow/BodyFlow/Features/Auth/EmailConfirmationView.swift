import SwiftUI
import UIKit

@MainActor
struct EmailConfirmationView: View {
    let email: String
    let allowsDevelopmentConfirmation: Bool
    let model: AppFlowModel
    @State private var submissionTask: Task<Void, Never>?
    @Environment(\.locale) private var locale

    var body: some View {
        AuthScreenLayout(
            titleKey: "auth.confirmation.title",
            titleFallback: "Confirme seu e-mail",
            messageKey: "auth.confirmation.message-format",
            messageFallback: confirmationMessage,
            messageOverride: confirmationMessage
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                AuthOperationMessage(state: model.authOperationState)

                if allowsDevelopmentConfirmation {
                    Button(action: confirmForDevelopment) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .accessibilityHidden(true)
                            }
                            Text(
                                isSubmitting
                                    ? copy("auth.confirmation.submitting", fallback: "Confirmando")
                                    : copy("auth.confirmation.development", fallback: "Continuar no ambiente de teste")
                            )
                            Spacer()
                        }
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("auth.confirm-development")
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
        .accessibilityIdentifier("screen.auth.email-confirmation")
        .onDisappear(perform: cancelSubmission)
    }

    private var isSubmitting: Bool {
        model.authOperationState == .submitting
    }

    private func confirmForDevelopment() {
        guard submissionTask == nil else { return }
        submissionTask = Task {
            await model.confirmEmailForDevelopment()
            if case .failed(let error) = model.authOperationState {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: error.authMessage(for: language)
                )
            }
            submissionTask = nil
        }
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var confirmationMessage: String {
        PremiumPresentationCopy.format(
            "auth.confirmation.message-format",
            locale: locale,
            fallback: "Enviamos as orientações de confirmação para %@. Confirme o e-mail antes de criar seu perfil.",
            email
        )
    }

    private func copy(_ key: String.LocalizationValue, fallback: String) -> String {
        PremiumPresentationCopy.string(key, locale: locale, fallback: fallback)
    }
}

#if DEBUG
#Preview("Confirmação · Normal") {
    EmailConfirmationView(
        email: "person@example.invalid",
        allowsDevelopmentConfirmation: true,
        model: .authPreview(
            state: .awaitingEmailConfirmation(
                email: "person@example.invalid"
            )
        )
    )
}

#Preview("Confirmação · Loading") {
    EmailConfirmationView(
        email: "person@example.invalid",
        allowsDevelopmentConfirmation: true,
        model: .authPreview(
            state: .awaitingEmailConfirmation(
                email: "person@example.invalid"
            ),
            operationState: .submitting
        )
    )
}

#Preview("Confirmação · Erro recuperável") {
    EmailConfirmationView(
        email: "person@example.invalid",
        allowsDevelopmentConfirmation: true,
        model: .authPreview(
            state: .awaitingEmailConfirmation(
                email: "person@example.invalid"
            ),
            operationState: .failed(.serviceUnavailable)
        )
    )
}
#endif
