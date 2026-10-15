protocol RegistrationProviding: Sendable {
    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws
        -> RegistrationProposalResponse

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws
        -> RegistrationProposalResponse

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws
        -> RegistrationConfirmationResponse

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws
        -> RegistrationCancellationResponse
}

/// Reads the current owned projection without retrying a mutation.
protocol WorkoutRegistrationReading: Sendable {
    func loadWorkoutRegistration(id: String) async throws -> RegistrationProposalResponse
}
