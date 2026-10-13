#if DEBUG
import Foundation
import SwiftUI
import XCTest
@testable import BodyFlow

/// UI-node contracts over real retained models. Existing D1 suites own its
/// drain/CAS/receipt/reentrancy coverage. This file does not simulate a tap.
@MainActor
final class SignupBodyPhotoActionsRenderingTests: XCTestCase {
    func testCurrentCaptureAndResultOfferExplicitDeleteWithoutRenderSideEffects() async throws {
        for fixture in [SignupPhotoViewFixture.captureTerminal, .valid] {
            let h = try await SignupPhotoViewHarness(fixture: fixture, manual: 23)
            do {
                await h.prepare()
                let core = try XCTUnwrap(h.model.capture)
                XCTAssertTrue(core.isActive && core.hasAcceptedConsent)
                XCTAssertEqual(h.model.route, fixture == .valid ? .result : .capture)
                let baseline = await h.base.peer.snapshot()
                for language in SupportedAppLanguage.allCases {
                    let nodes = photoRouteNodes(h.model, language: language)
                    let buttons = nodes.filter { $0.identifier == "onboarding.photos.delete" }
                    XCTAssertEqual(buttons.count, 1, "Explicit action is available before signup completion")
                    XCTAssertEqual(buttons.first?.label, language == .portugueseBrazil ? "Apagar fotos" : "Delete photos")
                    XCTAssertTrue(buttons.first?.isButton == true && buttons.first?.isEnabled == true)
                    XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.delete.retry" })
                }
                XCTAssertTrue(h.model.capture === core)
                XCTAssertEqual(h.base.flow.draft.bodyFatPercent, 23)
                XCTAssertEqual(h.base.flow.draft.bodyFatOrigin, .typed)
                XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
                let after = await h.base.peer.snapshot(), binds = await h.factory.snapshot()
                XCTAssertEqual(after.calls, baseline.calls, "Rendering cannot DELETE/load/rebind/stage")
                XCTAssertEqual(binds, [h.base.owner.userID])
                h.base.ownerBox.current = .init(userID: h.base.owner.userID, restoreGeneration: 2)
                for language in SupportedAppLanguage.allCases {
                    let obsolete = photoRouteNodes(h.model, language: language)
                    XCTAssertFalse(obsolete.contains { $0.identifier == "onboarding.photos.delete" })
                }
                await h.stop()
            } catch { await h.stop(); throw error }
        }
    }

    func testKnownOwnerPhotosCanBeDeletedFromBodyDataOrConsentWithoutFreshAcceptance() async throws {
        for available in [false, true] {
            let h = try await PresentationHarness(manual: 23, available: available, hasEstimate: true)
            defer { h.clean() }
            await h.model.load()
            let core = try XCTUnwrap(h.model.capture)
            XCTAssertFalse(core.hasAcceptedConsent)
            XCTAssertTrue(core.state?.poses.contains { $0.photo != nil } == true)
            if available { h.model.select(.photos); XCTAssertEqual(h.model.route, .consent) }
            else { XCTAssertEqual(h.model.availability, .unavailable) }
            let baseline = await h.peer.snapshot()
            for language in SupportedAppLanguage.allCases {
                let bodyNodes = SignUpRenderingProbe.nodes(
                    BodyDataStepView(model: h.flow, photos: h.model)
                        .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                XCTAssertTrue(bodyNodes.first { $0.identifier == "onboarding.photos.delete" }?.isEnabled == true,
                    "Known owner photos remain deletable when photos are OFF or consent is not accepted")
                if available {
                    let consentNodes = SignUpRenderingProbe.nodes(
                        SignupBodyPhotoConsentRouteView(photos: h.model)
                            .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                    XCTAssertTrue(consentNodes.first { $0.identifier == "onboarding.photos.delete" }?.isEnabled == true)
                }
            }
            let after = await h.peer.snapshot()
            XCTAssertEqual(after.calls, baseline.calls)
            XCTAssertEqual(after.count(.consent), 0); XCTAssertEqual(after.count(.delete), 0)
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 23)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
        }
    }

    func testDeletionRecoveryStaysVisibleInBodyDataWhenItsPhotoRouteIsNil() async throws {
        let h = try await SignupDeleteCompositionHarness(recovery: .reload)
        defer { h.removeFolder() }
        try await h.prepare()
        let original = try XCTUnwrap(h.model.capture)
        await h.model.deletePhotos() // existing exact operation, not a simulated UI event
        let d1 = try XCTUnwrap(h.model.deletion)
        XCTAssertEqual(d1.phase, .failed(.offline))
        XCTAssertEqual(d1.receipt, SignupBodyPhotoDeleteReceipt(deleted: 0))
        XCTAssertFalse(original.isActive)
        XCTAssertNil(h.model.route)
        XCTAssertTrue(h.flow.hasPendingBodyPhotoDeletion)
        // Editing can remain allowed; advancing has its separate pending guard.
        let baseline = await h.photos.report(), beforeDraft = h.flow.draft
        for language in SupportedAppLanguage.allCases {
            let nodes = SignUpRenderingProbe.nodes(
                BodyDataStepView(model: h.flow, photos: h.model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            XCTAssertEqual(nodes.filter { $0.identifier == "onboarding.photos.delete.error" }.count, 1)
            let retries = nodes.filter { $0.identifier == "onboarding.photos.delete.retry" }
            XCTAssertEqual(retries.count, 1,
                "Recovery cannot live only in Surface because Parent.route is already nil")
            XCTAssertEqual(retries.first?.label, language == .portugueseBrazil ? "Tentar novamente" : "Try again")
            XCTAssertTrue(retries.first?.isButton == true && retries.first?.isEnabled == true)
            XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.delete" },
                "Recovery is the original intent, not a second fresh DELETE command")
        }
        let rendered = await h.photos.report()
        XCTAssertEqual(rendered.attempts, baseline.attempts)
        XCTAssertEqual(rendered.stateReads, baseline.stateReads)
        XCTAssertEqual(rendered.repairs, baseline.repairs)
        XCTAssertEqual(h.flow.draft.bodyFatPercent, beforeDraft.bodyFatPercent)
        XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
        XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
        await h.model.retryDeletion() // the existing recovery action, never deletePhotos again
        XCTAssertTrue(h.model.deletion === d1)
        XCTAssertEqual(d1.phase, .ready)
        XCTAssertFalse(h.flow.hasPendingBodyPhotoDeletion)
        let recovered = await h.photos.report()
        XCTAssertEqual(recovered.attempts, baseline.attempts, "Known receipt remains GET-only")
        XCTAssertEqual(recovered.postDeleteReads, baseline.postDeleteReads + 1)
        for language in SupportedAppLanguage.allCases {
            let nodes = SignUpRenderingProbe.nodes(
                BodyDataStepView(model: h.flow, photos: h.model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.delete.retry" })
            XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.delete.error" })
        }
        try await h.drain()
    }

    func testOnlyTheCurrentRetainedFailedPoseOffersRetryAndGetOnlyStatusesDoNot() async throws {
        let h = try await PresentationHarness(manual: 23, failOnceAt: .create)
        do {
            await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
            let core = try XCTUnwrap(h.model.capture)
            let input = CaptureModelHarness.data // model peer bytes; no JPEG/SDK claim
            await h.model.producePhoto(pose: .front, channel: .gallery) { authorization in
                try await authorization.validate(); return input
            }
            XCTAssertEqual(core.phase, .failed(.offline))
            XCTAssertEqual(h.model.route, .capture)
            XCTAssertNil(core.state?.poses.first { $0.pose == .front }?.photo,
                "The uncertain CREATE may exist remotely while local GET still shows no slot")
            let failed = await h.peer.snapshot()
            XCTAssertEqual(failed.count(.stage), 1); XCTAssertEqual(failed.count(.create), 1)
            XCTAssertEqual(failed.count(.put), 0); XCTAssertEqual(failed.count(.complete), 0)
            for language in SupportedAppLanguage.allCases {
                let nodes = SignUpRenderingProbe.nodes(
                    SignupBodyPhotoCaptureView(photos: h.model)
                        .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                let retries = nodes.filter { $0.identifier == "onboarding.photos.capture.retry.front" }
                XCTAssertEqual(retries.count, 1)
                XCTAssertEqual(retries.first?.label, language == .portugueseBrazil ? "Tentar novamente" : "Try again")
                XCTAssertTrue(retries.first?.isButton == true && retries.first?.isEnabled == true)
                for pose in ["side", "back"] {
                    XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.capture.retry." + pose })
                }
            }
            let rendered = await h.peer.snapshot()
            XCTAssertEqual(rendered.calls, failed.calls)
            await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
                try await authorization.validate(); return input
            }
            XCTAssertEqual(core.phase, .ready, "A successful different pose replaces the global phase")
            XCTAssertEqual(h.model.route, .capture)
            for language in SupportedAppLanguage.allCases {
                let nodes = SignUpRenderingProbe.nodes(
                    SignupBodyPhotoCaptureView(photos: h.model)
                        .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                XCTAssertTrue(nodes.first { $0.identifier == "onboarding.photos.capture.retry.front" }?.isEnabled == true,
                    "Front local failure remains eligible when side succeeded; do not gate on global phase")
                XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.capture.retry.side" })
            }
            await h.model.retry(pose: .front) // existing retained attempt; no second producer/input
            try await h.model.waitForLocalCleanup()
            XCTAssertTrue(h.model.capture === core && core.isActive)
            XCTAssertEqual(core.state?.poses.first { $0.pose == .front }?.photo?.status, "read")
            let recovered = await h.peer.snapshot()
            XCTAssertEqual(recovered.count(.stage), 2)
            let frontAttempts = recovered.creates.filter { $0.payload.pose == .front }
            XCTAssertEqual(frontAttempts.count, 2)
            XCTAssertEqual(frontAttempts.first, frontAttempts.last)
            XCTAssertEqual(recovered.count(.put), 2); XCTAssertEqual(recovered.count(.complete), 2)
            for language in SupportedAppLanguage.allCases {
                let nodes = SignUpRenderingProbe.nodes(
                    SignupBodyPhotoCaptureView(photos: h.model)
                        .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                XCTAssertFalse(nodes.contains { $0.identifier.hasPrefix("onboarding.photos.capture.retry.") },
                    "A successful retained pipeline is not a retry eligibility signal")
            }
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 23)
            XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            let binds = await h.factory.snapshot()
            XCTAssertEqual(binds, [h.owner.userID])
            await stopRetryHarness(h)
        } catch { await stopRetryHarness(h); throw error }

        // Positive DTO statuses alone must not manufacture local retry intent.
        for fixture in [SignupPhotoViewFixture.captureTerminal, .captureWaiting] {
            let legacy = try await SignupPhotoViewHarness(fixture: fixture)
            do {
                await legacy.prepare()
                XCTAssertEqual(legacy.model.route, .capture)
                let baseline = await legacy.base.peer.snapshot()
                for language in SupportedAppLanguage.allCases {
                    let nodes = SignUpRenderingProbe.nodes(
                        SignupBodyPhotoCaptureView(photos: legacy.model)
                            .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                    XCTAssertFalse(nodes.contains { $0.identifier.hasPrefix("onboarding.photos.capture.retry.") })
                }
                let after = await legacy.base.peer.snapshot()
                XCTAssertEqual(after.calls, baseline.calls)
                await legacy.stop()
            } catch { await legacy.stop(); throw error }
        }
    }

    private func stopRetryHarness(_ h: PresentationHarness) async {
        h.model.invalidate()
        if let core = h.model.capture {
            await core.invalidateAndWaitForOwnedCaptureWork()
            do { try await core.waitForLocalCleanup() }
            catch { XCTFail("Synthetic scoped local cleanup failed: \(error)") }
        }
        h.clean()
    }

    private func photoRouteNodes(_ photos: SignupBodyPhotoPresentationModel,
                                language: SupportedAppLanguage) -> [SignUpRenderingProbe.Node] {
        SignUpRenderingProbe.nodes(Group {
            if photos.route == .capture { SignupBodyPhotoCaptureView(photos: photos) }
            else if photos.route == .result { SignupBodyPhotoResultView(photos: photos) }
        }.environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
    }
}
#endif
