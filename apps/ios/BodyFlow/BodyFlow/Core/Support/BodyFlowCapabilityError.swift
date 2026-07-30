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
}
