import SwiftUI

/// A figure that counts up to its official value when it first appears
/// (Apple Fitness style). Only the drawing counts: the real text stays in
/// the tree from the first frame (transparent during the count), so
/// accessibility, VoiceOver and the UI tests always read the final value.
/// Finite (`duration`), event-driven; Reduce Motion, Low Power and a hot
/// device show the value at once.
enum BodyFlowCountUp {
    nonisolated static let duration: TimeInterval = 0.8

    struct Figure {
        let value: Int
        let render: (Int) -> String
        init(value: Int, render: @escaping (Int) -> String) {
            self.value = value
            self.render = render
        }
    }
}

private struct BodyFlowCountingTextModifier: ViewModifier, @preconcurrency Animatable {
    var shown: Double
    let render: (Int) -> String

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    func body(content: Content) -> some View {
        // Clear color, not opacity: the real text stays in the accessibility
        // tree (VoiceOver and the UI tests read the final value from frame one).
        content
            .foregroundStyle(.clear)
            .overlay(alignment: .leading) {
                Text(verbatim: render(Int(shown.rounded())))
                    .accessibilityHidden(true)
            }
    }
}

private struct BodyFlowCountUpModifier: ViewModifier {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var shown: Double?
    /// Once the count has landed the overlay is dropped: the figure is a
    /// plain Text again (what the accessibility audit and VoiceOver see).
    @State private var finished = false
    let figure: BodyFlowCountUp.Figure?

    private var still: Bool { reduceMotion || !visualPolicy.allowsMotion }

    func body(content: Content) -> some View {
        if let figure, !still, !finished {
            // Frame one draws 0 and the first update animates to the value;
            // resetting and animating in the same update would never count.
            content
                .modifier(BodyFlowCountingTextModifier(shown: shown ?? 0, render: figure.render))
                .onAppear {
                    guard shown == nil else { return }
                    withAnimation(.easeOut(duration: BodyFlowCountUp.duration)) {
                        shown = Double(figure.value)
                    } completion: {
                        finished = true
                    }
                }
                // A refreshed official value ends the count at once.
                .onChange(of: figure.value) { _, _ in finished = true }
        } else {
            content
        }
    }
}

extension View {
    func bodyFlowCountUp(_ figure: BodyFlowCountUp.Figure?) -> some View {
        modifier(BodyFlowCountUpModifier(figure: figure))
    }
}
