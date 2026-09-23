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

/// The day at a glance: one panel with the four official figures — both
/// energy balances first, then protein and hydration — on a single elevated
/// surface instead of four competing cards. Every remaining official value
/// stays one tap away in the panel's disclosure, grouped by domain and
/// keeping its identifier; nothing is abridged, only ranked.
@MainActor
struct TodaySummaryPanel: View {
    let energy: TodayEnergyDescriptor
    let protein: TodayProteinDescriptor
    let hydration: TodayHydrationDescriptor
    let completionMessage: String?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            if let completionMessage {
                BodyFlowStatusLine(
                    completionMessage,
                    kind: .info,
                    font: BodyFlowTypography.body
                )
                .padding(BodyFlowSpacing.sm)
                .bodyFlowWash(.brandPrimary)
                .accessibilityIdentifier("today.completion.insufficient-data")
            }

            BodyFlowCard(surface: .elevated) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    summaryRow {
                        remainingFoodCell
                    } trailing: {
                        netBalanceCell
                    }

                    Divider()

                    summaryRow {
                        proteinCell
                    } trailing: {
                        hydrationCell
                    }

                    Divider()

                    detailsDisclosure
                }
            }
        }
    }

    /// Two figures side by side while the width allows; stacked at
    /// accessibility sizes so neither is squeezed into a column.
    @ViewBuilder
    private func summaryRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                leading()
                Divider()
                trailing()
            }
        } else {
            HStack(alignment: .top, spacing: BodyFlowSpacing.md) {
                leading()
                Divider()
                trailing()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var remainingFoodCell: some View {
        TodaySummaryCell(
            title: copy("today.energy.food-remaining"),
            value: TodayValueFormatter.kcal(
                energy.remainingFoodKcal,
                language: language
            ),
            caption: copy("today.energy.food-remaining.detail"),
            prominence: .headline
        )
        .accessibilityValue(energy.remainingFoodAccessibilityValue(for: language))
        .accessibilityIdentifier("today.energy.remaining-food")
    }

    private var netBalanceCell: some View {
        TodaySummaryCell(
            title: copy("today.energy.net-balance"),
            value: TodayValueFormatter.kcal(
                energy.dailyBalanceKcal,
                language: language
            ),
            caption: copy("today.energy.net-balance.detail"),
            prominence: .headline
        )
        .accessibilityValue(energy.netBalanceAccessibilityValue(for: language))
        .accessibilityIdentifier("today.energy.net-balance")
    }

    private var proteinCell: some View {
        TodaySummaryCell(
            title: copy("today.protein.title"),
            value: TodayValueFormatter.grams(protein.consumedG),
            caption: copy("metric.consumed"),
            prominence: .supporting
        )
        .accessibilityIdentifier("today.protein")
    }

    private var hydrationCell: some View {
        TodaySummaryCell(
            title: copy("today.hydration.title"),
            value: TodayValueFormatter.milliliters(
                hydration.consumedML,
                language: language
            ),
            caption: copy("metric.consumed"),
            prominence: .supporting
        )
        .accessibilityValue(
            "\(TodayValueFormatter.milliliters(hydration.consumedML, language: language)); \(copy("metric.target").lowercased()) \(TodayValueFormatter.optionalMilliliters(hydration.targetML, language: language))"
        )
        .accessibilityIdentifier("today.hydration")
    }

    /// One disclosure for the whole panel. Inside, the remaining official
    /// rows keep their domain grouping and their identifiers.
    private var detailsDisclosure: some View {
        DisclosureGroup(
            isExpanded: $showsDetails.animation(
                BodyFlowMotion.animation(.disclosure, reduceMotion: reduceMotion)
            )
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                energyDetails
                proteinDetails
                hydrationDetails
            }
            .padding(.top, BodyFlowSpacing.sm)
        } label: {
            TodayDisclosureLabel(title: copy("today.energy.details.title"))
        }
        .font(BodyFlowTypography.headline)
        .accessibilityIdentifier("today.energy.details")
    }

    private var energyDetails: some View {
        detailGroup(copy("today.energy.title")) {
            FixtureMetricRow(
                title: copy("metric.target"),
                value: TodayValueFormatter.optionalKcal(
                    energy.targetKcal,
                    language: language
                )
            )
            Divider()
            FixtureMetricRow(
                title: copy("metric.consumed"),
                value: TodayValueFormatter.kcal(
                    energy.consumedKcal,
                    language: language
                )
            )
            Divider()
            FixtureMetricRow(
                title: copy("today.energy.food-excess"),
                value: TodayValueFormatter.kcal(
                    energy.foodExcessKcal,
                    language: language
                )
            )
            Divider()
            FixtureMetricRow(
                title: copy("today.energy.exercise"),
                value: TodayValueFormatter.kcal(
                    energy.exerciseKcal,
                    language: language
                )
            )
            Divider()
            FixtureMetricRow(
                title: copy("today.energy.balance-status"),
                value: energy.dailyBalanceStatus
            )
        }
    }

    private var proteinDetails: some View {
        detailGroup(copy("today.protein.title")) {
            FixtureMetricRow(
                title: copy("metric.target"),
                value: TodayValueFormatter.optionalGrams(
                    protein.targetG,
                    language: language
                )
            )
            Divider()
            FixtureMetricRow(
                title: copy("metric.remaining"),
                value: TodayValueFormatter.optionalGrams(
                    protein.remainingG,
                    language: language
                )
            )
            if let percentage = protein.percentage {
                Divider()
                FixtureMetricRow(
                    title: copy("metric.reported-progress"),
                    value: "\(percentage)%"
                )
            }
            Divider()
            FixtureMetricRow(
                title: copy("metric.status"),
                value: protein.status
            )
        }
        .accessibilityIdentifier("today.protein.details")
    }

    private var hydrationDetails: some View {
        detailGroup(copy("today.hydration.title")) {
            FixtureMetricRow(
                title: copy("metric.target"),
                value: TodayValueFormatter.optionalMilliliters(
                    hydration.targetML,
                    language: language
                )
            )
            Divider()
            FixtureMetricRow(
                title: copy("metric.remaining"),
                value: TodayValueFormatter.optionalMilliliters(
                    hydration.remainingML,
                    language: language
                )
            )
            if let percentage = hydration.percentage {
                Divider()
                FixtureMetricRow(
                    title: copy("metric.reported-progress"),
                    value: "\(percentage)%"
                )
            }
            Divider()
            BodyFlowStatusLine(
                hydration.status,
                kind: .info,
                font: BodyFlowTypography.callout
            )
        }
        .accessibilityIdentifier("today.hydration.details")
    }

    @ViewBuilder
    private func detailGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(verbatim: title)
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .accessibilityElement(children: .contain)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}

/// One figure in the day panel: label with its domain glyph, the received
/// value, and the caption that carries its official meaning. Read as a single
/// element so VoiceOver announces meaning and number together.
@MainActor
private struct TodaySummaryCell: View {
    enum Prominence { case headline, supporting }

    let title: String
    let value: String
    let caption: String
    let prominence: Prominence

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            // The label stays on one line at regular sizes so the two columns
            // keep their figures on the same baseline.
            Text(verbatim: title)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: value)
                .font(
                    prominence == .headline
                        ? BodyFlowTypography.metricLarge
                        : BodyFlowTypography.metricSmall
                )
                .foregroundStyle(BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: caption)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
