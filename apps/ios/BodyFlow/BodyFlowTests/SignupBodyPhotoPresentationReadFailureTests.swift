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


#if DEBUG
import SwiftUI
import XCTest

/// The real standalone BodyData view, over the existing P13 private peer.
/// Explicit model.load is recovery setup, not a simulated tap on the button.
@MainActor
final class SignupBodyPhotoPresentationReadFailureRenderingTests: XCTestCase {
    func testInitialReadErrorOffersRetryAndManualChoicesThenRecoversOnTheSameCore() async throws {
        for language in SupportedAppLanguage.allCases {
            let h = try await PresentationHarness(manual: 24)
            defer { h.clean() }
            let peer = SignupPhotoPresentationReadFailurePeer(base: h.peer)
            let factory = PresentationFactoryPeer(scope: presentationScope(h.scope, photos: peer))
            let model = SignupBodyPhotoPresentationModel(flow: h.flow, ownerToken: h.owner,
                capability: factory.capability,
                timeProvider: PresentationFixedTime(now: PresentationHarness.now),
                keyProvider: DeterministicIdempotencyKeyProvider(prefix: "presentation-read-ui-retry"),
                isCurrentOwner: { $0 == h.ownerBox.current })
            defer { model.invalidate() }

            await model.load()
            let core = try XCTUnwrap(model.capture)
            XCTAssertNil(core.state)
            XCTAssertEqual(core.phase, .failed(.unavailable))
            XCTAssertTrue(model.loadFailed)
            XCTAssertEqual(model.availability, .unavailable)
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)
            XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            let firstReads = await peer.readCount(), firstBindings = await factory.snapshot()
            XCTAssertEqual(firstReads, 1)
            XCTAssertEqual(firstBindings, [h.owner.userID])

            let host = SignUpRenderingProbe.host(
                BodyDataStepView(model: h.flow, photos: model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            defer { host.detach() }
            let failed = host.nodes()
            let error = try XCTUnwrap(failed.first { $0.identifier == "onboarding.photos.load.error" })
            let retry = try XCTUnwrap(failed.first { $0.identifier == "onboarding.photos.load.retry" })
            XCTAssertEqual(error.label, OnboardingCopy.string("state.error.detail", language: language))
            XCTAssertEqual(retry.label, OnboardingCopy.string("onboarding.retry", language: language))
            XCTAssertTrue(retry.isButton && retry.isEnabled)
            let typed = try XCTUnwrap(failed.first { $0.identifier == "onboarding.body-fat.choice.typed" })
            let skip = try XCTUnwrap(failed.first { $0.identifier == "onboarding.body-fat.choice.skip" })
            let photos = try XCTUnwrap(failed.first { $0.identifier == "onboarding.body-fat.choice.photos" })
            XCTAssertTrue(typed.isEnabled && typed.isSelected && skip.isEnabled)
            XCTAssertFalse(photos.isEnabled)
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)

            // Actual retry API. This does not assert that a UI tap dispatches it.
            await model.load()
            XCTAssertTrue(model.capture === core && core.isActive)
            XCTAssertFalse(model.loadFailed)
            XCTAssertEqual(model.availability, .available)
            let recovered = host.nodes() // SAME view and model, no second host/load.
            XCTAssertFalse(recovered.contains { $0.identifier == "onboarding.photos.load.error" })
            XCTAssertFalse(recovered.contains { $0.identifier == "onboarding.photos.load.retry" })
            let enabledPhotos = try XCTUnwrap(recovered.first { $0.identifier == "onboarding.body-fat.choice.photos" })
            let retainedTyped = try XCTUnwrap(recovered.first { $0.identifier == "onboarding.body-fat.choice.typed" })
            let retainedSkip = try XCTUnwrap(recovered.first { $0.identifier == "onboarding.body-fat.choice.skip" })
            XCTAssertTrue(enabledPhotos.isEnabled)
            XCTAssertTrue(retainedTyped.isEnabled && retainedTyped.isSelected && retainedSkip.isEnabled)
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)
            XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            let finalReads = await peer.readCount(), finalBindings = await factory.snapshot()
            XCTAssertEqual(finalReads, 2)
            XCTAssertEqual(finalBindings, [h.owner.userID], "Retry keeps the original scope")
            let trace = await h.peer.snapshot()
            XCTAssertEqual(trace.count(.state), 1,
                "The existing peer throws the first read before forwarding to its base")
            XCTAssertTrue(trace.mutationAndStageSteps.isEmpty)
            let unusedBindings = await h.factory.snapshot()
            XCTAssertTrue(unusedBindings.isEmpty)
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
            let activeWork = await h.cleanup.registry.activeCount
            XCTAssertEqual(activeWork, 0)
        }
    }
}
#endif
