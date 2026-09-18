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
        captureError: BodyFlowCapabilityError?,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        switch state {
        case .unavailable:
            message = Self.copy("state.unavailable.title", language: language)
            action = nil
        case let .failed(_, error):
            message = Self.message(for: error, language: language)
            action = Self.action(for: error)
        case let .succeeded(receipt):
            message = Self.successMessage(for: receipt, language: language)
            action = nil
        case .idle, .submitting:
            if let captureError {
                message = Self.message(for: captureError, language: language)
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

    private static func message(
        for error: BodyFlowCapabilityError,
        language: SupportedAppLanguage
    ) -> String {
        error == .operationUnavailable
            ? copy("state.unavailable.title", language: language)
            : copy("registration.operation.failed", language: language)
    }

    private static func successMessage(
        for receipt: RegistrationMutationReceipt,
        language: SupportedAppLanguage
    ) -> String {
        switch receipt {
        case .propose: copy("registration.operation.proposed", language: language)
        case .edit: copy("registration.operation.edited", language: language)
        case .confirm: copy("registration.operation.confirmed", language: language)
        case .cancel: copy("registration.operation.cancelled", language: language)
        }
    }

    private static func copy(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        RegistrationCopy.string(key, language: language)
    }
}

struct RegistrationOperationSummary: View {
    let state: RegistrationMutationState
    let captureError: BodyFlowCapabilityError?
    let perform: @MainActor (RegistrationOperationAction) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let descriptor = RegistrationOperationSummaryDescriptor(
            state: state,
            captureError: captureError,
            language: language
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
                                    ? copy("registration.operation.new-proposal")
                                    : copy("state.retry")
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

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }

}
