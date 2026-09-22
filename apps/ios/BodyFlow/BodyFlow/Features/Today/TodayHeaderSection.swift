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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Secondary day context only. The shell brand and the inline "Hoje"
    // navigation title already identify the screen, so this block no longer
    // repeats an eyebrow or a decorative headline; it keeps the received
    // date/protocol/freshness readable without outranking the summary. The
    // rows share one line when the width allows and wrap otherwise.
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the three rows alone would fill the
                // first screen ahead of Energy. The date stays visible; the
                // protocol and freshness rows (same received values) move
                // behind a native disclosure.
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                        protocolLabel
                        updatedLabel
                    }
                    .padding(.top, BodyFlowSpacing.xs)
                } label: {
                    localDateLabel
                }
                .accessibilityIdentifier("today.header.details")
            } else {
                regularLayout
            }
        }
        .font(BodyFlowTypography.caption)
        .foregroundStyle(BodyFlowColor.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var regularLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BodyFlowSpacing.md) {
                localDateLabel
                protocolLabel
                updatedLabel
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BodyFlowSpacing.md) {
                    localDateLabel
                    protocolLabel
                }
                updatedLabel
            }
            VStack(alignment: .leading, spacing: 2) {
                localDateLabel
                protocolLabel
                updatedLabel
            }
        }
    }

    private var localDateLabel: some View {
        Label(
            "\(copy("today.header.local-date")): \(descriptor.localDate)",
            systemImage: "calendar"
        )
        .accessibilityIdentifier("today.header.local-date")
    }

    private var protocolLabel: some View {
        Label(
            "\(copy("today.header.protocol")): \(descriptor.protocolName ?? unavailable)",
            systemImage: "doc.text"
        )
        .accessibilityIdentifier("today.header.protocol")
    }

    private var updatedLabel: some View {
        Label(
            "\(copy("today.header.updated")): \(TodayValueFormatter.timestamp(descriptor.updatedAt, language: language))",
            systemImage: "clock"
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
