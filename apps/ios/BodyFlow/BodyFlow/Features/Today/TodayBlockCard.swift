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

    /// The server's `availability` code in the reader's language; an unknown
    /// code is shown as sent rather than guessed.
    static func availabilityText(
        _ availability: String?,
        language: SupportedAppLanguage
    ) -> String {
        switch availability {
        case "available": TodayCopy.string("common.available", language: language)
        case "unavailable", nil: TodayCopy.string("common.not-available", language: language)
        case let other?: other
        }
    }
}

@MainActor
struct TodayBlockCard: View {
    let descriptor: TodayBlockDescriptor
    @Environment(\.locale) private var locale

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                HStack(spacing: BodyFlowSpacing.sm) {
                    BodyFlowDomainGlyph(domain: .block)
                    Text(verbatim: copy("today.block.title"))
                        .font(BodyFlowTypography.cardTitle)
                        .foregroundStyle(BodyFlowColor.primaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                // The meter draws the server's reported percentage only.
                BodyFlowMeter(
                    fraction: descriptor.percentage.map { min(max(Double($0) / 100, 0), 1) },
                    domain: .block
                )

                // These are passive values for one block. Keep its heading
                // separate and let the existing localized rows read together.
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
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
                    BodyFlowStatusLine(
                        TodayBlockDescriptor.availabilityText(
                            descriptor.availability,
                            language: language
                        ),
                        kind: descriptor.enabled == true ? .success : .info,
                        font: BodyFlowTypography.callout
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.block.metrics")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.block")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
