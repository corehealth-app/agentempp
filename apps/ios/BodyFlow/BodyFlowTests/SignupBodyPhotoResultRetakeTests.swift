#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

/// Existing declared DTO peer verifies route/proof;
/// its scripted byte payload is not camera/JPEG/AI/live transport evidence.
@MainActor
@Suite("Signup photo retake after an official result", .serialized)
struct SignupBodyPhotoResultRetakeTests {
    @Test("R01 explicit retake reuses Parent/Core/scope; a fresh official ID invalidates a same-24 proof",
          arguments: [false, true])
    func replacementAfterResultKeepsScopeAndNeedsNewExplicitConfirmation(confirmed: Bool) async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        let original = try #require(core.state)
        let originalCandidate = try #require(OnboardingBodyPhotoConfirmation.candidate(from: original, sex: .masculine))
        try #require(h.model.route == .result && originalCandidate.value == 24)
        if confirmed { try #require(h.model.confirmEstimate()) }
        let baseline = await h.peer.snapshot()
        #expect(h.model.beginRetake())
        #expect(h.model.route == .capture)
        #expect(h.model.capture === core && core.isActive && core.hasAcceptedConsent)
        #expect(core.state == original, "Changing the presentation route must not manufacture another server state")
        #expect(h.flow.draft.bodyFatPercent == (confirmed ? 24 : nil))
        #expect(h.flow.draft.bodyFatOrigin == (confirmed ? .photos : nil))
        #expect(h.flow.draft.bodyPhotoConfirmation == (confirmed ? originalCandidate : nil))
        #expect(h.model.confirmableEstimate == nil && !h.model.confirmEstimate(),
            "Capture mode must not authorize a cached old result confirmation")
        #expect(await h.peer.snapshot().calls == baseline.calls,
            "Retake intent itself does not GET/consent/create/delete or renew the scope")
        #expect(await h.factory.snapshot() == [h.owner.userID])

        // This is the actual Parent → retained D1 → existing Core pipeline.
        let input = CaptureModelHarness.data
        await h.model.producePhoto(pose: .front, channel: .gallery) { authorization in
            try await authorization.validate()
            let data = input
            try await authorization.validate()
            return data
        }
        try await h.model.waitForLocalCleanup()
        let current = try #require(core.state)
        let replacement = try #require(OnboardingBodyPhotoConfirmation.candidate(from: current, sex: .masculine))
        #expect(h.model.capture === core && h.model.route == .result)
        #expect(replacement.value == originalCandidate.value && replacement.value == 24)
        #expect(replacement.sourceIDs.front != originalCandidate.sourceIDs.front)
        #expect(replacement.sourceIDs.side == originalCandidate.sourceIDs.side)
        #expect(replacement.sourceIDs.back == originalCandidate.sourceIDs.back)
        #expect(replacement.fingerprint != originalCandidate.fingerprint)
        #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyFatOrigin == nil)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil,
            "A new official source identity invalidates an old confirmed24 proof, without auto-confirming the new24")
        let after = await h.peer.snapshot()
        #expect(after.count(.state) == baseline.count(.state) + 1,
            "Only the existing capture pipeline's authoritative GET is added")
        #expect(after.count(.consent) == baseline.count(.consent))
        #expect(after.count(.stage) == baseline.count(.stage) + 1)
        #expect(after.count(.create) == baseline.count(.create) + 1)
        #expect(after.count(.put) == baseline.count(.put) + 1)
        #expect(after.count(.complete) == baseline.count(.complete) + 1)
        #expect(after.count(.delete) == 0 && after.count(.repair) == 0)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        #expect(await h.cleanup.registry.activeCount == 0)
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        #expect(h.model.confirmEstimate())
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
        #expect(h.flow.draft.bodyPhotoConfirmation == replacement)
        #expect(!h.flow.requiresBodyPhotoRevalidation)
    }

    @Test("R02 a cancelled source after entering retake sends nothing and preserves the unchanged official proof")
    func cancelledRetakeSourceDoesNotFabricateReplacement() async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        try #require(h.model.confirmEstimate())
        let core = try #require(h.model.capture), old = try #require(h.flow.draft.bodyPhotoConfirmation)
        let originalState = core.state, baseline = await h.peer.snapshot()
        #expect(h.model.beginRetake() && h.model.route == .capture)
        await h.model.producePhoto(pose: .front, channel: .camera) { authorization in
            try await authorization.validate()
            return nil // the actual SDK/stand-in cancellation contract
        }
        #expect(h.model.route == .capture, "Cancelled source is not a new result or implicit result confirmation")
        #expect(h.model.capture === core && core.state == originalState)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
        #expect(h.flow.draft.bodyPhotoConfirmation == old && old.matches(h.flow.draft))
        #expect(h.model.confirmableEstimate == nil && !h.model.confirmEstimate())
        #expect(await h.peer.snapshot().calls == baseline.calls)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        try await h.model.waitForLocalCleanup()
        #expect(await h.cleanup.registry.activeCount == 0)
    }

    @Test("R03 a restored owner cannot enter the old Parent's retake route")
    func restoredOwnerRejectsOldResultAction() async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let baseline = await h.peer.snapshot()
        h.ownerBox.current = .init(userID: h.owner.userID, restoreGeneration: 2)
        #expect(!h.model.beginRetake())
        #expect(h.model.route == nil && h.model.confirmableEstimate == nil)
        #expect(await h.peer.snapshot().calls == baseline.calls)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyPhotoConfirmation == nil)
    }
}
#endif
