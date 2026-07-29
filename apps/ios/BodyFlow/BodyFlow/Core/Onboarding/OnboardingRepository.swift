enum OnboardingRepositoryError: Error, Equatable, Sendable {
    case invalidDraft
    case developmentConsentForbidden
    case storageUnavailable
    case serviceUnavailable
}

protocol OnboardingRepository: Sendable {
    func loadDraft(for userID: String) async throws -> OnboardingDraft?
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws
    func complete(_ draft: OnboardingDraft, for userID: String) async throws
    func clear(for userID: String) async throws
}
