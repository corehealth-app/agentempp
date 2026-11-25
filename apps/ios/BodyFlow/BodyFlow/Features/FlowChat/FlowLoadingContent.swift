import SwiftUI
import UIKit

struct FlowWaitingBubble: View {
    let label: String
    var identifier = "conversation.responding"
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @State private var gate = BodyFlowLoadingGate()

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(height: 0).accessibilityHidden(true)
            if gate.isVisible {
                HStack(spacing: BodyFlowSpacing.sm) {
                    FlowLoaderMotion()
                    Text(verbatim: label)
                        .font(BodyFlowTypography.supporting)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, BodyFlowSpacing.sm)
                .padding(.vertical, BodyFlowSpacing.xs)
                .background(
                    BodyFlowColor.surface, in: FlowBubbleShape.shape(tailOnTrailing: false))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier)
                .transition(BodyFlowMotion.stateTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: gate.isVisible)
        .task {
            let token = gate.begin()
            do {
                try await Task.sleep(for: .milliseconds(150))
                try Task.checkCancellation()
                gate.reveal(token)
            } catch { /* Quick responses do not need a waiting bubble. */ }
        }
        .onDisappear { gate.end() }
    }
}

struct FlowHistorySkeleton: View {
    let label: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            bubble(width: 156, outgoing: true)
            bubble(width: 216, outgoing: false)
            bubble(width: 118, outgoing: true)
            HStack(spacing: BodyFlowSpacing.sm) {
                FlowLoaderMotion()
                Text(verbatim: label)
                    .font(BodyFlowTypography.supporting)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, BodyFlowSpacing.sm)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityIdentifier(identifier)
    }

    private func bubble(width: CGFloat, outgoing: Bool) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Capsule().fill(BodyFlowColor.accent.opacity(0.14)).frame(height: 7)
            if !outgoing {
                Capsule().fill(BodyFlowColor.accent.opacity(0.09)).frame(width: 66, height: 7)
            }
        }
        .padding(BodyFlowSpacing.md)
        .frame(maxWidth: width)
        .background(
            outgoing ? BodyFlowColor.accent.opacity(0.08) : BodyFlowColor.surface,
            in: FlowBubbleShape.shape(tailOnTrailing: outgoing))
        .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
        .accessibilityHidden(true)
    }
}

private struct FlowLoaderMotion: UIViewRepresentable {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @Environment(\.scenePhase) private var scenePhase

    func makeUIView(context: Context) -> FlowLoaderMotionView { FlowLoaderMotionView() }

    func updateUIView(_ view: FlowLoaderMotionView, context: Context) {
        view.updateColors()
        view.isAnimating = !reduceMotion && visualPolicy.allowsMotion && scenePhase == .active
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: FlowLoaderMotionView, context: Context
    ) -> CGSize? { uiView.intrinsicContentSize }
}

final class FlowLoaderMotionView: BodyFlowLoopingView {
    private struct Orbit {
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
        let direction: CGFloat
        let period: CFTimeInterval
        let role: BodyFlowColor.Role
    }

    private let orbits: [Orbit] = [
        .init(x: 17, y: 4, diameter: 5, direction: 1, period: 4.1, role: .brandSecondary),
        .init(x: 12, y: 5, diameter: 7, direction: -1, period: 3.4, role: .brandPrimary),
        .init(x: 7, y: 4, diameter: 5, direction: 1, period: 2.9, role: .brandPrimary),
    ]
    private(set) var particles: [UIView] = []
    static let animationKey = "bodyflow.flow-waiting"

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for orbit in orbits {
            let diameter = orbit.diameter
            let particle = UIView(frame: CGRect(
                x: 22 - diameter / 2 - orbit.x * orbit.direction,
                y: 11 - diameter / 2, width: diameter, height: diameter))
            particle.layer.cornerRadius = diameter / 2
            particle.alpha = 0.8
            addSubview(particle)
            particles.append(particle)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 22) }

    func updateColors() {
        for (particle, orbit) in zip(particles, orbits) {
            particle.backgroundColor = UIColor(BodyFlowColor.color(orbit.role))
        }
    }

    override func startLoop() {
        for (particle, orbit) in zip(particles, orbits) {
            let span = orbit.x * orbit.direction
            let direction = orbit.y * orbit.direction
            let animation = CAAnimationGroup()
            animation.animations = [
                keyframes("transform.translation.x", [0, span, 2 * span, span, 0], orbit.period),
                keyframes("transform.translation.y", [0, direction, 0, -direction, 0], orbit.period),
                keyframes("transform.scale", [0.78, 0.9, 1.14, 0.95, 0.78], orbit.period),
                keyframes("opacity", [0.52, 0.78, 1, 0.78, 0.52], orbit.period),
            ]
            animation.duration = orbit.period
            animation.repeatCount = .infinity
            particle.layer.add(animation, forKey: Self.animationKey)
        }
    }

    override func stopLoop() {
        particles.forEach { $0.layer.removeAnimation(forKey: Self.animationKey) }
    }

    private func keyframes(
        _ property: String, _ values: [CGFloat], _ duration: CFTimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: property)
        animation.values = values
        animation.duration = duration
        animation.calculationMode = .cubic
        return animation
    }
}
