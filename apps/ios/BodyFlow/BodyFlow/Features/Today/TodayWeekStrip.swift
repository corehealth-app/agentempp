import Observation
import SwiftUI

/// The seven days ending today, each with what the stored series says about
/// it: a record within the food target, a record over it, or no record.
/// It is an indicator only — a past day cannot be opened from here.
struct TodayWeekDescriptor: Equatable, Sendable {
    enum Status: Equatable, Sendable { case none, within, over }

    struct Day: Equatable, Sendable, Identifiable {
        let date: String
        let weekday: String
        let number: String
        let status: Status
        let isToday: Bool
        var id: String { date }
    }

    let days: [Day]

    var recordedCount: Int { days.filter { $0.status != .none }.count }

    init(localDate: String, trends: TrendsSnapshot?, language: SupportedAppLanguage) {
        let calendar = ProgressTrendsPresentation.calendar
        guard let today = ProgressTrendsPresentation.date(from: localDate) else {
            days = []
            return
        }
        let stored = Dictionary(
            (trends?.daily ?? []).map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let weekday = DateFormatter()
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.locale = language.formattingLocale
        weekday.dateFormat = "EEEEE"
        let key = DateFormatter()
        key.calendar = calendar
        key.timeZone = calendar.timeZone
        key.locale = Locale(identifier: "en_US_POSIX")
        key.dateFormat = "yyyy-MM-dd"
        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return nil }
            let dateKey = key.string(from: date)
            let status: Status
            if let day = stored[dateKey], day.caloriesConsumed > 0 {
                status = day.caloriesTarget.map { day.caloriesConsumed > $0 } == true ? .over : .within
            } else {
                status = .none
            }
            return Day(
                date: dateKey,
                weekday: weekday.string(from: date).uppercased(with: language.formattingLocale),
                number: String(calendar.component(.day, from: date)),
                status: status,
                isToday: offset == 6
            )
        }
    }
}

/// Loads the week beside Today (the same stored series the charts use). A
/// failure simply leaves the strip without marks; it never blocks the day.
@MainActor
@Observable
final class TodayWeekViewModel {
    private let provider: any ProgressProviding
    private var sequence = 0
    private(set) var trends: TrendsSnapshot?

    init(provider: any ProgressProviding) {
        self.provider = provider
    }

    func load() async {
        sequence += 1
        let current = sequence
        guard let response = try? await provider.trends(days: 7),
              current == sequence, !Task.isCancelled else { return }
        trends = response.data
    }
}

@MainActor
struct TodayWeekStrip: View {
    let descriptor: TodayWeekDescriptor
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Seven columns cannot hold accessibility text; say it instead.
                Text(verbatim: summary)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: BodyFlowSpacing.xxs) {
                    ForEach(descriptor.days) { day in
                        cell(day)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
            }
        }
        .accessibilityIdentifier("today.week")
    }

    private func cell(_ day: TodayWeekDescriptor.Day) -> some View {
        VStack(spacing: BodyFlowSpacing.xxs) {
            Text(verbatim: day.weekday)
                .font(.caption2)
                .foregroundStyle(BodyFlowColor.color(day.isToday ? .onPrimary : .textSecondary))
            Text(verbatim: day.number)
                .font(BodyFlowTypography.headline.monospacedDigit())
                .foregroundStyle(BodyFlowColor.color(day.isToday ? .onPrimary : .textPrimary))
            Circle()
                .fill(dotColor(day))
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BodyFlowSpacing.xs)
        .background {
            if day.isToday {
                RoundedRectangle(cornerRadius: BodyFlowRadius.field, style: .continuous)
                    .fill(BodyFlowColor.color(.brandPrimary))
            }
        }
    }

    private func dotColor(_ day: TodayWeekDescriptor.Day) -> Color {
        switch day.status {
        case .none: .clear
        case .within: BodyFlowColor.color(day.isToday ? .onPrimary : .energyVivid)
        case .over: BodyFlowColor.color(day.isToday ? .onPrimary : .fatVivid)
        }
    }

    private var summary: String {
        String(
            format: TodayCopy.string("today.week.summary", language: BodyFlowPresentationLanguage.resolve(locale)),
            descriptor.recordedCount
        )
    }
}
