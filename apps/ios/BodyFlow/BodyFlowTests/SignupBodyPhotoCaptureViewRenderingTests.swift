#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class SignupBodyPhotoCaptureViewRenderingTests: XCTestCase {
    func testThreeKnownPoseStatesUseTheExistingCoreWithoutExtraReadsStackOrPercentage() async throws {
        for fixture in [SignupPhotoViewFixture.captureTerminal, .captureWaiting] {
            let h = try await SignupPhotoViewHarness(fixture: fixture, manual: 23)
            do {
                await h.prepare()
                let core = try XCTUnwrap(h.model.capture)
                XCTAssertEqual(h.model.route, .capture)
                if fixture == .captureWaiting {
                    let armed = await core.waitForPollingEvent()
                    XCTAssertTrue(armed, "Actual existing Core poll must be armed before measuring view reads")
                }
                let baseline = await h.base.peer.snapshot()
                let statuses = fixture == .captureTerminal
                    ? ["read", "unreadable", "reading_failed"] : ["uploaded", "reading", "pending_upload"]
                for language in SupportedAppLanguage.allCases {
                    let nodes = SignUpRenderingProbe.nodes(
                        SignupBodyPhotoCaptureView(photos: h.model).environment(\.locale, language.formattingLocale),
                        width: 393, height: 3_000)
                    let rows = try SignupBodyPhotoPose.allCases.map { pose in
                        try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.capture.pose." + pose.rawValue })
                    }
                    XCTAssertEqual(rows.map(\.frame.minY), rows.map(\.frame.minY).sorted())
                    for (pose, status) in zip(SignupBodyPhotoPose.allCases, statuses) {
                        let id = "onboarding.photos.capture.status." + pose.rawValue + "." + status
                        let node = try XCTUnwrap(nodes.first { $0.identifier == id })
                        XCTAssertFalse(node.label.isEmpty)
                    }
                    let progress = try NSRegularExpression(pattern: "\\b[0-9]+(?:[.,][0-9]+)?\\s*%")
                    XCTAssertFalse(nodes.contains { node in
                        progress.firstMatch(in: node.label, range: NSRange(node.label.startIndex..., in: node.label)) != nil
                    }, "Capture wait has no invented numeric progress percentage")
                    if fixture == .captureTerminal {
                        XCTAssertFalse(nodes.first { $0.identifier == "onboarding.photos.capture.retry.back" }?.isEnabled == true,
                            "GET-only reading_failed has no retained pipeline; don't promise a dead retry")
                    }
                    XCTAssertFalse(nodes.contains { $0.identifier == "onboarding.photos.result.confirm" })
                }
                let live = PremiumRenderingTestSupport.liveAccessibilityHost(SignupBodyPhotoCaptureView(photos: h.model), width: 393)
                XCTAssertTrue(Self.navigationControllers(in: live.nativeViews(UIView.self)).isEmpty, "Content does not add its own native navigation controller")
                XCTAssertTrue(live.nativeViews(UIProgressView.self).isEmpty, "Indeterminate waiting is not numeric progress")
                live.detach()
                let after = await h.base.peer.snapshot(), binds = await h.factory.snapshot()
                XCTAssertEqual(after.calls, baseline.calls, "View appearances don't issue GET/retry/create or run another poll")
                XCTAssertEqual(binds, [h.base.owner.userID])
                XCTAssertEqual(h.base.flow.draft.bodyFatPercent, 23)
                XCTAssertEqual(h.base.flow.draft.bodyFatOrigin, .typed)
                XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
                await h.stop()
            } catch { await h.stop(); throw error }
        }
    }
    /// Real responder/containment objects under this hosted view. A hidden
    /// navigation bar is not a count of NavigationStacks. No private class names.
    private static func navigationControllers(in inspectedViews: [UIView]) -> [UINavigationController] {
        let inspectedIDs = Set(inspectedViews.map { ObjectIdentifier($0) })
        var seenControllers: Set<ObjectIdentifier> = []
        var found: [UINavigationController] = []
        func collect(_ controller: UIViewController) {
            guard seenControllers.insert(ObjectIdentifier(controller)).inserted else { return }
            if let navigation = controller as? UINavigationController,
               let nativeView = navigation.viewIfLoaded,
               inspectedIDs.contains(ObjectIdentifier(nativeView)), nativeView.window != nil {
                found.append(navigation)
            }
            controller.children.forEach(collect)
        }
        for nativeView in inspectedViews {
            var responder: UIResponder? = nativeView
            var visited: Set<ObjectIdentifier> = []
            while let current = responder,
                  visited.insert(ObjectIdentifier(current)).inserted {
                if let controller = current as? UIViewController { collect(controller) }
                responder = current.next
            }
        }
        return found
    }
}
#endif
