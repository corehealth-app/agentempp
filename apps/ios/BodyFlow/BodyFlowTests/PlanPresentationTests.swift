import Foundation
import Testing

@testable import BodyFlow

@Suite("Plan Presentation")
struct PlanPresentationTests {
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
