#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

/// The real coordinator's synchronous admission boundary. Repeated task
/// claims are simulated directly; this does not render/reappear AppRootView.
@MainActor
@Suite("Signup root initial photo load belongs to one retained parent", .serialized)
struct SignupBodyPhotoRootInitialLoadClaimTests {
    @Test("UI02 one initial-load claim per full owner retains models and prevents a second GET")
    func initialPhotoLoadIsClaimedOncePerRetainedOwner() async throws {
        let h = try await PresentationHarness(manual: 24)
        var root = OnboardingRootCoordinator()
        let keys = DeterministicIdempotencyKeyProvider(prefix: "root-photo-initial-claim-key")
        defer { root.photosModel?.invalidate(); root.flowModel?.invalidate(); h.clean() }
        #expect(root.claimInitialPhotoLoad(ownerToken: nil) == nil)
        #expect(root.claimInitialPhotoLoad(ownerToken: h.owner) == nil)
        synchronize(&root, harness: h, userID: h.owner.userID, generation: 1, keys: keys)
        let flow = try #require(root.flowModel)
        let photos = try #require(root.photosModel)
        try #require(root.canRender(ownerToken: h.owner))
        #expect(root.claimInitialPhotoLoad(ownerToken: nil) == nil,
            "A nil caller must not consume the real owner's first claim")
        let nextOwner = OnboardingOwnerToken(userID: h.owner.userID, restoreGeneration: 2)
        #expect(root.claimInitialPhotoLoad(ownerToken: nextOwner) == nil,
            "A different full owner must not consume the current parent's claim")
        let firstClaim = root.claimInitialPhotoLoad(ownerToken: h.owner)
        let first = try #require(firstClaim,
            "The current retained parent must be admitted for its first actual load")
        #expect(first === photos && root.photosModel === photos && root.flowModel === flow)
        #expect(await h.factory.snapshot().isEmpty,
            "Claim is synchronous admission, not a hidden factory/read")
        let before = await h.peer.snapshot()
        #expect(before.calls.isEmpty)
        #expect(root.claimInitialPhotoLoad(ownerToken: h.owner) == nil,
            "Repeated claim is denied even before the admitted load starts")
        await first.load()
        let core = try #require(photos.capture)
        try #require(core.isActive && core.state != nil)
        #expect(root.claimInitialPhotoLoad(ownerToken: h.owner) == nil)

        // Repeat the same synchronize path, as a recreated task could do,
        // and change form mode while retaining the original objects.
        flow.updateHeightCM(178.5)
        synchronize(&root, harness: h, userID: h.owner.userID, generation: 1, keys: keys)
        #expect(root.photosModel === photos && root.flowModel === flow && photos.capture === core)
        #expect(flow.draft.heightCM == 178.5)
        #expect(root.claimInitialPhotoLoad(ownerToken: h.owner) == nil)
        photos.select(.photos)
        photos.select(.typed)
        photos.select(.photos)
        #expect(root.claimInitialPhotoLoad(ownerToken: h.owner) == nil)
        let unchanged = await h.peer.snapshot()
        #expect(unchanged.count(.state) == 1 && unchanged.mutationAndStageSteps.isEmpty)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        #expect(root.photosModel === photos && root.flowModel === flow && photos.capture === core)
        #expect(flow.draft.bodyFatPercent == 24 && flow.draft.bodyFatOrigin == .typed)
        #expect(flow.draft.bodyPhotoConfirmation == nil)

        // Same userID, new restoreGeneration: a different full owner receives
        // a new parent and an independent initial claim, with the same factory.
        h.ownerBox.current = nextOwner
        synchronize(&root, harness: h, userID: h.owner.userID, generation: 2, keys: keys)
        #expect(!flow.isActive && !photos.isActive && !core.isActive)
        let freshFlow = try #require(root.flowModel)
        let freshPhotos = try #require(root.photosModel)
        #expect(freshFlow !== flow && freshPhotos !== photos && freshPhotos.capture == nil)
        #expect(root.ownerToken == nextOwner && root.canRender(ownerToken: nextOwner))
        #expect(root.claimInitialPhotoLoad(ownerToken: h.owner) == nil,
            "The old full owner must not consume the fresh parent's first claim")
        let freshClaim = root.claimInitialPhotoLoad(ownerToken: nextOwner)
        let fresh = try #require(freshClaim)
        #expect(fresh === freshPhotos)
        #expect(root.claimInitialPhotoLoad(ownerToken: nextOwner) == nil)
        await fresh.load()
        let freshCore = try #require(freshPhotos.capture)
        #expect(freshCore !== core && freshCore.isActive)
        #expect(root.claimInitialPhotoLoad(ownerToken: nextOwner) == nil)
        let final = await h.peer.snapshot()
        #expect(final.count(.state) == 2 && final.mutationAndStageSteps.isEmpty)
        #expect(await h.factory.snapshot() == [h.owner.userID, h.owner.userID])
        #expect(freshFlow.draft.bodyFatPercent == 24 && freshFlow.draft.bodyFatOrigin == .typed)
        #expect(freshFlow.draft.bodyPhotoConfirmation == nil)

        synchronize(&root, harness: h, userID: nil, generation: 3, keys: keys)
        #expect(!freshFlow.isActive && !freshPhotos.isActive && !freshCore.isActive)
        #expect(root.ownerToken == nil && root.photosModel == nil && root.flowModel == nil)
        #expect(root.claimInitialPhotoLoad(ownerToken: nil) == nil)
        #expect(root.claimInitialPhotoLoad(ownerToken: nextOwner) == nil)
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
    }

    private func synchronize(_ root: inout OnboardingRootCoordinator,
        harness h: PresentationHarness, userID: String?, generation: Int,
        keys: any IdempotencyKeyProviding) {
        let ownerBox = h.ownerBox
        root.synchronize(activeUserID: userID,
            restoredDraft: userID == nil ? nil : h.flow.draft,
            restoreGeneration: generation,
            onboarding: SignupPhotoPresentationOnboardingRepository(),
            persona: PresentationPersona(), developmentConsentAvailability: .syntheticDevelopment,
            idempotencyKeyProvider: keys, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: {},
            signupBodyPhotoCapture: h.factory.capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            isCurrentPhotoOwner: { $0 == ownerBox.current })
    }
}
#endif
