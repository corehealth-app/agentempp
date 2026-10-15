import SwiftUI

enum RegistrationOperationAction: Equatable, Sendable {
    case retry
    case newProposal
    case reviewCurrent

    var titleKey: String.LocalizationValue {
        switch self {
        case .retry: "state.retry"
        case .newProposal: "registration.operation.new-proposal"
        case .reviewCurrent: "registration.operation.review-current"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .retry: "registration.mutation.retry"
        case .newProposal: "registration.mutation.new-proposal"
        case .reviewCurrent: "registration.mutation.review-current"
        }
    }
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
        case let .failed(attempt, error):
            message = Self.message(for: error, language: language)
            action = Self.action(for: error, registrationID: attempt.registrationID)
            kind = error == .operationUnavailable ? .unavailable : .error
        case let .succeeded(receipt):
            message = Self.successMessage(for: receipt, language: language)
            if case let .workoutCurrent(response) = receipt,
               ["cancelled", "expired"].contains(response.data.status) {
                action = .newProposal
            } else {
                action = nil
            }
            kind = Self.kind(for: receipt)
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

    /// A message that asks something of the patient — try again, or make a
    /// new proposal — must be seen: the sheet brings it into view by itself.
    /// A result that asks nothing (a success, an unavailable capability)
    /// never moves the sheet.
    ///
    /// > RC U1B-L4 — a FAILURE that offers no action (the operation is not
    /// > available in this version, or the record was already saved) is not
    /// > brought into view either: after "Calcular refeição" its line stays
    /// > below the review that came back from the top. Read by the review of
    /// > 2026-10-11, not reproduced: no fixture ends a calculation that way
    /// > (pendência da audit 2026-10-10).
    var asksToBeSeen: Bool {
        message != nil && action != nil
    }

    private static func action(
        for error: BodyFlowCapabilityError,
        registrationID: String? = nil
    ) -> RegistrationOperationAction? {
        switch error {
        // An already saved record is neither retried nor proposed again.
        case .operationUnavailable, .registrationAlreadyConfirmed:
            nil
        case .registrationExpired, .registrationNotPending:
            .newProposal
        case .registrationRevisionConflict, .registrationReviewRequired:
            registrationID == nil ? .newProposal : .reviewCurrent
        case .registrationAuthorityStale:
            .newProposal
        default:
            .retry
        }
    }

    private static func message(
        for error: BodyFlowCapabilityError,
        language: SupportedAppLanguage
    ) -> String {
        switch error {
        case .operationUnavailable: copy("state.unavailable.title", language: language)
        case .registrationRevisionConflict: copy("registration.operation.revision-conflict", language: language)
        case .registrationReviewRequired: copy("registration.operation.review-required", language: language)
        case .registrationAuthorityStale: copy("registration.operation.authority-stale", language: language)
        default: copy("registration.operation.failed", language: language)
        }
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
        // The record is saved as it was; the edit or the cancellation the
        // patient just asked for did not happen, and the message says so.
        case .alreadyConfirmed:
            copy("registration.operation.already-confirmed", language: language)
        case let .workoutCurrent(response):
            switch response.data.status {
            case "pending": copy("registration.operation.current-pending", language: language)
            case "confirmed": copy("registration.operation.current-confirmed", language: language)
            case "cancelled": copy("registration.operation.current-cancelled", language: language)
            default: copy("registration.operation.current-expired", language: language)
            }
        }
    }

    /// An already saved record is not this operation's success: the patient
    /// asked for a change that was not applied. It reads as a warning, which
    /// neither celebrates nor plays the success haptic.
    private static func kind(
        for receipt: RegistrationMutationReceipt
    ) -> BodyFlowStatusLine.Kind {
        switch receipt {
        case .alreadyConfirmed: .warning
        case let .workoutCurrent(response): response.data.status == "pending" ? .info : .warning
        case .propose, .edit, .confirm, .cancel: .success
        }
    }

    /// Only the two terminal outcomes of a submit speak; idle, a warning and
    /// unavailable stay silent.
    static func feedback(
        for kind: BodyFlowStatusLine.Kind
    ) -> BodyFlowHaptics.Result? {
        switch kind {
        case .success: .success
        case .error: .failure
        case .info, .warning, .pending, .empty, .unavailable: nil
        }
    }

    /// A confirmed registration earns a short burst in the energy color;
    /// nothing else does.
    static func celebration(
        for kind: BodyFlowStatusLine.Kind
    ) -> BodyFlowDomain? {
        kind == .success ? .energy : nil
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
    var isWorking = false
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
                            Text(copy(action.titleKey))
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                        .disabled(isWorking)
                        .accessibilityIdentifier(action.accessibilityIdentifier)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.operation.summary")
        // Result feedback for the patient's own submit; the message above is
        // always the primary channel.
        .bodyFlowResultFeedback(
            RegistrationOperationSummaryDescriptor.feedback,
            trigger: descriptor.kind
        )
        .bodyFlowCelebration(
            RegistrationOperationSummaryDescriptor.celebration,
            trigger: descriptor.kind
        )
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }

}
