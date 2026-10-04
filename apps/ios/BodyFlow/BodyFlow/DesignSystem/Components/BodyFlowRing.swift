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
    /// Color past the target.
    var exceededRole: BodyFlowColor.Role = .feedbackWarning
    /// Direction B: the arc glows softly in dark mode.
    var glows = false
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var swept = false

    /// Clamped so an over-target day never draws past a full circle.
    nonisolated static func clampedFraction(consumed: Int, target: Int?) -> Double? {
        guard let target, target > 0 else { return nil }
        return min(max(Double(consumed) / Double(target), 0), 1)
    }

    private var still: Bool { reduceMotion || !visualPolicy.allowsMotion }

    nonisolated static let haloWidth: CGFloat = 10
    nonisolated static let haloOpacity: Double = 0.22

    private func arc(_ fraction: Double, lineWidth: CGFloat) -> some View {
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

    var body: some View {
        ZStack {
            Circle()
                .stroke(track ?? BodyFlowColor.color(.borderSubtle), lineWidth: lineWidth)
            if let fraction {
                if glows, colorScheme == .dark {
                    // Direction B's glow as a wider, translucent arc under
                    // the real one. Not a blur/shadow: an offscreen effect
                    // behind the figure makes the system contrast audit fail
                    // the small text drawn inside the ring.
                    arc(fraction, lineWidth: lineWidth + Self.haloWidth)
                        .opacity(Self.haloOpacity)
                }
                arc(fraction, lineWidth: lineWidth)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { swept = true }
        .accessibilityHidden(true)
    }
}
