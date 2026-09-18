import Foundation
import SwiftUI

struct MealProposalItemPresentation: Equatable, Sendable {
    let name: String
    let quantityG: Decimal
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
}

struct MealProposalTotalsPresentation: Equatable, Sendable {
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
}

struct MealProposalPresentation: Equatable, Sendable {
    let registrationID: String
    let status: String
    let mealType: String?
    let items: [MealProposalItemPresentation]
    let totals: MealProposalTotalsPresentation?
    let warnings: [String]
    let expiresAt: APITimestamp

    var allowsEdit: Bool { status == "pending" }
    var allowsConfirm: Bool { status == "pending" }
    var allowsCancel: Bool { status == "pending" }

    var visibleText: String {
        var values = [status]
        if let mealType { values.append(mealType) }
        values.append(contentsOf: items.flatMap { item in
            [
                item.name,
                String(describing: item.quantityG),
                item.kcal.map(String.init(describing:)),
                item.proteinG.map(String.init(describing:)),
                item.carbsG.map(String.init(describing:)),
                item.fatG.map(String.init(describing:)),
            ].compactMap { $0 }
        })
        values.append(contentsOf: warnings)
        return values.joined(separator: " ")
    }

    init(registration: RegistrationSnapshot) {
        registrationID = registration.id
        status = registration.status
        expiresAt = registration.expiresAt

        switch registration.proposal {
        case let .meal(proposal):
            mealType = proposal.mealType
            items = proposal.items.map {
                MealProposalItemPresentation(
                    name: $0.name,
                    quantityG: $0.quantityG,
                    kcal: $0.kcal,
                    proteinG: $0.proteinG,
                    carbsG: $0.carbsG,
                    fatG: $0.fatG
                )
            }
            totals = proposal.totals.map {
                MealProposalTotalsPresentation(
                    kcal: $0.kcal,
                    proteinG: $0.proteinG,
                    carbsG: $0.carbsG,
                    fatG: $0.fatG
                )
            }
            warnings = proposal.warnings
        case .workout, .unknown:
            mealType = nil
            items = []
            totals = nil
            warnings = []
        }
    }
}

enum RegistrationMetricUnit: Sendable {
    case kilocalories
    case grams
}

enum RegistrationMetricPresentation {
    static func text(
        label: String,
        value: Decimal,
        unit: RegistrationMetricUnit,
        language: SupportedAppLanguage
    ) -> String {
        let number = value.formatted(.number.locale(language.formattingLocale))
        switch unit {
        case .kilocalories:
            return "\(number) kcal"
        case .grams:
            return "\(label): \(number) g"
        }
    }
}

struct MealProposalView: View {
    let proposal: MealProposalPresentation
    let isSubmitting: Bool
    let edit: @MainActor () -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.proposal.meal-title"))
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)

            ForEach(Array(proposal.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(item.name)
                        .font(BodyFlowTypography.headline)
                    Text("\(decimalText(item.quantityG)) g")
                        .foregroundStyle(BodyFlowColor.secondaryText)
                    nutrientText(
                        copy("registration.metric.energy"),
                        value: item.kcal,
                        unit: .kilocalories
                    )
                    nutrientText(
                        copy("registration.metric.protein"),
                        value: item.proteinG,
                        unit: .grams
                    )
                    nutrientText(
                        copy("registration.metric.carbs"),
                        value: item.carbsG,
                        unit: .grams
                    )
                    nutrientText(
                        copy("registration.metric.fat"),
                        value: item.fatG,
                        unit: .grams
                    )
                }
                .padding(.vertical, BodyFlowSpacing.xs)
            }

            if let totals = proposal.totals {
                BodyFlowCard(surface: .card) {
                    VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(copy("registration.proposal.totals"))
                        .font(BodyFlowTypography.headline)
                    nutrientText(
                        copy("registration.metric.energy"),
                        value: totals.kcal,
                        unit: .kilocalories
                    )
                    nutrientText(
                        copy("registration.metric.protein"),
                        value: totals.proteinG,
                        unit: .grams
                    )
                    nutrientText(
                        copy("registration.metric.carbs"),
                        value: totals.carbsG,
                        unit: .grams
                    )
                    nutrientText(
                        copy("registration.metric.fat"),
                        value: totals.fatG,
                        unit: .grams
                    )
                    }
                }
            }

            Label(copy("registration.proposal.service-values"), systemImage: "checkmark.seal")
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)

            ForEach(proposal.warnings, id: \.self) { warning in
                Text(warning)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            Text(expiryText)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)

            if proposal.allowsConfirm {
                Button(action: confirm) {
                    Text(copy("registration.proposal.confirm"))
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("registration.proposal.confirm")
            }
            if proposal.allowsEdit {
                Button(action: edit) {
                    Text(copy("registration.proposal.edit-first-item"))
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(BodyFlowButtonStyle(role: .secondary))
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("registration.proposal.edit")
            }
            if proposal.allowsCancel {
                Button(action: cancel) {
                    Text(copy("registration.proposal.cancel"))
                        .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(BodyFlowButtonStyle(role: .tertiary))
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("registration.proposal.cancel")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.proposal")
    }

    @ViewBuilder
    private func nutrientText(
        _ name: String,
        value: Decimal?,
        unit: RegistrationMetricUnit
    ) -> some View {
        if let value {
            Text(RegistrationMetricPresentation.text(
                label: name,
                value: value,
                unit: unit,
                language: language
            ))
        }
    }

    private func decimalText(_ value: Decimal) -> String {
        value.formatted(.number.locale(language.formattingLocale))
    }

    private var language: SupportedAppLanguage {
        BodyFlowPresentationLanguage.resolve(locale)
    }

    private var expiryText: String {
        let format = copy("registration.proposal.expires")
        let value = proposal.expiresAt.value.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: language.formattingLocale
        ))
        return String(format: format, locale: language.formattingLocale, value)
    }

    private func copy(_ key: String.LocalizationValue) -> String {
        RegistrationCopy.string(key, language: language)
    }
}
