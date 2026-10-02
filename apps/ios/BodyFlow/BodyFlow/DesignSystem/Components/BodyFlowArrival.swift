import SwiftUI

/// Content that has just loaded settles into place instead of cutting in:
/// each block fades and rises 8 pt, in a short cascade by position. Reduce
/// Motion, Low Power and a hot device show everything at once. Layout,
/// identifiers and values are untouched; only opacity and a small offset
/// animate, and the cascade never exceeds a quarter second.
enum BodyFlowArrival {
    nonisolated static let rise: CGFloat = 8
    nonisolated static let step: Double = 0.04
    nonisolated static let maxDelayedIndex = 6

    /// Delay for the block at `index`; capped so a long list never waits.
    nonisolated static func delay(index: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        return Double(min(max(index, 0), maxDelayedIndex)) * step
    }
}

private struct BodyFlowArrivalModifier: ViewModifier {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var shown = false
    let index: Int

    private var still: Bool { reduceMotion || !visualPolicy.allowsMotion }

    func body(content: Content) -> some View {
        content
            .opacity(shown || still ? 1 : 0)
            .offset(y: shown || still ? 0 : BodyFlowArrival.rise)
            .animation(
                BodyFlowMotion.animation(.content, reduceMotion: still)?
                    .delay(BodyFlowArrival.delay(index: index, reduceMotion: still)),
                value: shown
            )
            .onAppear { shown = true }
    }
}

extension View {
    func bodyFlowArrival(index: Int) -> some View {
        modifier(BodyFlowArrivalModifier(index: index))
    }
}

/// A soft highlight that slides across a loading placeholder (1.2 s per
/// pass) so the skeleton reads as "working", not frozen. Driven by a
/// timeline, so nothing keeps animating once the view is gone, and paused
/// whenever motion is reduced.
enum BodyFlowShimmer {
    nonisolated static let period: TimeInterval = 1.2

    /// Position of the highlight, from −1 (before the leading edge) to 2
    /// (past the trailing edge), for the given elapsed time.
    nonisolated static func phase(elapsed: TimeInterval) -> CGFloat {
        let fraction = (elapsed.truncatingRemainder(dividingBy: period)) / period
        return CGFloat(-1 + fraction * 3)
    }
}

private struct BodyFlowShimmerPhaseKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Set by one `bodyFlowShimmerTimeline()` per skeleton; nil keeps every
    /// placeholder still.
    var bodyFlowShimmerPhase: CGFloat? {
        get { self[BodyFlowShimmerPhaseKey.self] }
        set { self[BodyFlowShimmerPhaseKey.self] = newValue }
    }
}

/// One clock for the whole skeleton (30 fps at most), stopped whenever
/// motion is reduced; the placeholders only read the phase.
private struct BodyFlowShimmerTimelineModifier: ViewModifier {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var start = Date()

    private var paused: Bool { reduceMotion || !visualPolicy.allowsMotion }

    func body(content: Content) -> some View {
        if paused {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                content.environment(
                    \.bodyFlowShimmerPhase,
                    BodyFlowShimmer.phase(elapsed: context.date.timeIntervalSince(start))
                )
            }
        }
    }
}

private struct BodyFlowShimmerModifier: ViewModifier {
    @Environment(\.bodyFlowShimmerPhase) private var phase

    func body(content: Content) -> some View {
        content.overlay {
            if let phase {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            BodyFlowColor.color(.surfaceElevated).opacity(BodyFlowOpacity.shimmer),
                            .clear,
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: geometry.size.width * phase)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .clipped()
    }
}

extension View {
    func bodyFlowShimmerTimeline() -> some View {
        modifier(BodyFlowShimmerTimelineModifier())
    }

    func bodyFlowShimmer() -> some View {
        modifier(BodyFlowShimmerModifier())
    }
}
