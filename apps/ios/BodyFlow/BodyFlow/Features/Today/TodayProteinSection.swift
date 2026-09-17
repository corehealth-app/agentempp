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
    @Environment(\.locale) private var locale

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label(copy("today.protein.title"), systemImage: "leaf")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                FixtureMetricRow(
                    title: copy("metric.consumed"),
                    value: TodayValueFormatter.grams(descriptor.consumedG)
                )
                Divider()
                FixtureMetricRow(
                    title: copy("metric.target"),
                    value: TodayValueFormatter.optionalGrams(
                        descriptor.targetG,
                        language: language
                    )
                )
                Divider()
                FixtureMetricRow(
                    title: copy("metric.remaining"),
                    value: TodayValueFormatter.optionalGrams(
                        descriptor.remainingG,
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
                FixtureMetricRow(
                    title: copy("metric.status"),
                    value: descriptor.status
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.protein")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
