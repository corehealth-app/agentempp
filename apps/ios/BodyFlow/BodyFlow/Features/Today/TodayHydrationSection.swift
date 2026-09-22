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
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Label(copy("today.hydration.title"), systemImage: "drop")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                // Received consumed value as the tile's summary figure; the
                // caption keeps its official meaning. Unchanged formatting.
                TodaySummaryFigure(
                    value: TodayValueFormatter.milliliters(
                        descriptor.consumedML,
                        language: language
                    ),
                    caption: copy("metric.consumed")
                )

                // Consumed stays the always-visible official value; the
                // remaining fields are the same unabridged data, moved
                // behind a native disclosure (mirrors Energy/Protein) so
                // this reads as a compact summary, not a long table. The
                // combined accessibilityValue below is unaffected — it is
                // computed independently of which rows are shown.
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
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
                    .padding(.top, BodyFlowSpacing.sm)
                } label: {
                    TodayDisclosureLabel(title: copy("today.energy.details.title"))
                }
                .font(BodyFlowTypography.headline)
                .accessibilityIdentifier("today.hydration.details")
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
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
