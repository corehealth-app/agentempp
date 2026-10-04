import Foundation
import Testing

@testable import BodyFlow

@Suite("Today Presentation")
struct TodayPresentationTests {
    @Test("gram values format with the requested language locale")
    func gramValuesFollowTheLanguageLocale() throws {
        let value = try #require(Decimal(string: "90.5"))
        #expect(TodayValueFormatter.optionalGrams(value, language: .portugueseBrazil) == "90,5 g")
        #expect(TodayValueFormatter.optionalGrams(value, language: .englishUnitedStates) == "90.5 g")
        #expect(TodayValueFormatter.optionalGrams(nil, language: .portugueseBrazil) == "Indisponível")
    }

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
        // The fixture is an older server: no `daily_balance_includes_exercise`,
        // so the balance reads as one that includes exercise.
        #expect(presentation.energy.dailyBalanceIncludesExercise)
        #expect(presentation.energy.netBalanceText == "Déficit de 83 kcal")
        #expect(presentation.energy.netBalanceCaption == "Exercício incluído")
        #expect(presentation.energy.netBalanceAccessibilityValue
            == "déficit de 83 quilocalorias; exercício incluído")
    }

    @Test("the day balance is named in both languages and never called a net deficit")
    func dayBalanceLabel() throws {
        #expect(try AppLocalization.string("today.energy.net-balance", for: .portugueseBrazil)
            == "Balanço do dia")
        #expect(try AppLocalization.string("today.energy.net-balance", for: .englishUnitedStates)
            == "Day balance")
    }

    @Test("the day balance reads as a deficit, a surplus or zero, never with a minus sign", arguments: [
        DayBalanceCase(
            kcal: -1_535, includesExercise: true,
            portuguese: "Déficit de 1.535 kcal", english: "1,535 kcal deficit",
            portugueseSpoken: "déficit de 1.535 quilocalorias; exercício incluído",
            englishSpoken: "deficit of 1,535 kilocalories; exercise included"
        ),
        DayBalanceCase(
            kcal: 142, includesExercise: true,
            portuguese: "Superávit de 142 kcal", english: "142 kcal surplus",
            portugueseSpoken: "superávit de 142 quilocalorias; exercício incluído",
            englishSpoken: "surplus of 142 kilocalories; exercise included"
        ),
        DayBalanceCase(
            kcal: 0, includesExercise: true,
            portuguese: "0 kcal", english: "0 kcal",
            portugueseSpoken: "0 quilocalorias; exercício incluído",
            englishSpoken: "0 kilocalories; exercise included"
        ),
        DayBalanceCase(
            kcal: -83, includesExercise: false,
            portuguese: "Déficit de 83 kcal", english: "83 kcal deficit",
            portugueseSpoken: "déficit de 83 quilocalorias; exercício já contado no nível de atividade",
            englishSpoken: "deficit of 83 kilocalories; exercise already counted in your activity level"
        ),
        DayBalanceCase(
            kcal: 1_142, includesExercise: false,
            portuguese: "Superávit de 1.142 kcal", english: "1,142 kcal surplus",
            portugueseSpoken: "superávit de 1.142 quilocalorias; exercício já contado no nível de atividade",
            englishSpoken: "surplus of 1,142 kilocalories; exercise already counted in your activity level"
        ),
        DayBalanceCase(
            kcal: 0, includesExercise: false,
            portuguese: "0 kcal", english: "0 kcal",
            portugueseSpoken: "0 quilocalorias; exercício já contado no nível de atividade",
            englishSpoken: "0 kilocalories; exercise already counted in your activity level"
        ),
        // The exact reported days, not near variants.
        // Ganho de massa eating exactly the target: +142 kcal, exercise in
        // the activity level.
        DayBalanceCase(
            kcal: 142, includesExercise: false,
            portuguese: "Superávit de 142 kcal", english: "142 kcal surplus",
            portugueseSpoken: "superávit de 142 quilocalorias; exercício já contado no nível de atividade",
            englishSpoken: "surplus of 142 kilocalories; exercise already counted in your activity level"
        ),
        // The QA account today: -2297 kcal, exercise in the activity level.
        DayBalanceCase(
            kcal: -2_297, includesExercise: false,
            portuguese: "Déficit de 2.297 kcal", english: "2,297 kcal deficit",
            portugueseSpoken: "déficit de 2.297 quilocalorias; exercício já contado no nível de atividade",
            englishSpoken: "deficit of 2,297 kilocalories; exercise already counted in your activity level"
        ),
        // Recomposição on 19/05: -832 kcal, exercise included.
        DayBalanceCase(
            kcal: -832, includesExercise: true,
            portuguese: "Déficit de 832 kcal", english: "832 kcal deficit",
            portugueseSpoken: "déficit de 832 quilocalorias; exercício incluído",
            englishSpoken: "deficit of 832 kilocalories; exercise included"
        ),
    ])
    func dayBalanceIsSignAware(_ expected: DayBalanceCase) throws {
        let snapshot = try BodyFlowTestFixtures.decodeToday { data in
            data["daily_balance_kcal"] = expected.kcal
            data["daily_balance_includes_exercise"] = expected.includesExercise
        }.data
        let energy = TodayPresentation(snapshot: snapshot).energy

        #expect(energy.dailyBalanceKcal == expected.kcal)
        #expect(energy.dailyBalanceIncludesExercise == expected.includesExercise)
        #expect(energy.netBalanceText == expected.portuguese)
        #expect(energy.netBalanceText(for: .portugueseBrazil) == expected.portuguese)
        #expect(energy.netBalanceText(for: .englishUnitedStates) == expected.english)
        #expect(energy.netBalanceAccessibilityValue == expected.portugueseSpoken)
        #expect(energy.netBalanceAccessibilityValue(for: .englishUnitedStates)
            == expected.englishSpoken)
        #expect(energy.netBalanceCaption(for: .portugueseBrazil) == (expected.includesExercise
            ? "Exercício incluído" : "Exercício já contado no nível de atividade"))
        #expect(energy.netBalanceCaption(for: .englishUnitedStates) == (expected.includesExercise
            ? "Exercise included" : "Exercise already counted in your activity level"))
        for text in [
            energy.netBalanceText(for: .portugueseBrazil),
            energy.netBalanceText(for: .englishUnitedStates),
            energy.netBalanceAccessibilityValue(for: .portugueseBrazil),
            energy.netBalanceAccessibilityValue(for: .englishUnitedStates),
        ] {
            #expect(!text.contains("-") && !text.contains("−"))
            #expect(!text.contains("menos") && !text.contains("minus"))
        }
        // The food line is untouched by the balance and by its exercise flag.
        #expect(energy.remainingFoodText == "731 kcal")
        #expect(energy.remainingFoodAccessibilityValue == "731 quilocalorias; exercício excluído")
        #expect(energy.exerciseText == "419 kcal")
    }

    @Test("an unavailable day balance stays unavailable whatever the exercise flag says", arguments: [true, false])
    func unavailableDayBalanceKeepsItsWording(includesExercise: Bool) throws {
        let snapshot = try BodyFlowTestFixtures.decodeToday { data in
            data["daily_balance_kcal"] = NSNull()
            data["daily_balance_includes_exercise"] = includesExercise
        }.data
        let energy = TodayPresentation(snapshot: snapshot).energy

        #expect(energy.netBalanceText == "Indisponível")
        #expect(energy.netBalanceText(for: .englishUnitedStates) == "Not available")
        #expect(energy.netBalanceAccessibilityValue == "Indisponível")
        #expect(energy.netBalanceAccessibilityValue(for: .englishUnitedStates) == "Not available")
    }

    @Test("English client-owned Today copy and energy announcements are localized")
    func englishClientOwnedCopyIsLocalized() throws {
        let presentation = TodayPresentation(
            snapshot: try BodyFlowTestFixtures.decodeInconsistentToday().data
        )

        #expect(presentation.attention.pending[0].title(for: .englishUnitedStates)
            == "Meal proposal")
        #expect(presentation.attention.pending[1].title(for: .englishUnitedStates)
            == "Workout proposal")
        #expect(presentation.attention.pending[1].detail(for: .englishUnitedStates)
            == "Pending confirmation")
        #expect(presentation.completionMessage(for: .englishUnitedStates) == nil)
        #expect(presentation.energy.remainingFoodAccessibilityValue(
            for: .englishUnitedStates
        ) == "731 kilocalories; exercise excluded")
        #expect(presentation.energy.netBalanceAccessibilityValue(
            for: .englishUnitedStates
        ) == "deficit of 83 kilocalories; exercise included")
        #expect(presentation.energy.netBalanceText(for: .englishUnitedStates)
            == "83 kcal deficit")
        #expect(presentation.energy.netBalanceCaption(for: .englishUnitedStates)
            == "Exercise included")
    }

    @Test("header values come from the response without client clock defaults")
    func headerUsesResponse() throws {
        let snapshot = try Self.snapshotWithUpdatedAt().data
        let presentation = TodayPresentation(snapshot: snapshot)

        #expect(presentation.header.localDate == "2026-07-20")
        #expect(presentation.header.protocolName == "Recomposição corporal")
        #expect(presentation.header.updatedAt == APITimestamp(
            value: Date(timeIntervalSince1970: 1_784_563_200)
        ))
    }

    @Test("staging muscle-gain protocol is readable in the Today header")
    func muscleGainProtocolIsLocalized() throws {
        let snapshot = try Self.mutateResponse { data in
            data["protocol"] = "ganho_massa"
        }.data

        #expect(TodayPresentation(snapshot: snapshot).header.protocolName == "Ganho de massa")
        #expect(TodayPresentation(
            snapshot: snapshot,
            language: .englishUnitedStates
        ).header.protocolName == "Muscle gain")
    }

    @Test("core metrics precede pending context while preserving response order")
    func coreMetricsPrecedePendingContext() throws {
        let presentation = TodayPresentation(
            snapshot: try BodyFlowTestFixtures.decodeInconsistentToday().data
        )

        #expect(presentation.sectionOrder.prefix(5) == [
            .energy,
            .protein,
            .hydration,
            .attention,
            .pending,
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

    @Test("core metrics precede pending information without merging meanings")
    func coreMetricsPrecedeAttention() throws {
        let presentation = TodayPresentation(
            snapshot: try BodyFlowTestFixtures.decodeInconsistentToday().data
        )

        #expect(presentation.sectionOrder.prefix(5) == [
            .energy,
            .protein,
            .hydration,
            .attention,
            .pending,
        ])
        #expect(presentation.energy.remainingFoodKcal == 731)
        #expect(presentation.energy.dailyBalanceKcal == -83)
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

    // The server sends "not_configured" for a patient with no routine items
    // (packages/core daily-state). Staging device gate 2026-09-28: QA account A
    // saw "Indisponível" for both collections instead of the empty state.
    @Test("not configured routine collection presents the empty state, not unavailable")
    func notConfiguredRoutineCollectionUsesEmptyState() throws {
        let response = try Self.routineAvailabilitySnapshot(
            supplementsAvailability: "not_configured",
            supplementsItems: [],
            medicationsAvailability: "not_configured",
            medicationsItems: []
        )
        let collections = TodayPresentation(snapshot: response.data)
            .routineCollections

        #expect(collections.map(\.state) == [.empty, .empty])
        #expect(collections.allSatisfy { $0.items.isEmpty })
    }

    @Test("an unknown routine availability stays unavailable")
    func unknownRoutineAvailabilityStaysUnavailable() throws {
        let response = try Self.routineAvailabilitySnapshot(
            supplementsAvailability: "paused",
            supplementsItems: [],
            medicationsAvailability: "available",
            medicationsItems: []
        )
        let collections = TodayPresentation(snapshot: response.data)
            .routineCollections

        #expect(collections[0].state == .unavailable)
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
        #expect(TodayPresentation(snapshot: snapshot).completionMessage(
            for: .englishUnitedStates
        ) == "Insufficient data to close the day")
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

    @Test("device gate meal energy keeps its fraction and reads in the app language")
    func fractionalMealEnergyIsShownAsReceived() throws {
        let presentation = TodayPresentation(
            snapshot: try BodyFlowTestFixtures.decodeToday(
                mealsJSON: BodyFlowTestFixtures.deviceGateMealsJSON
            ).data
        )

        #expect(presentation.meals.map(\.kcal) == [
            Decimal(string: "200"),
            Decimal(string: "284.6"),
            Decimal(string: "191"),
        ])
        let beans = try #require(presentation.meals.first { $0.id == "device-gate-meal-beans" })
        #expect(TodayValueFormatter.mealKcal(beans.kcal, language: .portugueseBrazil) == "284,6 kcal")
        #expect(TodayValueFormatter.mealKcal(beans.kcal, language: .englishUnitedStates) == "284.6 kcal")
        #expect(TodayValueFormatter.mealKcal(Decimal(string: "1200.5"), language: .portugueseBrazil) == "1.200,5 kcal")
        #expect(TodayValueFormatter.mealKcal(0, language: .portugueseBrazil) == "0 kcal")
        #expect(TodayValueFormatter.mealKcal(nil, language: .portugueseBrazil) == "Indisponível")
        #expect(TodayValueFormatter.mealKcal(nil, language: .englishUnitedStates) == "Not available")
    }

    @Test("absent workout values and balances read as not available, never as zero")
    func absentWorkoutValuesAndBalancesAreNotAvailable() throws {
        let response = try BodyFlowTestFixtures.decodeToday { data in
            data["remaining_food_kcal"] = NSNull()
            data["food_excess_kcal"] = NSNull()
            data["daily_balance_kcal"] = NSNull()
            data["workouts"] = [
                [
                    "id": "workout-without-intensity",
                    "workout_type": "caminhada",
                    "duration_min": 30,
                    "estimated_kcal": NSNull(),
                    "intensity": NSNull(),
                    "performed_at": "2026-07-20T07:30:00.000Z",
                ],
            ]
        }
        let presentation = TodayPresentation(snapshot: response.data)

        #expect(presentation.energy.remainingFoodText == "Indisponível")
        #expect(presentation.energy.foodExcessText == "Indisponível")
        #expect(presentation.energy.netBalanceText == "Indisponível")
        #expect(presentation.energy.remainingFoodAccessibilityValue == "Indisponível")
        #expect(presentation.energy.netBalanceAccessibilityValue == "Indisponível")
        #expect(presentation.energy.exerciseText == "419 kcal")
        let workout = try #require(presentation.workouts.first)
        #expect(workout.intensity == nil)
        #expect(workout.estimatedKcal == nil)
        #expect(workout.detailText(language: .portugueseBrazil) == "30 min")
        #expect(
            TodayValueFormatter.optionalKcal(workout.estimatedKcal, language: .englishUnitedStates)
                == "Not available"
        )
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
        ("taco", "Referência confirmada"),
        // Staging 2026-09-29: TACO fuzzy matches showed "Origem não informada".
        ("canonical_fuzzy", "Referência aproximada"),
        ("canonical_composite", "Referência aproximada"),
        ("canonical_composite_partial", "Referência aproximada"),
        ("rule_based", "Referência aproximada"),
        ("history", "Referência aproximada"),
        ("pending_approved", "Referência aproximada"),
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

struct DayBalanceCase: Sendable, CustomTestStringConvertible {
    let kcal: Int
    let includesExercise: Bool
    let portuguese: String
    let english: String
    let portugueseSpoken: String
    let englishSpoken: String

    var testDescription: String {
        "\(kcal) kcal, exercise \(includesExercise ? "included" : "in the activity level")"
    }
}
