import SwiftUI

/// A horizontal progress bar for an official pair of values (consumed against
/// a target), in the color of its domain. It only draws the fraction it is
/// given: the figures next to it stay the source of truth, and it is hidden
/// from VoiceOver. On first appearance the fill sweeps in; Reduce Motion, Low
/// Power and a hot device draw it at once. Past the target the fill takes the
/// warning color, like the ring.
struct BodyFlowMeter: View {
    /// 0…1 already filled; `nil` draws the empty track only (no target).
    let fraction: Double?
    let domain: BodyFlowDomain
    var exceeded = false
    var height: CGFloat = 8

    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var swept = false

    /// Clamped so an over-target day never draws past the end.
    nonisolated static func clampedFraction(consumed: Decimal, target: Decimal?) -> Double? {
        guard let target, target > 0 else { return nil }
        let value = NSDecimalNumber(decimal: consumed).doubleValue / NSDecimalNumber(decimal: target).doubleValue
        return min(max(value, 0), 1)
    }

    private var still: Bool { reduceMotion || !visualPolicy.allowsMotion }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(BodyFlowColor.color(.borderSubtle))
                // Nothing is drawn for 0: no pill for progress that does not exist.
                if let fraction, fraction > 0 {
                    Capsule()
                        .fill(BodyFlowColor.color(exceeded ? .feedbackWarning : domain.colorRole))
                        .frame(width: max(height, geometry.size.width * (swept || still ? fraction : 0)))
                        .animation(BodyFlowMotion.animation(.sweep, reduceMotion: still), value: swept)
                        .animation(BodyFlowMotion.animation(.content, reduceMotion: still), value: fraction)
                }
            }
        }
        .frame(height: height)
        .onAppear { swept = true }
        .accessibilityHidden(true)
    }
}
