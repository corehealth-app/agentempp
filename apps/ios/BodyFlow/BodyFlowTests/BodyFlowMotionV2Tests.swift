import Foundation
import Testing

@testable import BodyFlow

/// Direction v2 motion is finite and event-driven, and every kind collapses
/// under Reduce Motion. Nothing here may loop.
@Suite("Motion v2")
struct BodyFlowMotionV2Tests {
    @Test func navigationAndSweepCollapseUnderReduceMotion() {
        #expect(BodyFlowMotion.animation(.navigation, reduceMotion: true) == nil)
        #expect(BodyFlowMotion.animation(.navigation, reduceMotion: false) != nil)
        #expect(AppShellView.tabSlide == 16)
    }

    @Test func tabsSlideInTheDirectionOfTravel() {
        // Today ← Plan: Today sits to the left of Plan, so it waits at −16.
        #expect(AppShellView.tabSlideOffset(for: .today, selected: .plan) == -AppShellView.tabSlide)
        #expect(AppShellView.tabSlideOffset(for: .profile, selected: .plan) == AppShellView.tabSlide)
        #expect(AppShellView.tabSlideOffset(for: .plan, selected: .plan) == 0)
    }

    @Test func celebrationsAreShortBoundedBursts() {
        #expect(BodyFlowCelebration.duration <= 1.5)
        #expect(BodyFlowCelebration.particleCount <= 40)
        let particles = BodyFlowCelebration.particles()
        #expect(particles.count == BodyFlowCelebration.particleCount)
        #expect(Set(particles.map(\.id)).count == particles.count)
        #expect(particles.allSatisfy { $0.distance <= BodyFlowCelebration.spread && $0.delay < 0.2 })
    }

    @Test func countUpAndMeshAreBounded() {
        #expect(BodyFlowCountUp.duration <= 0.8)
        #expect(SplashView.meshDuration <= 3)
        let figure = BodyFlowCountUp.Figure(value: 731) { "\($0) kcal" }
        #expect(figure.render(figure.value) == "731 kcal")
    }
}
