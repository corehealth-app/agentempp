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
        remainingFoodAccessibilityValue(for: .portugueseBrazil)
    }

    var netBalanceAccessibilityValue: String {
        netBalanceAccessibilityValue(for: .portugueseBrazil)
    }

    func remainingFoodAccessibilityValue(
        for language: SupportedAppLanguage
    ) -> String {
        let format = TodayCopy.string(
            "today.energy.food-remaining.accessibility",
            language: language
        )
        return String(
            format: format,
            locale: language.formattingLocale,
            TodayValueFormatter.integer(remainingFoodKcal, language: language)
        )
    }

    func netBalanceAccessibilityValue(
        for language: SupportedAppLanguage
    ) -> String {
        let formatted = TodayValueFormatter.integer(
            dailyBalanceKcal,
            language: language
        )
        let signedValue = if formatted.hasPrefix("-") {
            "\(TodayCopy.string("number.minus", language: language)) \(formatted.dropFirst())"
        } else {
            formatted
        }
        let format = TodayCopy.string(
            "today.energy.net-balance.accessibility",
            language: language
        )
        return String(
            format: format,
            locale: language.formattingLocale,
            signedValue
        )
    }
}

@MainActor
struct TodayEnergySection: View {
    let descriptor: TodayEnergyDescriptor
    let completionMessage: String?
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Label(copy("today.energy.title"), systemImage: "bolt.heart")
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

            BodyFlowCard {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    // Side by side at regular text sizes (labels wrap inside
                    // each half); stacked at accessibility sizes. The previous
                    // ViewThatFits compared unwrapped ideal widths, so the
                    // Portuguese labels always forced the stacked fallback.
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                            remainingFoodMetric
                            Divider()
                            netBalanceMetric
                        }
                    } else {
                        HStack(alignment: .top, spacing: BodyFlowSpacing.md) {
                            remainingFoodMetric
                            Divider()
                            netBalanceMetric
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    // The two protected values above (remaining-food,
                    // net-balance) always stay visible. The remaining five
                    // rows are the same official values, unabridged, moved
                    // behind a native disclosure so the card reads as a
                    // compact summary first.
                    DisclosureGroup {
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
                                title: copy("metric.consumed"),
                                value: TodayValueFormatter.kcal(
                                    descriptor.consumedKcal,
                                    language: language
                                )
                            )
                            Divider()
                            FixtureMetricRow(
                                title: copy("today.energy.food-excess"),
                                value: TodayValueFormatter.kcal(
                                    descriptor.foodExcessKcal,
                                    language: language
                                )
                            )
                            Divider()
                            FixtureMetricRow(
                                title: copy("today.energy.exercise"),
                                value: TodayValueFormatter.kcal(
                                    descriptor.exerciseKcal,
                                    language: language
                                )
                            )
                            Divider()
                            FixtureMetricRow(
                                title: copy("today.energy.balance-status"),
                                value: descriptor.dailyBalanceStatus
                            )
                        }
                        .padding(.top, BodyFlowSpacing.sm)
                    } label: {
                        TodayDisclosureLabel(title: copy("today.energy.details.title"))
                    }
                    .font(BodyFlowTypography.headline)
                    .accessibilityIdentifier("today.energy.details")
                }
            }
        }
    }

    private var remainingFoodMetric: some View {
        TodayEnergyMetric(
            title: copy("today.energy.food-remaining"),
            value: TodayValueFormatter.kcal(
                descriptor.remainingFoodKcal,
                language: language
            ),
            explanation: copy("today.energy.food-remaining.detail"),
            systemImage: "fork.knife",
            accessibilityValue: descriptor.remainingFoodAccessibilityValue(
                for: language
            )
        )
        .accessibilityIdentifier("today.energy.remaining-food")
    }

    private var netBalanceMetric: some View {
        TodayEnergyMetric(
            title: copy("today.energy.net-balance"),
            value: TodayValueFormatter.kcal(
                descriptor.dailyBalanceKcal,
                language: language
            ),
            explanation: copy("today.energy.net-balance.detail"),
            systemImage: "plusminus",
            accessibilityValue: descriptor.netBalanceAccessibilityValue(
                for: language
            )
        )
        .accessibilityIdentifier("today.energy.net-balance")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}

@MainActor
private struct TodayEnergyMetric: View {
    let title: String
    let value: String
    let explanation: String
    let systemImage: String
    let accessibilityValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Label(title, systemImage: systemImage)
                .font(BodyFlowTypography.supporting)
                .foregroundStyle(BodyFlowColor.secondaryText)
            Text(value)
                .font(BodyFlowTypography.metricSmall)
                .foregroundStyle(BodyFlowColor.primaryText)
            Text(explanation)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }
}
