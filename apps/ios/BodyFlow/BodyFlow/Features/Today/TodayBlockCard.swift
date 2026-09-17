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
    @Environment(\.locale) private var locale

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label(copy("today.block.title"), systemImage: "circle.hexagongrid")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                FixtureMetricRow(
                    title: copy("metric.target"),
                    value: TodayValueFormatter.optionalKcal(
                        descriptor.targetKcal,
                        language: language
                    )
                )
                Divider()
                FixtureMetricRow(
                    title: copy("metric.current"),
                    value: TodayValueFormatter.optionalKcal(
                        descriptor.currentKcal,
                        language: language
                    )
                )
                if let percentage = descriptor.percentage {
                    Divider()
                    FixtureMetricRow(
                        title: copy("metric.reported-percentage"),
                        value: "\(percentage)%"
                    )
                }
                if let completedBlocks = descriptor.completedBlocks {
                    Divider()
                    FixtureMetricRow(
                        title: copy("today.block.completed"),
                        value: TodayValueFormatter.integer(
                            completedBlocks,
                            language: language
                        )
                    )
                }
                if let totalCreditedKcal = descriptor.totalCreditedKcal {
                    Divider()
                    FixtureMetricRow(
                        title: copy("today.block.credited"),
                        value: TodayValueFormatter.kcal(
                            totalCreditedKcal,
                            language: language
                        )
                    )
                }
                Label(
                    descriptor.availability
                        ?? copy("common.not-available"),
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
            "\(copy("metric.target")) \(TodayValueFormatter.optionalKcal(descriptor.targetKcal, language: language)); \(copy("metric.current").lowercased()) \(TodayValueFormatter.optionalKcal(descriptor.currentKcal, language: language))"
        )
        .accessibilityIdentifier("today.block")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
