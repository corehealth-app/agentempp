#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// Native result-to-retake controls on the same retained Parent/Core.
@MainActor
final class SignupBodyPhotoResultRetakeRenderingTests: XCTestCase {
    func testEveryCurrentResultOffersExplicitRetakeAndTheSameCoreRendersPoseActionsWithoutNewReadsInBothLanguages() async throws {
        for fixture in [SignupPhotoViewFixture.valid, .unusable, .legacyReadings] {
            let h = try await SignupPhotoViewHarness(fixture: fixture, camera: .synthetic)
            do {
                await h.prepare()
                let core = try XCTUnwrap(h.model.capture)
                XCTAssertEqual(h.model.route, .result)
                let baseline = await h.base.peer.snapshot()
                for language in SupportedAppLanguage.allCases {
                    let result = SignUpRenderingProbe.nodes(
                        SignupBodyPhotoResultView(photos: h.model)
                            .environment(\.locale, language.formattingLocale)
                            .environment(\.scenePhase, .active), width: 393, height: 3_000)
                    let button = try XCTUnwrap(result.first { $0.identifier == "onboarding.photos.result.retake" },
                        "An unusable/old-readings result must offer retake as well as manual/skip")
                    XCTAssertEqual(result.filter { $0.identifier == "onboarding.photos.result.retake" }.count, 1)
                    XCTAssertEqual(button.label, language == .portugueseBrazil ? "Refazer fotos" : "Retake photos")
                    XCTAssertTrue(button.isEnabled)
                    XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                }
                XCTAssertTrue(h.model.beginRetake())
                XCTAssertEqual(h.model.route, .capture)
                XCTAssertTrue(h.model.capture === core && core.hasAcceptedConsent)
                for language in SupportedAppLanguage.allCases {
                    let captures = SignUpRenderingProbe.nodes(
                        SignupBodyPhotoCaptureView(photos: h.model, onCamera: { _ in }, onGallery: { _ in })
                            .environment(\.locale, language.formattingLocale)
                            .environment(\.scenePhase, .active), width: 393, height: 3_000)
                    for pose in SignupBodyPhotoPose.allCases {
                        XCTAssertNotNil(captures.first { $0.identifier == "onboarding.photos.capture.camera." + pose.rawValue })
                        XCTAssertNotNil(captures.first { $0.identifier == "onboarding.photos.capture.gallery." + pose.rawValue })
                    }
                    XCTAssertFalse(captures.contains { $0.identifier == "onboarding.photos.result.confirm" })
                }
                let after = await h.base.peer.snapshot(), binds = await h.factory.snapshot()
                XCTAssertEqual(after.calls, baseline.calls)
                XCTAssertEqual(binds, [h.base.owner.userID])
                XCTAssertNil(h.base.flow.draft.bodyFatPercent)
                XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
                await h.stop()
            } catch { await h.stop(); throw error }
        }
    }
}
#endif
