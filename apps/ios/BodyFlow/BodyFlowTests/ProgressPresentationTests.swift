import Foundation
import Testing

@testable import BodyFlow

@Suite("Progress Presentation")
struct ProgressPresentationTests {
    @Test("presentation formats only received progress values")
    func receivedValues() {
        let presentation = ProgressPresentation(snapshot: BodyFlowTestFixtures.progressSnapshot)

        #expect(presentation.xpText == "12.345 XP")
        #expect(presentation.levelText == "13")
        #expect(presentation.currentStreakText == "4 dias")
        #expect(presentation.longestStreakText == "29 dias")
        #expect(presentation.completedBlocksText == "7")
        #expect(presentation.deficitBlockText == "611 kcal")
        #expect(presentation.weightText == "83,75 kg")
        #expect(presentation.bodyFatText == "18,25%")
        #expect(presentation.badges == ["badge-z", "badge-a"])
        #expect(presentation.lastActiveDateText == "28/07/2026")
        #expect(presentation.nextReevaluationText == "19/08/2026")
        #expect(presentation.updatedAtText == "29/07/2026")
    }

    @Test("missing measurements stay unavailable instead of becoming zero")
    func optionalMeasurementsRemainUnavailable() {
        var snapshot = BodyFlowTestFixtures.progressSnapshot
        snapshot = ProgressSnapshot(
            xpTotal: snapshot.xpTotal, level: snapshot.level,
            currentStreak: snapshot.currentStreak, longestStreak: snapshot.longestStreak,
            blocksCompleted: snapshot.blocksCompleted, deficitBlock: snapshot.deficitBlock,
            currentWeight: nil, currentBodyFatPercent: nil, badgesEarned: snapshot.badgesEarned,
            lastActiveDate: snapshot.lastActiveDate, nextReevaluation: snapshot.nextReevaluation,
            updatedAt: snapshot.updatedAt
        )

        let presentation = ProgressPresentation(snapshot: snapshot)
        #expect(presentation.weightText == "Indisponível")
        #expect(presentation.bodyFatText == "Indisponível")
        #expect(presentation.weightText != "0 kg")
        #expect(presentation.bodyFatText != "0%")
    }

    @Test("zero deficit block is displayed as literal official data")
    func zeroDeficitBlockRemainsVisible() {
        let snapshot = ProgressSnapshot(
            xpTotal: 12_345, level: 13, currentStreak: 4, longestStreak: 29,
            blocksCompleted: 7, deficitBlock: 0,
            currentWeight: Decimal(string: "83.75"),
            currentBodyFatPercent: Decimal(string: "18.25"),
            badgesEarned: ["badge-z", "badge-a"], lastActiveDate: "2026-07-28",
            nextReevaluation: "2026-08-19",
            updatedAt: BodyFlowTestFixtures.progressSnapshot.updatedAt
        )

        let presentation = ProgressPresentation(snapshot: snapshot)
        #expect(presentation.deficitBlockText == "0 kcal")
    }
}
