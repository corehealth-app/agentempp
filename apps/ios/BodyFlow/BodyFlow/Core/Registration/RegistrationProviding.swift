protocol RegistrationProviding: Sendable {
    func propose(_ request: RegistrationProposalRequest) async throws
        -> RegistrationProposalResponse

    func edit(_ command: RegistrationEditCommand) async throws
        -> RegistrationProposalResponse

    func confirm(_ command: RegistrationIDCommand) async throws
        -> RegistrationConfirmationResponse

    func cancel(_ command: RegistrationIDCommand) async throws
        -> RegistrationCancellationResponse
}
