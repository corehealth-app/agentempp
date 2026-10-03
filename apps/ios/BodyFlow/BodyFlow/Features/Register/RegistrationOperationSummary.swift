import SwiftUI

enum RegistrationOperationAction: Equatable, Sendable {
    case retry
    case newProposal
}

struct RegistrationOperationSummaryDescriptor: Equatable {
    let message: String?
    let action: RegistrationOperationAction?
    /// How the message reads: a confirmed operation, a recoverable failure,
    /// or a capability this build does not offer.
    let kind: BodyFlowStatusLine.Kind

    init(
        state: RegistrationMutationState,
        captureError: BodyFlowCapabilityError?,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        switch state {
        case .unavailable:
            message = Self.copy("state.unavailable.title", language: language)
            action = nil
            kind = .unavailable
        case let .failed(_, error):
            message = Self.message(for: error, language: language)
            action = Self.action(for: error)
            kind = error == .operationUnavailable ? .unavailable : .error
        case let .succeeded(receipt):
            message = Self.successMessage(for: receipt, language: language)
            action = nil
            kind = .success
        case .idle, .submitting:
            if let captureError {
                message = Self.message(for: captureError, language: language)
                action = Self.action(for: captureError)
                kind = captureError == .operationUnavailable ? .unavailable : .error
            } else {
                message = nil
                action = nil
                kind = .info
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
                    BodyFlowStatusLine(message, kind: descriptor.kind)
                    if let action = descriptor.action {
                        Button {
                            perform(action)
                        } label: {
                            Text(
                                action == .newProposal
                                    ? copy("registration.operation.new-proposal")
                                    : copy("state.retry")
                            )
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                        .accessibilityIdentifier(
                            action == .newProposal
                                ? "registration.mutation.new-proposal"
                                : "registration.mutation.retry"
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.operation.summary")
        // Result feedback for the patient's own submit; the message above is
        // always the primary channel.
        .bodyFlowResultFeedback(Self.feedback, trigger: descriptor.kind)
        // A confirmed registration earns a short burst in the energy color.
        .bodyFlowCelebration({ $0 == .success ? .energy : nil }, trigger: descriptor.kind)
    }

    /// Only the two terminal outcomes of a submit speak; idle and
    /// unavailable stay silent.
    private static func feedback(
        for kind: BodyFlowStatusLine.Kind
    ) -> BodyFlowHaptics.Result? {
        switch kind {
        case .success: .success
        case .error: .failure
        case .info, .warning, .pending, .empty, .unavailable: nil
        }
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }

}
