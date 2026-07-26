enum CoachPersonaRepositoryError: Error, Equatable, Sendable {
    case storageUnavailable
    case serviceUnavailable
}

protocol CoachPersonaRepository: Sendable {
    func selectedPersona(for userID: String) async throws -> CoachPersona?
    func setPersona(_ persona: CoachPersona, for userID: String) async throws
}
