import Foundation
import SwiftUI

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
    let lastActiveDateText: String
    let nextReevaluationText: String
    let updatedAtText: String

    init(snapshot: ProgressSnapshot) {
        xpText = "\(Self.integer(snapshot.xpTotal)) XP"
        levelText = Self.integer(snapshot.level)
        currentStreakText = "\(Self.integer(snapshot.currentStreak)) dias"
        longestStreakText = "\(Self.integer(snapshot.longestStreak)) dias"
        completedBlocksText = Self.integer(snapshot.blocksCompleted)
        deficitBlockText = snapshot.deficitBlock.map { "\(Self.integer($0)) kcal" }
            ?? "Indisponível"
        weightText = snapshot.currentWeight.map { "\(Self.decimal($0)) kg" }
            ?? "Indisponível"
        bodyFatText = snapshot.currentBodyFatPercent.map { "\(Self.decimal($0))%" }
            ?? "Indisponível"
        badges = snapshot.badgesEarned
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

            progressCard
            measurementsCard
            datesCard

            if !presentation.badges.isEmpty {
                BodyFlowCard {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        Text("Conquistas")
                            .font(BodyFlowTypography.headline)
                        ForEach(presentation.badges, id: \.self) { badge in
                            Text(badge).font(BodyFlowTypography.body)
                        }
                    }
                }
                .accessibilityIdentifier("progress.badges")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.received-values")
    }

    private var progressCard: some View {
        BodyFlowCard {
            VStack(spacing: BodyFlowSpacing.sm) {
                FixtureMetricRow(title: "XP total", value: presentation.xpText, systemImage: "sparkles")
                Divider()
                FixtureMetricRow(title: "Nível", value: presentation.levelText, systemImage: "medal")
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
