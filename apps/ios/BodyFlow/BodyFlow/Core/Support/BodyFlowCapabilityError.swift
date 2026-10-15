enum BodyFlowCapabilityError: Error, Equatable, Sendable {
    case operationUnavailable
    case offline
    case serviceUnavailable
    case invalidInput
    case idempotencyConflict
    case registrationNotPending
    case registrationExpired
    case registrationRevisionConflict
    case registrationReviewRequired
    case registrationAuthorityStale
    /// `409 registration_already_confirmed`: the record of this proposal is
    /// already saved on the server. Not a failure to retry and not a reason
    /// to propose again; the registration models show it as confirmed.
    case registrationAlreadyConfirmed
    case routineTransitionInvalid
    case routineSnoozeInvalid
    case invalidIdempotencyKey
    case invalidContentContract
    case invalidContentCursor
    case unsupportedMarkdown
    case unsupportedCoachContract
    case contentNotFound
    case contentCoverNotFound
    case invalidContentCover
    case contentCoverTooLarge
    case subscriptionRequired
    case contentVersionChanged
    case idempotencyRequestInProgress
    case coachLocaleUnsupported
}
