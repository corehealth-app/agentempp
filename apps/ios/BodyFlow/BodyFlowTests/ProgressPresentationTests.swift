import Foundation
import SwiftUI
import Testing
import UIKit

@testable import BodyFlow

@Suite("Progress Presentation")
struct ProgressPresentationTests {
    @Test("official 80 kg measurement uses the supplied instant, source and locale")
    func profileWeightProvenance() throws {
        let snapshot = try JSONDecoder().decode(ProfileWeightSnapshot.self, from: Data(
            #"{"weight_kg":80,"weight_measured_at":"2026-10-01T16:15:33.319Z","weight_instant_source":"measured"}"#.utf8
        ))
        let timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let pt = ProfileWeightPresentation(snapshot: snapshot, language: .portugueseBrazil, timeZone: timeZone)
        #expect(pt.weightText == "80 kg")
        #expect(pt.dateText.hasPrefix("Medido em "))
        #expect(pt.dateText.contains("2026"))
        #expect(pt.dateText.contains("13:15"))
        let recorded = ProfileWeightPresentation(snapshot: ProfileWeightSnapshot(
            weightKG: 80, measuredAt: snapshot.measuredAt, instantSource: "recorded"
        ), language: .englishUnitedStates, timeZone: timeZone)
        #expect(recorded.dateText.hasPrefix("Recorded on "))
        let unknown = ProfileWeightPresentation(snapshot: ProfileWeightSnapshot(
            weightKG: 80, measuredAt: snapshot.measuredAt, instantSource: nil
        ), language: .portugueseBrazil, timeZone: timeZone)
        #expect(unknown.dateText == "Data não informada")
        let missing = ProfileWeightPresentation(snapshot: ProfileWeightSnapshot(
            weightKG: nil, measuredAt: nil, instantSource: nil
        ), language: .portugueseBrazil, timeZone: timeZone)
        #expect(missing.weightText == "Não disponível")
        #expect(missing.dateText == "Data não informada")
    }

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
        #expect(presentation.weightText == "Não disponível")
        #expect(presentation.bodyFatText == "Não disponível")
        #expect(presentation.weightText != "0 kg")
        #expect(presentation.bodyFatText != "0%")
    }

    @Test("English presentation localizes official values without changing badges")
    func englishPresentation() {
        let presentation = ProgressPresentation(
            snapshot: BodyFlowTestFixtures.progressSnapshot,
            language: .englishUnitedStates
        )

        #expect(presentation.xpText == "12,345 XP")
        #expect(presentation.levelText == "Level 13")
        #expect(presentation.currentStreakText == "4 days")
        #expect(presentation.longestStreakText == "29 days")
        #expect(presentation.completedBlocksText == "7")
        #expect(presentation.deficitBlockText == "611 kcal")
        #expect(presentation.weightText == "83.75 kg")
        #expect(presentation.bodyFatText == "18.25%")
        #expect(presentation.badges == ["badge-z", "badge-a"])
        #expect(presentation.medalRows.map(\.text) == ["badge-z", "badge-a"])
        #expect(presentation.lastActiveDateText == "07/28/2026")
        #expect(presentation.nextReevaluationText == "08/19/2026")
        #expect(presentation.updatedAtText == "07/29/2026")
    }

    @Test("English nil measurements stay distinct from literal zero")
    func englishOptionalMeasurementsRemainUnavailable() {
        let fixture = BodyFlowTestFixtures.progressSnapshot
        let presentation = ProgressPresentation(
            snapshot: ProgressSnapshot(
                xpTotal: fixture.xpTotal,
                level: fixture.level,
                currentStreak: fixture.currentStreak,
                longestStreak: fixture.longestStreak,
                blocksCompleted: fixture.blocksCompleted,
                deficitBlock: fixture.deficitBlock,
                currentWeight: nil,
                currentBodyFatPercent: nil,
                badgesEarned: fixture.badgesEarned,
                lastActiveDate: nil,
                nextReevaluation: nil,
                updatedAt: fixture.updatedAt
            ),
            language: .englishUnitedStates
        )

        #expect(presentation.weightText == "Not available")
        #expect(presentation.bodyFatText == "Not available")
        #expect(presentation.lastActiveDateText == "Not available")
        #expect(presentation.nextReevaluationText == "Not available")
        #expect(presentation.weightText != "0 kg")
        #expect(presentation.bodyFatText != "0%")
    }

    @Test("day units use the selected language and literal official count")
    func localizedSingularDay() {
        let official = snapshot(currentStreak: 1, longestStreak: 1)

        let portuguese = ProgressPresentation(snapshot: official)
        let english = ProgressPresentation(
            snapshot: official,
            language: .englishUnitedStates
        )

        #expect(portuguese.currentStreakText == "1 dia")
        #expect(portuguese.longestStreakText == "1 dia")
        #expect(english.currentStreakText == "1 day")
        #expect(english.longestStreakText == "1 day")
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

    @Test("English zero streak stays supportive and routes only to Today")
    func englishZeroStreakOffersSupportiveTodayRestart() {
        let presentation = ProgressPresentation(
            snapshot: snapshot(currentStreak: 0),
            language: .englishUnitedStates
        )

        #expect(
            presentation.streakRestartMessage
                == "Your streak can restart today. What you have built still counts."
        )
        #expect(presentation.streakRestartActionTitle == "Resume in Today")
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

    @Test("Today restart uses primary action colors rather than achievement gold")
    func todayRestartUsesReadablePrimaryActionColors() throws {
        let presentation = ProgressPresentation(snapshot: snapshot(currentStreak: 0))
        let section = try #require(
            presentation.gamificationSections.first { $0.kind == .streakRestart }
        )
        guard case let .streakRestart(_, _, _, appearance) = section else {
            Issue.record("Expected the official streak restart section")
            return
        }

        #expect(appearance.background == .brandPrimary)
        #expect(appearance.foreground == .onPrimary)

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
