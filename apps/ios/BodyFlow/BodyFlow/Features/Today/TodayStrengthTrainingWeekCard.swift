import Foundation
import SwiftUI

/// Presentation of the official weekly response. It never chooses a week,
/// counts workouts or recalculates the percentage on the device.
struct TodayStrengthTrainingWeekDescriptor: Equatable, Sendable {
    let title: String
    let calendarLines: [String]
    let countText: String?
    let countDetail: String?
    let percentageText: String?
    let sourceText: String?
    let targetDetail: String?
    let message: String?
    let refreshTitle: String
    let refreshHint: String

    init(section: TodayStrengthTrainingWeek, language: SupportedAppLanguage) {
        func copy(_ key: String.LocalizationValue) -> String {
            TodayCopy.string(key, language: language)
        }
        func format(_ key: String.LocalizationValue, _ arguments: String...) -> String {
            String(format: copy(key), arguments: arguments.map { $0 as CVarArg })
        }
        title = copy("today.strength-week.title")
        refreshTitle = copy("today.refresh")
        refreshHint = copy("today.strength-week.refresh-hint")

        guard case let .available(value) = section else {
            calendarLines = []
            countText = nil
            countDetail = nil
            percentageText = nil
            sourceText = nil
            targetDetail = nil
            if case .conflict = section {
                message = copy("today.strength-week.conflict")
            } else {
                message = copy("today.strength-week.unavailable")
            }
            return
        }

        calendarLines = [
            format("today.strength-week.week", Self.civilDate(value.weekStart, language: language)),
            format("today.strength-week.as-of", Self.civilDate(value.asOfLocalDate, language: language)),
            format("today.strength-week.zone", value.timeZone),
        ]
        let completed = TodayValueFormatter.integer(value.completedStrengthDays, language: language)
        switch value.targetAvailability {
        case .available:
            // The validated contract supplies both values. Missing data never
            // becomes a denominator or a locally computed percentage.
            countText = value.plannedDays.map {
                format("today.strength-week.ratio", completed, TodayValueFormatter.integer($0, language: language))
            }
            countDetail = copy("today.strength-week.ratio-detail")
            percentageText = value.percentage.map {
                format("today.strength-week.percentage", TodayValueFormatter.integer($0, language: language))
            }
            targetDetail = nil
        case .zero, .absent:
            countText = completed
            countDetail = copy("today.strength-week.completed-detail")
            percentageText = nil
            targetDetail = copy(value.targetAvailability == .zero
                ? "today.strength-week.zero" : "today.strength-week.absent")
        }
        switch value.targetSource {
        case .acceptedPlan: sourceText = copy("today.strength-week.source-plan")
        case .informedFrequency: sourceText = copy("today.strength-week.source-frequency")
        case .absent: sourceText = nil
        }
        message = nil
    }

    private static func civilDate(_ value: String, language: SupportedAppLanguage) -> String {
        // The decoder validated these civil dates. UTC is only a formatting
        // calendar: neither the observation timestamp nor device time shifts it.
        guard let date = ProgressTrendsPresentation.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.calendar = ProgressTrendsPresentation.calendar
        formatter.timeZone = formatter.calendar.timeZone
        formatter.locale = language.formattingLocale
        formatter.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return formatter.string(from: date)
    }
}

@MainActor
struct TodayStrengthTrainingWeekCard: View {
    let descriptor: TodayStrengthTrainingWeekDescriptor
    var isRefreshing = false
    var refresh: (() -> Void)?

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.sm) {
                Text(verbatim: descriptor.title)
                    .font(BodyFlowTypography.cardTitle)
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("today.strength-week.title")

                information
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.strength-week")

                if let refresh {
                    Button(action: refresh) {
                        Text(verbatim: descriptor.refreshTitle)
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary, isLoading: isRefreshing))
                    .disabled(isRefreshing)
                    .accessibilityHint(descriptor.refreshHint)
                    .accessibilityIdentifier("today.strength-week.refresh")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            ForEach(Array(descriptor.calendarLines.enumerated()), id: \.offset) { _, line in
                supporting(line)
            }
            if let count = descriptor.countText {
                Text(verbatim: count)
                    .font(BodyFlowTypography.metricSmall.monospacedDigit())
                    .foregroundStyle(BodyFlowColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = descriptor.countDetail { supporting(detail) }
            if let percentage = descriptor.percentageText { supporting(percentage) }
            if let target = descriptor.targetDetail { supporting(target) }
            if let source = descriptor.sourceText { supporting(source) }
            if let message = descriptor.message { supporting(message) }
        }
    }

    private func supporting(_ value: String) -> some View {
        Text(verbatim: value)
            .font(BodyFlowTypography.supporting)
            .foregroundStyle(BodyFlowColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
