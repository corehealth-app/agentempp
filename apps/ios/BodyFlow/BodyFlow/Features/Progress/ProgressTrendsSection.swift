import Charts
import SwiftUI

/// What the charts draw, built only from the stored series. Days without a
/// snapshot are absent (a gap in the bars), a day over its target is marked,
/// and the weight line uses the dated reevaluation weights as received.
struct ProgressTrendsPresentation: Equatable, Sendable {
    struct CaloriesBar: Equatable, Sendable, Identifiable {
        let date: Date
        let label: String
        let consumed: Int
        let target: Int?
        var overTarget: Bool { target.map { consumed > $0 } ?? false }
        var id: Date { date }
    }

    struct WeightPoint: Equatable, Sendable, Identifiable {
        let date: Date
        let label: String
        let kilograms: Double
        var id: Date { date }
    }

    struct BlockPoint: Equatable, Sendable, Identifiable {
        let date: Date
        let accumulated: Int
        var id: Date { date }
    }

    let window: Int
    let calories: [CaloriesBar]
    let weights: [WeightPoint]
    let block: [BlockPoint]
    /// The window's days, oldest first; true where a snapshot exists.
    let recordedDays: [Bool]
    let target: Int?
    let latestWeight: String?

    var isEmpty: Bool { calories.isEmpty && weights.isEmpty }

    /// The weight axis: the measured range with one kilogram of air on each
    /// side (never from zero, where a real change is an invisible slope).
    var weightRange: ClosedRange<Double> {
        let values = weights.map(\.kilograms)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - 1).rounded(.down)...(high + 1).rounded(.up)
    }

    init(snapshot: TrendsSnapshot, language: SupportedAppLanguage, today: Date = .now) {
        window = snapshot.days
        let parsed = snapshot.daily.compactMap { day -> (Date, TrendsDay)? in
            Self.date(from: day.date).map { ($0, day) }
        }
        // The server sends the last `days` stored rows; the charts show a
        // true calendar window of `days` days ending at the latest record,
        // so "14 dias" never stretches over weeks of sparse records.
        let days: [(Date, TrendsDay)]
        if let latest = parsed.map(\.0).max(),
           let start = Self.calendar.date(byAdding: .day, value: -(snapshot.days - 1), to: latest) {
            days = parsed.filter { $0.0 >= start }.sorted { $0.0 < $1.0 }
        } else {
            days = []
        }
        calories = days.map { date, day in
            CaloriesBar(
                date: date,
                label: Self.dayLabel(date, language: language),
                consumed: day.caloriesConsumed,
                target: day.caloriesTarget
            )
        }
        block = snapshot.clinicalPolicy?.hide.block == true ? [] : days.compactMap { date, day in
            day.deficitAccumulated.map { BlockPoint(date: date, accumulated: $0) }
        }
        weights = snapshot.weights.compactMap { weight in
            Self.date(from: weight.date).map {
                WeightPoint(
                    date: $0,
                    label: Self.dayLabel($0, language: language),
                    kilograms: NSDecimalNumber(decimal: weight.weightKG).doubleValue
                )
            }
        }
        target = days.last?.1.caloriesTarget
        latestWeight = snapshot.weights.last.map { Self.kilograms($0.weightKG, language: language) }
        let calendar = Self.calendar
        let end = calendar.startOfDay(for: days.last?.0 ?? today)
        let recorded = Set(days.map { calendar.startOfDay(for: $0.0) })
        recordedDays = (0..<snapshot.days).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - (snapshot.days - 1), to: end) else { return false }
            return recorded.contains(day)
        }
    }

    nonisolated static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    nonisolated static func date(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    nonisolated static func kilograms(_ value: Decimal, language: SupportedAppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.formattingLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return (formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)") + " kg"
    }

    nonisolated static func dayLabel(_ date: Date, language: SupportedAppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = language.formattingLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}

/// Weight over time, the last days against the food target, the block's
/// accumulation and the days with a record — all official values; a tap on
/// a calorie bar reads that day.
@MainActor
struct ProgressTrendsSection: View {
    let model: ProgressTrendsViewModel
    let showsBlock7700: Bool
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDate: Date?

    var body: some View {
        switch model.state {
        case .idle, .loading:
            BodyFlowCard { BodyFlowDelayedProgress(label: copy("progress.trends.title")) }
                .accessibilityIdentifier("progress.trends.loading")
        case .unavailable:
            BodyFlowCard {
                BodyFlowStatusLine(copy("progress.trends.unavailable"), kind: .unavailable)
            }
            .accessibilityIdentifier("progress.trends.unavailable")
        case let .loaded(snapshot):
            let presentation = ProgressTrendsPresentation(snapshot: snapshot, language: language)
            if presentation.isEmpty {
                emptyCard
            } else {
                charts(presentation)
            }
        }
    }

    private var emptyCard: some View {
        BodyFlowCard {
            HStack(alignment: .top, spacing: BodyFlowSpacing.sm) {
                BodyFlowDomainGlyph(domain: .progress)
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    Text(verbatim: copy("progress.trends.title"))
                        .font(BodyFlowTypography.cardTitle)
                        .foregroundStyle(BodyFlowColor.primaryText)
                    Text(verbatim: copy("progress.trends.empty"))
                        .font(BodyFlowTypography.supporting)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.trends.empty")
    }

    private func charts(_ presentation: ProgressTrendsPresentation) -> some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            BodyFlowSectionHeader(copy("progress.trends.title"), symbol: .trends)
            if !presentation.weights.isEmpty { weightCard(presentation) }
            if !presentation.calories.isEmpty {
                caloriesCard(presentation)
                if showsBlock7700 { blockCard(presentation) }
                daysCard(presentation)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.trends")
    }

    // MARK: Weight

    private func weightCard(_ presentation: ProgressTrendsPresentation) -> some View {
        BodyFlowCard(surface: .elevated) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                cardTitle(copy("progress.trends.weight"), domain: .progress, value: presentation.latestWeight)
                // The scale frames the measured range (with a kilogram of
                // air), so a real change reads as a slope, not a flat line
                // on a 0–80 axis. The area starts at the scale's floor.
                let range = presentation.weightRange
                Chart(presentation.weights) { point in
                    AreaMark(
                        x: .value("date", point.date),
                        yStart: .value("floor", range.lowerBound),
                        yEnd: .value("kg", point.kilograms)
                    )
                    .foregroundStyle(BodyFlowDomain.progress.fill.opacity(BodyFlowOpacity.glyphWash))
                    .interpolationMethod(.monotone)
                    LineMark(x: .value("date", point.date), y: .value("kg", point.kilograms))
                        .foregroundStyle(BodyFlowDomain.progress.fill)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    PointMark(x: .value("date", point.date), y: .value("kg", point.kilograms))
                        .foregroundStyle(BodyFlowDomain.progress.fill)
                }
                .chartYScale(domain: range)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(
                    format: copy("progress.trends.weight.accessibility"),
                    presentation.weights.count, presentation.latestWeight ?? ""
                ))
                axisRange(first: presentation.weights.first, last: presentation.weights.last)
            }
        }
        .accessibilityIdentifier("progress.trends.weight")
    }

    // MARK: Calories

    private func caloriesCard(_ presentation: ProgressTrendsPresentation) -> some View {
        let selected = selectedDate.flatMap { date in
            presentation.calories.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        return BodyFlowCard(surface: .elevated) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                cardTitle(
                    String(format: copy("progress.trends.calories"), presentation.window),
                    domain: .energy,
                    value: nil,
                    note: presentation.target.map { "\(copy("progress.trends.target")) \(TodayValueFormatter.kcal($0, language: language))" }
                )
                Chart {
                    ForEach(presentation.calories) { bar in
                        BarMark(x: .value("date", bar.date, unit: .day), y: .value("kcal", bar.consumed))
                            .foregroundStyle(BodyFlowColor.color(bar.overTarget ? .fatVivid : .energyVivid))
                            .cornerRadius(3)
                            .opacity(selected == nil || selected?.id == bar.id ? 1 : 0.45)
                    }
                    if let target = presentation.target {
                        RuleMark(y: .value("target", target))
                            .foregroundStyle(BodyFlowColor.color(.controlBoundary))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    if let selected {
                        RuleMark(x: .value("date", selected.date, unit: .day))
                            .foregroundStyle(BodyFlowColor.color(.textSecondary))
                            .annotation(position: .top, alignment: .center) {
                                Text(verbatim: "\(selected.label) · \(TodayValueFormatter.kcal(selected.consumed, language: language))")
                                    .font(BodyFlowTypography.caption.weight(.semibold))
                                    .padding(BodyFlowSpacing.xxs)
                                    .background(BodyFlowColor.color(.surfaceElevated), in: RoundedRectangle(cornerRadius: BodyFlowRadius.small))
                                    .overlay(RoundedRectangle(cornerRadius: BodyFlowRadius.small).strokeBorder(BodyFlowColor.color(.borderSubtle)))
                            }
                    }
                }
                // Tap a bar to read its day (a tap never competes with the
                // page scroll the way a press-and-drag scrub does).
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = location.x - geometry[plotFrame].origin.x
                                guard let tapped: Date = proxy.value(atX: x) else { return }
                                let nearest = presentation.calories.min {
                                    abs($0.date.timeIntervalSince(tapped)) < abs($1.date.timeIntervalSince(tapped))
                                }
                                selectedDate = selectedDate == nearest?.date ? nil : nearest?.date
                            }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 160)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: copy("progress.trends.calories.accessibility"), presentation.calories.count))
                dateRange(first: presentation.calories.first?.label, last: presentation.calories.last?.label)
                HStack(spacing: BodyFlowSpacing.md) {
                    legend(copy("progress.trends.under"), color: .energyVivid)
                    legend(copy("progress.trends.over"), color: .fatVivid)
                }
            }
        }
        .accessibilityIdentifier("progress.trends.calories")
    }

    // MARK: Block

    private func blockCard(_ presentation: ProgressTrendsPresentation) -> some View {
        BodyFlowCard(surface: .elevated) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                cardTitle(
                    copy("progress.trends.block"),
                    domain: .block,
                    value: presentation.block.last.map { TodayValueFormatter.kcal($0.accumulated, language: language) }
                )
                Chart(presentation.block) { point in
                    AreaMark(x: .value("date", point.date, unit: .day), y: .value("kcal", point.accumulated))
                        .foregroundStyle(BodyFlowDomain.block.fill.opacity(BodyFlowOpacity.glyphWash))
                    LineMark(x: .value("date", point.date, unit: .day), y: .value("kcal", point.accumulated))
                        .foregroundStyle(BodyFlowDomain.block.fill)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copy("progress.trends.block"))
                dateRange(first: presentation.calories.first?.label, last: presentation.calories.last?.label)
            }
        }
        .accessibilityIdentifier("progress.trends.block")
    }

    // MARK: Days

    private func daysCard(_ presentation: ProgressTrendsPresentation) -> some View {
        let count = presentation.recordedDays.filter { $0 }.count
        return BodyFlowCard(surface: .elevated) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                cardTitle(
                    copy("progress.trends.days"),
                    domain: .progress,
                    value: String(format: copy("progress.trends.days.value"), count, presentation.window)
                )
                HStack(spacing: BodyFlowSpacing.xxs) {
                    ForEach(Array(presentation.recordedDays.enumerated()), id: \.offset) { _, recorded in
                        Capsule()
                            .fill(recorded ? BodyFlowDomain.progress.color : BodyFlowColor.color(.borderSubtle))
                            .frame(height: 10)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.trends.days")
    }

    // MARK: Pieces

    /// Title with its glyph and the latest official value: one line at
    /// regular sizes, stacked at accessibility sizes so neither is squeezed.
    @ViewBuilder
    private func cardTitle(_ title: String, domain: BodyFlowDomain, value: String?, note: String? = nil) -> some View {
        let heading = HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
            BodyFlowDomainGlyph(domain: domain, diameter: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(BodyFlowTypography.cardTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                if let note {
                    Text(verbatim: note)
                        .font(BodyFlowTypography.caption)
                        .foregroundStyle(BodyFlowColor.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        // The latest official value: number large, unit small.
        let figure = value.map { value in
            BodyFlowFigure.text(
                value, value: BodyFlowTypography.metricSmall, unit: BodyFlowTypography.caption,
                unitColor: BodyFlowColor.secondaryText
            )
            .foregroundStyle(BodyFlowColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xxs) {
                    heading
                    figure
                }
            } else {
                HStack(alignment: .center, spacing: BodyFlowSpacing.sm) {
                    heading
                    Spacer(minLength: BodyFlowSpacing.sm)
                    figure
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Real text under a chart (an accessible element, unlike drawn axis
    /// labels): the first and last date of the series.
    @ViewBuilder
    private func dateRange(first: String?, last: String?) -> some View {
        if let first, let last {
            HStack {
                Text(verbatim: first)
                Spacer(minLength: BodyFlowSpacing.sm)
                Text(verbatim: last)
            }
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.secondaryText)
        }
    }

    @ViewBuilder
    private func axisRange(first: ProgressTrendsPresentation.WeightPoint?, last: ProgressTrendsPresentation.WeightPoint?) -> some View {
        if let first, let last {
            HStack {
                Text(verbatim: "\(first.label) · \(ProgressTrendsPresentation.kilograms(Decimal(first.kilograms), language: language))")
                Spacer(minLength: BodyFlowSpacing.sm)
                Text(verbatim: "\(last.label) · \(ProgressTrendsPresentation.kilograms(Decimal(last.kilograms), language: language))")
            }
            .font(BodyFlowTypography.caption)
            .foregroundStyle(BodyFlowColor.secondaryText)
        }
    }

    private func legend(_ title: String, color: BodyFlowColor.Role) -> some View {
        HStack(spacing: BodyFlowSpacing.xxs) {
            Circle().fill(BodyFlowColor.color(color)).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(verbatim: title).font(BodyFlowTypography.caption).foregroundStyle(BodyFlowColor.secondaryText)
        }
    }

    private var language: SupportedAppLanguage { BodyFlowPresentationLanguage.resolve(locale) }
    private func copy(_ key: String.LocalizationValue) -> String { ProgressCopy.string(key, language: language) }
}
