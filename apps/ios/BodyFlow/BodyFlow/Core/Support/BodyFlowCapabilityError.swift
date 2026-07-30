enum BodyFlowCapabilityError: Error, Equatable, Sendable {
    case invalidIdempotencyKey
    case operationUnavailable
}
