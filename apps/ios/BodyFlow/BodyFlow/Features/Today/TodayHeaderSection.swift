import Foundation
import SwiftUI

struct TodayHeaderDescriptor: Equatable, Sendable {
    let localDate: String
    let protocolName: String?
    let updatedAt: APITimestamp?

    /// The patient's local day the way a person reads it: pt-BR "domingo,
    /// 4 de outubro", en "Sunday, October 4". The value is already that
    /// local day, so it is read and written on the UTC calendar and never
    /// shifted by the device's time zone. A value that is not a calendar
    /// date is shown as received.
    func readableLocalDate(for language: SupportedAppLanguage) -> String {
        let calendar = ProgressTrendsPresentation.calendar
        guard let date = ProgressTrendsPresentation.date(from: localDate) else {
            return localDate
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard localDate.split(separator: "-").compactMap({ Int($0) })
            == [parts.year, parts.month, parts.day].compactMap({ $0 }) else {
            return localDate
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = language.formattingLocale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }
}

enum TodayValueFormatter {
    static func integer(_ value: Int) -> String {
        integer(value, language: .portugueseBrazil)
    }

    static func integer(
        _ value: Int,
        language: SupportedAppLanguage
    ) -> String {
        value.formatted(.number.locale(language.formattingLocale))
    }

    static func kcal(_ value: Int) -> String {
        kcal(value, language: .portugueseBrazil)
    }

    static func kcal(
        _ value: Int,
        language: SupportedAppLanguage
    ) -> String {
        "\(integer(value, language: language)) kcal"
    }

    static func optionalKcal(_ value: Int?) -> String {
        value.map(kcal) ?? "Indisponível"
    }

    static func optionalKcal(
        _ value: Int?,
        language: SupportedAppLanguage
    ) -> String {
        value.map { kcal($0, language: language) }
            ?? TodayCopy.string("common.not-available", language: language)
    }

    /// Energy of one confirmed meal as the server stored it (up to two
    /// decimals): pt-BR "284,6 kcal", en "284.6 kcal"; never rounded here, and
    /// an absent value reads "not available", never "0 kcal".
    static func mealKcal(
        _ value: Decimal?,
        language: SupportedAppLanguage
    ) -> String {
        guard let value else {
            return TodayCopy.string("common.not-available", language: language)
        }
        return "\(value.formatted(.number.locale(language.formattingLocale))) kcal"
    }

    static func grams(_ value: Decimal) -> String {
        grams(value, language: .portugueseBrazil)
    }

    // Grams follow the same locale as every other figure on the card, so
    // pt-BR reads "90,5 g" next to "1.250 ml" instead of a raw "90.5 g".
    static func grams(
        _ value: Decimal,
        language: SupportedAppLanguage
    ) -> String {
        "\(value.formatted(.number.locale(language.formattingLocale))) g"
    }

    static func optionalGrams(_ value: Decimal?) -> String {
        value.map(grams) ?? "Indisponível"
    }

    static func optionalGrams(
        _ value: Decimal?,
        language: SupportedAppLanguage
    ) -> String {
        value.map { grams($0, language: language) }
            ?? TodayCopy.string("common.not-available", language: language)
    }

    static func milliliters(_ value: Int) -> String {
        milliliters(value, language: .portugueseBrazil)
    }

    static func milliliters(
        _ value: Int,
        language: SupportedAppLanguage
    ) -> String {
        "\(integer(value, language: language)) ml"
    }

    static func optionalMilliliters(_ value: Int?) -> String {
        value.map(milliliters) ?? "Indisponível"
    }

    static func optionalMilliliters(
        _ value: Int?,
        language: SupportedAppLanguage
    ) -> String {
        value.map { milliliters($0, language: language) }
            ?? TodayCopy.string("common.not-available", language: language)
    }

    static func timestamp(_ value: APITimestamp?) -> String {
        timestamp(value, language: .portugueseBrazil)
    }

    static func timestamp(
        _ value: APITimestamp?,
        language: SupportedAppLanguage
    ) -> String {
        guard let value else {
            return TodayCopy.string("common.not-available", language: language)
        }
        return value.value.formatted(
            .dateTime
                .day(.twoDigits)
                .month(.twoDigits)
                .year()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .locale(language.formattingLocale)
        )
    }
}

enum TodayCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }
}

@MainActor
struct TodayHeaderSection: View {
    let descriptor: TodayHeaderDescriptor
    @Environment(\.locale) private var locale
    @Environment(\.bodyFlowReduceMotion) private var reduceMotion
    @State private var showsDetails = false

    // The date anchors the day; protocol and freshness are still available
    // from the server verbatim after expanding the native disclosure.
    var body: some View {
        DisclosureGroup(
            isExpanded: $showsDetails.animation(
                BodyFlowMotion.animation(.disclosure, reduceMotion: reduceMotion)
            )
        ) {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                protocolLabel
                updatedLabel
            }
            .padding(.top, BodyFlowSpacing.xs)
            .accessibilityElement(children: .contain)
        } label: {
            localDateLabel
        }
        .font(BodyFlowTypography.caption)
        .foregroundStyle(BodyFlowColor.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.header.details")
    }

    private var localDateLabel: some View {
        Label(
            verbatim: descriptor.readableLocalDate(for: language),
            symbol: .calendar
        )
        .accessibilityIdentifier("today.header.local-date")
    }

    private var protocolLabel: some View {
        Label(
            verbatim: "\(copy("today.header.protocol")): \(descriptor.protocolName ?? unavailable)",
            symbol: .protocolDocument
        )
        .accessibilityIdentifier("today.header.protocol")
    }

    private var updatedLabel: some View {
        Label(
            verbatim: "\(copy("today.header.updated")): \(TodayValueFormatter.timestamp(descriptor.updatedAt, language: language))",
            symbol: .clock
        )
        .accessibilityIdentifier("today.header.updated-at")
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var unavailable: String { copy("common.not-available") }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
