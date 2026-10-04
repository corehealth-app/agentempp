import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

/// The looping indicators (Flow "typing" dots, the opening's stair loader)
/// are layer animations: they run only in a window, only when motion is
/// allowed, and their still frame is a complete drawing.
@MainActor
@Suite("Layer animations")
struct BodyFlowLayerAnimationsTests {
    private func hosted<V: UIView>(_ view: V) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.addSubview(view)
        window.isHidden = false
        return window
    }

    @Test
    func typingDotsBounceOneAfterTheOtherOnlyWhenAllowed() {
        let view = BodyFlowTypingDotsView()
        #expect(view.dots.count == 3)
        #expect(view.intrinsicContentSize == BodyFlowTypingDotsMetrics.size)

        // Not in a window: nothing runs even when allowed.
        view.isAnimating = true
        #expect(!view.isLooping)
        #expect(view.dots.allSatisfy { $0.layer.animation(forKey: BodyFlowTypingDotsView.animationKey) == nil })

        let window = hosted(view)
        #expect(view.isLooping)
        let groups = view.dots.compactMap {
            $0.layer.animation(forKey: BodyFlowTypingDotsView.animationKey) as? CAAnimationGroup
        }
        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.repeatCount == .infinity && $0.duration == BodyFlowTypingDotsMetrics.period })
        // Each dot starts after the previous one.
        #expect(abs(groups[1].beginTime - groups[0].beginTime - BodyFlowTypingDotsMetrics.stagger) < 1e-6)
        #expect(groups[2].beginTime > groups[1].beginTime)

        // Reduce Motion / Low Power: still dots.
        view.isAnimating = false
        #expect(!view.isLooping)
        #expect(view.dots.allSatisfy { $0.layer.animation(forKey: BodyFlowTypingDotsView.animationKey) == nil })
        window.isHidden = true
    }

    @Test
    func typingDotsFitTheirBounce() {
        let metrics = BodyFlowTypingDotsMetrics.self
        #expect(metrics.size.width == 3 * metrics.dotDiameter + 2 * metrics.dotSpacing)
        #expect(metrics.size.height == metrics.dotDiameter + metrics.rise)
        #expect(metrics.offsets().min() == -metrics.rise)
        #expect(metrics.offsets().first == 0 && metrics.offsets().last == 0)
        // The whole wave fits one period: the last dot is back before it restarts.
        #expect(Double(metrics.dotCount - 1) * metrics.stagger + 0.45 * metrics.period <= metrics.period)
    }

    @Test
    func stairLoaderStaysInsideItsBoxAndTheBallLandsOnAStep() {
        let metrics = BodyFlowStairLoaderMetrics.self
        let box = CGRect(origin: .zero, size: metrics.size)
        for origin in metrics.stepOrigins {
            #expect(box.contains(CGRect(origin: origin, size: metrics.stepSize)))
        }
        // The ball rests on the middle step and its bounce stays in the box.
        let resting = metrics.ballRestingCenter
        #expect(resting.x == metrics.stepOrigins[1].x + metrics.stepSize.width / 2)
        #expect(resting.y + metrics.ballDiameter / 2 == metrics.stepOrigins[1].y)
        #expect(resting.y - metrics.ballDiameter / 2 - metrics.bounceHeight >= 0)
        // One full bounce per step: the staircase moves one stride while the
        // ball goes up and comes down.
        #expect(metrics.stepPeriod == metrics.halfBounce * 2)
        #expect(metrics.stepOrigins[1].x - metrics.stepOrigins[0].x == metrics.stride.width)
        #expect(metrics.stepOrigins[1].y - metrics.stepOrigins[0].y == metrics.stride.height)
    }

    @Test
    func stairLoaderLoopsOnlyWhenAllowedAndRestsOnAStillFrame() {
        let view = BodyFlowStairLoaderView()
        let key = BodyFlowStairLoaderView.animationKey
        #expect(view.steps.count == 4)
        let window = hosted(view)
        #expect(!view.isLooping)
        #expect(view.ball.layer.animation(forKey: key) == nil)

        view.isAnimating = true
        #expect(view.isLooping)
        let bounce = view.ball.layer.animation(forKey: key) as? CAAnimationGroup
        #expect(bounce?.autoreverses == true)
        #expect(bounce?.repeatCount == .infinity)
        #expect(bounce?.duration == BodyFlowStairLoaderMetrics.halfBounce)
        #expect(view.steps.allSatisfy { $0.layer.animation(forKey: key) != nil })

        view.isAnimating = false
        #expect(view.ball.layer.animation(forKey: key) == nil)
        #expect(view.steps.allSatisfy { $0.layer.animation(forKey: key) == nil })
        // Still frame: three visible steps at their origins, the fourth hidden.
        #expect(view.steps.prefix(3).map(\.frame.origin) == BodyFlowStairLoaderMetrics.stepOrigins)
        #expect(view.steps[3].layer.opacity == 0)
        window.isHidden = true
    }
}
