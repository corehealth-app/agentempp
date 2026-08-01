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
