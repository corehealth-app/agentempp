import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

@Suite("Progress Presentation")
struct ProgressPresentationTests {
    @Test("presentation formats only received progress values")
    func receivedValues() {
        let presentation = ProgressPresentation(snapshot: BodyFlowTestFixtures.progressSnapshot)

        #expect(presentation.xpText == "12.345 XP")
        #expect(presentation.levelText == "Nível 13")
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

    @Test("maximum official gamification integers remain literal")
    func maximumGamificationIntegersRemainLiteral() {
        let presentation = ProgressPresentation(
            snapshot: snapshot(
                xpTotal: Int.max,
                level: Int.max,
                currentStreak: Int.max,
                longestStreak: Int.max
            )
        )

        #expect(presentation.xpText == "9.223.372.036.854.775.807 XP")
        #expect(presentation.levelText == "Nível 9.223.372.036.854.775.807")
        #expect(presentation.currentStreakText == "9.223.372.036.854.775.807 dias")
        #expect(presentation.longestStreakText == "9.223.372.036.854.775.807 dias")
    }

    @Test("duplicate medals retain positional identity")
    func duplicateMedalsRemainSeparate() {
        let presentation = ProgressPresentation(
            snapshot: snapshot(badges: ["Constância", "Constância"])
        )
        let rows = presentation.medalRows

        #expect(rows.map(\.text) == ["Constância", "Constância"])
        #expect(Set(rows.map(\.id)).count == 2)
    }

    @Test("empty earned medals section remains visible")
    func emptyEarnedMedalsSectionRemainsVisible() throws {
        let presentation = ProgressPresentation(snapshot: snapshot(badges: []))
        let section = try #require(
            presentation.gamificationSections.first { $0.kind == .earnedMedals }
        )
        guard case let .earnedMedals(rows, emptyMessage) = section else {
            Issue.record("Expected the earned-medals section")
            return
        }

        #expect(rows.isEmpty)
        #expect(emptyMessage == "Nenhuma medalha conquistada.")
    }

    @Test("zero streak offers supportive Today restart only")
    func zeroStreakOffersSupportiveTodayRestart() {
        let presentation = ProgressPresentation(
            snapshot: snapshot(currentStreak: 0)
        )

        #expect(
            presentation.streakRestartMessage
                == "Sua sequência pode recomeçar hoje. O que você já construiu continua contando."
        )
        #expect(presentation.streakRestartActionTitle == "Retomar em Hoje")
        #expect(presentation.streakRestartDestination == .today)
    }

    @Test("nonzero streak omits restart presentation")
    func nonzeroStreakOmitsRestartPresentation() {
        let presentation = ProgressPresentation(
            snapshot: snapshot(currentStreak: 4)
        )

        #expect(presentation.streakRestartMessage == nil)
        #expect(presentation.streakRestartActionTitle == nil)
        #expect(presentation.streakRestartDestination == nil)
    }

    @Test("daily missions remain bounded unavailable")
    func dailyMissionsRemainUnavailable() {
        let presentation = ProgressPresentation(snapshot: BodyFlowTestFixtures.progressSnapshot)

        #expect(presentation.missionsUnavailableText == "Missões diárias — Indisponível nesta versão.")
    }

    @Test("presentation exposes only official gamification sections")
    func onlyOfficialGamificationSectionsArePresented() {
        let nonzero = ProgressPresentation(snapshot: BodyFlowTestFixtures.progressSnapshot)
        let zero = ProgressPresentation(snapshot: snapshot(currentStreak: 0))

        #expect(nonzero.gamificationSections.map(\.kind) == [
            .officialSummary,
            .earnedMedals,
            .missionsUnavailable,
        ])
        #expect(zero.gamificationSections.map(\.kind) == [
            .officialSummary,
            .streakRestart,
            .earnedMedals,
            .missionsUnavailable,
        ])
    }

    @MainActor
    @Test("Today restart action changes only the selected tab")
    func todayRestartActionChangesOnlySelectedTab() throws {
        let presentation = ProgressPresentation(snapshot: snapshot(currentStreak: 0))
        let section = try #require(
            presentation.gamificationSections.first(where: { $0.kind == .streakRestart })
        )
        guard case let .streakRestart(_, _, action, _) = section else {
            Issue.record("Expected the official streak restart section")
            return
        }
        var selectedTab = AppTab.progress
        var writes: [AppTab] = []
        let selection = Binding(
            get: { selectedTab },
            set: { newValue in
                selectedTab = newValue
                writes.append(newValue)
            }
        )

        action.perform(on: selection)

        #expect(selectedTab == .today)
        #expect(writes == [.today])
    }

    @Test("Today restart uses semantic achievement colors with readable contrast")
    func todayRestartUsesReadableSemanticColors() throws {
        let presentation = ProgressPresentation(snapshot: snapshot(currentStreak: 0))
        let section = try #require(
            presentation.gamificationSections.first { $0.kind == .streakRestart }
        )
        guard case let .streakRestart(_, _, _, appearance) = section else {
            Issue.record("Expected the official streak restart section")
            return
        }

        #expect(appearance.background == .achievement)
        #expect(appearance.foreground == .onAchievement)

        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let foreground = UIColor(appearance.foreground.color)
                .resolvedColor(with: traits)
            let background = UIColor(appearance.background.color)
                .resolvedColor(with: traits)

            #expect(try contrastRatio(foreground: foreground, background: background) >= 4.5)
        }
    }

    private func snapshot(
        xpTotal: Int = 12_345,
        level: Int = 13,
        currentStreak: Int = 4,
        longestStreak: Int = 29,
        badges: [String] = ["badge-z", "badge-a"]
    ) -> ProgressSnapshot {
        let fixture = BodyFlowTestFixtures.progressSnapshot
        return ProgressSnapshot(
            xpTotal: xpTotal,
            level: level,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            blocksCompleted: fixture.blocksCompleted,
            deficitBlock: fixture.deficitBlock,
            currentWeight: fixture.currentWeight,
            currentBodyFatPercent: fixture.currentBodyFatPercent,
            badgesEarned: badges,
            lastActiveDate: fixture.lastActiveDate,
            nextReevaluation: fixture.nextReevaluation,
            updatedAt: fixture.updatedAt
        )
    }

    private func contrastRatio(
        foreground: UIColor,
        background: UIColor
    ) throws -> CGFloat {
        let foregroundLuminance = try relativeLuminance(of: foreground)
        let backgroundLuminance = try relativeLuminance(of: background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(of color: UIColor) throws -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        try #require(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return (0.2126 * linearize(red))
            + (0.7152 * linearize(green))
            + (0.0722 * linearize(blue))
    }

}
