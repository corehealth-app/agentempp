enum BodyFlowCapabilityError: Error, Equatable, Sendable {
    case operationUnavailable
    case offline
    case serviceUnavailable
    case invalidInput
    case idempotencyConflict
    case registrationNotPending
    case registrationExpired
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
