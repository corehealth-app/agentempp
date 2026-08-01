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

struct MealProposalView: View {
    let proposal: MealProposalPresentation
    let isSubmitting: Bool
    let edit: @MainActor () -> Void
    let confirm: @MainActor () -> Void
    let cancel: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
            Text("Proposta de refeição")
                .font(BodyFlowTypography.title)
                .fontWeight(.semibold)

            ForEach(Array(proposal.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text(item.name)
                        .font(BodyFlowTypography.headline)
                    Text("\(decimalText(item.quantityG)) g")
                        .foregroundStyle(BodyFlowColor.secondaryText)
                    nutrientText("kcal", value: item.kcal)
                    nutrientText("Proteína", value: item.proteinG)
                    nutrientText("Carboidratos", value: item.carbsG)
                    nutrientText("Gorduras", value: item.fatG)
                }
            }

            if let totals = proposal.totals {
                VStack(alignment: .leading, spacing: BodyFlowSpacing.xs) {
                    Text("Totais")
                        .font(BodyFlowTypography.headline)
                    nutrientText("kcal", value: totals.kcal)
                    nutrientText("Proteína", value: totals.proteinG)
                    nutrientText("Carboidratos", value: totals.carbsG)
                    nutrientText("Gorduras", value: totals.fatG)
                }
            }

            ForEach(proposal.warnings, id: \.self) { warning in
                Text(warning)
                    .font(BodyFlowTypography.callout)
                    .foregroundStyle(BodyFlowColor.secondaryText)
            }
            Text("Expira em \(proposal.expiresAt.value.formatted(date: .abbreviated, time: .shortened))")
                .font(BodyFlowTypography.caption)
                .foregroundStyle(BodyFlowColor.secondaryText)

            if proposal.allowsEdit {
                Button("Editar", action: edit)
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("registration.proposal.edit")
            }
            if proposal.allowsConfirm {
                Button("Confirmar", action: confirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("registration.proposal.confirm")
            }
            if proposal.allowsCancel {
                Button("Cancelar proposta", action: cancel)
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("registration.proposal.cancel")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("registration.proposal")
    }

    @ViewBuilder
    private func nutrientText(_ name: String, value: Decimal?) -> some View {
        if let value {
            Text("\(decimalText(value)) \(name == "kcal" ? "kcal" : "g de \(name)")")
        }
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
