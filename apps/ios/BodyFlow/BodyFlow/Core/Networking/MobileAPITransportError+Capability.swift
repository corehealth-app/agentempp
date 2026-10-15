import Foundation

extension MobileAPITransportError {
    /// The capability state a screen shows for a transport failure. Codes
    /// follow docs/mobile/api-v1.md; anything unknown is a generic failure
    /// with retry, never a fabricated success.
    var capabilityError: BodyFlowCapabilityError {
        switch self {
        case .network, .timeout:
            return .offline
        case .unavailableConfiguration, .missingSession:
            return .operationUnavailable
        case .conflict(let code, _):
            switch code {
            case "registration_not_pending":
                return .registrationNotPending
            case "registration_already_confirmed":
                return .registrationAlreadyConfirmed
            case "registration_revision_conflict":
                return .registrationRevisionConflict
            case "registration_authority_stale":
                return .registrationAuthorityStale
            case "registration_revision_required", "registration_request_conflict",
                 "registration_revision_exhausted", "registration_capture_conflict":
                return .registrationReviewRequired
            case "idempotency_key_conflict":
                return .idempotencyConflict
            case "idempotency_request_in_progress":
                return .idempotencyRequestInProgress
            case "routine_transition_invalid":
                return .routineTransitionInvalid
            case "content_version_changed":
                return .contentVersionChanged
            case "coach_locale_unsupported":
                return .coachLocaleUnsupported
            default:
                return .serviceUnavailable
            }
        case .validation(let code, _):
            return code == "routine_snooze_invalid" ? .routineSnoozeInvalid : .invalidInput
        case .http(let status, let code, _):
            switch (status, code) {
            case (402, _):
                return .subscriptionRequired
            case (410, _):
                return .registrationExpired
            case (404, "content_not_found"):
                return .contentNotFound
            case (404, "content_cover_not_found"):
                return .contentCoverNotFound
            default:
                return .serviceUnavailable
            }
        default:
            return .serviceUnavailable
        }
    }
}
