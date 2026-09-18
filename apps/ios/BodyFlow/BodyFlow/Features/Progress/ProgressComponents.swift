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

@MainActor
struct ProgressContentView: View {
    let presentation: ProgressPresentation
    @Binding var selectedTab: AppTab
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text(copy("progress.eyebrow"))
                    .font(BodyFlowTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(BodyFlowColor.accent)
                Text(copy("progress.title"))
                    .font(BodyFlowTypography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(BodyFlowColor.primaryText)
            }

            measurementsCard
            consistencyCard
            ForEach(presentation.gamificationSections) { section in
                gamificationSection(section)
            }
            datesCard
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.received-values")
    }

    private var progressCard: some View {
        BodyFlowCard(surface: .card) {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: copy("progress.metric.xp-total"), value: presentation.xpText, systemImage: "sparkles")
                Divider()
                Label {
                    Text(presentation.levelText)
                        .font(BodyFlowTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "medal")
                        .foregroundStyle(BodyFlowColor.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.levelText)
                Divider()
                FixtureMetricRow(title: copy("progress.metric.completed-blocks"), value: presentation.completedBlocksText, systemImage: "checkmark.seal")
                Divider()
                FixtureMetricRow(title: copy("progress.metric.reported-deficit"), value: presentation.deficitBlockText, systemImage: "arrow.down.circle")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy("progress.summary.accessibility"))
        .accessibilityIdentifier("progress.summary")
    }

    @ViewBuilder
    private func gamificationSection(_ section: ProgressGamificationSection) -> some View {
        switch section {
        case .officialSummary:
            progressCard
        case let .streakRestart(message, actionTitle, action, appearance):
            streakRestartCard(
                message: message,
                actionTitle: actionTitle,
                action: action,
                appearance: appearance
            )
        case let .earnedMedals(rows, emptyMessage):
            medalsCard(rows: rows, emptyMessage: emptyMessage)
        case let .missionsUnavailable(text):
            missionsUnavailableCard(text: text)
        }
    }

    private func streakRestartCard(
        message: String,
        actionTitle: String,
        action: ProgressTabSelectionAction,
        appearance: ProgressActionAppearance
    ) -> some View {
        BodyFlowCard(surface: .card) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(message)
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    action.perform(on: $selectedTab)
                } label: {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(appearance.foreground.color)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.background.color)
                .accessibilityIdentifier("progress.streak.resume-today")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.streak.restart")
    }

    private func medalsCard(rows: [ProgressMedalRow], emptyMessage: String?) -> some View {
        BodyFlowCard(surface: .card) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(copy("progress.medals.title"))
                    .font(BodyFlowTypography.headline)
                    .accessibilityAddTraits(.isHeader)
                if let emptyMessage {
                    Text(emptyMessage)
                        .font(BodyFlowTypography.body)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rows) { medal in
                    HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                        Image(systemName: "medal")
                            .foregroundStyle(BodyFlowColor.achievement)
                            .accessibilityHidden(true)
                        Text(medal.text)
                            .font(BodyFlowTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(medal.text)
                    .accessibilityIdentifier("progress.medal.\(medal.id.offset)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.badges")
    }

    private func missionsUnavailableCard(text: String) -> some View {
        BodyFlowCard(surface: .card) {
            Text(text)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("progress.missions.unavailable")
    }

    private var measurementsCard: some View {
        BodyFlowCard(surface: .card) {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: copy("progress.metric.current-weight"), value: presentation.weightText, systemImage: "scalemass")
                Divider()
                FixtureMetricRow(title: copy("progress.metric.body-fat"), value: presentation.bodyFatText, systemImage: "figure")
            }
        }
        .accessibilityIdentifier("progress.measurements")
    }

    private var consistencyCard: some View {
        BodyFlowCard(surface: .card) {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: copy("progress.metric.current-streak"), value: presentation.currentStreakText, systemImage: "flame")
                Divider()
                FixtureMetricRow(title: copy("progress.metric.longest-streak"), value: presentation.longestStreakText, systemImage: "trophy")
            }
        }
        .accessibilityIdentifier("progress.consistency")
    }

    private var datesCard: some View {
        BodyFlowCard(surface: .card) {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: copy("progress.metric.last-activity"), value: presentation.lastActiveDateText)
                Divider()
                FixtureMetricRow(title: copy("progress.metric.next-reevaluation"), value: presentation.nextReevaluationText)
                Divider()
                FixtureMetricRow(title: copy("progress.metric.updated-at"), value: presentation.updatedAtText)
            }
        }
        .accessibilityIdentifier("progress.dates")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        ProgressCopy.string(key, language: language)
    }
}
