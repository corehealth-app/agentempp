import SwiftUI

enum TodayStatusText {
    enum Kind { case balance, protein, hydration }

    static func label(
        _ code: String,
        kind: Kind,
        language: SupportedAppLanguage
    ) -> String {
        let key: String.LocalizationValue
        switch (kind, code) {
        case (.balance, "provisional"): key = "today.status.day-in-progress"
        case (.balance, "final"): key = "today.status.final-balance"
        case (.balance, "insufficient_data"): key = "today.status.insufficient-data"
        case (.protein, "below_target"): key = "today.status.below-target"
        case (.protein, "target_unavailable"): key = "today.status.target-unavailable"
        case (.protein, "target_reached"), (.hydration, "target_reached"):
            key = "today.status.target-reached"
        case (.hydration, "not_recorded"): key = "today.status.no-records"
        case (.hydration, "tracked_without_target"): key = "today.status.tracked-without-target"
        case (.hydration, "not_started"): key = "today.status.not-started"
        case (.hydration, "in_progress"): key = "today.status.in-progress"
        default: return code
        }
        return TodayCopy.string(key, language: language)
    }
}

struct TodayEnergyDescriptor: Equatable, Sendable {
    let targetKcal: Int?
    let consumedKcal: Int
    let remainingFoodKcal: Int?
    let foodExcessKcal: Int?
    let exerciseKcal: Int
    let dailyBalanceKcal: Int?
    let dailyBalanceStatus: String

    var targetText: String {
        TodayValueFormatter.optionalKcal(targetKcal)
    }

    var consumedText: String {
        TodayValueFormatter.kcal(consumedKcal)
    }

    var remainingFoodText: String {
        TodayValueFormatter.optionalKcal(remainingFoodKcal)
    }

    var foodExcessText: String {
        TodayValueFormatter.optionalKcal(foodExcessKcal)
    }

    var exerciseText: String {
        TodayValueFormatter.kcal(exerciseKcal)
    }

    var netBalanceText: String {
        TodayValueFormatter.optionalKcal(dailyBalanceKcal)
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
        guard let remainingFoodKcal else {
            return TodayCopy.string("common.not-available", language: language)
        }
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
        guard let dailyBalanceKcal else {
            return TodayCopy.string("common.not-available", language: language)
        }
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

/// The day at a glance: the food balance (excluding exercise) leads inside
/// the hero card as a big energy ring with the official figure beside it;
/// macros and hydration follow in their own colors; the technical daily
/// balance remains one tap away in the disclosure (direction v2, 03/10).
@MainActor
struct TodaySummaryPanel: View {
    let energy: TodayEnergyDescriptor
    let protein: TodayProteinDescriptor
    let macros: TodayMacrosDescriptor
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

            energyHero

            BodyFlowCard(surface: .elevated) {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                    macrosBlock
                    Divider()
                    hydrationRow
                    Divider()
                    detailsDisclosure
                }
            }
        }
    }

    // MARK: Energy hero

    private var energyHero: some View {
        BodyFlowHeroCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Label(verbatim: copy("today.energy.title"), symbol: .energy)
                    .font(BodyFlowTypography.cardTitle)
                    .accessibilityAddTraits(.isHeader)

                // Ring beside the figure when the width allows; stacked on a
                // narrow phone or at accessibility sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: BodyFlowSpacing.md) {
                        foodRing
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                            remainingFoodFigure
                            foodExcessCell
                        }
                    }
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                        foodRing
                        remainingFoodFigure
                        foodExcessCell
                    }
                }

                summaryRow {
                    TodaySummaryCell(
                        title: copy("metric.consumed"),
                        value: TodayValueFormatter.kcal(energy.consumedKcal, language: language),
                        caption: copy("today.energy.title"),
                        prominence: .supporting,
                        tone: .hero
                    )
                    .accessibilityIdentifier("today.energy.consumed")
                } trailing: {
                    TodaySummaryCell(
                        title: copy("metric.target"),
                        value: TodayValueFormatter.optionalKcal(energy.targetKcal, language: language),
                        caption: copy("today.energy.title"),
                        prominence: .supporting,
                        tone: .hero
                    )
                    .accessibilityIdentifier("today.energy.target")
                }
            }
        }
    }

    /// The ring only draws consumed ÷ target; the figure is the official
    /// value. No ring without a target. The energy glyph sits in the middle
    /// so the ring never shows a second number.
    @ViewBuilder private var foodRing: some View {
        if let fraction = BodyFlowRing.clampedFraction(consumed: energy.consumedKcal, target: energy.targetKcal) {
            BodyFlowRing(
                fraction: fraction,
                exceeded: (energy.foodExcessKcal ?? 0) > 0,
                diameter: 104,
                lineWidth: 11,
                role: .accentCoral,
                track: BodyFlowColor.color(.onHero).opacity(BodyFlowOpacity.heroTrack),
                exceededRole: .achievement
            )
            .overlay {
                // Fixed size: the ring is fixed, so the decorative glyph never
                // outgrows it at accessibility text sizes.
                Image(symbol: .energy)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(BodyFlowColor.color(.onHero))
                    .accessibilityHidden(true)
            }
        }
    }

    private var remainingFoodFigure: some View {
        TodaySummaryCell(
            title: copy("today.energy.food-remaining"),
            value: TodayValueFormatter.optionalKcal(
                energy.remainingFoodKcal,
                language: language
            ),
            caption: copy("today.energy.food-remaining.detail"),
            prominence: .headline,
            tone: .hero
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityValue(energy.remainingFoodAccessibilityValue(for: language))
        .accessibilityIdentifier("today.energy.remaining-food")
    }

    private var foodExcessCell: some View {
        TodaySummaryCell(
            title: copy("today.energy.food-excess"),
            value: TodayValueFormatter.optionalKcal(
                energy.foodExcessKcal,
                language: language
            ),
            caption: copy("today.energy.food-remaining.detail"),
            prominence: .supporting,
            tone: .hero
        )
        .accessibilityIdentifier("today.energy.food-excess")
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
                trailing()
            }
        } else {
            HStack(alignment: .top, spacing: BodyFlowSpacing.md) {
                leading()
                trailing()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Macros

    private var macrosBlock: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
            Text(verbatim: copy("today.macros.title"))
                .font(BodyFlowTypography.cardTitle)
                .foregroundStyle(BodyFlowColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            proteinRow
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BodyFlowSpacing.md) {
                    macroChip(.carbs, title: copy("today.macros.carbs"), grams: macros.carbsG)
                    macroChip(.fat, title: copy("today.macros.fat"), grams: macros.fatG)
                }
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    macroChip(.carbs, title: copy("today.macros.carbs"), grams: macros.carbsG)
                    macroChip(.fat, title: copy("today.macros.fat"), grams: macros.fatG)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.macros")
    }

    /// Protein against its target: the only macro with an official target,
    /// so the only one with a meter.
    private var proteinRow: some View {
        let consumed = TodayValueFormatter.grams(protein.consumedG, language: language)
        let target = TodayValueFormatter.optionalGrams(protein.targetG, language: language)
        // "x / meta" only when a target exists; otherwise the consumed figure alone.
        let figure = protein.targetG == nil ? consumed : "\(consumed) / \(target)"
        return HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
            BodyFlowDomainGlyph(domain: .protein)
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.sm) {
                        Text(verbatim: copy("today.protein.title"))
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.primaryText)
                        Spacer(minLength: BodyFlowSpacing.sm)
                        Text(verbatim: figure)
                            .font(BodyFlowTypography.callout.monospacedDigit())
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                        Text(verbatim: copy("today.protein.title"))
                            .font(BodyFlowTypography.headline)
                            .foregroundStyle(BodyFlowColor.primaryText)
                        Text(verbatim: figure)
                            .font(BodyFlowTypography.callout.monospacedDigit())
                            .foregroundStyle(BodyFlowColor.secondaryText)
                    }
                }
                // Reaching the protein target is the positive outcome the
                // server reports ("Meta atingida"), so the meter never warns.
                BodyFlowMeter(
                    fraction: BodyFlowMeter.clampedFraction(consumed: protein.consumedG, target: protein.targetG),
                    domain: .protein
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.protein")
    }

    private func macroChip(_ domain: BodyFlowDomain, title: String, grams: Decimal) -> some View {
        HStack(spacing: BodyFlowSpacing.xs) {
            BodyFlowDomainGlyph(domain: domain, diameter: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                Text(verbatim: TodayValueFormatter.grams(grams, language: language))
                    .font(BodyFlowTypography.headline.monospacedDigit())
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .contentTransition(.numericText())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BodyFlowSpacing.xs)
        .bodyFlowWash(domain.colorRole)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.macros.\(domain == .carbs ? "carbs" : "fat")")
    }

    // MARK: Hydration

    /// The ring draws the server's reported percentage only; without one it
    /// stays an empty track.
    private var hydrationRow: some View {
        let consumed = TodayValueFormatter.milliliters(hydration.consumedML, language: language)
        let target = TodayValueFormatter.optionalMilliliters(hydration.targetML, language: language)
        return HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
            BodyFlowRing(
                fraction: hydration.percentage.map { min(max(Double($0) / 100, 0), 1) },
                exceeded: false,
                diameter: 44,
                lineWidth: 5,
                role: .hydration
            )
            .overlay {
                Image(symbol: .hydration)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BodyFlowColor.color(.hydration))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                Text(verbatim: copy("today.hydration.title"))
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)
                Text(verbatim: consumed)
                    .font(BodyFlowTypography.metricSmall)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .contentTransition(.numericText())
                    .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: consumed)
                Text(verbatim: "\(copy("metric.target")): \(target)")
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(consumed); \(copy("metric.target").lowercased()) \(target)")
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.energy.details")
    }

    private var energyDetails: some View {
        detailGroup(copy("today.energy.title")) {
            FixtureMetricRow(
                title: copy("today.energy.net-balance"),
                value: TodayValueFormatter.optionalKcal(
                    energy.dailyBalanceKcal,
                    language: language
                )
            )
            .accessibilityValue(energy.netBalanceAccessibilityValue(for: language))
            .accessibilityIdentifier("today.energy.net-balance")
            Text(copy("today.energy.net-balance.detail"))
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
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
                value: TodayStatusText.label(energy.dailyBalanceStatus, kind: .balance, language: language)
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
                value: TodayStatusText.label(protein.status, kind: .protein, language: language)
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
                TodayStatusText.label(hydration.status, kind: .hydration, language: language),
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
    /// On the hero card every line is `onHero`; elsewhere the label and
    /// caption are secondary text.
    enum Tone { case standard, hero }

    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    let title: String
    let value: String
    let caption: String
    let prominence: Prominence
    var tone: Tone = .standard

    private var labelColor: Color {
        tone == .hero ? BodyFlowColor.color(.onHero) : BodyFlowColor.secondaryText
    }
    private var valueColor: Color {
        tone == .hero ? BodyFlowColor.color(.onHero) : BodyFlowColor.primaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
            // The label stays on one line at regular sizes so the two columns
            // keep their figures on the same baseline.
            Text(verbatim: title)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(labelColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: value)
                .font(
                    prominence == .headline
                        ? BodyFlowTypography.metricLarge
                        : BodyFlowTypography.metricSmall
                )
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
                // A refreshed official value rolls its digits instead of
                // snapping; the value itself is never interpolated.
                .contentTransition(.numericText())
                .animation(BodyFlowMotion.animation(.content, reduceMotion: reduceMotion), value: value)

            Text(verbatim: caption)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(labelColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
