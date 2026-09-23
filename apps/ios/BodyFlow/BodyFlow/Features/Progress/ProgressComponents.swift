import Foundation
import SwiftUI

struct ProgressMedalRow: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let offset: Int
        let text: String
    }

    let id: ID
    let text: String

    init(offset: Int, text: String) {
        id = ID(offset: offset, text: text)
        self.text = text
    }
}

struct ProgressTabSelectionAction: Equatable, Sendable {
    let destination: AppTab

    @MainActor
    func perform(on selection: Binding<AppTab>) {
        selection.wrappedValue = destination
    }
}

enum ProgressActionColorToken: Equatable, Sendable {
    case brandPrimary
    case onPrimary
    case achievement
    case onAchievement

    var color: Color {
        switch self {
        case .brandPrimary: BodyFlowColor.color(.brandPrimary)
        case .onPrimary: BodyFlowColor.color(.onPrimary)
        case .achievement: BodyFlowColor.achievement
        case .onAchievement: BodyFlowColor.onAchievement
        }
    }
}

struct ProgressActionAppearance: Equatable, Sendable {
    let background: ProgressActionColorToken
    let foreground: ProgressActionColorToken

    static let streakRestart = ProgressActionAppearance(
        background: .brandPrimary,
        foreground: .onPrimary
    )
}

enum ProgressGamificationSectionKind: Hashable, Sendable {
    case officialSummary
    case streakRestart
    case earnedMedals
    case missionsUnavailable
}

enum ProgressGamificationSection: Identifiable, Equatable, Sendable {
    case officialSummary
    case streakRestart(
        message: String,
        actionTitle: String,
        action: ProgressTabSelectionAction,
        appearance: ProgressActionAppearance
    )
    case earnedMedals(rows: [ProgressMedalRow], emptyMessage: String?)
    case missionsUnavailable(String)

    var id: ProgressGamificationSectionKind { kind }

    var kind: ProgressGamificationSectionKind {
        switch self {
        case .officialSummary: .officialSummary
        case .streakRestart: .streakRestart
        case .earnedMedals: .earnedMedals
        case .missionsUnavailable: .missionsUnavailable
        }
    }
}

struct ProgressPresentation: Equatable, Sendable {
    let xpText: String
    let levelText: String
    let currentStreakText: String
    let longestStreakText: String
    let completedBlocksText: String
    let deficitBlockText: String
    let weightText: String
    let bodyFatText: String
    let badges: [String]
    let medalRows: [ProgressMedalRow]
    let streakRestartMessage: String?
    let streakRestartActionTitle: String?
    let streakRestartDestination: AppTab?
    let missionsUnavailableText: String
    let gamificationSections: [ProgressGamificationSection]
    let lastActiveDateText: String
    let nextReevaluationText: String
    let updatedAtText: String

    init(
        snapshot: ProgressSnapshot,
        language: SupportedAppLanguage = .portugueseBrazil
    ) {
        xpText = "\(Self.integer(snapshot.xpTotal, language: language)) XP"
        levelText = "\(Self.copy("progress.level", language)) \(Self.integer(snapshot.level, language: language))"
        currentStreakText = Self.days(snapshot.currentStreak, language: language)
        longestStreakText = Self.days(snapshot.longestStreak, language: language)
        completedBlocksText = Self.integer(snapshot.blocksCompleted, language: language)
        deficitBlockText = "\(Self.integer(snapshot.deficitBlock, language: language)) kcal"
        weightText = snapshot.currentWeight.map {
            "\(Self.decimal($0, language: language)) kg"
        } ?? Self.copy("progress.not-available", language)
        bodyFatText = snapshot.currentBodyFatPercent.map {
            "\(Self.decimal($0, language: language))%"
        } ?? Self.copy("progress.not-available", language)
        badges = snapshot.badgesEarned
        medalRows = snapshot.badgesEarned.enumerated().map { offset, text in
            ProgressMedalRow(offset: offset, text: text)
        }
        if snapshot.currentStreak == 0 {
            streakRestartMessage = Self.copy("progress.streak.restart-message", language)
            streakRestartActionTitle = Self.copy("progress.streak.restart-action", language)
            streakRestartDestination = .today
        } else {
            streakRestartMessage = nil
            streakRestartActionTitle = nil
            streakRestartDestination = nil
        }
        missionsUnavailableText = Self.copy("progress.missions.unavailable", language)
        var sections: [ProgressGamificationSection] = [.officialSummary]
        if
            let message = streakRestartMessage,
            let actionTitle = streakRestartActionTitle,
            let destination = streakRestartDestination
        {
            sections.append(
                .streakRestart(
                    message: message,
                    actionTitle: actionTitle,
                    action: ProgressTabSelectionAction(destination: destination),
                    appearance: .streakRestart
                )
            )
        }
        sections.append(
            .earnedMedals(
                rows: medalRows,
                emptyMessage: medalRows.isEmpty
                    ? Self.copy("progress.medals.empty", language) : nil
            )
        )
        sections.append(.missionsUnavailable(missionsUnavailableText))
        gamificationSections = sections
        lastActiveDateText = snapshot.lastActiveDate.map {
            Self.date($0, language: language)
        } ?? Self.copy("progress.not-available", language)
        nextReevaluationText = snapshot.nextReevaluation.map {
            Self.date($0, language: language)
        } ?? Self.copy("progress.not-available", language)
        updatedAtText = Self.timestamp(snapshot.updatedAt, language: language)
    }

    private static func integer(
        _ value: Int,
        language: SupportedAppLanguage
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func decimal(
        _ value: Decimal,
        language: SupportedAppLanguage
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static func date(
        _ value: String,
        language: SupportedAppLanguage
    ) -> String {
        let source = DateFormatter()
        source.locale = Locale(identifier: "en_US_POSIX")
        source.timeZone = TimeZone(secondsFromGMT: 0)
        source.dateFormat = "yyyy-MM-dd"
        guard let date = source.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = language.formattingLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = language == .englishUnitedStates
            ? "MM/dd/yyyy" : "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private static func timestamp(
        _ value: APITimestamp,
        language: SupportedAppLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.formattingLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = language == .englishUnitedStates
            ? "MM/dd/yyyy" : "dd/MM/yyyy"
        return formatter.string(from: value.value)
    }

    private static func days(
        _ value: Int,
        language: SupportedAppLanguage
    ) -> String {
        let key: String.LocalizationValue
        if value == 1 {
            key = "progress.day.singular"
        } else {
            key = "progress.day.plural"
        }
        return "\(integer(value, language: language)) \(copy(key, language))"
    }

    private static func copy(
        _ key: String.LocalizationValue,
        _ language: SupportedAppLanguage
    ) -> String {
        ProgressCopy.string(key, language: language)
    }
}

enum ProgressCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }
}

/// The progress screen: one heading, the patient's body and consistency
/// figures in one card, the official summary in its own card, achievements
/// (restart, medals, missions) in a third, and the reference dates as a quiet
/// provenance block. Every value is the server's; nothing is derived here.
@MainActor
struct ProgressContentView: View {
    let presentation: ProgressPresentation
    @Binding var selectedTab: AppTab
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            BodyFlowSectionHeader(copy("progress.title"))

            bodyCard

            if presentation.gamificationSections.contains(where: { $0.kind == .officialSummary }) {
                summaryCard
            }

            if !achievementSections.isEmpty {
                achievementsCard(achievementSections)
            }

            datesBlock
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.received-values")
    }

    /// The official sections that are not the summary itself, in the
    /// presentation's order: restart (when the streak is zero), medals,
    /// missions.
    private var achievementSections: [ProgressGamificationSection] {
        presentation.gamificationSections.filter { $0.kind != .officialSummary }
    }

    // MARK: Card A — measurements and consistency

    private var bodyCard: some View {
        BodyFlowCard(surface: .card) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                metricGroup(copy("progress.section.measurements")) {
                    metricRow(
                        copy("progress.metric.current-weight"),
                        presentation.weightText,
                        symbol: .weight
                    )
                    Divider()
                    metricRow(
                        copy("progress.metric.body-fat"),
                        presentation.bodyFatText,
                        symbol: .bodyComposition
                    )
                }
                .accessibilityIdentifier("progress.measurements")

                Divider()

                metricGroup(copy("progress.section.consistency")) {
                    metricRow(
                        copy("progress.metric.current-streak"),
                        presentation.currentStreakText,
                        symbol: .streak
                    )
                    Divider()
                    metricRow(
                        copy("progress.metric.longest-streak"),
                        presentation.longestStreakText,
                        symbol: .longestStreak
                    )
                }
                .accessibilityIdentifier("progress.consistency")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.body")
    }

    // MARK: Card B — official summary

    private var summaryCard: some View {
        BodyFlowCard(surface: .card) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                groupHeading(copy("progress.section.summary"))
                metricRow(copy("progress.metric.xp-total"), presentation.xpText, symbol: .xp)
                Divider()
                Label {
                    Text(presentation.levelText)
                        .font(BodyFlowTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(symbol: .level)
                        .foregroundStyle(BodyFlowColor.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.levelText)
                Divider()
                metricRow(
                    copy("progress.metric.completed-blocks"),
                    presentation.completedBlocksText,
                    symbol: .completedBlocks
                )
                Divider()
                metricRow(
                    copy("progress.metric.reported-deficit"),
                    presentation.deficitBlockText,
                    symbol: .deficit
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy("progress.summary.accessibility"))
        .accessibilityIdentifier("progress.summary")
    }

    // MARK: Card C — achievements

    private func achievementsCard(
        _ sections: [ProgressGamificationSection]
    ) -> some View {
        BodyFlowCard(surface: .card) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                groupHeading(copy("progress.section.achievements"))
                ForEach(Array(sections.enumerated()), id: \.element.id) { offset, section in
                    if offset > 0 {
                        Divider()
                    }
                    achievementSection(section)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.achievements")
    }

    @ViewBuilder
    private func achievementSection(_ section: ProgressGamificationSection) -> some View {
        switch section {
        case .officialSummary:
            EmptyView()
        case let .streakRestart(message, actionTitle, action, appearance):
            streakRestartBlock(
                message: message,
                actionTitle: actionTitle,
                action: action,
                appearance: appearance
            )
        case let .earnedMedals(rows, emptyMessage):
            medalsBlock(rows: rows, emptyMessage: emptyMessage)
        case let .missionsUnavailable(text):
            BodyFlowStatusLine(text, kind: .unavailable, font: BodyFlowTypography.body)
                .accessibilityIdentifier("progress.missions.unavailable")
        }
    }

    private func streakRestartBlock(
        message: String,
        actionTitle: String,
        action: ProgressTabSelectionAction,
        appearance: ProgressActionAppearance
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(message)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                action.perform(on: $selectedTab)
            } label: {
                Text(actionTitle)
                    .frame(minHeight: BodyFlowSpacing.minimumTapTarget)
            }
            .buttonStyle(BodyFlowButtonStyle(role: Self.role(for: appearance)))
            .accessibilityIdentifier("progress.streak.resume-today")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.streak.restart")
    }

    /// The presentation keeps naming the restart's colors; the button role
    /// that carries exactly that pair renders it.
    static func role(for appearance: ProgressActionAppearance) -> BodyFlowButtonRole {
        appearance.background == .brandPrimary && appearance.foreground == .onPrimary
            ? .primary
            : .secondary
    }

    private func medalsBlock(rows: [ProgressMedalRow], emptyMessage: String?) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(copy("progress.medals.title"))
                .font(BodyFlowTypography.supporting)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            if let emptyMessage {
                Text(emptyMessage)
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows) { medal in
                Label {
                    Text(medal.text)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(symbol: .medal)
                        .foregroundStyle(BodyFlowColor.achievement)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(medal.text)
                .accessibilityIdentifier("progress.medal.\(medal.id.offset)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.badges")
    }

    // MARK: Provenance

    private var datesBlock: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(copy("progress.section.dates"))
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            ProgressProvenanceRow(
                title: copy("progress.metric.last-activity"),
                value: presentation.lastActiveDateText
            )
            ProgressProvenanceRow(
                title: copy("progress.metric.next-reevaluation"),
                value: presentation.nextReevaluationText
            )
            ProgressProvenanceRow(
                title: copy("progress.metric.updated-at"),
                value: presentation.updatedAtText
            )
        }
        .padding(.horizontal, BodyFlowSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.dates")
    }

    // MARK: Building blocks

    private func metricGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            groupHeading(title)
            content()
        }
        .accessibilityElement(children: .contain)
    }

    private func groupHeading(_ title: String) -> some View {
        Text(verbatim: title)
            .font(BodyFlowTypography.cardTitle)
            .foregroundStyle(BodyFlowColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func metricRow(
        _ title: String,
        _ value: String,
        symbol: BodyFlowSymbol
    ) -> some View {
        FixtureMetricRow(title: title, value: value, systemImage: symbol.systemName)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        ProgressCopy.string(key, language: language)
    }
}

/// A reference date: label and received value in the supporting style, so
/// the block reads as provenance under the cards rather than as a fourth
/// card of figures.
@MainActor
private struct ProgressProvenanceRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    titleText
                    valueText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                    titleText
                    Spacer(minLength: BodyFlowSpacing.sm)
                    valueText
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(verbatim: title)
            .font(BodyFlowTypography.supporting)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(verbatim: value)
            .font(BodyFlowTypography.supporting)
            .foregroundStyle(BodyFlowColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
