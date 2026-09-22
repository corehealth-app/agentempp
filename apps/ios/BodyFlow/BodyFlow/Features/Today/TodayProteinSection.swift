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
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Label(copy("today.protein.title"), systemImage: "leaf")
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                // Received consumed value as the tile's summary figure; the
                // caption keeps its official meaning. Unchanged formatting.
                TodaySummaryFigure(
                    value: TodayValueFormatter.grams(descriptor.consumedG),
                    caption: copy("metric.consumed")
                )

                // Consumed stays the always-visible official value; the
                // remaining fields are the same unabridged data, moved
                // behind a native disclosure so this reads as a compact
                // summary next to Energy/Hydration rather than a long table.
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
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
                    .padding(.top, BodyFlowSpacing.sm)
                } label: {
                    TodayDisclosureLabel(title: copy("today.energy.details.title"))
                }
                .font(BodyFlowTypography.headline)
                .accessibilityIdentifier("today.protein.details")
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
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

/// Presentation-only summary figure for Today's compact tiles: a received,
/// already-formatted value with its official caption, read as one element.
@MainActor
struct TodaySummaryFigure: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(BodyFlowTypography.metricSmall)
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value)
    }
}

/// Leading-aligned disclosure title. A plain string title is laid out centred
/// by the system disclosure style once it wraps at accessibility sizes.
@MainActor
struct TodayDisclosureLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
