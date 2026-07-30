import SwiftUI

struct TodayEnergyDescriptor: Equatable, Sendable {
    let targetKcal: Int?
    let consumedKcal: Int
    let remainingFoodKcal: Int
    let foodExcessKcal: Int
    let exerciseKcal: Int
    let dailyBalanceKcal: Int
    let dailyBalanceStatus: String

    var targetText: String {
        TodayValueFormatter.optionalKcal(targetKcal)
    }

    var consumedText: String {
        TodayValueFormatter.kcal(consumedKcal)
    }

    var remainingFoodText: String {
        TodayValueFormatter.kcal(remainingFoodKcal)
    }

    var foodExcessText: String {
        TodayValueFormatter.kcal(foodExcessKcal)
    }

    var exerciseText: String {
        TodayValueFormatter.kcal(exerciseKcal)
    }

    var netBalanceText: String {
        TodayValueFormatter.kcal(dailyBalanceKcal)
    }

    var remainingFoodAccessibilityValue: String {
        "\(TodayValueFormatter.integer(remainingFoodKcal)) quilocalorias; exercício excluído"
    }

    var netBalanceAccessibilityValue: String {
        let formatted = TodayValueFormatter.integer(dailyBalanceKcal)
        let signedValue = if formatted.hasPrefix("-") {
            "menos \(formatted.dropFirst())"
        } else {
            formatted
        }
        return "\(signedValue) quilocalorias; exercício incluído"
    }
}

@MainActor
struct TodayEnergySection: View {
    let descriptor: TodayEnergyDescriptor
    let completionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Label("Energia", systemImage: "bolt.heart")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.primaryText)

            if let completionMessage {
                Label(completionMessage, systemImage: "info.circle")
                    .font(BodyFlowTypography.body)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .padding(BodyFlowSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        BodyFlowColor.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .accessibilityIdentifier("today.completion.insufficient-data")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                    remainingFoodCard
                    netBalanceCard
                }
                VStack(spacing: BodyFlowSpacing.sm) {
                    remainingFoodCard
                    netBalanceCard
                }
            }

            BodyFlowCard {
                VStack(spacing: BodyFlowSpacing.sm) {
                    FixtureMetricRow(title: "Meta", value: descriptor.targetText)
                    Divider()
                    FixtureMetricRow(title: "Consumido", value: descriptor.consumedText)
                    Divider()
                    FixtureMetricRow(title: "Excesso alimentar", value: descriptor.foodExcessText)
                    Divider()
                    FixtureMetricRow(title: "Exercício", value: descriptor.exerciseText)
                    Divider()
                    FixtureMetricRow(
                        title: "Status do balanço",
                        value: descriptor.dailyBalanceStatus
                    )
                }
            }
        }
    }

    private var remainingFoodCard: some View {
        TodayEnergyMetricCard(
            title: "Restam para comida",
            value: descriptor.remainingFoodText,
            explanation: "Exercício excluído",
            systemImage: "fork.knife",
            accessibilityValue: descriptor.remainingFoodAccessibilityValue
        )
        .accessibilityIdentifier("today.energy.remaining-food")
    }

    private var netBalanceCard: some View {
        TodayEnergyMetricCard(
            title: "Déficit líquido",
            value: descriptor.netBalanceText,
            explanation: "Exercício incluído",
            systemImage: "plusminus",
            accessibilityValue: descriptor.netBalanceAccessibilityValue
        )
        .accessibilityIdentifier("today.energy.net-balance")
    }
}

@MainActor
private struct TodayEnergyMetricCard: View {
    let title: String
    let value: String
    let explanation: String
    let systemImage: String
    let accessibilityValue: String

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                Label(title, systemImage: systemImage)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                Text(value)
                    .font(BodyFlowTypography.title)
                    .fontWeight(.bold)
                    .foregroundStyle(BodyFlowColor.primaryText)
                Text(explanation)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }
}
