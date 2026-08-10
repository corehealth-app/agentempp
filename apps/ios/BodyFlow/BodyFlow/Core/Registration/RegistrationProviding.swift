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
