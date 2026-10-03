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
