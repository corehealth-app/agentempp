#if DEBUG
import Foundation
import SwiftUI
import XCTest
@testable import BodyFlow

/// Negative UI eligibility control after an actual completed local pipeline.
/// Existing public-DTO projection scripts the known worker terminal status;
/// it does not claim a live worker/provider result or restart capability.
@MainActor
final class SignupBodyPhotoRetainedTerminalRetryRenderingTests: XCTestCase {
    func testRetainedCompletedReadingFailedPhotoOffersNewChoiceAndNoRetry() async throws {
        let h = try await PresentationHarness(manual: 23)
        do {
            await h.model.load()
            h.model.select(.photos)
            await h.model.acceptConsent()
            let core = try XCTUnwrap(h.model.capture)
            XCTAssertTrue(core.isActive && core.hasAcceptedConsent)
            await h.peer.setStateProjection { raw in
                let poses = raw.poses.map { slot -> SignupBodyPhotoSlot in
                    guard slot.pose == .front, let photo = slot.photo else { return slot }
                    return SignupBodyPhotoSlot(pose: slot.pose,
                        photo: SignupBodyPhoto(id: photo.id, status: "reading_failed", createdAt: photo.createdAt))
                }
                return SignupBodyPhotoState(available: raw.available, unavailableReason: raw.unavailableReason,
                    consent: raw.consent, minimumAge: raw.minimumAge, poses: poses,
                    estimate: raw.estimate, remainingUploads: raw.remainingUploads)
            }
            let input = CaptureModelHarness.data
            await h.model.producePhoto(pose: .front, channel: .gallery) { authorization in
                try await authorization.validate()
                return input
            }
            try await h.model.waitForLocalCleanup()
            XCTAssertTrue(h.model.capture === core && core.isActive)
            XCTAssertEqual(h.model.route, .capture)
            XCTAssertEqual(core.phase, .failed(.readingFailed))
            let front = try XCTUnwrap(core.state?.poses.first { $0.pose == .front }?.photo)
            XCTAssertEqual(front.status, "reading_failed")
            let completed = await h.peer.snapshot()
            XCTAssertEqual(completed.count(.stage), 1)
            XCTAssertEqual(completed.count(.create), 1)
            XCTAssertEqual(completed.count(.put), 1)
            XCTAssertEqual(completed.count(.complete), 1)
            let completion = try XCTUnwrap(completed.completes.first)
            XCTAssertEqual(completion.payload.assetID, front.id,
                "The terminal GET belongs to the photo whose completion already succeeded")
            for language in SupportedAppLanguage.allCases {
                let nodes = SignUpRenderingProbe.nodes(
                    SignupBodyPhotoCaptureView(photos: h.model,
                        onGallery: { _ in XCTFail("Rendering cannot dispatch a source producer") })
                        .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
                XCTAssertEqual(nodes.filter {
                    $0.identifier == "onboarding.photos.capture.status.front.reading_failed"
                }.count, 1)
                XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.capture.retry.front" },
                    "A retained completed pipeline does not authorize restarting a failed official reading")
                let choices = nodes.filter { $0.identifier == "onboarding.photos.capture.gallery.front" }
                XCTAssertEqual(choices.count, 1)
                XCTAssertTrue(choices.first?.isButton == true && choices.first?.isEnabled == true,
                    "The current owner can choose another input instead of a misleading GET-only Retry")
            }
            let rendered = await h.peer.snapshot(), binds = await h.factory.snapshot()
            XCTAssertEqual(rendered.calls, completed.calls, "Rendering must not GET/stage/reprocess")
            XCTAssertEqual(binds, [h.owner.userID])
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 23)
            XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            await stop(h)
        } catch { await stop(h); throw error }
    }

    private func stop(_ h: PresentationHarness) async {
        let core = h.model.capture
        h.model.invalidate()
        if let core {
            await core.invalidateAndWaitForOwnedCaptureWork()
            do { try await core.waitForLocalCleanup() }
            catch { XCTFail("Synthetic scoped cleanup failed: \(error)") }
        }
        h.clean()
    }
}
#endif
