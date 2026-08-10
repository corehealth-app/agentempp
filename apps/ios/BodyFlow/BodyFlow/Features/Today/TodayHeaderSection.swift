import Foundation
import SwiftUI

struct TodayHeaderDescriptor: Equatable, Sendable {
    let localDate: String
    let protocolName: String?
    let updatedAt: APITimestamp?
}

enum TodayValueFormatter {
    private static let locale = Locale(identifier: "pt_BR")

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func kcal(_ value: Int) -> String {
        "\(integer(value)) kcal"
    }

    static func optionalKcal(_ value: Int?) -> String {
        value.map(kcal) ?? "Indisponível"
    }

    static func grams(_ value: Decimal) -> String {
        "\(NSDecimalNumber(decimal: value).stringValue) g"
    }

    static func optionalGrams(_ value: Decimal?) -> String {
        value.map(grams) ?? "Indisponível"
    }

    static func milliliters(_ value: Int) -> String {
        "\(integer(value)) ml"
    }

    static func optionalMilliliters(_ value: Int?) -> String {
        value.map(milliliters) ?? "Indisponível"
    }

    static func timestamp(_ value: APITimestamp?) -> String {
        guard let value else { return "Indisponível" }
        return value.value.formatted(
            .dateTime
                .day(.twoDigits)
                .month(.twoDigits)
                .year()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .locale(locale)
        )
    }
}

@MainActor
struct TodayHeaderSection: View {
    let descriptor: TodayHeaderDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
            Text("HOJE")
                .font(BodyFlowTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(BodyFlowColor.accent)

            Text("Seu dia, com clareza.")
                .font(BodyFlowTypography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(BodyFlowColor.primaryText)

            Label("Data local: \(descriptor.localDate)", systemImage: "calendar")
                .accessibilityIdentifier("today.header.local-date")

            Label(
                "Protocolo: \(descriptor.protocolName ?? "Indisponível")",
                systemImage: "doc.text"
            )
            .accessibilityIdentifier("today.header.protocol")

            Label(
                "Atualizado: \(TodayValueFormatter.timestamp(descriptor.updatedAt))",
                systemImage: "clock"
            )
            .accessibilityIdentifier("today.header.updated-at")
        }
        .font(BodyFlowTypography.callout)
        .foregroundStyle(BodyFlowColor.secondaryText)
        .accessibilityElement(children: .contain)
    }
}
