import SwiftUI
import UIKit

/// The "liquid" loader: seven rounded bars that rise and fall as one wave,
/// each a step behind the one before it, with a small drop that leaves a
/// bar as it reaches its crest. Drawn in the brand teal and its tint.
///
/// A layer animation on `BodyFlowLoopingView`, like the other looping
/// indicators (see `BodyFlowLayerAnimations.swift` for why): it is handed to
/// the render server once and never makes anything wait. It is decorative —
/// the block that hosts it carries the accessible text. Under Reduce Motion,
/// Low Power or a hot device it draws one still wave.
enum BodyFlowLiquidLoaderMetrics {
    nonisolated static let barCount = 7
    nonisolated static let barWidth: CGFloat = 10
    nonisolated static let barSpacing: CGFloat = 8
    /// A bar at the bottom and at the crest of the wave.
    nonisolated static let minimumBarHeight: CGFloat = 14
    nonisolated static let maximumBarHeight: CGFloat = 46
    nonisolated static let dropDiameter: CGFloat = 6
    /// Between the highest crest and a drop that has just left it.
    nonisolated static let dropGap: CGFloat = 3
    /// How far a drop travels up before it fades.
    nonisolated static let dropRise: CGFloat = 9
    /// One full rise and fall of a bar.
    nonisolated static let period: CFTimeInterval = 1.4
    /// From one bar to the next: the wave crosses the seven bars in exactly
    /// one period, so it never breaks at the ends.
    nonisolated static var stagger: CFTimeInterval { period / Double(barCount) }
    /// The soft highlight down the left side of each bar.
    nonisolated static let highlightWidth: CGFloat = 3
    nonisolated static let highlightInset: CGFloat = 2
    nonisolated static let highlightOpacity: Float = 0.3
    nonisolated static let highlightRole = BodyFlowColor.Role.onPrimary

    /// A bar and its drop are one colour: the brand teal and its tint,
    /// alternating along the wave.
    nonisolated static var barRoles: [BodyFlowColor.Role] {
        (0..<barCount).map { $0.isMultiple(of: 2) ? .brandPrimary : .brandSecondary }
    }

    nonisolated static var size: CGSize {
        CGSize(
            width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing,
            height: maximumBarHeight + dropGap + dropRise + dropDiameter
        )
    }

    /// The left edge of a bar.
    nonisolated static func barX(_ index: Int) -> CGFloat {
        CGFloat(index) * (barWidth + barSpacing)
    }

    /// The still frame: one wavelength of a sine sampled at the seven bars
    /// (a wave at rest, not a straight row).
    nonisolated static var stillHeights: [CGFloat] {
        (0..<barCount).map { index in
            let phase = 2 * Double.pi * Double(index) / Double(barCount)
            let level = (1 + sin(phase)) / 2
            return minimumBarHeight + (maximumBarHeight - minimumBarHeight) * CGFloat(level)
        }
    }

    /// The bar whose drop is drawn in the still frame: the highest one.
    nonisolated static var stillDropIndex: Int {
        let heights = stillHeights
        return heights.firstIndex(of: heights.max() ?? 0) ?? 0
    }

    /// How late a bar is, as local time already elapsed when the loop
    /// starts: the first bar leads and each next one is a stagger behind, so
    /// the wave is already travelling in the first frame.
    nonisolated static func timeOffset(_ index: Int) -> CFTimeInterval {
        Double(barCount - 1 - index) * stagger
    }

    /// A bar is at the bottom at 0 and 1 and at its crest at 0.5.
    nonisolated static let waveKeyTimes: [NSNumber] = [0, 0.5, 1]
    /// The drop exists only around the crest of its bar.
    nonisolated static let dropKeyTimes: [NSNumber] = [0, 0.38, 0.5, 0.72, 1]
    nonisolated static let dropOpacities: [Float] = [0, 0, 1, 0, 0]
    nonisolated static func dropOffsets() -> [CGFloat] { [0, 0, 0, -dropRise, -dropRise] }
}

struct BodyFlowLiquidLoader: UIViewRepresentable {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy

    func makeUIView(context: Context) -> BodyFlowLiquidLoaderView {
        let view = BodyFlowLiquidLoaderView()
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: BodyFlowLiquidLoaderView, context: Context) {
        // Dynamic colours: they follow light and dark by themselves.
        view.applyColors(
            bars: BodyFlowLiquidLoaderMetrics.barRoles.map { UIColor(BodyFlowColor.color($0)) },
            highlight: UIColor(BodyFlowColor.color(BodyFlowLiquidLoaderMetrics.highlightRole))
        )
        view.isAnimating = !(reduceMotion || !visualPolicy.allowsMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BodyFlowLiquidLoaderView, context: Context) -> CGSize? {
        BodyFlowLiquidLoaderMetrics.size
    }
}

final class BodyFlowLiquidLoaderView: BodyFlowLoopingView {
    static let animationKey = "bodyflow.liquid"
    /// The moving part of each bar. It slides inside a clipping column that
    /// stands on the baseline, so a bar keeps its round ends at any height.
    private(set) var bars: [UIView] = []
    private(set) var drops: [UIView] = []
    private var highlights: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: BodyFlowLiquidLoaderMetrics.size))
        let metrics = BodyFlowLiquidLoaderMetrics.self
        let columnTop = metrics.size.height - metrics.maximumBarHeight
        for index in 0..<metrics.barCount {
            let column = UIView(frame: CGRect(
                x: metrics.barX(index), y: columnTop,
                width: metrics.barWidth, height: metrics.maximumBarHeight
            ))
            column.layer.cornerRadius = metrics.barWidth / 2
            column.layer.masksToBounds = true
            addSubview(column)

            let bar = UIView(frame: column.bounds)
            bar.layer.cornerRadius = metrics.barWidth / 2
            // The bar hangs from its top edge: `position.y` is how far its
            // crest is below the top of the column.
            bar.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.layer.position = CGPoint(x: metrics.barWidth / 2, y: 0)
            column.addSubview(bar)
            bars.append(bar)

            let highlight = UIView(frame: CGRect(
                x: metrics.highlightInset, y: metrics.barWidth / 2,
                width: metrics.highlightWidth,
                height: metrics.maximumBarHeight - metrics.barWidth
            ))
            highlight.layer.cornerRadius = metrics.highlightWidth / 2
            highlight.layer.opacity = metrics.highlightOpacity
            bar.addSubview(highlight)
            highlights.append(highlight)

            let drop = UIView(frame: CGRect(
                x: metrics.barX(index) + (metrics.barWidth - metrics.dropDiameter) / 2,
                y: columnTop - metrics.dropGap - metrics.dropDiameter,
                width: metrics.dropDiameter, height: metrics.dropDiameter
            ))
            drop.layer.cornerRadius = metrics.dropDiameter / 2
            addSubview(drop)
            drops.append(drop)
        }
        applyStillFrame()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { BodyFlowLiquidLoaderMetrics.size }

    /// The visible height of each bar as it rests (no animation applied).
    var restingBarHeights: [CGFloat] {
        bars.map { BodyFlowLiquidLoaderMetrics.maximumBarHeight - $0.layer.position.y }
    }

    func applyColors(bars barColors: [UIColor], highlight: UIColor) {
        for (index, bar) in bars.enumerated() where index < barColors.count {
            bar.backgroundColor = barColors[index]
            drops[index].backgroundColor = barColors[index]
        }
        highlights.forEach { $0.backgroundColor = highlight }
    }

    override func startLoop() {
        let metrics = BodyFlowLiquidLoaderMetrics.self
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let travel = metrics.maximumBarHeight - metrics.minimumBarHeight
        for index in bars.indices {
            let wave = CAKeyframeAnimation(keyPath: "position.y")
            wave.values = [travel, 0, travel]
            wave.keyTimes = metrics.waveKeyTimes
            wave.timingFunctions = [ease, ease]
            configure(wave, index: index)
            bars[index].layer.add(wave, forKey: Self.animationKey)

            let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
            rise.values = metrics.dropOffsets()
            rise.keyTimes = metrics.dropKeyTimes
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = metrics.dropOpacities
            fade.keyTimes = metrics.dropKeyTimes
            let drop = CAAnimationGroup()
            drop.animations = [rise, fade]
            configure(drop, index: index)
            drops[index].layer.add(drop, forKey: Self.animationKey)
        }
    }

    override func stopLoop() {
        (bars + drops).forEach { $0.layer.removeAnimation(forKey: Self.animationKey) }
        applyStillFrame()
    }

    private func configure(_ animation: CAAnimation, index: Int) {
        let metrics = BodyFlowLiquidLoaderMetrics.self
        animation.duration = metrics.period
        animation.repeatCount = .infinity
        animation.timeOffset = metrics.timeOffset(index)
        animation.isRemovedOnCompletion = false
    }

    /// One still wave, with the drop of its highest bar.
    private func applyStillFrame() {
        let metrics = BodyFlowLiquidLoaderMetrics.self
        let heights = metrics.stillHeights
        for index in bars.indices {
            bars[index].layer.position.y = metrics.maximumBarHeight - heights[index]
            drops[index].layer.opacity = index == metrics.stillDropIndex ? 1 : 0
        }
    }
}
