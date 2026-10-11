import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

/// The liquid loader of the staged loading block: seven bars in one wave,
/// each with its drop, as a layer loop that runs only in a window and only
/// when motion is allowed, and rests on a still wave otherwise.
///
/// Every test requires the seven bars and drops before it reads an index, a
/// range or `allSatisfy`: over an empty view those would trap or pass in
/// vacuum instead of failing an expectation.
@MainActor
@Suite("Liquid loader")
struct BodyFlowLiquidLoaderTests {
    private let metrics = BodyFlowLiquidLoaderMetrics.self
    private let key = BodyFlowLiquidLoaderView.animationKey

    private func hosted<V: UIView>(_ view: V) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.addSubview(view)
        window.isHidden = false
        return window
    }

    @Test
    func sevenBarsEachWithItsDrop() throws {
        let view = BodyFlowLiquidLoaderView()
        try #require(view.bars.count == 7)
        try #require(view.drops.count == 7)
        #expect(metrics.barCount == 7)
        #expect(view.intrinsicContentSize == metrics.size)
        for index in 0..<7 {
            let barCenter = metrics.barX(index) + metrics.barWidth / 2
            #expect(abs(view.drops[index].center.x - barCenter) < 0.01, "drop \(index) sits above its own bar")
            #expect(view.drops[index].frame.maxY <= metrics.size.height - metrics.maximumBarHeight)
        }
    }

    @Test
    func loopsOnlyInAWindowAndOnlyWhenAllowed() throws {
        let view = BodyFlowLiquidLoaderView()
        try #require(view.bars.count == 7)
        try #require(view.drops.count == 7)

        // Not in a window: nothing runs even when allowed.
        view.isAnimating = true
        #expect(!view.isLooping)
        #expect((view.bars + view.drops).allSatisfy { $0.layer.animation(forKey: key) == nil })

        let window = hosted(view)
        #expect(view.isLooping)
        let animations = (view.bars + view.drops).compactMap { $0.layer.animation(forKey: key) }
        try #require(animations.count == 14)
        #expect(animations.allSatisfy { $0.repeatCount == .infinity && $0.duration == metrics.period })

        // Reduce Motion / Low Power / a hot device: nothing moves.
        view.isAnimating = false
        #expect(!view.isLooping)
        #expect((view.bars + view.drops).allSatisfy { $0.layer.animation(forKey: key) == nil })
        window.isHidden = true
    }

    @Test
    func waveTravelsWithOnePhaseStepPerBar() throws {
        let view = BodyFlowLiquidLoaderView()
        try #require(view.bars.count == 7)
        try #require(view.drops.count == 7)
        view.isAnimating = true
        let window = hosted(view)
        let waves = view.bars.compactMap { $0.layer.animation(forKey: key) }
        let drops = view.drops.compactMap { $0.layer.animation(forKey: key) }
        try #require(waves.count == 7)
        try #require(drops.count == 7)

        // Each bar is one step behind the one before it, and the seven steps
        // are exactly one period: the wave never breaks at the ends.
        for index in 0..<6 {
            #expect(abs(waves[index].timeOffset - waves[index + 1].timeOffset - metrics.stagger) < 1e-9)
        }
        #expect(abs(metrics.stagger * 7 - metrics.period) < 1e-9)
        // A drop keeps the time of its own bar.
        for index in 0..<7 {
            #expect(abs(drops[index].timeOffset - waves[index].timeOffset) < 1e-9)
        }
        // A bar is at its crest half way through its period, and its drop is
        // only opaque around that moment.
        #expect(metrics.waveKeyTimes == [0, 0.5, 1])
        try #require(metrics.dropKeyTimes.count == metrics.dropOpacities.count)
        for (time, opacity) in zip(metrics.dropKeyTimes, metrics.dropOpacities) where opacity > 0 {
            #expect(abs(time.doubleValue - 0.5) < 0.2)
        }
        #expect(metrics.dropOpacities.max() == 1)
        #expect(metrics.dropOpacities.first == 0 && metrics.dropOpacities.last == 0)
        window.isHidden = true
    }

    @Test
    func restsOnAStillWaveAndStaysInsideItsBox() throws {
        let view = BodyFlowLiquidLoaderView()
        try #require(view.bars.count == 7)
        try #require(view.drops.count == 7)
        let still = metrics.stillHeights
        try #require(still.count == 7)

        // A wave at rest, not a straight row.
        #expect(Set(still.map { ($0 * 100).rounded() }).count > 3)
        #expect(still.allSatisfy { $0 >= metrics.minimumBarHeight && $0 <= metrics.maximumBarHeight })

        let window = hosted(view)
        #expect(!view.isLooping)
        let resting = view.restingBarHeights
        try #require(resting.count == 7)
        for index in 0..<7 {
            #expect(abs(resting[index] - still[index]) < 0.01)
        }
        // One drop is drawn in the still frame: over the highest bar.
        #expect(view.drops.filter { $0.layer.opacity > 0 }.count == 1)
        #expect(view.drops[metrics.stillDropIndex].layer.opacity == 1)

        // After a loop the same still frame comes back.
        view.isAnimating = true
        view.isAnimating = false
        let after = view.restingBarHeights
        try #require(after.count == 7)
        for index in 0..<7 {
            #expect(abs(after[index] - still[index]) < 0.01)
        }

        // The tallest bar and the whole travel of a drop fit the box.
        let box = CGRect(origin: .zero, size: metrics.size)
        #expect(metrics.size.width == 7 * metrics.barWidth + 6 * metrics.barSpacing)
        #expect(metrics.maximumBarHeight + metrics.dropGap + metrics.dropRise + metrics.dropDiameter
            <= metrics.size.height)
        for drop in view.drops {
            #expect(box.contains(drop.frame))
            #expect(box.contains(drop.frame.offsetBy(dx: 0, dy: -metrics.dropRise)))
        }
        #expect(metrics.dropOffsets().min() == -metrics.dropRise)
        window.isHidden = true
    }

    /// A highlight makes what it is drawn on lighter. Proven on the colour
    /// the screen actually shows: the highlight at its opacity over each
    /// bar, in light and in dark.
    @Test
    func highlightLightensEveryBarInLightAndInDark() throws {
        let opacity = Double(metrics.highlightOpacity)
        #expect(opacity > 0 && opacity < 1)
        for dark in [false, true] {
            let traits = UITraitCollection { $0.userInterfaceStyle = dark ? .dark : .light }
            let highlight = try #require(components(metrics.highlightRole, traits))
            let roles = Set(metrics.barRoles)
            try #require(roles.count == 2)
            for role in roles {
                let bar = try #require(components(role, traits))
                let mixed = zip(highlight, bar).map { opacity * $0 + (1 - opacity) * $1 }
                #expect(
                    luminance(mixed) > luminance(bar),
                    "dark=\(dark) \(role): the highlight darkens the bar (\(luminance(mixed)) vs \(luminance(bar)))"
                )
                #expect(
                    luminance(highlight) > luminance(bar),
                    "dark=\(dark) \(role): the highlight colour is not lighter than the bar"
                )
            }
        }
    }

    private func components(_ role: BodyFlowColor.Role, _ traits: UITraitCollection) -> [Double]? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let color = UIColor(BodyFlowColor.color(role)).resolvedColor(with: traits)
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return [Double(red), Double(green), Double(blue)]
    }

    /// Relative luminance (WCAG) of an sRGB colour.
    private func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    @Test
    func usesTheBrandTealAndItsTintsOnly() throws {
        let view = BodyFlowLiquidLoaderView()
        try #require(view.bars.count == 7)
        try #require(view.drops.count == 7)
        let roles = metrics.barRoles
        try #require(roles.count == 7)
        // The brand teal and its tint — never a domain colour, never a rainbow.
        #expect(Set(roles).isSubset(of: [.brandPrimary, .brandSecondary]))
        #expect(Set(roles).count == 2)
        // Second update (2026-10-10): the highlight is the warm light of the
        // brand surfaces — the same in light and in dark. It was `.onPrimary`,
        // which is almost black in dark mode: a dark stripe, not a highlight.
        #expect(metrics.highlightRole == .onHero)

        let colors = roles.map { UIColor(BodyFlowColor.color($0)) }
        view.applyColors(bars: colors, highlight: UIColor(BodyFlowColor.color(metrics.highlightRole)))
        for index in 0..<7 {
            #expect(view.bars[index].backgroundColor == colors[index])
            // A drop is the colour of its bar.
            #expect(view.drops[index].backgroundColor == colors[index])
        }
    }
}
