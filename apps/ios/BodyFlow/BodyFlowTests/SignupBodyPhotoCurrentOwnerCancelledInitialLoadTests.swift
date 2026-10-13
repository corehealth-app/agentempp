#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// PRIVATE TEST CANDIDATE. Actual root claim + held scope factory + Task.cancel.
/// No AppRoot reappearance, compiler/native run, backend or UI-account claim.
@MainActor
final class SignupBodyPhotoCurrentOwnerCancelledInitialLoadTests: XCTestCase {
    func testCurrentOwnerCancelledInitialLoadShowsRetryAndExplicitRetryReusesTheSuccessfulBoundTask() async throws {
        let h = try await PresentationHarness(holdFactory: true)
        var root = OnboardingRootCoordinator()
        defer { root.photosModel?.invalidate(); root.flowModel?.invalidate(); h.clean() }
        synchronize(&root, h: h, generation: 1)
        let flow = try XCTUnwrap(root.flowModel), photos = try XCTUnwrap(root.photosModel)
        let admitted = try XCTUnwrap(root.claimInitialPhotoLoad(ownerToken: h.owner))
        XCTAssertTrue(admitted === photos)
        let loading = Task { await admitted.load(); await h.factory.gate.operationFinished() }
        let entered = await h.factory.gate.entryOrOperationEnd()
        guard entered else {
            await h.factory.gate.release(); await loading.value
            XCTFail("The real capability.scoped must enter its hold before cancellation")
            throw CancelledInitialLoadFixtureError.factoryNeverEntered
        }
        do {
            let before = await h.peer.snapshot()
            let initialBinds = await h.factory.snapshot()
            XCTAssertTrue(before.calls.isEmpty)
            XCTAssertEqual(initialBinds, [h.owner.userID])
            loading.cancel() // actual root/admitted load task cancellation, same owner
            await h.factory.gate.release() // actual successful bound scope, ignores caller cancellation
            await loading.value
            XCTAssertTrue(root.canRender(ownerToken: h.owner))
            XCTAssertTrue(root.photosModel === photos && root.flowModel === flow)
            XCTAssertNil(photos.capture?.state)
            XCTAssertTrue(photos.loadFailed,
                "Current-owner cancelled initial load with no state must offer an explicit retry")
            XCTAssertEqual(photos.availability, .unavailable)
            let cancelledTrace = await h.peer.snapshot()
            let cancelledBinds = await h.factory.snapshot()
            XCTAssertTrue(cancelledTrace.calls.isEmpty,
                "Cancellation cannot manufacture GET or automatically retry")
            XCTAssertEqual(cancelledBinds, [h.owner.userID])

            synchronize(&root, h: h, generation: 1)
            XCTAssertTrue(root.photosModel === photos && root.flowModel === flow)
            XCTAssertNil(root.claimInitialPhotoLoad(ownerToken: h.owner),
                "Keep one root initial claim; recovery is explicit, never a second automatic claim")
            for language in SupportedAppLanguage.allCases {
                let nodes = SignUpRenderingProbe.nodes(
                    BodyDataStepView(model: flow, photos: photos)
                        .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                XCTAssertNotNil(nodes.first { $0.identifier == "onboarding.photos.load.error" })
                let retry = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.load.retry" })
                XCTAssertTrue(retry.isEnabled)
            }
            let rendered = await h.peer.snapshot()
            XCTAssertTrue(rendered.calls.isEmpty,
                "Rendering the error/retry does not auto-load")
            await photos.load() // same public action BodyData's explicit retry delegates to
            let core = try XCTUnwrap(photos.capture)
            XCTAssertNotNil(core.state)
            XCTAssertFalse(photos.loadFailed)
            XCTAssertEqual(photos.availability, .available)
            XCTAssertTrue(root.photosModel === photos && root.flowModel === flow)
            XCTAssertNil(root.claimInitialPhotoLoad(ownerToken: h.owner))
            let recoveredBinds = await h.factory.snapshot()
            XCTAssertEqual(recoveredBinds, [h.owner.userID],
                "Successful bound task from the cancelled first load must be retained, not rebound")
            let recovered = await h.peer.snapshot()
            XCTAssertEqual(recovered.count(.state), 1)
            XCTAssertTrue(recovered.mutationAndStageSteps.isEmpty)
            XCTAssertNil(flow.draft.bodyFatPercent)
            XCTAssertNil(flow.draft.bodyPhotoConfirmation)
            for language in SupportedAppLanguage.allCases {
                let nodes = SignUpRenderingProbe.nodes(
                    BodyDataStepView(model: flow, photos: photos)
                        .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.load.retry" })
                XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.load.error" })
            }
            let renderedRecovered = await h.peer.snapshot()
            XCTAssertEqual(renderedRecovered.count(.state), 1)
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await h.factory.gate.release(); await loading.value
            throw error
        }
    }

    func testCancelledOldOwnerCannotPublishRetryFailureIntoTheFreshRoot() async throws {
        let h = try await PresentationHarness(holdFactory: true)
        var root = OnboardingRootCoordinator()
        defer { root.photosModel?.invalidate(); root.flowModel?.invalidate(); h.clean() }
        synchronize(&root, h: h, generation: 1)
        let old = try XCTUnwrap(root.claimInitialPhotoLoad(ownerToken: h.owner))
        let oldFlow = try XCTUnwrap(root.flowModel)
        let loading = Task { await old.load(); await h.factory.gate.operationFinished() }
        let entered = await h.factory.gate.entryOrOperationEnd()
        guard entered else {
            await h.factory.gate.release(); await loading.value
            XCTFail("The old actual capability bind must enter before owner replacement")
            throw CancelledInitialLoadFixtureError.factoryNeverEntered
        }
        loading.cancel()
        let next = OnboardingOwnerToken(userID: h.owner.userID, restoreGeneration: 2)
        h.ownerBox.current = next
        synchronize(&root, h: h, generation: 2)
        let fresh = try XCTUnwrap(root.photosModel), freshFlow = try XCTUnwrap(root.flowModel)
        XCTAssertFalse(old.isActive)
        XCTAssertFalse(oldFlow.isActive)
        XCTAssertTrue(fresh !== old && freshFlow !== oldFlow)
        await h.factory.gate.release(); await loading.value
        XCTAssertFalse(old.loadFailed, "Late cancellation/error cannot publish into an obsolete Parent")
        XCTAssertFalse(fresh.loadFailed)
        XCTAssertNil(fresh.capture?.state)
        XCTAssertTrue(root.canRender(ownerToken: next))
        XCTAssertNil(root.claimInitialPhotoLoad(ownerToken: h.owner))
        XCTAssertTrue(root.claimInitialPhotoLoad(ownerToken: next) === fresh)
        let trace = await h.peer.snapshot(), binds = await h.factory.snapshot()
        XCTAssertTrue(trace.calls.isEmpty)
        XCTAssertEqual(binds, [h.owner.userID])
        XCTAssertNil(freshFlow.draft.bodyFatPercent)
        XCTAssertNil(freshFlow.draft.bodyPhotoConfirmation)
    }

    private func synchronize(_ root: inout OnboardingRootCoordinator,
                             h: PresentationHarness, generation: Int) {
        let box = h.ownerBox
        root.synchronize(activeUserID: h.owner.userID, restoredDraft: h.flow.draft,
            restoreGeneration: generation, onboarding: SignupPhotoPresentationOnboardingRepository(),
            persona: PresentationPersona(), developmentConsentAvailability: .syntheticDevelopment,
            idempotencyKeyProvider: DeterministicIdempotencyKeyProvider(prefix: "root-cancelled-first-load"),
            telemetry: DisabledTelemetryClient(), onStepChanged: { _ in }, onCompleted: {},
            signupBodyPhotoCapture: h.factory.capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            isCurrentPhotoOwner: { $0 == box.current })
    }
}
private enum CancelledInitialLoadFixtureError: Error { case factoryNeverEntered }
#endif
