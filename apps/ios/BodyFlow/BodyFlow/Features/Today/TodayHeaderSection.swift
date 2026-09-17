import Foundation
import SwiftUI

struct TodayHeaderDescriptor: Equatable, Sendable {
    let localDate: String
    let protocolName: String?
    let updatedAt: APITimestamp?
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

    static func grams(_ value: Decimal) -> String {
        "\(NSDecimalNumber(decimal: value).stringValue) g"
    }

    static func optionalGrams(_ value: Decimal?) -> String {
        value.map(grams) ?? "Indisponível"
    }

    static func optionalGrams(
        _ value: Decimal?,
        language: SupportedAppLanguage
    ) -> String {
        value.map(grams)
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

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text(copy("today.eyebrow"))
                .font(BodyFlowTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.accent)

            Text(copy("today.title"))
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.primaryText)

            Label(
                "\(copy("today.header.local-date")): \(descriptor.localDate)",
                systemImage: "calendar"
            )
                .accessibilityIdentifier("today.header.local-date")

            Label(
                "\(copy("today.header.protocol")): \(descriptor.protocolName ?? unavailable)",
                systemImage: "doc.text"
            )
            .accessibilityIdentifier("today.header.protocol")

            Label(
                "\(copy("today.header.updated")): \(TodayValueFormatter.timestamp(descriptor.updatedAt, language: language))",
                systemImage: "clock"
            )
            .accessibilityIdentifier("today.header.updated-at")
        }
        .font(BodyFlowTypography.callout)
        .foregroundStyle(BodyFlowColor.secondaryText)
        .accessibilityElement(children: .contain)
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var unavailable: String { copy("common.not-available") }

    private func copy(_ key: String.LocalizationValue) -> String {
        TodayCopy.string(key, language: language)
    }
}
