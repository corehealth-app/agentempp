#if DEBUG
import Foundation
@testable import BodyFlow

// Explicit test factory returns the existing real-store/gate scope. It is not
// a production factory substitute or evidence of live DI/authentication wiring.
actor CleanupRootFactoryPeer {
    let scope: SignupBodyPhotoCleanupScope
    let firstBindBarrier: CleanupProcessorBarrier
    private let holdsFirstBind: Bool
    private var calls: [String] = []

    init(scope: SignupBodyPhotoCleanupScope, holdsFirstBind: Bool = false) {
        self.scope = scope
        self.holdsFirstBind = holdsFirstBind
        firstBindBarrier = CleanupProcessorBarrier(holds: holdsFirstBind)
    }

    func bind(_ userID: String) async throws -> SignupBodyPhotoCleanupScope {
        calls.append(userID)
        let capturedScope = scope
        // The old factory deliberately ignores cancellation after the hold;
        // root must fence its result instead of waiting for its cooperation.
        if holdsFirstBind && calls.count == 1 { await firstBindBarrier.enter() }
        return capturedScope
    }

    func snapshot() -> [String] { calls }
    nonisolated var capability: SignupBodyPhotoCleanupCapability {
        SignupBodyPhotoCleanupCapability { userID in try await self.bind(userID) }
    }
}

func cleanupRootOwner(_ userID: String = CleanupProcessorHarness.a) -> SignupBodyPhotoCleanupOwnerToken {
    .init(userID: userID, activationID: UUID())
}
#endif
