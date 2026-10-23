import Foundation
import SwiftUI

struct MealProposalItemPresentation: Equatable, Sendable {
    let name: String
    let quantityG: Decimal
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
    /// The server has not calculated this item; it must be fixed before the
    /// meal can be confirmed.
    var needsClarification = false
    var quantityDisplay: MealQuantityDisplay? = nil
}

struct MealProposalTotalsPresentation: Equatable, Sendable {
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
}

/// What a proposal may say about where its calories came from. It is said
/// only when it is true of the whole proposal.
enum MealProposalKcalProvenance: Equatable, Sendable {
    /// Every item carries the official calculation.
    case calculated
    /// At least one item carries a value the person typed.
    case includesPatientReported
    /// An origin is unknown, or an item has no calculation yet: nothing is
    /// claimed.
    case unstated

    init(items: [MealProposalItemSnapshot]) {
        let typedByThePerson = items.contains {
            if case .patientReported = $0.kcalOrigin { true } else { false }
        }
        if typedByThePerson {
            self = .includesPatientReported
        } else if !items.isEmpty,
                  items.allSatisfy({ $0.kcalOrigin == .official && !$0.needsClarification }) {
            self = .calculated
        } else {
            self = .unstated
        }
    }

    var noteKey: String.LocalizationValue? {
        switch self {
        case .calculated: "registration.proposal.service-values"
        case .includesPatientReported: "registration.proposal.includes-user-kcal"
        case .unstated: nil
        }
    }
}

struct MealProposalPresentation: Equatable, Sendable {
    let registrationID: String
    let status: String
    let mealType: String?
    let items: [MealProposalItemPresentation]
    let totals: MealProposalTotalsPresentation?
    let warnings: [String]
    let expiresAt: APITimestamp
    let kcalProvenance: MealProposalKcalProvenance

    var allowsEdit: Bool { status == "pending" }
    /// An item the server has not calculated blocks the confirmation (the
    /// server refuses it too).
    var hasUnresolvedItems: Bool { items.contains(where: \.needsClarification) }
    var allowsConfirm: Bool { status == "pending" && !hasUnresolvedItems }
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
                    fatG: $0.fatG,
                    needsClarification: $0.needsClarification,
                    quantityDisplay: $0.quantityDisplay
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
            // Old pendings may contain the legacy operator instruction.
            // The mobile surface supplies its own localized, actionable
            // unresolved-item explanation below. Keep unrelated warnings.
            let rejectedNames = proposal.items.filter { $0.nutritionSource == "composite_rejected" }.map(\.name)
            warnings = proposal.warnings.filter { warning in
                !(warning.contains("Peça pro paciente")
                    && rejectedNames.contains { warning.contains($0) })
            }
            kcalProvenance = MealProposalKcalProvenance(items: proposal.items)
        case .workout, .unknown:
            mealType = nil
            items = []
            totals = nil
            warnings = []
            kcalProvenance = .unstated
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
    var editItem: @MainActor (Int) -> Void = { _ in }
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text(copy("registration.proposal.meal-title"))
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)

            ForEach(Array(proposal.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(item.name)
                        .font(BodyFlowTypography.headline)
                    Text(MealQuantityValue(grams: item.quantityG, metadata: item.quantityDisplay, name: item.name).label(language: language) ?? "")
                        .foregroundStyle(BodyFlowColor.secondaryText)
                    if item.needsClarification {
                        unresolvedItemNotice(index: index)
                    } else {
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

            if let noteKey = proposal.kcalProvenance.noteKey {
                Label(
                    copy(noteKey),
                    systemImage: proposal.kcalProvenance == .calculated
                        ? "checkmark.seal" : BodyFlowSymbol.person.rawValue
                )
                .font(BodyFlowTypography.callout)
                .foregroundStyle(BodyFlowColor.secondaryText)
                .accessibilityIdentifier("registration.proposal.kcal-provenance")
            }

            ForEach(proposal.warnings, id: \.self) { warning in
                Text(warning)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            Text(expiryText)
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)

            if proposal.status == "pending", proposal.hasUnresolvedItems {
                BodyFlowStatusLine(blockedExplanation, kind: .warning)
                    .accessibilityIdentifier("registration.proposal.confirm.blocked")
                if proposal.allowsEdit,
                   let index = proposal.items.firstIndex(where: \.needsClarification) {
                    Button { editItem(index) } label: {
                        Text(copy("registration.proposal.item.resolve"))
                            .frame(minHeight: BodyFlowSpacing.minimumTapTarget + 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BodyFlowButtonStyle(role: .primary))
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("registration.proposal.item.\(index).resolve")
                }
            }
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
            if proposal.allowsEdit && !proposal.hasUnresolvedItems {
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

    /// An item without calculation shows why and how to fix it instead of
    /// zeros that would read as a result.
    @ViewBuilder
    private func unresolvedItemNotice(index: Int) -> some View {
        BodyFlowStatusLine(copy("registration.proposal.item.needs-clarification"), kind: .warning)
            .accessibilityIdentifier("registration.proposal.item.\(index).needs-clarification")
    }

    private var blockedExplanation: String {
        let names = proposal.items.filter(\.needsClarification).map(\.name).joined(separator: ", ")
        return String(format: copy("registration.proposal.confirm.blocked.named"),
            locale: language.formattingLocale, names)
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
