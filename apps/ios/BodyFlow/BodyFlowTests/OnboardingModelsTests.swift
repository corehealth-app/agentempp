import Testing

@testable import BodyFlow

@Suite("Onboarding models")
struct OnboardingModelsTests {
    @Test("only public coach personas are selectable")
    func selectablePersonas() {
        #expect(CoachPersona.allCases == [.focus, .impulse, .zen])
        #expect(CoachPersona.allCases.map(\.displayName) == [
            "Focus", "Impulse", "Zen",
        ])
    }

    @Test("onboarding follows the approved seven-step order")
    func onboardingOrder() {
        #expect(OnboardingStep.allCases == [
            .welcome, .bodyData, .objective, .routine,
            .persona, .consent, .completion,
        ])
    }

    @Test("objectives mirror the backend domain vocabulary")
    func objectiveCodes() {
        #expect(BodyFlowObjective.allCases.map(\.rawValue) == [
            "recomposicao", "ganho_massa", "manutencao",
        ])
    }
}
