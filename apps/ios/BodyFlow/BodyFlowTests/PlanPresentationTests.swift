import Foundation
import Testing

@testable import BodyFlow

@Suite("Plan Presentation")
struct PlanPresentationTests {
    @Test("closed server enums render display labels while unknown values stay raw")
    func closedEnumsRenderDisplayLabels() {
        let generated = APITimestamp(value: Date(timeIntervalSince1970: 1_784_589_300))
        func snapshot(planType: String, prescriptionType: String) -> PlanSnapshot {
            PlanSnapshot(
                training: TrainingPlanSnapshot(
                    id: "training-1", planType: planType, daysPerWeek: 3,
                    equipmentSummary: nil, generatedAt: generated,
                    validUntil: nil, version: nil, notes: nil
                ),
                nutrition: [NutritionPrescriptionSnapshot(
                    id: "nutrition-1", type: prescriptionType, payload: nil,
                    generatedAt: generated, validUntil: nil, version: nil, notes: nil
                )]
            )
        }

        let portuguese = PlanPresentation(
            snapshot: snapshot(planType: "full_body", prescriptionType: "shopping_list")
        )
        #expect(portuguese.trainingFields.first?.value == "Corpo inteiro")
        #expect(portuguese.nutritionSections.first?.fields.first?.value == "Lista de compras")

        let english = PlanPresentation(
            snapshot: snapshot(planType: "split", prescriptionType: "combined"),
            language: .englishUnitedStates
        )
        #expect(english.trainingFields.first?.value == "Split routine")
        #expect(english.nutritionSections.first?.fields.first?.value == "Diet and shopping list")

        let custom = PlanPresentation(
            snapshot: snapshot(planType: "custom", prescriptionType: "diet")
        )
        #expect(custom.trainingFields.first?.value == "Personalizado")
        #expect(custom.nutritionSections.first?.fields.first?.value == "Dieta")

        // Values outside the documented enums are official server data and
        // stay visible as received.
        let unknown = PlanPresentation(
            snapshot: snapshot(planType: "strength", prescriptionType: "macro_targets")
        )
        #expect(unknown.trainingFields.first?.value == "strength")
        #expect(unknown.nutritionSections.first?.fields.first?.value == "macro_targets")
    }

    @Test("presentation contains each approved training and nutrition metadata field")
    func stableFields() {
        let presentation = PlanPresentation(snapshot: snapshot())

        #expect(presentation.trainingFields.map(\.title) == [
            "Tipo de treino", "Dias por semana", "Equipamentos",
            "Gerado em", "Válido até", "Versão", "Observações",
        ])
        #expect(presentation.trainingFields.map(\.value) == [
            "strength", "4", "Halteres e banco", "20/07/2026",
            "19/08/2026", "3", "Progressão semanal",
        ])
        #expect(presentation.nutritionSections[0].fields.map(\.title) == [
            "Tipo de prescrição", "Gerado em", "Válido até", "Versão", "Observações",
        ])
    }

    @Test("English presentation localizes labels and formatting without changing values")
    func englishLabelsAndDates() {
        let presentation = PlanPresentation(
            snapshot: snapshot(),
            language: .englishUnitedStates
        )

        #expect(presentation.trainingFields.map(\.title) == [
            "Training type", "Days per week", "Equipment",
            "Generated on", "Valid until", "Version", "Notes",
        ])
        #expect(presentation.trainingFields.map(\.value) == [
            "strength", "4", "Halteres e banco", "07/20/2026",
            "08/19/2026", "3", "Progressão semanal",
        ])
        #expect(presentation.nutritionSections[0].title == "Nutrition prescription")
        #expect(presentation.nutritionSections[0].fields.map(\.title) == [
            "Prescription type", "Generated on", "Valid until", "Version", "Notes",
        ])
    }

    @Test("optional metadata stays omitted while literal zero remains visible")
    func optionalMetadataAndZeroRemainDistinct() {
        let generated = APITimestamp(value: Date(timeIntervalSince1970: 1_784_589_300))
        let presentation = PlanPresentation(snapshot: PlanSnapshot(
            training: TrainingPlanSnapshot(
                id: "training-zero",
                planType: "mobility",
                daysPerWeek: 0,
                equipmentSummary: nil,
                generatedAt: generated,
                validUntil: nil,
                version: 0,
                notes: nil
            ),
            nutrition: []
        ))

        #expect(presentation.trainingFields.map(\.id) == [
            "plan.training.type", "plan.training.days",
            "plan.training.generated", "plan.training.version",
        ])
        #expect(presentation.trainingFields.first { $0.id == "plan.training.days" }?.value == "0")
        #expect(presentation.trainingFields.first { $0.id == "plan.training.version" }?.value == "0")
    }

    @Test("opaque nutrition payload never becomes a presentation row")
    func opaquePayloadIsNotRendered() {
        let presentation = PlanPresentation(snapshot: snapshot())
        let renderedText = presentation.nutritionSections.flatMap(\.fields)
            .flatMap { [$0.title, $0.value] }

        #expect(!renderedText.contains("projected_weight"))
        #expect(!renderedText.contains("Planejadas"))
        #expect(!renderedText.contains("Concluídas"))
        #expect(!renderedText.contains("malicious-value"))
    }

    @Test("no active training or nutrition plan is presentation empty")
    func noActivePlanIsEmpty() {
        #expect(PlanPresentation(snapshot: PlanSnapshot(
            training: nil,
            nutrition: []
        )).isEmpty)
    }

    private func snapshot() -> PlanSnapshot {
        let generated = APITimestamp(
            value: Date(timeIntervalSince1970: 1_784_589_300)
        )
        let validUntil = APITimestamp(
            value: Date(timeIntervalSince1970: 1_787_151_600)
        )
        return PlanSnapshot(
            training: TrainingPlanSnapshot(
                id: "training-1",
                planType: "strength",
                daysPerWeek: 4,
                equipmentSummary: "Halteres e banco",
                generatedAt: generated,
                validUntil: validUntil,
                version: 3,
                notes: "Progressão semanal"
            ),
            nutrition: [NutritionPrescriptionSnapshot(
                id: "nutrition-1",
                type: "macro_targets",
                payload: .object([
                    "projected_weight": .string("malicious-value"),
                    "planned_sessions": .number(99),
                ]),
                generatedAt: generated,
                validUntil: validUntil,
                version: 2,
                notes: "Prescrição revisada"
            )]
        )
    }
}
