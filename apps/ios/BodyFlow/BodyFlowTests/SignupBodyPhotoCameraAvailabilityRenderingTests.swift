#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class SignupBodyPhotoCameraAvailabilityRenderingTests: XCTestCase {
    func testNoCameraUnavailableDeniedAndAllowedKeepGalleryAndNeverAskOnAppearanceInBothLanguages() async throws {
        for scenario in 0..<5 {
            let requests = SignupCameraAppearanceCounter()
            let camera = MealCameraAccess(origin: scenario == 0 ? .none : .device,
                isAvailable: { scenario != 0 && scenario != 1 },
                permission: { scenario < 3 ? .denied : (scenario == 3 ? .notAsked : .authorized) },
                requestAccess: { requests.record(); return false })
            let h = try await SignupPhotoViewHarness(fixture: .captureTerminal, camera: camera)
            do {
                await h.prepare()
                let core = try XCTUnwrap(h.model.capture), baseline = await h.base.peer.snapshot()
                XCTAssertEqual(h.model.route, .capture)
                for language in SupportedAppLanguage.allCases {
                    let nodes = SignUpRenderingProbe.nodes(SignupBodyPhotoCaptureView(photos: h.model,
                        onCamera: { _ in XCTFail("Rendering cannot invoke camera") },
                        onGallery: { _ in XCTFail("Rendering cannot invoke gallery") })
                        .environment(\.locale, language.formattingLocale)
                        .environment(\.scenePhase, .active), width: 393, height: 3_000)
                    for pose in SignupBodyPhotoPose.allCases {
                        let cameraNode = nodes.first { $0.identifier == "onboarding.photos.capture.camera." + pose.rawValue }
                        if scenario < 2 { XCTAssertNil(cameraNode) }
                        else { XCTAssertNotNil(cameraNode); XCTAssertEqual(cameraNode?.isEnabled, scenario >= 3) }
                        XCTAssertTrue(nodes.first { $0.identifier == "onboarding.photos.capture.gallery." + pose.rawValue }?.isEnabled == true)
                    }
                    let hint = nodes.first { $0.identifier == "onboarding.photos.capture.camera-help" }
                    if scenario < 3 {
                        let expected = language == .portugueseBrazil
                            ? (scenario < 2 ? "A câmera não está disponível. Você pode escolher as fotos da galeria." : "A câmera está bloqueada. Escolha fotos da galeria ou permita a câmera nos Ajustes.")
                            : (scenario < 2 ? "The camera is unavailable. You can choose photos from your library." : "Camera access is blocked. Choose library photos or allow the camera in Settings.")
                        XCTAssertEqual(hint?.label, expected)
                    } else { XCTAssertNil(hint) }
                }
                XCTAssertEqual(requests.count, 0)
                let after = await h.base.peer.snapshot(), binds = await h.factory.snapshot()
                XCTAssertEqual(after.calls, baseline.calls)
                XCTAssertEqual(binds, [h.base.owner.userID])
                XCTAssertTrue(h.model.capture === core && core.isActive)
                XCTAssertNil(h.base.flow.draft.bodyFatPercent)
                await h.stop()
            } catch { await h.stop(); throw error }
        }
    }
}

private final class SignupCameraAppearanceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    var count: Int { lock.withLock { requests } }
    func record() { lock.withLock { requests += 1 } }
}
#endif
