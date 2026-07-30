enum MealDetectionInput: Hashable, Sendable {
    case text(String)
    case photoSample(label: String)
    case audioSample(label: String)
}

protocol MealDetectionProviding: Sendable {
    func detect(_ input: MealDetectionInput) async throws
        -> RegistrationProposalRequest
}
