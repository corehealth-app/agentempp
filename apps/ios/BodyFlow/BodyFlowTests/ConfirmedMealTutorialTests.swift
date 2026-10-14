import Foundation
import Testing
@testable import BodyFlow

@Suite("Confirmed meal editing in the existing guided tutorial")
struct ConfirmedMealTutorialTests {
    private let key = "tutorial.history.confirmed-meal-editing"

    private func facts(editing: Bool) -> GuidedTutorialFacts {
        GuidedTutorialFacts(mealMedia: false, planDrafts: false, planImport: false,
            reminders: false, realAccount: true, confirmedMealEditing: editing)
    }

    @Test("Default OFF preserves the existing eight tutorial steps without an editing promise")
    func defaultOffKeepsExistingTutorial() throws {
        let session = GuidedTutorialFacts(mealMedia: false, planDrafts: false, planImport: false,
            reminders: false, realAccount: true)
        let text = GuidedTutorialContent.steps(facts: session)
        #expect(text.map(\.area) == [.welcome, .today, .flow, .plan, .register, .progress, .routineLibrary, .profile])
        let today = try #require(text.first { $0.area == .today })
        #expect(today.lineKeys == ["tutorial.today.food", "tutorial.today.balance", "tutorial.today.refresh", "tutorial.today.details"])
        #expect(!text.flatMap(\.lineKeys).contains(key))
        let visual = GuidedTourContent.steps(facts: session)
        #expect(visual.map(\.id) == ["welcome", "flow", "library", "register", "plan", "progress", "profile", "trail"])
        #expect(visual.map(\.target) == [nil, .flow, .library, .register, .planTab, .progressTab, .profileTab, nil])
        #expect(visual.allSatisfy { $0.additionalLineKey == nil })
    }

    @Test("Both presentations explain only eligible confirmed meal corrections and explicit selected-item deletion",
          arguments: SupportedAppLanguage.allCases)
    func availableEditingHasQualifiedCopy(_ language: SupportedAppLanguage) throws {
        let session = facts(editing: true)
        let text = GuidedTutorialContent.steps(facts: session)
        let today = try #require(text.first { $0.area == .today })
        #expect(today.lineKeys == ["tutorial.today.food", "tutorial.today.balance", "tutorial.today.refresh", "tutorial.today.details", key])
        #expect(text.filter { $0.lineKeys.contains(key) }.map(\.area) == [.today])
        let visual = GuidedTourContent.steps(facts: session)
        #expect(visual.map(\.id) == ["welcome", "flow", "library", "register", "plan", "progress", "profile", "trail"])
        #expect(visual.map(\.target) == [nil, .flow, .library, .register, .planTab, .progressTab, .profileTab, nil])
        let trail = try #require(visual.first { $0.id == "trail" })
        #expect(trail.additionalLineKey == key)
        #expect(visual.filter { $0.additionalLineKey != nil }.map(\.id) == ["trail"])
        let copy = try AppLocalization.string(String.LocalizationValue(key), for: language)
        #expect(copy != key && !copy.isEmpty)
        let required = language == .portugueseBrazil
            ? ["Hoje", "Histórico", "refeição confirmada", "Se o registro permitir alterações", "um alimento por vez", "revise antes de salvar", "selecione os itens e confirme", "somente para consulta"]
            : ["Today", "History", "confirmed meal", "If the record allows changes", "one food item at a time", "review before saving", "select items and confirm", "View-only records"]
        for phrase in required { #expect(copy.localizedCaseInsensitiveContains(phrase)) }
        for phrase in (language == .portugueseBrazil ? ["treino", "desfazer", "todas as refeições"] : ["workout", "undo", "every meal"]) {
            #expect(!copy.localizedCaseInsensitiveContains(phrase))
        }
        // The proposal review/confirmation explanation remains the existing one.
        let register = try #require(text.first { $0.area == .register })
        #expect(register.lineKeys.contains("tutorial.register.review"))
        let review = try AppLocalization.string("tutorial.register.review", for: language)
        #expect(review.localizedCaseInsensitiveContains(language == .portugueseBrazil ? "proposta" : "proposal"))
        #expect(review.localizedCaseInsensitiveContains(language == .portugueseBrazil ? "confirmar" : "confirm"))
    }
}
