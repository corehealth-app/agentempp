import SwiftUI

struct TodayBlockDescriptor: Equatable, Sendable {
    let enabled: Bool?
    let availability: String?
    let targetKcal: Int?
    let currentKcal: Int?
    let percentage: Int?
    let completedBlocks: Int?
    let totalCreditedKcal: Int?
    let source: String?

    var targetText: String {
        TodayValueFormatter.optionalKcal(targetKcal)
    }

    var currentText: String {
        TodayValueFormatter.optionalKcal(currentKcal)
    }
}

@MainActor
struct TodayBlockCard: View {
    let descriptor: TodayBlockDescriptor

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label("Bloco 7.700", systemImage: "circle.hexagongrid")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                FixtureMetricRow(title: "Meta", value: descriptor.targetText)
                Divider()
                FixtureMetricRow(title: "Atual", value: descriptor.currentText)
                if let percentage = descriptor.percentage {
                    Divider()
                    FixtureMetricRow(
                        title: "Percentual informado",
                        value: "\(percentage)%"
                    )
                }
                if let completedBlocks = descriptor.completedBlocks {
                    Divider()
                    FixtureMetricRow(
                        title: "Blocos concluídos",
                        value: TodayValueFormatter.integer(completedBlocks)
                    )
                }
                if let totalCreditedKcal = descriptor.totalCreditedKcal {
                    Divider()
                    FixtureMetricRow(
                        title: "Total creditado",
                        value: TodayValueFormatter.kcal(totalCreditedKcal)
                    )
                }
                Label(
                    descriptor.availability ?? "Indisponível",
                    systemImage: descriptor.enabled == true
                        ? "checkmark.circle"
                        : "info.circle"
                )
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(
            "Meta \(descriptor.targetText); atual \(descriptor.currentText)"
        )
        .accessibilityIdentifier("today.block")
    }
}
