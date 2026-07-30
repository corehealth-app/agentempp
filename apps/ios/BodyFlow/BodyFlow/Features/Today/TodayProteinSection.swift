import SwiftUI

struct TodayProteinDescriptor: Equatable, Sendable {
    let consumedG: Decimal
    let targetG: Decimal?
    let remainingG: Decimal?
    let percentage: Int?
    let status: String
}

@MainActor
struct TodayProteinSection: View {
    let descriptor: TodayProteinDescriptor

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label("Proteína", systemImage: "leaf")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                FixtureMetricRow(
                    title: "Consumido",
                    value: TodayValueFormatter.grams(descriptor.consumedG)
                )
                Divider()
                FixtureMetricRow(
                    title: "Meta",
                    value: TodayValueFormatter.optionalGrams(descriptor.targetG)
                )
                Divider()
                FixtureMetricRow(
                    title: "Restante",
                    value: TodayValueFormatter.optionalGrams(descriptor.remainingG)
                )
                if let percentage = descriptor.percentage {
                    Divider()
                    FixtureMetricRow(
                        title: "Progresso informado",
                        value: "\(percentage)%"
                    )
                }
                Divider()
                FixtureMetricRow(title: "Status", value: descriptor.status)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.protein")
    }
}
