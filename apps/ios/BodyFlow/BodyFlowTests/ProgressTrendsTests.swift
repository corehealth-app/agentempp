import Foundation
import Testing

@testable import BodyFlow

@Suite("Progress trends")
struct ProgressTrendsTests {
    @Test("An unavailable target never classifies recorded food as below or above a target", arguments: [
        (nil as Int?, 650, nil as Bool?, nil as Int?), (0, 650, nil, nil), (-1, 650, nil, nil),
        (2_000, 1_800, false, 2_000), (2_000, 2_000, false, 2_000), (2_000, 2_200, true, 2_000),
        (nil, 0, nil, nil), (2_000, 0, false, 2_000),
    ])
    func calorieComparison(_ input: (Int?, Int, Bool?, Int?)) throws {
        let day = TrendsDay(date: "2026-11-18", caloriesConsumed: input.1, caloriesTarget: input.0,
            exerciseCalories: 0, proteinG: 25, proteinTarget: nil, waterConsumedML: 0,
            deficitAccumulated: nil, xpEarned: 15, dayClosed: false)
        let presentation = ProgressTrendsPresentation(
            snapshot: TrendsSnapshot(days: 7, daily: [day], weights: []), language: .portugueseBrazil
        )
        let bar = try #require(presentation.calories.first)
        let comparison: Bool? = bar.overTarget
        #expect(comparison == input.2)
        #expect(bar.consumed == input.1)
        #expect(bar.target == input.3)
        #expect(presentation.recordedDays.last == true)
    }

    @Test("A shared target line requires the same available target on every visible day", arguments: [
        ([2_000, 2_000] as [Int?], 2_000 as Int?),
        ([2_000, 2_100], nil), ([nil, 2_000], nil), ([2_000, nil], nil),
        ([nil, nil], nil), ([0, 0], nil),
    ])
    func commonCalorieTarget(_ input: ([Int?], Int?)) {
        let days = input.0.enumerated().map { index, target in
            TrendsDay(date: "2026-11-\(17 + index)", caloriesConsumed: 650, caloriesTarget: target,
                exerciseCalories: 0, proteinG: 25, proteinTarget: nil, waterConsumedML: 0,
                deficitAccumulated: nil, xpEarned: 15, dayClosed: false)
        }
        let presentation = ProgressTrendsPresentation(
            snapshot: TrendsSnapshot(days: 7, daily: days, weights: []), language: .portugueseBrazil
        )
        #expect(presentation.target == input.1)
        #expect(presentation.calories.map(\.consumed) == [650, 650])
    }

    @Test("Clinical calorie visibility suppresses comparisons without removing consumption")
    func hiddenCalorieTarget() throws {
        let day = TrendsDay(date: "2026-11-18", caloriesConsumed: 650, caloriesTarget: 2_000,
            exerciseCalories: 0, proteinG: 25, proteinTarget: nil, waterConsumedML: 0,
            deficitAccumulated: 400, xpEarned: 15, dayClosed: false)
        var snapshot = TrendsSnapshot(days: 7, daily: [day], weights: [])
        snapshot.clinicalPolicy = try JSONDecoder().decode(CurrentClinicalPolicy.self,
            from: Data(CurrentClinicalPolicyTests.policy.utf8))
        let presentation = ProgressTrendsPresentation(snapshot: snapshot, language: .portugueseBrazil)
        let bar = try #require(presentation.calories.first)
        let comparison: Bool? = bar.overTarget
        #expect(bar.target == nil)
        #expect(comparison == nil)
        #expect(presentation.target == nil)
        #expect(bar.consumed == 650)
        #expect(presentation.block.isEmpty)
    }

    @Test("clinical null accumulated block is a gap, preserving consumption and XP")
    func clinicalNullIsNotAZeroPoint() throws {
        let raw = #"{"date":"2026-10-26","calories_consumed":650,"calories_target":null,"exercise_calories":100,"protein_g":25,"protein_target":null,"water_consumed_ml":500,"deficit_accumulated":null,"xp_earned":15,"day_closed":true}"#
        let day = try JSONDecoder().decode(TrendsDay.self, from: Data(raw.utf8))
        #expect(day.deficitAccumulated == nil)
        #expect(day.xpEarned == 15)
        let presentation = ProgressTrendsPresentation(
            snapshot: TrendsSnapshot(days: 7, daily: [day], weights: []), language: .portugueseBrazil
        )
        #expect(presentation.block.isEmpty)
        #expect(presentation.calories.first?.consumed == 650)
        #expect(presentation.recordedDays.last == true)
    }
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
        #expect(presentation.calories.filter { $0.overTarget == true }.map(\.consumed) == [2_310, 2_120])
        #expect(presentation.target == 1_935)
        #expect(presentation.weights.map(\.kilograms) == [80.0, 79.1, 78.4])
        // The axis frames the measured range, never from zero.
        #expect(presentation.weightRange == 77.0...81.0)
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

    @Test("The window is calendar days ending at the latest record, not the last N rows")
    func windowIsCalendarDays() {
        func day(_ date: String, _ kcal: Int) -> TrendsDay {
            TrendsDay(date: date, caloriesConsumed: kcal, caloriesTarget: 2_000, exerciseCalories: 0, proteinG: 0,
                      proteinTarget: nil, waterConsumedML: 0, deficitAccumulated: 0, xpEarned: 0, dayClosed: true)
        }
        // Sparse records over five weeks; only the last seven calendar days count.
        let snapshot = TrendsSnapshot(
            days: 7,
            daily: [day("2026-09-01", 1), day("2026-09-10", 2), day("2026-09-27", 3), day("2026-09-29", 4), day("2026-10-01", 5)],
            weights: []
        )
        let presentation = ProgressTrendsPresentation(snapshot: snapshot, language: .portugueseBrazil)
        // Window = 25/09…01/10: three records inside, two outside.
        #expect(presentation.calories.map(\.consumed) == [3, 4, 5])
        #expect(presentation.block.count == 3)
        #expect(presentation.recordedDays == [false, false, true, false, true, false, true])
    }

    @Test("Trends copy exists in both languages", arguments: SupportedAppLanguage.allCases)
    func copyExists(_ language: SupportedAppLanguage) throws {
        for key in ["progress.trends.title", "progress.trends.weight", "progress.trends.calories", "progress.trends.block",
                    "progress.trends.days", "progress.trends.days.value", "progress.trends.empty", "progress.trends.unavailable",
                    "progress.trends.target", "progress.trends.over", "progress.trends.under",
                    "progress.trends.food", "progress.trends.no-target",
                    "progress.trends.weight.accessibility", "progress.trends.calories.accessibility"] {
            let text = try AppLocalization.string(String.LocalizationValue(key), for: language)
            #expect(text != key && !text.isEmpty, "\(key) / \(language)")
        }
    }
}
