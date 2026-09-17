import Testing
@testable import BodyFlow

@Suite("App tabs")
struct AppTabTests {
    @Test("tabs keep product order, symbols, and stable identifiers")
    func stableContract() {
        #expect(AppTab.allCases.map(\.title) == [
            "Hoje", "Registrar", "Plano", "Progresso", "Perfil",
        ])
        #expect(AppTab.allCases.map(\.systemImage) == [
            "house", "plus.circle", "list.clipboard",
            "chart.line.uptrend.xyaxis", "person.crop.circle",
        ])
        #expect(AppTab.allCases.map(\.accessibilityIdentifier) == [
            "tab.hoje", "tab.registrar", "tab.plano",
            "tab.progresso", "tab.perfil",
        ])
        #expect(AppTab.allCases.map(\.rootAccessibilityIdentifier) == [
            "screen.hoje", "screen.registrar", "screen.plano",
            "screen.progresso", "screen.perfil",
        ])
    }

    @Test("English labels preserve tab order and technical identity")
    func englishLabelsPreserveTechnicalContract() {
        #expect(AppTab.allCases.map {
            $0.title(for: .englishUnitedStates)
        } == [
            "Today", "Register", "Plan", "Progress", "Profile",
        ])
        #expect(AppTab.allCases.map(\.rawValue) == [
            "today", "register", "plan", "progress", "profile",
        ])
    }
}
