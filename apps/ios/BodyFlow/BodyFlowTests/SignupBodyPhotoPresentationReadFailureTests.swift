#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo initial read failure", .serialized)
struct SignupBodyPhotoPresentationReadFailureTests {
    @Test("P13 failed initial GET leaves manual/skip usable and retry reuses the scope and capture",
        arguments: [false, true])
    func failedInitialReadDoesNotStayLoading(skip: Bool) async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        let peer = SignupPhotoPresentationReadFailurePeer(base: h.peer)
        let factory = PresentationFactoryPeer(scope: presentationScope(h.scope, photos: peer))
        let model = SignupBodyPhotoPresentationModel(flow: h.flow, ownerToken: h.owner,
            capability: factory.capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "presentation-read-failure"),
            isCurrentOwner: { $0 == h.ownerBox.current })
        defer { model.invalidate() }

        await model.load()
        let first = try #require(model.capture)
        #expect(first.state == nil && first.phase == .failed(.unavailable))
        #expect(model.loadFailed)
        #expect(model.availability == .unavailable && model.route == nil)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        model.select(skip ? .skip : .typed)
        #expect(model.choice == (skip ? .skip : .typed))
        #expect(h.flow.draft.bodyFatPercent == (skip ? nil : 24))

        await model.load()
        let second = try #require(model.capture)
        #expect(first === second && second.state?.available == true)
        #expect(!model.loadFailed && model.availability == .available)
        #expect(h.flow.draft.bodyFatPercent == (skip ? nil : 24))
        #expect(h.flow.draft.bodyFatOrigin == (skip ? nil : .typed))
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(await factory.snapshot() == [h.owner.userID])
        #expect(await peer.readCount() == 2)
        let trace = await h.peer.snapshot()
        #expect(trace.mutationAndStageSteps.isEmpty)
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        #expect(await h.cleanup.registry.activeCount == 0)
    }
}

private actor SignupPhotoPresentationReadFailurePeer: SignupBodyPhotosProviding {
    let base: PresentationPhotoPeer
    private var reads = 0
    init(base: PresentationPhotoPeer) { self.base = base }
    func readCount() -> Int { reads }
    func state() async throws -> SignupBodyPhotoState {
        reads += 1
        if reads == 1 { throw SignupBodyPhotoFailure.unavailable }
        return try await base.state()
    }
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt {
        try await base.consent(attempt)
    }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt {
        try await base.create(attempt)
    }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt {
        try await base.complete(attempt)
    }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        try await base.delete(attempt)
    }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        try await base.repair(attempt)
    }
}
#endif
