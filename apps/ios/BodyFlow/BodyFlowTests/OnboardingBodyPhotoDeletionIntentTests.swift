#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup deletion intent guards the real Flow", .serialized)
struct OnboardingBodyPhotoDeletionIntentTests {
    @Test("An old deletion cannot unblock a new intent on the same Flow",
        arguments: [1, 2])
    func obsoleteIntentCannotFinishNewOperation(_ restoreGeneration: Int) async throws {
        let h = try await SignupDeleteCompositionHarness()
        defer { h.removeFolder() }
        try await h.prepare()
        let before = h.flow.draft
        let old = try #require(h.flow.beginBodyPhotoDeletion(for: h.owner))
        let currentOwner = OnboardingOwnerToken(userID: h.owner.userID,
            restoreGeneration: restoreGeneration)
        let current = try #require(h.flow.beginBodyPhotoDeletion(for: currentOwner))
        let oldFinished = h.flow.finishBodyPhotoDeletion(old)
        #expect(!oldFinished)
        let state = try #require(h.model.capture?.state)
        let confirmationDuringDeletion = h.flow.confirmBodyPhotoEstimate(state)
        #expect(!confirmationDuringDeletion)
        let calls = await h.flowPeer.report(), step = h.flow.step
        await h.flow.continueFromCurrentStep()
        let blocked = await h.flowPeer.report()
        #expect(blocked == calls && h.flow.step == step)
        #expect(h.flow.draft == before, "The blocker is outside the draft; independently typed24 is preserved")
        let finished = h.flow.finishBodyPhotoDeletion(current)
        try #require(finished)
        await h.flow.continueFromCurrentStep()
        let released = await h.flowPeer.report()
        #expect(released.saves == calls.saves + 1 && h.flow.step != step)
        let repeated = h.flow.finishBodyPhotoDeletion(current)
        #expect(!repeated)
        try await h.drain()
    }
}
#endif
