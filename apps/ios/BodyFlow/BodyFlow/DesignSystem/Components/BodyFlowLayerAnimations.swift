import SwiftUI
import UIKit

/// Two looping indicators drawn with Core Animation: the "Flow is typing"
/// dots and the stair loader of the opening. A third one, the liquid loader
/// of the staged loading block, lives in `BodyFlowLiquidLoader.swift` on the
/// same `BodyFlowLoopingView`.
///
/// Why Core Animation and not a SwiftUI `repeatForever`/`TimelineView`: a
/// SwiftUI loop re-evaluates the view every frame on the main thread, which
/// costs battery for as long as the wait lasts and keeps the app permanently
/// "animating" for XCTest (each idle wait then stalls 60 s — the lesson of
/// the skeleton shimmer, 2026-10-03). A layer animation is handed to the
/// render server once, like the system activity indicator, and costs the
/// main thread nothing.
///
/// Both are decorative: the screen that hosts them carries the accessible
/// text. Under Reduce Motion, Low Power or a hot device they draw one still
/// frame.

// MARK: - Typing dots

enum BodyFlowTypingDotsMetrics {
    nonisolated static let dotCount = 3
    nonisolated static let dotDiameter: CGFloat = 8
    nonisolated static let dotSpacing: CGFloat = 6
    /// How far a dot rises at the top of its bounce.
    nonisolated static let rise: CGFloat = 5
    /// One full wave: every dot bounces once, one after the other.
    nonisolated static let period: CFTimeInterval = 1.2
    /// Delay between one dot and the next.
    nonisolated static let stagger: CFTimeInterval = 0.16
    nonisolated static let restingOpacity: Float = 0.45

    nonisolated static var size: CGSize {
        CGSize(
            width: CGFloat(dotCount) * dotDiameter + CGFloat(dotCount - 1) * dotSpacing,
            height: dotDiameter + rise
        )
    }

    /// A dot bounces during the first 45 % of the wave and rests after it.
    nonisolated static let keyTimes: [NSNumber] = [0, 0.2, 0.45, 1]
    nonisolated static func offsets() -> [CGFloat] { [0, -rise, 0, 0] }
    nonisolated static func opacities() -> [Float] { [restingOpacity, 1, restingOpacity, restingOpacity] }
}

/// Three dots that bounce one after the other, as in a messaging app while
/// the other side is typing.
struct BodyFlowTypingDots: UIViewRepresentable {
    var role: BodyFlowColor.Role = .textSecondary
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy

    func makeUIView(context: Context) -> BodyFlowTypingDotsView {
        let view = BodyFlowTypingDotsView()
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: BodyFlowTypingDotsView, context: Context) {
        view.dotColor = UIColor(BodyFlowColor.color(role))
        view.isAnimating = !(reduceMotion || !visualPolicy.allowsMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BodyFlowTypingDotsView, context: Context) -> CGSize? {
        BodyFlowTypingDotsMetrics.size
    }
}

final class BodyFlowTypingDotsView: BodyFlowLoopingView {
    static let animationKey = "bodyflow.typing"
    private(set) var dots: [UIView] = []

    var dotColor: UIColor = .secondaryLabel {
        didSet { dots.forEach { $0.backgroundColor = dotColor } }
    }

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: BodyFlowTypingDotsMetrics.size))
        let metrics = BodyFlowTypingDotsMetrics.self
        for index in 0..<metrics.dotCount {
            let dot = UIView(frame: CGRect(
                x: CGFloat(index) * (metrics.dotDiameter + metrics.dotSpacing),
                y: metrics.rise,
                width: metrics.dotDiameter,
                height: metrics.dotDiameter
            ))
            dot.layer.cornerRadius = metrics.dotDiameter / 2
            dot.backgroundColor = dotColor
            dot.layer.opacity = metrics.restingOpacity
            addSubview(dot)
            dots.append(dot)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { BodyFlowTypingDotsMetrics.size }

    override func startLoop() {
        let metrics = BodyFlowTypingDotsMetrics.self
        let start = layer.convertTime(CACurrentMediaTime(), from: nil)
        for (index, dot) in dots.enumerated() {
            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = metrics.offsets()
            bounce.keyTimes = metrics.keyTimes
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = metrics.opacities()
            fade.keyTimes = metrics.keyTimes
            let group = CAAnimationGroup()
            group.animations = [bounce, fade]
            group.duration = metrics.period
            group.repeatCount = .infinity
            group.beginTime = start + Double(index) * metrics.stagger
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            dot.layer.add(group, forKey: Self.animationKey)
        }
    }

    override func stopLoop() {
        dots.forEach { $0.layer.removeAnimation(forKey: Self.animationKey) }
    }
}

// MARK: - Stair loader

/// A ball that climbs an endless staircase: it bounces in place while the
/// steps slide down and to the left under it, a new one fading in at the top
/// and the last one fading out.
enum BodyFlowStairLoaderMetrics {
    nonisolated static let size = CGSize(width: 120, height: 132)
    nonisolated static let stepSize = CGSize(width: 44, height: 7)
    /// From one step to the next: left and down.
    nonisolated static let stride = CGSize(width: -35, height: 38)
    /// Top-left corner of the newest (top-right) step.
    nonisolated static let firstStepOrigin = CGPoint(x: 76, y: 42)
    nonisolated static let ballDiameter: CGFloat = 26
    /// How high the ball leaves the step it bounced on.
    nonisolated static let bounceHeight: CGFloat = 46
    /// The ball goes up in `halfBounce` and comes down in `halfBounce`; in
    /// that same time every step moves one stride.
    nonisolated static let halfBounce: CFTimeInterval = 0.5
    nonisolated static var stepPeriod: CFTimeInterval { halfBounce * 2 }
    nonisolated static let restingStepOpacity: Float = 0.9

    /// Origins of the three visible steps, newest first.
    nonisolated static var stepOrigins: [CGPoint] {
        (0..<3).map { index in
            CGPoint(
                x: firstStepOrigin.x + stride.width * CGFloat(index),
                y: firstStepOrigin.y + stride.height * CGFloat(index)
            )
        }
    }

    /// The ball rests on the middle step, centered on it.
    nonisolated static var ballRestingCenter: CGPoint {
        let step = stepOrigins[1]
        return CGPoint(x: step.x + stepSize.width / 2, y: step.y - ballDiameter / 2)
    }
}

struct BodyFlowStairLoader: UIViewRepresentable {
    var ballRole: BodyFlowColor.Role = .accentCoral
    var stepRole: BodyFlowColor.Role = .onHero
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy

    func makeUIView(context: Context) -> BodyFlowStairLoaderView {
        let view = BodyFlowStairLoaderView()
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: BodyFlowStairLoaderView, context: Context) {
        view.ball.backgroundColor = UIColor(BodyFlowColor.color(ballRole))
        let stepColor = UIColor(BodyFlowColor.color(stepRole))
        view.steps.forEach { $0.backgroundColor = stepColor }
        view.isAnimating = !(reduceMotion || !visualPolicy.allowsMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BodyFlowStairLoaderView, context: Context) -> CGSize? {
        BodyFlowStairLoaderMetrics.size
    }
}

final class BodyFlowStairLoaderView: BodyFlowLoopingView {
    static let animationKey = "bodyflow.stairs"
    let ball = UIView()
    /// Four layers for three visible steps: [0] fades in at the top, [1] and
    /// [2] slide one stride, [3] fades out at the bottom.
    private(set) var steps: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: BodyFlowStairLoaderMetrics.size))
        let metrics = BodyFlowStairLoaderMetrics.self
        let origins = metrics.stepOrigins
        for index in 0..<4 {
            let step = UIView(frame: CGRect(origin: origins[min(index, 2)], size: metrics.stepSize))
            step.layer.cornerRadius = metrics.stepSize.height / 2
            step.layer.opacity = index == 3 ? 0 : metrics.restingStepOpacity
            addSubview(step)
            steps.append(step)
        }
        ball.frame = CGRect(
            x: metrics.ballRestingCenter.x - metrics.ballDiameter / 2,
            y: metrics.ballRestingCenter.y - metrics.ballDiameter / 2,
            width: metrics.ballDiameter,
            height: metrics.ballDiameter
        )
        ball.layer.cornerRadius = metrics.ballDiameter / 2
        // Squash and stretch pivot on the foot of the ball.
        ball.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        ball.layer.position = CGPoint(
            x: metrics.ballRestingCenter.x,
            y: metrics.ballRestingCenter.y + metrics.ballDiameter / 2
        )
        addSubview(ball)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { BodyFlowStairLoaderMetrics.size }

    override func startLoop() {
        let metrics = BodyFlowStairLoaderMetrics.self
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)

        // Ball: up and down on the spot, squashed on the step, stretched as
        // it leaves it.
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 0
        rise.toValue = -metrics.bounceHeight
        let squashX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        squashX.values = [1.0, 0.8, 1.0, 1.0]
        squashX.keyTimes = [0, 0.4, 0.6, 1]
        let squashY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squashY.values = [0.7, 1.2, 1.0, 1.0]
        squashY.keyTimes = [0, 0.4, 0.6, 1]
        let bounce = CAAnimationGroup()
        bounce.animations = [rise, squashX, squashY]
        bounce.duration = metrics.halfBounce
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = ease
        bounce.isRemovedOnCompletion = false
        ball.layer.add(bounce, forKey: Self.animationKey)

        // Steps: each cycle the staircase moves one stride.
        func loop(_ animations: [CAAnimation]) -> CAAnimationGroup {
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = metrics.stepPeriod
            group.repeatCount = .infinity
            group.timingFunction = ease
            group.isRemovedOnCompletion = false
            return group
        }
        func slide() -> [CAAnimation] {
            let x = CABasicAnimation(keyPath: "transform.translation.x")
            x.fromValue = 0
            x.toValue = metrics.stride.width
            let y = CABasicAnimation(keyPath: "transform.translation.y")
            y.fromValue = 0
            y.toValue = metrics.stride.height
            return [x, y]
        }
        func fade(from: Float, to: Float) -> CAAnimation {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = from
            opacity.toValue = to
            return opacity
        }
        steps[0].layer.add(loop([fade(from: 0, to: metrics.restingStepOpacity)]), forKey: Self.animationKey)
        steps[1].frame.origin = metrics.stepOrigins[0]
        steps[1].layer.add(loop(slide()), forKey: Self.animationKey)
        steps[2].frame.origin = metrics.stepOrigins[1]
        steps[2].layer.add(loop(slide()), forKey: Self.animationKey)
        steps[3].layer.add(loop([fade(from: metrics.restingStepOpacity, to: 0)]), forKey: Self.animationKey)
    }

    override func stopLoop() {
        let metrics = BodyFlowStairLoaderMetrics.self
        ([ball] + steps).forEach { $0.layer.removeAnimation(forKey: Self.animationKey) }
        // The still frame: three steps, the ball resting on the middle one.
        for (index, step) in steps.enumerated() {
            step.frame.origin = metrics.stepOrigins[min(index, 2)]
            step.layer.opacity = index == 3 ? 0 : metrics.restingStepOpacity
        }
    }
}

// MARK: - Looping host

/// Starts its loop only while it is in a window and allowed to move, and
/// restarts it when the app returns to the foreground (the system removes
/// layer animations in the background).
class BodyFlowLoopingView: UIView {
    var isAnimating = false {
        didSet { if oldValue != isAnimating { refresh() } }
    }

    private(set) var isLooping = false
    private var foregroundObserver: (any NSObjectProtocol)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            }
        } else if window == nil, let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        refresh()
    }

    private func refresh() {
        let shouldLoop = isAnimating && window != nil
        guard shouldLoop != isLooping else { return }
        isLooping = shouldLoop
        if shouldLoop { startLoop() } else { stopLoop() }
    }

    private func restart() {
        guard isLooping else { return }
        stopLoop()
        startLoop()
    }

    func startLoop() {}
    func stopLoop() {}
}
