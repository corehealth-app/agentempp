import SwiftUI

struct TodayHydrationDescriptor: Equatable, Sendable {
    let consumedML: Int
    let targetML: Int?
    let remainingML: Int?
    let percentage: Int?
    let status: String

    var targetText: String {
        TodayValueFormatter.optionalMilliliters(targetML)
    }

    var remainingText: String {
        TodayValueFormatter.optionalMilliliters(remainingML)
    }
}

@MainActor
struct TodayHydrationSection: View {
    let descriptor: TodayHydrationDescriptor

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label("Hidratação", systemImage: "drop")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                FixtureMetricRow(
                    title: "Consumido",
                    value: TodayValueFormatter.milliliters(descriptor.consumedML)
                )
                Divider()
                FixtureMetricRow(title: "Meta", value: descriptor.targetText)
                Divider()
                FixtureMetricRow(title: "Restante", value: descriptor.remainingText)
                if let percentage = descriptor.percentage {
                    Divider()
                    FixtureMetricRow(
                        title: "Progresso informado",
                        value: "\(percentage)%"
                    )
                }
                Divider()
                Label(descriptor.status, systemImage: "info.circle")
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(
            "\(TodayValueFormatter.milliliters(descriptor.consumedML)); meta \(descriptor.targetText)"
        )
        .accessibilityIdentifier("today.hydration")
    }
}
