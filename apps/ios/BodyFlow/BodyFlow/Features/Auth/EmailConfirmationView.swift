import SwiftUI
import UIKit

@MainActor
struct EmailConfirmationView: View {
    let email: String
    let allowsDevelopmentConfirmation: Bool
    let model: AppFlowModel
    @State private var submissionTask: Task<Void, Never>?

    var body: some View {
        AuthScreenLayout(
            title: "Confirme seu e-mail",
            message: "Enviamos as orientações de confirmação para \(email). Confirme o e-mail antes de criar seu perfil."
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
                                    ? "Confirmando"
                                    : "Continuar no ambiente de teste"
                            )
                            Spacer()
                        }
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("auth.confirm-development")
                }

                Button {
                    Task { await model.showSignIn() }
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
                    argument: error.authMessage
                )
            }
            submissionTask = nil
        }
    }

    private func cancelSubmission() {
        submissionTask?.cancel()
        submissionTask = nil
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
