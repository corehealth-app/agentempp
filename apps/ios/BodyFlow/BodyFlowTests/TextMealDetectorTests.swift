import Foundation
import Testing

@testable import BodyFlow

@Suite("Text meal detector")
struct TextMealDetectorTests {
    @Test("one food per line with grams becomes a structured proposal")
    func linesBecomeItems() throws {
        let items = try TextMealDetector.items(from: "Arroz integral 120 g\nFrango grelhado 150g\n10,5 g de azeite")
        #expect(items.map(\.foodName) == ["Arroz integral", "Frango grelhado", "azeite"])
        #expect(items.map(\.quantityG) == [120, 150, Decimal(string: "10.5")])
        #expect(items.allSatisfy { $0.userKcal == nil })
    }

    @Test("a line without an explicit gram figure is rejected, not guessed")
    func missingGramsIsInvalid() {
        #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try TextMealDetector.items(from: "2 ovos")
        }
        #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try TextMealDetector.items(from: "arroz 12000 g")
        }
        #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try TextMealDetector.items(from: "   ")
        }
        #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try TextMealDetector.items(from: "120 g")
        }
    }

    @Test("the suggested meal type follows the hour and the samples stay unavailable")
    func suggestedMealTypeAndSamples() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func detector(hour: Int) -> TextMealDetector {
            let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: hour))!
            return TextMealDetector(now: { date }, calendar: calendar)
        }
        for (hour, expected) in [(8, MealType.breakfast), (13, .lunch), (16, .snack), (20, .dinner), (23, .supper)] {
            let request = try await detector(hour: hour).detect(.text("arroz 120 g"))
            guard case let .meal(meal) = request else { Issue.record("expected a meal"); return }
            #expect(meal.mealType == expected)
            #expect(meal.consumedAt == nil)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await detector(hour: 12).detect(.photoSample(label: "x"))
        }
    }
}
