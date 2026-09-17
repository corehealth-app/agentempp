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
    @Environment(\.locale) private var locale

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label(copy("today.hydration.title"), systemImage: "drop")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                FixtureMetricRow(
                    title: copy("metric.consumed"),
                    value: TodayValueFormatter.milliliters(
                        descriptor.consumedML,
                        language: language
                    )
                )
                Divider()
                FixtureMetricRow(
                    title: copy("metric.target"),
                    value: TodayValueFormatter.optionalMilliliters(
                        descriptor.targetML,
                        language: language
                    )
                )
                Divider()
                FixtureMetricRow(
                    title: copy("metric.remaining"),
                    value: TodayValueFormatter.optionalMilliliters(
                        descriptor.remainingML,
                        language: language
                    )
                )
                if let percentage = descriptor.percentage {
                    Divider()
                    FixtureMetricRow(
                        title: copy("metric.reported-progress"),
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
            "\(TodayValueFormatter.milliliters(descriptor.consumedML, language: language)); \(copy("metric.target").lowercased()) \(TodayValueFormatter.optionalMilliliters(descriptor.targetML, language: language))"
        )
        .accessibilityIdentifier("today.hydration")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
