#if DEBUG
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class SignupBodyPhotoFlowSurfaceRenderingTests: XCTestCase {
    func testSurfaceUsesItsHostNavigationControllerAndOneScrollWithoutLoadingAgain() async throws {
        let h = try await SignupPhotoViewHarness()
        do {
            await h.prepare()
            let parent = h.model
            let core = try XCTUnwrap(parent.capture)
            XCTAssertEqual(parent.route, .result)
            XCTAssertTrue(core.isActive && core.hasAcceptedConsent)
            let baseline = await h.base.peer.snapshot()
            let counter = SignupPhotoFlowCloseCounter()
            // This is the one stack supplied by the route host. The surface
            // must contribute only its scroll/content, never another stack.
            let host = UIHostingController(rootView: NavigationStack {
                SignupBodyPhotoFlowSurface(photos: parent, close: { counter.calls += 1 })
            })
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
            // UIKit containment requires a plain container, not adding native
            // hosting children directly under another SwiftUI hosting view.
            let container = UIViewController()
            window.rootViewController = container
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true; window.rootViewController = nil
                previousWindow?.makeKey()
            }
            container.addChild(host)
            container.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
            host.didMove(toParent: container)
            defer {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            settleHostLayout(host)
            let controllers = descendantControllers(host)
            let navigation = controllers.compactMap { $0 as? UINavigationController }
            XCTAssertEqual(navigation.count, 1,
                "Count actual controller descendants; invisible navigation bars are not stack metrology")
            let scrolls = descendantViews(host.view).compactMap { $0 as? UIScrollView }
            XCTAssertEqual(scrolls.count, 1, "One scroll belongs to this route surface")
            let scroll = try XCTUnwrap(scrolls.first,
                "EmptyView scaffold must fail by missing actual scroll, after real route prerequisite")
            XCTAssertGreaterThan(scroll.contentSize.height, BodyFlowSpacing.lg * 2,
                "A real current route must contribute content beyond the surface's padding")
            XCTAssertEqual(counter.calls, 0, "Rendering must not close, consent, confirm or select a mode")
            XCTAssertTrue(h.model === parent && parent.capture === core)
            XCTAssertEqual(parent.route, .result)
            XCTAssertNil(h.base.flow.draft.bodyFatPercent)
            XCTAssertNil(h.base.flow.draft.bodyFatOrigin)
            XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
            let after = await h.base.peer.snapshot(), binds = await h.factory.snapshot()
            XCTAssertEqual(after.calls, baseline.calls, "Surface does not GET/bind/poll/send/delete on appearance")
            XCTAssertEqual(binds, [h.base.owner.userID])
            await h.stop()
        } catch { await h.stop(); throw error }
    }

    // Swift 6 disallows RunLoop.run directly inside an async test. Keep
    // the exact native layout recipe in a synchronous MainActor helper.
    private func settleHostLayout(_ host: UIViewController) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        host.view.layoutIfNeeded()
    }

    private func descendantControllers(_ root: UIViewController) -> [UIViewController] {
        var visited: Set<ObjectIdentifier> = []
        var result: [UIViewController] = []
        func visit(_ controller: UIViewController) {
            guard visited.insert(ObjectIdentifier(controller)).inserted else { return }
            result.append(controller)
            controller.children.forEach(visit)
        }
        visit(root)
        return result
    }

    private func descendantViews(_ root: UIView) -> [UIView] {
        var result: [UIView] = []
        func visit(_ view: UIView) { result.append(view); view.subviews.forEach(visit) }
        visit(root)
        return result
    }
}

@MainActor
private final class SignupPhotoFlowCloseCounter { var calls = 0 }
#endif
