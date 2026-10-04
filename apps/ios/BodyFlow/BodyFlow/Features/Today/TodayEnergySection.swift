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

/// The day at a glance (directions A/B, approved 03/10): the food balance
/// (excluding exercise) sits in the middle of a big energy ring with the
/// consumed, target and excess figures beside it; the three macros follow
/// as tiles; hydration and exercise as a pair; the technical daily balance
/// remains one tap away in the disclosure.
@MainActor
struct TodaySummaryPanel: View {
    let energy: TodayEnergyDescriptor
    let protein: TodayProteinDescriptor
    let macros: TodayMacrosDescriptor
    let hydration: TodayHydrationDescriptor
    let completionMessage: String?
    /// False once the first count has landed: figures are plain text again.
    var countsUp = true

    nonisolated static let heroRingDiameter: CGFloat = 148
    nonisolated static let stackedRingDiameter: CGFloat = 104

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @State private var showsDetails = false

    /// Up to xLarge the figures fit inside the ring and three tiles fit a
    /// row; from xxLarge on everything stacks and wraps at full width.
    private var compactType: Bool { dynamicTypeSize <= .xLarge }

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
            macrosRow
            dayPair

            BodyFlowCard(surface: .elevated) {
                detailsDisclosure
            }
        }
    }

    // MARK: Energy hero

    /// Exactly on the food target (nothing left, nothing over): the ring
    /// closes and the day earns a burst. A later refresh that lands here
    /// triggers it; the first appearance never does.
    private var foodTargetMet: Bool {
        energy.targetKcal != nil && energy.remainingFoodKcal == 0 && (energy.foodExcessKcal ?? 0) == 0
    }

    private var ringFraction: Double? {
        BodyFlowRing.clampedFraction(consumed: energy.consumedKcal, target: energy.targetKcal)
    }

    private var energyHero: some View {
        BodyFlowDataHeroCard {
            if compactType, energy.remainingFoodKcal != nil {
                // The note keeps a full step of air below the ring: the
                // system contrast audit samples around small text, and a
                // caption hugging the colored arc reads as low contrast.
                VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
                    HStack(alignment: .center, spacing: BodyFlowSpacing.md) {
                        centeredRing
                        VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                            consumedStat
                            targetStat
                            excessStat
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    exerciseExcludedNote
                }
            } else {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    if ringFraction != nil {
                        BodyFlowRing(
                            fraction: ringFraction,
                            exceeded: (energy.foodExcessKcal ?? 0) > 0,
                            diameter: Self.stackedRingDiameter,
                            lineWidth: 11,
                            role: .energyVivid,
                            exceededRole: .fatVivid,
                            glows: true
                        )
                    }
                    remainingFoodFigure
                    consumedStat
                    targetStat
                    excessStat
                }
            }
        }
        .bodyFlowCelebration({ $0 ? .energy : nil }, trigger: foodTargetMet)
    }

    /// The ring draws consumed ÷ target only; the figure in its middle is the
    /// official "Restam" value. Without a target the track stays empty.
    private var centeredRing: some View {
        ZStack {
            BodyFlowRing(
                fraction: ringFraction,
                exceeded: (energy.foodExcessKcal ?? 0) > 0,
                diameter: Self.heroRingDiameter,
                lineWidth: 15,
                role: .energyVivid,
                exceededRole: .fatVivid,
                glows: true
            )
            VStack(spacing: 0) {
                remainingFigureText
                    .bodyFlowCountUp(remainingCounting)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .contentTransition(.numericText())
                // One short word under the figure; the element's own label
                // below says "Restam para comida". Known limitation: in dark
                // mode the system contrast audit flags this word although
                // the rendered pixels measure 15:1 (it appears to judge small
                // text over the ring by the arc's color). The audited suite
                // runs in light, where there is no finding.
                Text(verbatim: copy("today.energy.food-remaining.short"))
                    .font(BodyFlowTypography.caption)
                    .foregroundStyle(BodyFlowColor.primaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Self.heroRingDiameter - 44)
            .accessibilityElement(children: .combine)
            // Spoken with its full meaning; the value carries the official figure.
            .accessibilityLabel(copy("today.energy.food-remaining"))
            .accessibilityValue(energy.remainingFoodAccessibilityValue(for: language))
            .accessibilityIdentifier("today.energy.remaining-food")
        }
    }

    private var remainingText: String {
        TodayValueFormatter.optionalKcal(energy.remainingFoodKcal, language: language)
    }

    private var remainingFigureText: Text {
        Self.figure(remainingText, value: .system(.title, design: .rounded).weight(.bold).monospacedDigit())
    }

    private var remainingCounting: BodyFlowCountUp.Figure? {
        guard countsUp, let remaining = energy.remainingFoodKcal else { return nil }
        return BodyFlowCountUp.Figure(
            value: remaining,
            render: { TodayValueFormatter.kcal($0, language: language) },
            text: { Self.figure(
                TodayValueFormatter.kcal($0, language: language),
                value: .system(.title, design: .rounded).weight(.bold).monospacedDigit()
            ) }
        )
    }

    /// The stacked variant (large text, or no official "Restam" figure).
    private var remainingFoodFigure: some View {
        TodaySummaryCell(
            title: copy("today.energy.food-remaining"),
            value: remainingText,
            caption: copy("today.energy.food-remaining.detail"),
            prominence: .headline
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityValue(energy.remainingFoodAccessibilityValue(for: language))
        .accessibilityIdentifier("today.energy.remaining-food")
    }

    /// What the ring's figure is, and that exercise never frees food: said
    /// once, right under the ring.
    private var exerciseExcludedNote: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: copy("today.energy.food-remaining"))
                .font(BodyFlowTypography.caption.weight(.semibold))
                .foregroundStyle(BodyFlowColor.primaryText)
            Text(verbatim: copy("today.energy.food-remaining.detail"))
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var consumedStat: some View {
        stat(
            copy("metric.consumed"),
            TodayValueFormatter.kcal(energy.consumedKcal, language: language),
            identifier: "today.energy.consumed",
            counting: countsUp ? energy.consumedKcal : nil
        )
    }

    private var targetStat: some View {
        stat(
            copy("metric.target"),
            TodayValueFormatter.optionalKcal(energy.targetKcal, language: language),
            identifier: "today.energy.target",
            counting: countsUp ? energy.targetKcal : nil
        )
    }

    private var excessStat: some View {
        stat(
            copy("today.energy.food-excess"),
            TodayValueFormatter.optionalKcal(energy.foodExcessKcal, language: language),
            identifier: "today.energy.food-excess",
            tint: (energy.foodExcessKcal ?? 0) > 0 ? BodyFlowColor.color(.feedbackWarning) : nil,
            counting: nil
        )
    }

    private func stat(
        _ title: String, _ value: String, identifier: String, tint: Color? = nil, counting: Int?
    ) -> some View {
        let font = BodyFlowTypography.metricSmall
        let figure = counting.map { target in
            BodyFlowCountUp.Figure(
                value: target,
                render: { TodayValueFormatter.kcal($0, language: language) },
                text: { Self.figure(TodayValueFormatter.kcal($0, language: language), value: font) }
            )
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: title)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Self.figure(value, value: font)
                .bodyFlowCountUp(figure)
                .foregroundStyle(tint ?? BodyFlowColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    /// Number large, unit small, one accessible string.
    private static func figure(_ full: String, value: Font) -> Text {
        BodyFlowFigure.text(
            full, value: value, unit: BodyFlowTypography.caption,
            unitColor: BodyFlowColor.secondaryText
        )
    }

    // MARK: Macros

    @ViewBuilder private var macrosRow: some View {
        Group {
            if compactType {
                HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                    proteinTile
                    macroTile(.carbs, title: copy("today.macros.carbs"), grams: macros.carbsG, identifier: "today.macros.carbs")
                    macroTile(.fat, title: copy("today.macros.fat"), grams: macros.fatG, identifier: "today.macros.fat")
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                    proteinTile
                    macroTile(.carbs, title: copy("today.macros.carbs"), grams: macros.carbsG, identifier: "today.macros.carbs")
                    macroTile(.fat, title: copy("today.macros.fat"), grams: macros.fatG, identifier: "today.macros.fat")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.macros")
    }

    /// Protein is the only macro with an official target, so the only one
    /// with a meter and an "of target" figure.
    private var proteinTile: some View {
        let consumed = TodayValueFormatter.grams(protein.consumedG, language: language)
        let target = protein.targetG.map { TodayValueFormatter.grams($0, language: language) }
        return BodyFlowCard(surface: .elevated, padding: BodyFlowSpacing.sm) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                tileLabel(copy("today.protein.title"), domain: .protein)
                (Self.figure(consumed, value: BodyFlowTypography.headline.monospacedDigit())
                    + Text(verbatim: target.map { " / \($0)" } ?? "")
                        .font(BodyFlowTypography.caption)
                        .foregroundStyle(BodyFlowColor.secondaryText))
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // Reaching the protein target is the positive outcome the
                // server reports ("Meta atingida"), so the meter never warns.
                BodyFlowMeter(
                    fraction: BodyFlowMeter.clampedFraction(consumed: protein.consumedG, target: protein.targetG),
                    domain: .protein, height: 5
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.protein")
    }

    private func macroTile(_ domain: BodyFlowDomain, title: String, grams: Decimal, identifier: String) -> some View {
        BodyFlowCard(surface: .elevated, padding: BodyFlowSpacing.sm) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                tileLabel(title, domain: domain)
                Self.figure(
                    TodayValueFormatter.grams(grams, language: language),
                    value: BodyFlowTypography.headline.monospacedDigit()
                )
                .foregroundStyle(BodyFlowColor.primaryText)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func tileLabel(_ title: String, domain: BodyFlowDomain) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BodyFlowSpacing.xxs) {
            Circle().fill(domain.fill).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(verbatim: title)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Hydration and exercise

    @ViewBuilder private var dayPair: some View {
        if compactType {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                hydrationTile
                exerciseTile
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                hydrationTile
                exerciseTile
            }
        }
    }

    private var hydrationTile: some View {
        let consumed = TodayValueFormatter.milliliters(hydration.consumedML, language: language)
        let target = TodayValueFormatter.optionalMilliliters(hydration.targetML, language: language)
        return pairTile(
            domain: .hydration,
            title: copy("today.hydration.title"),
            value: consumed,
            caption: "\(copy("metric.target")): \(target)"
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(consumed); \(copy("metric.target").lowercased()) \(target)")
        .accessibilityIdentifier("today.hydration")
    }

    /// Exercise shown on its own: it feeds the block, never the food balance.
    private var exerciseTile: some View {
        pairTile(
            domain: .exercise,
            title: copy("today.energy.exercise"),
            value: TodayValueFormatter.kcal(energy.exerciseKcal, language: language),
            caption: copy("today.energy.exercise.caption")
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.exercise")
    }

    private func pairTile(domain: BodyFlowDomain, title: String, value: String, caption: String) -> some View {
        BodyFlowCard(surface: .elevated, padding: BodyFlowSpacing.sm) {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                BodyFlowDomainGlyph(domain: domain, diameter: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: title)
                        .font(BodyFlowTypography.caption)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                    Self.figure(value, value: BodyFlowTypography.headline.monospacedDigit())
                        .foregroundStyle(BodyFlowColor.primaryText)
                        .contentTransition(.numericText())
                    Text(verbatim: caption)
                        .font(.caption2)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
    /// When set, the figure counts up to its value on first appearance
    /// (decorative; the accessible text is the final value from frame one).
    var counting: BodyFlowCountUp.Figure? = nil

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
                .bodyFlowCountUp(counting)
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
