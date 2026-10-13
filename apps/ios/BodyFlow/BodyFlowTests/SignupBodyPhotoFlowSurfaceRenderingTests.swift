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

#if DEBUG
extension SignupBodyPhotoFlowSurfaceRenderingTests {
    func testThirdActualCaptureOpensResultAtTopAndSameResultReadKeepsTheReadersPositionInBothLanguages() async throws {
        for language in [SupportedAppLanguage.portugueseBrazil, .englishUnitedStates] {
            let h = try await PresentationHarness()
            h.flow.updateLocaleIdentifier(language.rawValue) // actual consent/draft locale guard
            let document = try XCTUnwrap(SignupBodyPhotoCaptureFixtureConsent.document(for: language.rawValue))
            let fixture = SignupBodyPhotoCaptureFixture(mode: .demo, buildFlavor: .debug,
                directory: h.cleanup.folder.appendingPathComponent("route-scroll-fixture"),
                allowedOwnerID: h.owner.userID, document: document)
            let scope = try await fixture.capability.scoped(h.owner.userID)
            let factory = PresentationFactoryPeer(scope: scope)
            let box = h.ownerBox, clock = h.clock
            let parent = SignupBodyPhotoPresentationModel(flow: h.flow, ownerToken: h.owner,
                capability: factory.capability, timeProvider: PresentationFixedTime(now: PresentationHarness.now),
                keyProvider: DeterministicIdempotencyKeyProvider(prefix: "route-scroll-" + language.rawValue),
                pollingTiming: .init(elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }),
                isCurrentOwner: { $0 == box.current })
            defer { parent.invalidate(); h.clean() }
            await parent.load(); parent.select(.photos); await parent.acceptConsent()
            let core = try XCTUnwrap(parent.capture)
            XCTAssertTrue(core.isActive && core.hasAcceptedConsent)
            for pose in [SignupBodyPhotoPose.front, .side] {
                await scrollFixtureCapture(parent, pose: pose)
            }
            try await parent.waitForLocalCleanup()
            XCTAssertEqual(parent.route, .capture)
            XCTAssertNil(core.state?.estimate)
            let before = await fixture.report()
            XCTAssertEqual(before.creates, 2); XCTAssertEqual(before.uploads, 2)
            XCTAssertEqual(before.completes, 2)
            let counter = SignupPhotoFlowCloseCounter()
            let host = UIHostingController(rootView: NavigationStack {
                SignupBodyPhotoFlowSurface(photos: parent, close: { counter.calls += 1 })
            }.environment(\.locale, language.formattingLocale)
                .environment(\.dynamicTypeSize, .large)
                .environment(\.accessibilityEnabled, true))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
            let previousWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            // Declared native viewport; not a pixel reproduction of the PNG.
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
            let container = UIViewController()
            window.rootViewController = container; window.makeKeyAndVisible()
            defer {
                window.isHidden = true; window.rootViewController = nil
                previousWindow?.makeKey()
            }
            container.addChild(host); container.view.addSubview(host.view)
            host.view.frame = window.bounds; host.didMove(toParent: container)
            defer {
                host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
            }
            settleHostLayout(host)
            let navigation = try XCTUnwrap(descendantControllers(host).compactMap { $0 as? UINavigationController }.first)
            XCTAssertEqual(descendantControllers(host).compactMap { $0 as? UINavigationController }.count, 1)
            let captureScroll = try onlySurfaceScroll(host)
            let closeBefore = try fixedCloseFrame(host, scroll: captureScroll, window: window)
            let captureMaximum = maximumOffset(captureScroll)
            // A missing overflow is a fixture/setup error, not the scroll RED.
            guard captureMaximum > 80 else {
                XCTFail("Native fixture must make the back-pose area require a positive scroll offset: \(language.rawValue)")
                throw SignupPhotoRouteScrollFixtureError.noCaptureOverflow
            }
            captureScroll.setContentOffset(CGPoint(x: 0, y: captureMaximum), animated: false)
            settleHostLayout(host)
            XCTAssertGreaterThan(captureScroll.contentOffset.y + captureScroll.adjustedContentInset.top, 80)
            XCTAssertEqual(parent.route, .capture)
            XCTAssertEqual(try fixedCloseFrame(host, scroll: captureScroll, window: window), closeBefore)

            // This actual Parent -> D1 -> Core -> staged JPEG -> local uploader
            // completes the third current pose. No retake stub/route injection.
            await scrollFixtureCapture(parent, pose: .back)
            try await parent.waitForLocalCleanup()
            XCTAssertEqual(parent.route, .result)
            XCTAssertTrue(parent.capture === core && core.isActive && core.hasAcceptedConsent)
            XCTAssertEqual(core.state?.estimate?.readings?.map(\.bodyFatPercent),
                [Decimal(18), Decimal(24), Decimal(30)])
            XCTAssertNil(h.flow.draft.bodyFatPercent)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            settleHostLayout(host)
            let resultScroll = try onlySurfaceScroll(host)
            // Result begins with the first disclaimer in the current source.
            // Public UIScroll geometry is the native oracle; no private classes
            // or fabricated AX node from inside SwiftUI ScrollView.
            XCTAssertEqual(resultScroll.contentOffset.y, -resultScroll.adjustedContentInset.top, accuracy: 1,
                "Semantic capture -> result must begin at its content top: \(language.rawValue)")
            XCTAssertEqual(try fixedCloseFrame(host, scroll: resultScroll, window: window), closeBefore)
            XCTAssertTrue(descendantControllers(host).contains { $0 === navigation })

            let maximum = maximumOffset(resultScroll)
            guard maximum > 80 else {
                XCTFail("The result must have real overflow for the unchanged-route control")
                throw SignupPhotoRouteScrollFixtureError.noResultOverflow
            }
            let readerOffset = min(maximum, 120)
            resultScroll.setContentOffset(CGPoint(x: 0, y: readerOffset), animated: false)
            settleHostLayout(host)
            let positioned = resultScroll.contentOffset.y
            await core.load() // actual authoritative read, still the same result route
            XCTAssertEqual(parent.route, .result)
            settleHostLayout(host)
            let rereadScroll = try onlySurfaceScroll(host)
            XCTAssertEqual(rereadScroll.contentOffset.y, positioned, accuracy: 1,
                "An unchanged result read must not take the reader back to the top: \(language.rawValue)")
            XCTAssertEqual(try fixedCloseFrame(host, scroll: rereadScroll, window: window), closeBefore)
            XCTAssertTrue(parent.capture === core && core.isActive)
            XCTAssertEqual(counter.calls, 0)
            let binds = await factory.snapshot(), after = await fixture.report()
            XCTAssertEqual(binds, [h.owner.userID])
            XCTAssertEqual(after.consents, 1); XCTAssertEqual(after.creates, 3)
            XCTAssertEqual(after.uploads, 3); XCTAssertEqual(after.completes, 3)
            XCTAssertEqual(after.deletes, 0)
            XCTAssertNil(h.model.capture, "The unused base Parent never binds another scope")
            XCTAssertNil(h.flow.draft.bodyFatPercent)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
        }
    }

    private func scrollFixtureCapture(_ parent: SignupBodyPhotoPresentationModel, pose: SignupBodyPhotoPose) async {
        let input = DemoMealCamera.samplePhoto() // actual generated JPEG, synthetic only
        await parent.producePhoto(pose: pose, channel: .camera) { authorization in
            try await authorization.validate()
            return input
        }
    }

    private func onlySurfaceScroll(_ host: UIViewController) throws -> UIScrollView {
        let scrolls = descendantViews(host.view).compactMap { $0 as? UIScrollView }
        XCTAssertEqual(scrolls.count, 1, "Exactly the Surface-owned public UIScrollView")
        return try XCTUnwrap(scrolls.first)
    }

    private func maximumOffset(_ scroll: UIScrollView) -> CGFloat {
        max(-scroll.adjustedContentInset.top,
            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
    }

    private func fixedCloseFrame(_ host: UIViewController, scroll: UIScrollView, window: UIWindow) throws -> CGRect {
        UIAccessibility.post(notification: .screenChanged, argument: host.view)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let nodes = SignUpRenderingProbe.nodes(in: host.view)
        let close = try XCTUnwrap(nodes.first { $0.identifier == "onboarding.photos.flow.close" },
            "The real fixed close is outside the SwiftUI scroll and readable by the existing probe")
        XCTAssertTrue(close.isButton && close.isEnabled)
        XCTAssertGreaterThan(close.frame.width, 0); XCTAssertGreaterThan(close.frame.height, 0)
        let viewport = scroll.convert(scroll.bounds, to: window)
        let screenViewport = window.convert(viewport, to: nil)
        XCTAssertLessThanOrEqual(close.frame.maxY, screenViewport.minY + 1)
        return close.frame
    }
}
private enum SignupPhotoRouteScrollFixtureError: Error { case noCaptureOverflow, noResultOverflow }
#endif
