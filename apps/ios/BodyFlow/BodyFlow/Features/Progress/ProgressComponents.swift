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
    case achievement
    case onAchievement

    var color: Color {
        switch self {
        case .achievement: BodyFlowColor.achievement
        case .onAchievement: BodyFlowColor.onAchievement
        }
    }
}

struct ProgressActionAppearance: Equatable, Sendable {
    let background: ProgressActionColorToken
    let foreground: ProgressActionColorToken

    static let streakRestart = ProgressActionAppearance(
        background: .achievement,
        foreground: .onAchievement
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

    init(snapshot: ProgressSnapshot) {
        xpText = "\(Self.integer(snapshot.xpTotal)) XP"
        levelText = "Nível \(Self.integer(snapshot.level))"
        currentStreakText = "\(Self.integer(snapshot.currentStreak)) dias"
        longestStreakText = "\(Self.integer(snapshot.longestStreak)) dias"
        completedBlocksText = Self.integer(snapshot.blocksCompleted)
        deficitBlockText = "\(Self.integer(snapshot.deficitBlock)) kcal"
        weightText = snapshot.currentWeight.map { "\(Self.decimal($0)) kg" }
            ?? "Indisponível"
        bodyFatText = snapshot.currentBodyFatPercent.map { "\(Self.decimal($0))%" }
            ?? "Indisponível"
        badges = snapshot.badgesEarned
        medalRows = snapshot.badgesEarned.enumerated().map { offset, text in
            ProgressMedalRow(offset: offset, text: text)
        }
        if snapshot.currentStreak == 0 {
            streakRestartMessage = "Sua sequência pode recomeçar hoje. O que você já construiu continua contando."
            streakRestartActionTitle = "Retomar em Hoje"
            streakRestartDestination = .today
        } else {
            streakRestartMessage = nil
            streakRestartActionTitle = nil
            streakRestartDestination = nil
        }
        missionsUnavailableText = "Missões diárias — Indisponível nesta versão."
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
                emptyMessage: medalRows.isEmpty ? "Nenhuma medalha conquistada." : nil
            )
        )
        sections.append(.missionsUnavailable(missionsUnavailableText))
        gamificationSections = sections
        lastActiveDateText = snapshot.lastActiveDate.map(Self.date) ?? "Indisponível"
        nextReevaluationText = snapshot.nextReevaluation.map(Self.date) ?? "Indisponível"
        updatedAtText = Self.timestamp(snapshot.updatedAt)
    }

    private static func integer(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func decimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static func date(_ value: String) -> String {
        let source = DateFormatter()
        source.locale = Locale(identifier: "en_US_POSIX")
        source.timeZone = TimeZone(secondsFromGMT: 0)
        source.dateFormat = "yyyy-MM-dd"
        guard let date = source.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private static func timestamp(_ value: APITimestamp) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: value.value)
    }
}

@MainActor
struct ProgressContentView: View {
    let presentation: ProgressPresentation
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Text("CONSISTÊNCIA")
                    .font(BodyFlowTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(BodyFlowColor.accent)
                Text("Seu progresso")
                    .font(BodyFlowTypography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(BodyFlowColor.primaryText)
            }

            ForEach(presentation.gamificationSections) { section in
                gamificationSection(section)
            }
            measurementsCard
            datesCard
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.received-values")
    }

    private var progressCard: some View {
        BodyFlowCard {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: "XP total", value: presentation.xpText, systemImage: "sparkles")
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
                FixtureMetricRow(title: "Sequência atual", value: presentation.currentStreakText, systemImage: "flame")
                Divider()
                FixtureMetricRow(title: "Maior sequência", value: presentation.longestStreakText, systemImage: "trophy")
                Divider()
                FixtureMetricRow(title: "Blocos concluídos", value: presentation.completedBlocksText, systemImage: "checkmark.seal")
                Divider()
                FixtureMetricRow(title: "Déficit informado", value: presentation.deficitBlockText, systemImage: "arrow.down.circle")
            }
        }
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
        BodyFlowCard {
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
        .accessibilityIdentifier("progress.streak.restart")
    }

    private func medalsCard(rows: [ProgressMedalRow], emptyMessage: String?) -> some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text("Medalhas conquistadas")
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
                            .foregroundStyle(BodyFlowColor.accent)
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
        .accessibilityIdentifier("progress.badges")
    }

    private func missionsUnavailableCard(text: String) -> some View {
        BodyFlowCard {
            Text(text)
                .font(BodyFlowTypography.body)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("progress.missions.unavailable")
    }

    private var measurementsCard: some View {
        BodyFlowCard {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: "Peso atual", value: presentation.weightText, systemImage: "scalemass")
                Divider()
                FixtureMetricRow(title: "Gordura corporal", value: presentation.bodyFatText, systemImage: "figure")
            }
        }
        .accessibilityIdentifier("progress.measurements")
    }

    private var datesCard: some View {
        BodyFlowCard {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: "Última atividade", value: presentation.lastActiveDateText)
                Divider()
                FixtureMetricRow(title: "Próxima reavaliação", value: presentation.nextReevaluationText)
                Divider()
                FixtureMetricRow(title: "Atualizado em", value: presentation.updatedAtText)
            }
        }
        .accessibilityIdentifier("progress.dates")
    }
}
