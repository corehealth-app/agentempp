import Foundation
import SwiftUI

struct PlanField: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let value: String
}

struct NutritionPlanSection: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let fields: [PlanField]
}

struct PlanPresentation: Equatable, Sendable {
    let trainingFields: [PlanField]
    let nutritionSections: [NutritionPlanSection]

    init(snapshot: PlanSnapshot) {
        trainingFields = snapshot.training.map(Self.trainingFields) ?? []
        nutritionSections = snapshot.nutrition.map(Self.nutritionSection)
    }

    var isEmpty: Bool {
        trainingFields.isEmpty && nutritionSections.isEmpty
    }

    private static func trainingFields(
        _ training: TrainingPlanSnapshot
    ) -> [PlanField] {
        [
            PlanField(id: "plan.training.type", title: "Tipo de treino", value: training.planType),
            PlanField(id: "plan.training.days", title: "Dias por semana", value: "\(training.daysPerWeek)"),
            optionalField("plan.training.equipment", "Equipamentos", training.equipmentSummary),
            PlanField(id: "plan.training.generated", title: "Gerado em", value: date(training.generatedAt)),
            optionalField("plan.training.valid-until", "Válido até", training.validUntil.map(date)),
            optionalField("plan.training.version", "Versão", training.version.map(String.init)),
            optionalField("plan.training.notes", "Observações", training.notes),
        ].compactMap { $0 }
    }

    private static func nutritionSection(
        _ prescription: NutritionPrescriptionSnapshot
    ) -> NutritionPlanSection {
        NutritionPlanSection(
            id: prescription.id,
            title: "Prescrição nutricional",
            fields: [
                PlanField(id: "plan.nutrition.\(prescription.id).type", title: "Tipo de prescrição", value: prescription.type),
                PlanField(id: "plan.nutrition.\(prescription.id).generated", title: "Gerado em", value: date(prescription.generatedAt)),
                optionalField("plan.nutrition.\(prescription.id).valid-until", "Válido até", prescription.validUntil.map(date)),
                optionalField("plan.nutrition.\(prescription.id).version", "Versão", prescription.version.map(String.init)),
                optionalField("plan.nutrition.\(prescription.id).notes", "Observações", prescription.notes),
            ].compactMap { $0 }
        )
    }

    private static func optionalField(
        _ id: String,
        _ title: String,
        _ value: String?
    ) -> PlanField? {
        value.map { PlanField(id: id, title: title, value: $0) }
    }

    private static func date(_ timestamp: APITimestamp) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: timestamp.value)
    }
}

@MainActor
struct PlanContentView: View {
    let presentation: PlanPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: BodyFlowSpacing.lg) {
            if !presentation.trainingFields.isEmpty {
                PlanMetadataCard(
                    title: "Plano de treino",
                    fields: presentation.trainingFields,
                    accessibilityIdentifier: "plan.training"
                )
            }

            ForEach(presentation.nutritionSections) { section in
                PlanMetadataCard(
                    title: section.title,
                    fields: section.fields,
                    accessibilityIdentifier: "plan.nutrition.\(section.id)"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private struct PlanMetadataCard: View {
    let title: String
    let fields: [PlanField]
    let accessibilityIdentifier: String

    var body: some View {
        BodyFlowCard {
            VStack(alignment: .leading, spacing: BodyFlowSpacing.md) {
                Text(title)
                    .font(BodyFlowTypography.headline)
                    .foregroundStyle(BodyFlowColor.primaryText)

                ForEach(fields) { field in
                    FixtureMetricRow(title: field.title, value: field.value)
                    if field.id != fields.last?.id { Divider() }
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
