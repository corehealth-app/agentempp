import Foundation

/// Transient ownership for an explicit deletion. Never persisted in the draft.
struct OnboardingBodyPhotoDeletionIntent: Equatable {
    let owner: OnboardingOwnerToken
    private let id: UUID

    init(owner: OnboardingOwnerToken) {
        self.owner = owner
        id = UUID()
    }
}
