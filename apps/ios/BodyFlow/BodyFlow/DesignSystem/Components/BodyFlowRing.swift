import SwiftUI

/// A progress ring for an official pair of values (consumed against a
/// target). It only draws the fraction it is given: the numbers next to it
/// stay the source of truth, and it is hidden from VoiceOver. On first
/// appearance the arc sweeps in (brand duration); Reduce Motion, Low Power
/// and a hot device draw it at once.
struct BodyFlowRing: View {
    /// 0…1 of the ring already filled; `nil` when there is no target.
    let fraction: Double?
    /// Past the target: the whole ring takes the warning color.
    let exceeded: Bool
    var diameter: CGFloat = 56
    var lineWidth: CGFloat = 6
    /// Fill color role (a domain color or the brand); nil track = subtle border.
    var role: BodyFlowColor.Role = .brandPrimary
    var track: Color? = nil
    /// Color past the target; the hero passes gold, which reads on teal.
    var exceededRole: BodyFlowColor.Role = .feedbackWarning

    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var swept = false

    /// Clamped so an over-target day never draws past a full circle.
    nonisolated static func clampedFraction(consumed: Int, target: Int?) -> Double? {
        guard let target, target > 0 else { return nil }
        return min(max(Double(consumed) / Double(target), 0), 1)
    }

    private var still: Bool { reduceMotion || !visualPolicy.allowsMotion }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track ?? BodyFlowColor.color(.borderSubtle), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: swept || still ? fraction : 0)
                    .stroke(
                        BodyFlowColor.color(exceeded ? exceededRole : role),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(BodyFlowMotion.animation(.sweep, reduceMotion: still), value: swept)
                    .animation(BodyFlowMotion.animation(.content, reduceMotion: still), value: fraction)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { swept = true }
        .accessibilityHidden(true)
    }
}
