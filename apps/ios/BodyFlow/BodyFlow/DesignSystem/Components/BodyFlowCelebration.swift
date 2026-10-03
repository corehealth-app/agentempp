import SwiftUI

/// A short burst of particles in a domain color when the patient completes
/// something real (a confirmed meal, a routine item taken, the tour). It is
/// one finite animation per trigger — 1.4 s, then the particles are removed
/// from the tree — never a loop. Reduce Motion, Low Power and a hot device
/// skip it; the haptic and the status line remain the primary channels.
enum BodyFlowCelebration {
    nonisolated static let duration: TimeInterval = 1.4
    nonisolated static let particleCount = 24
    nonisolated static let spread: CGFloat = 120

    struct Particle: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let delay: Double
    }

    /// Deterministic layout (no randomness at render time), so a burst looks
    /// the same in a test as on the device.
    nonisolated static func particles() -> [Particle] {
        (0..<particleCount).map { index in
            let turn = Double(index) / Double(particleCount)
            return Particle(
                id: index,
                angle: turn * .pi * 2 + (index.isMultiple(of: 2) ? 0.15 : -0.1),
                distance: spread * (index.isMultiple(of: 3) ? 0.65 : 1),
                size: index.isMultiple(of: 4) ? 10 : 6,
                delay: index.isMultiple(of: 2) ? 0 : 0.08
            )
        }
    }
}

private struct BodyFlowCelebrationModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @Environment(\.bodyFlowVisualPolicy) private var visualPolicy
    @State private var burst: Int?
    @State private var burstDomain: BodyFlowDomain?
    let celebrates: (Trigger) -> BodyFlowDomain?
    let trigger: Trigger

    private var still: Bool { reduceMotion || !visualPolicy.allowsMotion }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let burst, let burstDomain {
                    BodyFlowCelebrationBurst(domain: burstDomain)
                        .id(burst)
                }
            }
            .onChange(of: trigger) { _, newValue in
                guard !still, let domain = celebrates(newValue) else { return }
                burstDomain = domain
                burst = (burst ?? 0) + 1
            }
            .task(id: burst) {
                guard burst != nil else { return }
                try? await Task.sleep(for: .seconds(BodyFlowCelebration.duration))
                guard !Task.isCancelled else { return }
                burst = nil
            }
    }
}

private struct BodyFlowCelebrationBurst: View {
    let domain: BodyFlowDomain
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(BodyFlowCelebration.particles()) { particle in
                Circle()
                    .fill(domain.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: fired ? cos(particle.angle) * particle.distance : 0,
                        y: fired ? sin(particle.angle) * particle.distance : 0
                    )
                    .scaleEffect(fired ? 0.2 : 1)
                    .opacity(fired ? 0 : 1)
                    .animation(
                        .easeOut(duration: BodyFlowCelebration.duration - 0.2).delay(particle.delay),
                        value: fired
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { fired = true }
    }
}

extension View {
    /// Plays a burst in the returned domain's color when `trigger` changes to
    /// a value the closure maps to a domain; nil stays silent.
    func bodyFlowCelebration<Trigger: Equatable>(
        _ celebrates: @escaping (Trigger) -> BodyFlowDomain?,
        trigger: Trigger
    ) -> some View {
        modifier(BodyFlowCelebrationModifier(celebrates: celebrates, trigger: trigger))
    }
}
