import Foundation
import Testing

@testable import BodyFlow

@Suite("Main history presentation")
struct HistoryPresentationTests {
    @Test("meal rows preserve provider order and matching rows stay separate")
    func preservesIndividualMealRows() throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let presentation = HistoryPresentation(snapshot: response.data)

        #expect(presentation.meals.map(\.id) == [
            "fixture-meal-row-1", "fixture-meal-row-2",
        ])
        #expect(presentation.meals.map(\.foodName) == [
            "Arroz integral", "Feijao carioca",
        ])
        #expect(presentation.sectionTitles == ["Registros de alimentos", "Treinos"])
    }

    @Test("section and metric copy is bilingual without changing server values")
    func bilingualCopyPreservesServerValues() throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let portuguese = HistoryPresentation(
            snapshot: response.data,
            language: .portugueseBrazil
        )
        let english = HistoryPresentation(
            snapshot: response.data,
            language: .englishUnitedStates
        )

        #expect(portuguese.sectionTitles == ["Registros de alimentos", "Treinos"])
        #expect(english.sectionTitles == ["Food records", "Workouts"])
        #expect(english.meals.map(\.foodName) == portuguese.meals.map(\.foodName))
    }

    @Test("history metrics keep unavailable values absent and preserve received zero")
    func nullableMetricsDoNotBecomeZero() {
        let portuguese = HistoryValuePresentation(language: .portugueseBrazil)
        let english = HistoryValuePresentation(language: .englishUnitedStates)

        #expect(portuguese.quantity(nil) == nil)
        #expect(portuguese.quantity(0) == "Quantidade: 0 g")
        #expect(english.quantity(0) == "Quantity: 0 g")
        #expect(portuguese.energy(nil) == nil)
        #expect(english.energy(0) == "Energy: 0 kcal")
        #expect(portuguese.duration(nil) == nil)
        #expect(english.duration(0) == "Duration: 0 min")
    }

    @Test("global empty requires both independent response arrays to be empty")
    func globalEmptyNeedsBothSectionsEmpty() throws {
        let mealsOnly = try BodyFlowTestFixtures.decodeHistoryMealsOnly()
        let workoutsOnly = try BodyFlowTestFixtures.decodeHistoryWorkoutsOnly()
        let empty = try BodyFlowTestFixtures.decodeEmptyHistory()

        #expect(!HistoryPresentation(snapshot: mealsOnly.data).isGloballyEmpty)
        #expect(!HistoryPresentation(snapshot: workoutsOnly.data).isGloballyEmpty)
        #expect(HistoryPresentation(snapshot: empty.data).isGloballyEmpty)
    }
}
