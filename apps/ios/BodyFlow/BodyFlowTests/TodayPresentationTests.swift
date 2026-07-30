import Foundation
import Testing

@testable import BodyFlow

@Suite("Today Presentation")
struct TodayPresentationTests {
    @Test("official descriptor fields remain independent response literals")
    func officialFieldsRemainLiteral() throws {
        let snapshot = try BodyFlowTestFixtures.decodeInconsistentToday().data
        let presentation = TodayPresentation(snapshot: snapshot)

        #expect(presentation.energy.targetKcal == 1_935)
        #expect(presentation.energy.consumedKcal == 1_200)
        #expect(presentation.energy.remainingFoodKcal == 731)
        #expect(presentation.energy.foodExcessKcal == 17)
        #expect(presentation.energy.exerciseKcal == 419)
        #expect(presentation.energy.dailyBalanceKcal == -83)
        #expect(presentation.energy.dailyBalanceStatus == "provisional")
    }

    @Test("food remaining and net balance announce distinct exercise semantics")
    func energySemanticsStayDistinct() throws {
        let presentation = TodayPresentation(
            snapshot: try BodyFlowTestFixtures.decodeInconsistentToday().data
        )

        #expect(presentation.energy.remainingFoodText == "731 kcal")
        #expect(presentation.energy.remainingFoodAccessibilityValue
            == "731 quilocalorias; exercício excluído")
        #expect(presentation.energy.netBalanceText == "-83 kcal")
        #expect(presentation.energy.netBalanceAccessibilityValue
            == "menos 83 quilocalorias; exercício incluído")
    }

    @Test("header values come from the response without client clock defaults")
    func headerUsesResponse() throws {
        let snapshot = try Self.snapshotWithUpdatedAt().data
        let presentation = TodayPresentation(snapshot: snapshot)

        #expect(presentation.header.localDate == "2026-07-20")
        #expect(presentation.header.protocolName == "recomposicao")
        #expect(presentation.header.updatedAt == APITimestamp(
            value: Date(timeIntervalSince1970: 1_784_563_200)
        ))
    }

    @Test("attention and pending sections precede official energy")
    func attentionPrecedesEnergy() throws {
        let presentation = TodayPresentation(
            snapshot: try BodyFlowTestFixtures.decodeInconsistentToday().data
        )

        #expect(presentation.sectionOrder.prefix(3) == [
            .attention,
            .pending,
            .energy,
        ])
        #expect(presentation.attention.pendingRegistrationIDs
            == ["pending-z", "pending-a"])
        #expect(presentation.attention.routineActionIDs == [
            try Self.routineAttentionID(
                kind: .supplement,
                itemID: "supplement-1",
                reminderRuleID: "rule-20",
                scheduledFor: "2026-07-20T23:00:00Z"
            ),
            try Self.routineAttentionID(
                kind: .supplement,
                itemID: "supplement-1",
                reminderRuleID: "rule-08",
                scheduledFor: "2026-07-20T11:00:00Z"
            ),
        ])
    }

    @Test("same routine rule at different times keeps distinct ordered identities")
    func routineAttentionIdentityIncludesScheduledTime() throws {
        let response = try Self.mutateResponse { data in
            var supplements = try #require(
                data["supplements"] as? [String: Any]
            )
            var items = try #require(
                supplements["items"] as? [[String: Any]]
            )
            var item = try #require(items.first)
            var occurrences = try #require(
                item["occurrences"] as? [[String: Any]]
            )
            let first = try #require(occurrences.first)
            var second = first
            second["scheduled_for"] = "2026-07-21T00:00:00Z"
            occurrences = [first, second]
            item["occurrences"] = occurrences
            items[0] = item
            supplements["items"] = items
            data["supplements"] = supplements
        }

        #expect(
            TodayPresentation(snapshot: response.data)
                .attention.routineActionIDs == [
                    try Self.routineAttentionID(
                        kind: .supplement,
                        itemID: "supplement-1",
                        reminderRuleID: "rule-20",
                        scheduledFor: "2026-07-20T23:00:00Z"
                    ),
                    try Self.routineAttentionID(
                        kind: .supplement,
                        itemID: "supplement-1",
                        reminderRuleID: "rule-20",
                        scheduledFor: "2026-07-21T00:00:00Z"
                    ),
                ]
        )
    }

    @Test("supplement and medication occurrence identities include their kind")
    func routineAttentionIdentityIncludesKind() throws {
        let response = try Self.routineIdentitySnapshot(
            supplementTimes: ["2026-07-20T23:00:00.100Z"],
            medicationTimes: ["2026-07-20T23:00:00.100Z"]
        )
        let ids = TodayPresentation(snapshot: response.data)
            .attention.routineActionIDs

        #expect(ids == [
            try Self.routineAttentionID(
                kind: .supplement,
                itemID: "shared-item",
                reminderRuleID: "shared-rule",
                scheduledFor: "2026-07-20T23:00:00.100Z"
            ),
            try Self.routineAttentionID(
                kind: .medication,
                itemID: "shared-item",
                reminderRuleID: "shared-rule",
                scheduledFor: "2026-07-20T23:00:00.100Z"
            ),
        ])
        #expect(ids[0] != ids[1])
    }

    @Test("routine occurrence identities preserve fractional timestamps")
    func routineAttentionIdentityPreservesFractionalTime() throws {
        let response = try Self.routineIdentitySnapshot(
            supplementTimes: [
                "2026-07-20T23:00:00.100Z",
                "2026-07-20T23:00:00.900Z",
            ],
            medicationTimes: []
        )
        let ids = TodayPresentation(snapshot: response.data)
            .attention.routineActionIDs

        #expect(ids == [
            try Self.routineAttentionID(
                kind: .supplement,
                itemID: "shared-item",
                reminderRuleID: "shared-rule",
                scheduledFor: "2026-07-20T23:00:00.100Z"
            ),
            try Self.routineAttentionID(
                kind: .supplement,
                itemID: "shared-item",
                reminderRuleID: "shared-rule",
                scheduledFor: "2026-07-20T23:00:00.900Z"
            ),
        ])
        #expect(ids[0] != ids[1])
    }

    @Test("unavailable empty routine collection remains unavailable")
    func unavailableRoutineCollectionIsNotEmptyState() throws {
        let response = try Self.routineAvailabilitySnapshot(
            supplementsAvailability: "unavailable",
            supplementsItems: [],
            medicationsAvailability: "available",
            medicationsItems: []
        )
        let collections = TodayPresentation(snapshot: response.data)
            .routineCollections

        #expect(collections.map(\.kind) == [.supplement, .medication])
        #expect(collections[0].state == .unavailable)
        #expect(collections[0].items.isEmpty)
    }

    @Test("available empty routine collection presents an empty state")
    func availableRoutineCollectionUsesEmptyState() throws {
        let response = try Self.routineAvailabilitySnapshot(
            supplementsAvailability: "available",
            supplementsItems: [],
            medicationsAvailability: "unavailable",
            medicationsItems: []
        )
        let collections = TodayPresentation(snapshot: response.data)
            .routineCollections

        #expect(collections[0].state == .empty)
        #expect(collections[0].items.isEmpty)
    }

    @Test("mixed routine availability remains separate in response order")
    func mixedRoutineCollectionsStayIndependent() throws {
        let original = try BodyFlowTestFixtures.decodeInconsistentToday()
        let response = try Self.routineAvailabilitySnapshot(
            supplementsAvailability: "available",
            supplementsItems: original.data.supplements.items,
            medicationsAvailability: "unavailable",
            medicationsItems: []
        )
        let collections = TodayPresentation(snapshot: response.data)
            .routineCollections

        #expect(collections.map(\.kind) == [.supplement, .medication])
        #expect(collections[0].state == .populated)
        #expect(collections[0].items.map(\.id) == ["supplement-1"])
        #expect(collections[1].state == .unavailable)
        #expect(collections[1].items.isEmpty)
    }

    @Test("insufficient data remains neutral loaded content")
    func incompleteCopy() throws {
        let snapshot = try Self.snapshot(
            completionStatus: "insufficient_data"
        )

        #expect(TodayPresentation(snapshot: snapshot).completionMessage
            == "Dados insuficientes para fechar o dia")
    }

    @Test("missing target hydration goal and block are unavailable never zero")
    func nilFieldsAreUnavailable() throws {
        let snapshot = try BodyFlowTestFixtures
            .decodeTodayWithoutCalorieTarget().data
        let presentation = TodayPresentation(snapshot: snapshot)

        #expect(presentation.energy.targetText == "Indisponível")
        #expect(presentation.hydration.targetText == "Indisponível")
        #expect(presentation.hydration.remainingText == "Indisponível")
        #expect(presentation.block.targetText == "7.700 kcal")

        let withoutBlock = TodayPresentation(
            snapshot: try BodyFlowTestFixtures
                .decodeTodayWithoutOptionalBlock().data
        )
        #expect(withoutBlock.block.targetText == "Indisponível")
        #expect(withoutBlock.block.currentText == "Indisponível")
    }

    @Test("confirmed meal rows preserve response order and individual ids")
    func mealRowsStayIndividualAndOrdered() throws {
        let presentation = TodayPresentation(
            snapshot: try BodyFlowTestFixtures.decodeInconsistentToday().data
        )

        #expect(presentation.meals.map(\.id) == ["meal-z", "meal-a"])
        #expect(presentation.meals.map(\.foodName) == [
            "Item sintético Z",
            "Item sintético A",
        ])
    }

    @Test(arguments: [
        ("canonical_exact", "Referência confirmada"),
        ("product_label", "Referência confirmada"),
        ("llm_estimate", "Estimativa"),
        ("category_mismatch", "Estimativa"),
        ("protein_mismatch", "Estimativa"),
        ("composite_rejected", "Estimativa"),
        ("user_kcal", "Informado pelo paciente"),
        ("user_correction", "Informado pelo paciente"),
        ("future_source", "Origem não informada"),
    ])
    func mapsNutritionProvenance(source: String, expected: String) {
        #expect(TodayNutritionProvenance.label(for: source) == expected)
    }

    @Test("missing nutrition provenance is origin not informed")
    func missingNutritionProvenance() {
        #expect(TodayNutritionProvenance.label(for: nil)
            == "Origem não informada")
    }

    @Test("nullable nutrition provenance decodes and reaches presentation")
    func nullableNutritionProvenanceDecodesAndPresents() throws {
        let response = try Self.mutateResponse { data in
            var meals = try #require(data["meals"] as? [[String: Any]])
            var meal = try #require(meals.first)
            meal["nutrition_source"] = NSNull()
            meals[0] = meal
            data["meals"] = meals
        }

        #expect(response.data.meals[0].nutritionSource == nil)
        #expect(
            TodayPresentation(snapshot: response.data).meals[0].provenance
                == "Origem não informada"
        )
    }

    private static func snapshotWithUpdatedAt() throws -> TodayResponse {
        try mutateResponse { data in
            data["updated_at"] = "2026-07-20T16:00:00Z"
        }
    }

    private static func snapshot(
        completionStatus: String
    ) throws -> TodaySnapshot {
        try mutateResponse { data in
            var completion = try #require(
                data["completion_status"] as? [String: Any]
            )
            completion["status"] = completionStatus
            data["completion_status"] = completion
        }.data
    }

    private static func mutateResponse(
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> TodayResponse {
        let original = try BodyFlowTestFixtures.decodeInconsistentToday()
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
                as? [String: Any]
        )
        var data = try #require(object["data"] as? [String: Any])
        try mutation(&data)
        object["data"] = data
        return try JSONDecoder().decode(
            TodayResponse.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private static func routineAvailabilitySnapshot(
        supplementsAvailability: String,
        supplementsItems: [TodayRoutineItem],
        medicationsAvailability: String,
        medicationsItems: [TodayRoutineItem]
    ) throws -> TodayResponse {
        try mutateResponse { data in
            data["supplements"] = [
                "availability": supplementsAvailability,
                "items": try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(supplementsItems)
                ),
            ]
            data["medications"] = [
                "availability": medicationsAvailability,
                "items": try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(medicationsItems)
                ),
            ]
        }
    }

    private static func routineIdentitySnapshot(
        supplementTimes: [String],
        medicationTimes: [String]
    ) throws -> TodayResponse {
        try mutateResponse { data in
            var supplements = try #require(
                data["supplements"] as? [String: Any]
            )
            let sourceItems = try #require(
                supplements["items"] as? [[String: Any]]
            )
            let sourceItem = try #require(sourceItems.first)
            let sourceOccurrences = try #require(
                sourceItem["occurrences"] as? [[String: Any]]
            )
            let sourceOccurrence = try #require(sourceOccurrences.first)

            func item(scheduledTimes: [String]) -> [String: Any] {
                var item = sourceItem
                item["id"] = "shared-item"
                item["occurrences"] = scheduledTimes.map { scheduledFor in
                    var occurrence = sourceOccurrence
                    occurrence["reminder_rule_id"] = "shared-rule"
                    occurrence["scheduled_for"] = scheduledFor
                    occurrence["status"] = "pending"
                    occurrence["last_action_at"] = NSNull()
                    occurrence["snoozed_until"] = NSNull()
                    return occurrence
                }
                return item
            }

            supplements["availability"] = "available"
            supplements["items"] = supplementTimes.isEmpty
                ? []
                : [item(scheduledTimes: supplementTimes)]
            data["supplements"] = supplements
            data["medications"] = [
                "availability": "available",
                "items": medicationTimes.isEmpty
                    ? []
                    : [item(scheduledTimes: medicationTimes)],
            ]
        }
    }

    private static func routineAttentionID(
        kind: TodayRoutineAttentionID.Kind,
        itemID: String,
        reminderRuleID: String,
        scheduledFor: String
    ) throws -> TodayRoutineAttentionID {
        TodayRoutineAttentionID(
            kind: kind,
            itemID: itemID,
            reminderRuleID: reminderRuleID,
            scheduledFor: try JSONDecoder().decode(
                APITimestamp.self,
                from: Data("\"\(scheduledFor)\"".utf8)
            )
        )
    }
}
