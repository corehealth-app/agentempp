import Foundation
import Testing

@testable import BodyFlow

@Suite("Progress trends")
struct ProgressTrendsTests {
    @Test("Bars, weights and recorded days come only from the stored series")
    func presentationIsHonest() {
        let presentation = ProgressTrendsPresentation(
            snapshot: DemoBodyFlowFixtures.loadedTrends.data, language: .portugueseBrazil
        )
        #expect(!presentation.isEmpty)
        #expect(presentation.window == 14)
        // Twelve stored days: two gaps stay gaps.
        #expect(presentation.calories.count == 12)
        #expect(presentation.recordedDays.count == 14)
        #expect(presentation.recordedDays.filter { $0 }.count == 12)
        #expect(presentation.recordedDays.last == true)
        #expect(presentation.calories.filter(\.overTarget).map(\.consumed) == [2_310, 2_120])
        #expect(presentation.target == 1_935)
        #expect(presentation.weights.map(\.kilograms) == [80.0, 79.1, 78.4])
        #expect(presentation.latestWeight == "78,4 kg")
        #expect(presentation.calories.last?.label == "20 de jul.")
        #expect(presentation.block.last?.accumulated == 1_200 + 11 * 110)
    }

    @Test("An account without days is empty, never a zero chart")
    func emptyIsEmpty() {
        let presentation = ProgressTrendsPresentation(
            snapshot: DemoBodyFlowFixtures.emptyTrends.data, language: .englishUnitedStates
        )
        #expect(presentation.isEmpty)
        #expect(presentation.calories.isEmpty && presentation.weights.isEmpty && presentation.block.isEmpty)
        #expect(presentation.recordedDays.allSatisfy { !$0 })
        #expect(presentation.latestWeight == nil)
    }

    @Test("Dates parse strictly and an unparsable day is dropped, not guessed")
    func dates() {
        #expect(ProgressTrendsPresentation.date(from: "2026-07-20") != nil)
        #expect(ProgressTrendsPresentation.date(from: "20/07/2026") == nil)
        let snapshot = TrendsSnapshot(
            days: 7,
            daily: [TrendsDay(date: "bad", caloriesConsumed: 1, caloriesTarget: nil, exerciseCalories: 0, proteinG: 0, proteinTarget: nil, waterConsumedML: 0, deficitAccumulated: 0, xpEarned: 0, dayClosed: false)],
            weights: []
        )
        #expect(ProgressTrendsPresentation(snapshot: snapshot, language: .portugueseBrazil).isEmpty)
        #expect(ProgressTrendsPresentation.kilograms(78.4, language: .englishUnitedStates) == "78.4 kg")
    }

    @Test("Trends copy exists in both languages", arguments: SupportedAppLanguage.allCases)
    func copyExists(_ language: SupportedAppLanguage) throws {
        for key in ["progress.trends.title", "progress.trends.weight", "progress.trends.calories", "progress.trends.block",
                    "progress.trends.days", "progress.trends.days.value", "progress.trends.empty", "progress.trends.unavailable",
                    "progress.trends.target", "progress.trends.over", "progress.trends.under",
                    "progress.trends.weight.accessibility", "progress.trends.calories.accessibility"] {
            let text = try AppLocalization.string(String.LocalizationValue(key), for: language)
            #expect(text != key && !text.isEmpty, "\(key) / \(language)")
        }
    }
}
