import SwiftUI

enum RegistrationOperationAction: Equatable, Sendable {
    case retry
    case newProposal
}

struct RegistrationOperationSummaryDescriptor: Equatable {
    let message: String?
    let action: RegistrationOperationAction?

    init(
        state: RegistrationMutationState,
        captureError: BodyFlowCapabilityError?
    ) {
        switch state {
        case .unavailable:
            message = "Indisponível nesta versão"
            action = nil
        case let .failed(_, error):
            message = Self.message(for: error)
            action = Self.action(for: error)
        case let .succeeded(receipt):
            message = Self.successMessage(for: receipt)
            action = nil
        case .idle, .submitting:
            if let captureError {
                message = Self.message(for: captureError)
                action = Self.action(for: captureError)
            } else {
                message = nil
                action = nil
            }
        }
    }

    private static func action(
        for error: BodyFlowCapabilityError
    ) -> RegistrationOperationAction? {
        switch error {
        case .operationUnavailable:
            nil
        case .registrationExpired, .registrationNotPending:
            .newProposal
        default:
            .retry
        }
    }

    private static func message(for error: BodyFlowCapabilityError) -> String {
        error == .operationUnavailable
            ? "Indisponível nesta versão"
            : "Não foi possível concluir. Tente novamente."
    }

    private static func successMessage(
        for receipt: RegistrationMutationReceipt
    ) -> String {
        switch receipt {
        case .propose: "Proposta criada. Revise antes de confirmar."
        case .edit: "Proposta atualizada. Revise antes de confirmar."
        case .confirm: "Registro confirmado."
        case .cancel: "Proposta cancelada."
        }
    }
}

struct RegistrationOperationSummary: View {
    let state: RegistrationMutationState
    let captureError: BodyFlowCapabilityError?
    let perform: @MainActor (RegistrationOperationAction) -> Void

    var body: some View {
        let descriptor = RegistrationOperationSummaryDescriptor(
            state: state,
            captureError: captureError
        )
        Group {
            if let message = descriptor.message {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(message)
                    if let action = descriptor.action {
                        Button {
                            perform(action)
                        } label: {
                            Text(
                                action == .newProposal
                                    ? "Criar nova proposta"
                                    : "Tentar novamente"
                            )
                            .frame(
                                minHeight: BodyFlowSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(
                            action == .newProposal
                                ? "registration.mutation.new-proposal"
                                : "registration.mutation.retry"
                        )
                    }
                }
            }
        }
        .font(BodyFlowTypography.callout)
        .foregroundStyle(BodyFlowColor.secondaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.operation.summary")
    }

}
