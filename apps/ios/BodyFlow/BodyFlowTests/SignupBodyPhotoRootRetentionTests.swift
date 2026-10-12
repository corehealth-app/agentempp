#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

/// Root retention/teardown only: actual coordinator, Presentation/Core and
/// immutable harness scope. No AppRoot rendering, camera, normalizer or ACK.
@MainActor
@Suite("Signup photo root owns one presentation per full token", .serialized)
struct SignupBodyPhotoRootRetentionTests {
    @Test("UI01 same root token retains Flow/Presentation/Core, including nil capability",
        arguments: [true, false])
    func sameOwnerSynchronizationRetainsModels(hasCapability: Bool) async throws {
        let h = try await PresentationHarness(manual: 24)
        var root = OnboardingRootCoordinator()
        let keys = DeterministicIdempotencyKeyProvider(prefix: "root-photo-retention-key")
        defer { root.photosModel?.invalidate(); root.flowModel?.invalidate(); h.clean() }
        synchronize(&root, harness: h, userID: h.owner.userID, generation: 1,
            capability: hasCapability ? h.factory.capability : nil, keys: keys)
        let flow = try #require(root.flowModel)
        let photos = try #require(root.photosModel,
            "The root must retain a Presentation even when capture is unavailable")
        try #require(root.canRender(ownerToken: h.owner))
        try #require(flow !== h.flow, "Exercise the coordinator-created Flow")
        await photos.load()
        let core = photos.capture
        if hasCapability {
            let loaded = try #require(core)
            try #require(loaded.isActive && loaded.state != nil)
            #expect(photos.availability == .available)
            photos.select(.photos)
            #expect(photos.route == .consent)
        } else {
            #expect(core == nil && photos.availability == .unavailable)
            photos.select(.photos)
            #expect(photos.choice == .typed && photos.route == nil)
        }
        photos.select(.typed)
        flow.updateHeightCM(178.5)
        flow.updateWeightKG(82.5)
        var staleRestore = h.flow.draft
        staleRestore.heightCM = 199
        staleRestore.weightKG = 99
        staleRestore.bodyFatPercent = 12
        synchronize(&root, harness: h, userID: h.owner.userID, generation: 1,
            capability: hasCapability ? h.factory.capability : nil,
            keys: keys, draft: staleRestore)
        #expect(root.flowModel === flow && root.photosModel === photos)
        #expect(photos.capture === core)
        #expect(flow.isActive && photos.isActive && root.canRender(ownerToken: h.owner))
        #expect(flow.draft.heightCM == 178.5 && flow.draft.weightKG == 82.5)
        #expect(flow.draft.bodyFatPercent == 24 && flow.draft.bodyFatOrigin == .typed)
        #expect(flow.draft.bodyPhotoConfirmation == nil && photos.choice == .typed)
        let factory = await h.factory.snapshot()
        let trace = await h.peer.snapshot()
        #expect(factory == (hasCapability ? [h.owner.userID] : []))
        #expect(trace.count(.state) == (hasCapability ? 1 : 0))
        #expect(trace.mutationAndStageSteps.isEmpty)
        if !hasCapability {
            // Nil capture is a retained unavailable parent, not a demo/fake.
            photos.select(.skip)
            #expect(photos.choice == .skip && flow.draft.bodyFatPercent == nil)
            #expect(flow.draft.bodyFatOrigin == nil && photos.route == nil)
        }
    }

    @Test("UI01 restore2 or nil invalidates Parent/Core before held GET returns",
        arguments: [false, true])
    func teardownBeforeDelayedState(signedOut: Bool) async throws {
        let h = try await PresentationHarness(manual: 24)
        var root = OnboardingRootCoordinator()
        let keys = DeterministicIdempotencyKeyProvider(prefix: "root-photo-state-key")
        defer { root.photosModel?.invalidate(); root.flowModel?.invalidate(); h.clean() }
        synchronize(&root, harness: h, userID: h.owner.userID, generation: 1,
            capability: h.factory.capability, keys: keys)
        let oldFlow = try #require(root.flowModel)
        let oldPhotos = try #require(root.photosModel)
        await oldPhotos.load()
        let oldCore = try #require(oldPhotos.capture)
        try #require(oldCore.state?.consent?.version == "test-v1")
        let oldDraft = oldFlow.draft
        await h.peer.changeDocument()
        await h.peer.holdNextState()
        let loading = Task { await oldPhotos.load(); await h.stateGate.operationFinished() }
        let entered = await h.stateGate.entryOrOperationEnd()
        if !entered {
            await h.stateGate.release(); await loading.value
            try #require(entered, "A real old GET must enter before teardown")
        }
        do {
            let next = OnboardingOwnerToken(userID: h.owner.userID, restoreGeneration: 2)
            h.ownerBox.current = next
            var freshDraft = h.flow.draft
            freshDraft.heightCM = 182
            freshDraft.bodyFatPercent = 17
            synchronize(&root, harness: h, userID: signedOut ? nil : h.owner.userID,
                generation: 2, capability: h.factory.capability, keys: keys, draft: freshDraft)
            // Synchronous boundary: there is deliberately NO await between
            // synchronize and these inactive checks.
            #expect(!oldFlow.isActive && !oldPhotos.isActive && !oldCore.isActive)
            #expect(oldCore.state == nil && oldPhotos.route == nil)
            #expect(!root.canRender(ownerToken: h.owner))
            if signedOut {
                #expect(root.flowModel == nil && root.photosModel == nil && root.ownerToken == nil)
            } else {
                let freshFlow = try #require(root.flowModel)
                let freshPhotos = try #require(root.photosModel)
                #expect(freshFlow !== oldFlow && freshPhotos !== oldPhotos)
                #expect(root.ownerToken == next && root.canRender(ownerToken: next))
                #expect(freshPhotos.capture == nil && freshPhotos.isActive)
            }
            await h.stateGate.release(); await loading.value
            #expect(oldCore.state == nil && !oldCore.isActive && !oldPhotos.isActive)
            #expect(oldPhotos.availability == .unavailable && oldPhotos.route == nil)
            #expect(oldFlow.draft == oldDraft)
            let trace = await h.peer.snapshot()
            #expect(trace.count(.state) == 2 && trace.mutationAndStageSteps.isEmpty)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            if !signedOut {
                let freshFlow = try #require(root.flowModel)
                let freshPhotos = try #require(root.photosModel)
                await freshPhotos.load()
                let freshCore = try #require(freshPhotos.capture)
                #expect(freshCore !== oldCore && freshCore.isActive)
                #expect(freshCore.state?.consent?.version == "test-v2")
                #expect(freshFlow.draft.heightCM == 182 && freshFlow.draft.bodyFatPercent == 17)
                #expect(freshFlow.draft.bodyFatOrigin == .typed && freshFlow.draft.bodyPhotoConfirmation == nil)
                #expect(await h.factory.snapshot() == [h.owner.userID, h.owner.userID])
                let finished = await h.peer.snapshot()
                #expect(finished.count(.state) == 3 && finished.mutationAndStageSteps.isEmpty)
            }
            // UI restore identity changed; this deliberately does not revoke
            // the harness auth lease or claim an authentication transition.
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await h.stateGate.release(); await loading.value
            throw error
        }
    }

    @Test("UI01 obsolete factory result cannot construct Core after restore2 or nil",
        arguments: [false, true])
    func teardownBeforeDelayedFactory(signedOut: Bool) async throws {
        let h = try await PresentationHarness(manual: 24, holdFactory: true)
        var root = OnboardingRootCoordinator()
        let keys = DeterministicIdempotencyKeyProvider(prefix: "root-photo-factory-key")
        defer { root.photosModel?.invalidate(); root.flowModel?.invalidate(); h.clean() }
        synchronize(&root, harness: h, userID: h.owner.userID, generation: 1,
            capability: h.factory.capability, keys: keys)
        let oldFlow = try #require(root.flowModel)
        let oldPhotos = try #require(root.photosModel)
        let oldDraft = oldFlow.draft
        let loading = Task { await oldPhotos.load(); await h.factory.gate.operationFinished() }
        let entered = await h.factory.gate.entryOrOperationEnd()
        if !entered {
            await h.factory.gate.release(); await loading.value
            try #require(entered, "A real scoped factory must enter before teardown")
        }
        do {
            let next = OnboardingOwnerToken(userID: h.owner.userID, restoreGeneration: 2)
            h.ownerBox.current = next
            synchronize(&root, harness: h, userID: signedOut ? nil : h.owner.userID,
                generation: 2, capability: h.factory.capability, keys: keys)
            // No await before the old parent/Flow boundary is checked.
            #expect(!oldFlow.isActive && !oldPhotos.isActive && oldPhotos.capture == nil)
            #expect(!root.canRender(ownerToken: h.owner))
            if signedOut {
                #expect(root.flowModel == nil && root.photosModel == nil && root.ownerToken == nil)
            } else {
                let freshPhotos = try #require(root.photosModel)
                #expect(freshPhotos !== oldPhotos && freshPhotos.isActive && freshPhotos.capture == nil)
                #expect(root.ownerToken == next && root.canRender(ownerToken: next))
            }
            await h.factory.gate.release(); await loading.value
            #expect(oldPhotos.capture == nil && !oldPhotos.isActive)
            #expect(oldPhotos.availability == .unavailable && oldPhotos.route == nil)
            #expect(oldFlow.draft == oldDraft)
            let trace = await h.peer.snapshot()
            #expect(trace.count(.state) == 0 && trace.mutationAndStageSteps.isEmpty)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            if !signedOut {
                let freshPhotos = try #require(root.photosModel)
                await freshPhotos.load()
                let freshCore = try #require(freshPhotos.capture)
                #expect(freshCore.isActive && freshPhotos.availability == .available)
                #expect(await h.factory.snapshot() == [h.owner.userID, h.owner.userID])
                let finished = await h.peer.snapshot()
                #expect(finished.count(.state) == 1 && finished.mutationAndStageSteps.isEmpty)
                #expect(oldPhotos.capture == nil)
            }
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await h.factory.gate.release(); await loading.value
            throw error
        }
    }

    /// No escaping closure captures the mutable coordinator struct. The
    /// current-owner box is MainActor-owned and the same one used by the peer.
    private func synchronize(_ root: inout OnboardingRootCoordinator,
        harness h: PresentationHarness, userID: String?, generation: Int,
        capability: SignupBodyPhotoCaptureCapability?, keys: any IdempotencyKeyProviding,
        draft: OnboardingDraft? = nil) {
        let ownerBox = h.ownerBox
        root.synchronize(activeUserID: userID,
            restoredDraft: userID == nil ? nil : (draft ?? h.flow.draft),
            restoreGeneration: generation,
            onboarding: SignupPhotoPresentationOnboardingRepository(),
            persona: PresentationPersona(), developmentConsentAvailability: .syntheticDevelopment,
            idempotencyKeyProvider: keys, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: {},
            signupBodyPhotoCapture: capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            isCurrentPhotoOwner: { $0 == ownerBox.current })
    }
}
#endif
