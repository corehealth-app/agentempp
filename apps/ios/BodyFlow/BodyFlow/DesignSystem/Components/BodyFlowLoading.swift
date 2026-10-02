import SwiftUI

/// A timer owns only its current appearance. Ending a read or beginning a
/// different read prevents an old, non-cooperative timer from flashing.
struct BodyFlowLoadingGate {
    private var generation = 0
    private var active: Int?
    private(set) var isVisible = false

    mutating func begin() -> Int {
        generation += 1
        active = generation
        isVisible = false
        return generation
    }

    mutating func reveal(_ token: Int) {
        guard active == token else { return }
        isVisible = true
    }

    mutating func end() {
        active = nil
        isVisible = false
    }
}

struct BodyFlowDelayedProgress: View {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @State private var gate = BodyFlowLoadingGate()
    var label: String? = nil
    var tint: Color = BodyFlowColor.accent

    var body: some View {
        HStack(spacing: BodyFlowSpacing.sm) {
            ZStack {
                if gate.isVisible {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                    } else {
                        ProgressView().tint(tint)
                    }
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
            if let label { Text(label).fixedSize(horizontal: false, vertical: true) }
        }
        .task {
            let token = gate.begin()
            do {
                try await Task.sleep(for: .milliseconds(150))
                try Task.checkCancellation()
                gate.reveal(token)
            } catch { /* Fast completion/disappearance leaves no spinner. */ }
        }
        .onDisappear { gate.end() }
    }
}

/// The first frame reserves the structure of each destination, with a soft
/// shimmer so it reads as working (still under Reduce Motion). No
/// percentages or invented user values; one accessible loading description.
struct BodyFlowFeatureSkeleton: View {
    enum Kind { case today, plan, progress, library }
    let kind: Kind
    var isEmbedded = false
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if isEmbedded { content }
            else { ScrollView { content } }
        }
        .bodyFlowShimmerTimeline()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PremiumPresentationCopy.string("splash.loading", locale: locale, fallback: "Carregando"))
        .accessibilityIdentifier("state.loading")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            bar(width: 150, height: 24)
            if kind == .today || kind == .progress {
                tile(height: kind == .today ? 152 : 180)
                HStack(spacing: BodyFlowSpacing.md) {
                    tile(height: 100)
                    tile(height: 100)
                }
            }
            ForEach(0..<(kind == .library ? 3 : 2), id: \.self) { _ in
                HStack(spacing: BodyFlowSpacing.md) {
                    if kind == .library { tile(height: 84).frame(width: 84) }
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                        bar(width: nil, height: 18)
                        bar(width: 120, height: 14)
                        if kind == .plan { bar(width: nil, height: 40) }
                    }
                }
            }
        }
        .padding(BodyFlowSpacing.md)
        .accessibilityHidden(true)
    }

    private func tile(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: BodyFlowRadius.card)
            .fill(BodyFlowColor.color(.backgroundSecondary))
            .frame(maxWidth: .infinity).frame(height: height)
            .bodyFlowShimmer()
            .clipShape(RoundedRectangle(cornerRadius: BodyFlowRadius.card))
    }

    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: BodyFlowRadius.small)
            .fill(BodyFlowColor.color(.borderSubtle))
            .frame(width: width, height: height)
            .bodyFlowShimmer()
            .clipShape(RoundedRectangle(cornerRadius: BodyFlowRadius.small))
    }
}
