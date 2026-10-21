import Foundation
import Testing

@testable import BodyFlow

@Suite("Today Contract")
struct TodayContractTests {
    @Test("official daily values remain exactly as received")
    func preservesOfficialDailyValues() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.targets.caloriesKcal == 1_935)
        #expect(response.data.consumed.caloriesKcal == 1_200)
        #expect(response.data.remainingFoodKcal == 731)
        #expect(response.data.foodExcessKcal == 17)
        #expect(response.data.exerciseKcal == 419)
        #expect(response.data.dailyBalanceKcal == -83)
        #expect(response.data.dailyBalanceStatus == "provisional")
    }

    @Test("envelope and extensible source decode their exact server keys")
    func decodesEnvelopeAndExtensibleSource() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.meta.apiVersion == "v1")
        #expect(response.meta.requestID == "request-today-contract-0001")
        #expect(response.data.localDate == "2026-07-20")
        #expect(response.data.calculationVersion == "bodyflow.daily-state.v2")
        #expect(response.data.meals[0].nutritionSource == "future_catalog_v99")
    }

    @Test("nullable targets and hydration without target remain absent")
    func preservesNullableTargetsAndHydration() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.targets.proteinG == nil)
        #expect(response.data.targets.proteinSource == nil)
        #expect(response.data.proteinStatus.targetG == nil)
        #expect(response.data.proteinStatus.remainingG == nil)
        #expect(response.data.proteinStatus.percentage == nil)
        #expect(response.data.hydration.consumedML == 1_250)
        #expect(response.data.hydration.targetML == nil)
        #expect(response.data.hydration.remainingML == nil)
        #expect(response.data.hydration.percentage == nil)
        #expect(response.data.hydration.status == "tracked_without_target")
    }

    @Test("device gate meals with a fractional official energy decode (2026-09-27)")
    func decodesDeviceGateFractionalMealEnergy() throws {
        let response = try BodyFlowTestFixtures.decodeToday(
            mealsJSON: BodyFlowTestFixtures.deviceGateMealsJSON
        )

        #expect(response.data.meals.map(\.id) == [
            "device-gate-meal-rice",
            "device-gate-meal-beans",
            "device-gate-meal-chicken",
        ])
        #expect(response.data.meals.map(\.kcal) == [
            Decimal(string: "200"),
            Decimal(string: "284.6"),
            Decimal(string: "191"),
        ])
        let beans = response.data.meals[1]
        #expect(beans.quantityG == Decimal(string: "86.5"))
        #expect(beans.proteinG == Decimal(string: "17.28"))
        #expect(beans.carbsG == Decimal(string: "52.96"))
        #expect(beans.fatG == Decimal(string: "1.09"))
        #expect(beans.nutritionSource == "canonical_fuzzy")
        #expect(response.data.meals[0].nutritionSource == "user_kcal")
        // The official day totals stay the server's integers.
        #expect(response.data.remainingFoodKcal == 731)
    }

    @Test("absent meal values stay absent instead of becoming zero")
    func keepsAbsentMealValuesAbsent() throws {
        let response = try BodyFlowTestFixtures.decodeToday(mealsJSON: """
            [
              {
                "id": "meal-without-values",
                "meal_type": null,
                "food_name": "Item sem cálculo",
                "quantity_g": null,
                "kcal": null,
                "protein_g": null,
                "carbs_g": null,
                "fat_g": null,
                "consumed_at": "2026-07-20T20:15:00.000Z",
                "nutrition_source": "no_match"
              },
              {
                "id": "meal-zero",
                "meal_type": "lanche",
                "food_name": "Água",
                "quantity_g": 250,
                "kcal": 0,
                "protein_g": 0,
                "carbs_g": 0,
                "fat_g": 0,
                "consumed_at": "2026-07-20T21:15:00.000Z",
                "nutrition_source": "rule_based"
              }
            ]
            """)

        let absent = response.data.meals[0]
        #expect(absent.mealType == nil)
        #expect(absent.quantityG == nil)
        #expect(absent.kcal == nil)
        #expect(absent.proteinG == nil)
        #expect(absent.carbsG == nil)
        #expect(absent.fatG == nil)
        #expect(response.data.meals[1].kcal == 0)
    }

    @Test("malformed meal energy is rejected, not coerced", arguments: [
        "\"284,6\"",
        "\"abc\"",
        "true",
    ])
    func rejectsMalformedMealEnergy(rawKcal: String) {
        let meal = """
            [
              {
                "id": "meal-malformed",
                "meal_type": "jantar",
                "food_name": "Item",
                "quantity_g": 100,
                "kcal": \(rawKcal),
                "protein_g": 1,
                "carbs_g": 1,
                "fat_g": 1,
                "consumed_at": "2026-07-20T20:15:00.000Z",
                "nutrition_source": null
              }
            ]
            """

        #expect(throws: DecodingError.self) {
            try BodyFlowTestFixtures.decodeToday(mealsJSON: meal)
        }
    }

    @Test("a workout logged without intensity, type, duration or energy still decodes")
    func decodesWorkoutWithAbsentValues() throws {
        // The WhatsApp tool stores `intensity: null` when the patient did not
        // say it; the contract (DailyStateWorkout) allows null in all four.
        let response = try BodyFlowTestFixtures.decodeToday { data in
            data["workouts"] = [
                [
                    "id": "workout-without-intensity",
                    "workout_type": "caminhada",
                    "duration_min": 30,
                    "estimated_kcal": 120,
                    "intensity": NSNull(),
                    "performed_at": "2026-07-20T07:30:00.000Z",
                ],
                [
                    "id": "workout-without-values",
                    "workout_type": NSNull(),
                    "duration_min": NSNull(),
                    "estimated_kcal": NSNull(),
                    "intensity": NSNull(),
                    "performed_at": "2026-07-20T08:30:00.000Z",
                ],
            ]
        }

        let first = response.data.workouts[0]
        #expect(first.intensity == nil)
        #expect(first.durationMin == 30)
        #expect(first.estimatedKcal == 120)
        let second = response.data.workouts[1]
        #expect(second.workoutType == nil)
        #expect(second.durationMin == nil)
        #expect(second.estimatedKcal == nil)
        #expect(second.intensity == nil)
    }

    @Test("an older server sends neither balance field: exercise counts as included, no reference")
    func decodesTodayWithoutTheBalanceSemanticsFields() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.dailyBalanceIncludesExercise == nil)
        #expect(response.data.dailyBalanceCountsExercise)
        #expect(response.data.dailyBalanceReferenceKcal == nil)
        #expect(response.data.dailyBalanceKcal == -83)
    }

    @Test("the two additive balance fields decode from their exact server keys", arguments: [true, false])
    func decodesTheBalanceSemanticsFields(includesExercise: Bool) throws {
        let response = try BodyFlowTestFixtures.decodeToday { data in
            data["protocol"] = includesExercise ? "recomposicao" : "ganho_massa"
            data["daily_balance_kcal"] = includesExercise ? -1_535 : 142
            data["daily_balance_includes_exercise"] = includesExercise
            data["daily_balance_reference_kcal"] = includesExercise ? 2_735 : 2_838
        }

        #expect(response.data.dailyBalanceIncludesExercise == includesExercise)
        #expect(response.data.dailyBalanceCountsExercise == includesExercise)
        #expect(response.data.dailyBalanceReferenceKcal == (includesExercise ? 2_735 : 2_838))
        #expect(response.data.dailyBalanceKcal == (includesExercise ? -1_535 : 142))
        // Every field that existed before keeps its literal value.
        #expect(response.data.remainingFoodKcal == 731)
        #expect(response.data.foodExcessKcal == 17)
        #expect(response.data.exerciseKcal == 419)
        #expect(response.data.dailyBalanceStatus == "provisional")

        let roundTrip = try JSONDecoder().decode(
            TodaySnapshot.self,
            from: JSONEncoder().encode(response.data)
        )
        #expect(roundTrip.dailyBalanceIncludesExercise == includesExercise)
        #expect(roundTrip.dailyBalanceReferenceKcal == response.data.dailyBalanceReferenceKcal)
        #expect(roundTrip.dailyBalanceKcal == response.data.dailyBalanceKcal)
    }

    @Test("null balance fields read like absent ones")
    func decodesNullBalanceSemanticsFields() throws {
        let response = try BodyFlowTestFixtures.decodeToday { data in
            data["daily_balance_includes_exercise"] = NSNull()
            data["daily_balance_reference_kcal"] = NSNull()
        }

        #expect(response.data.dailyBalanceIncludesExercise == nil)
        #expect(response.data.dailyBalanceCountsExercise)
        #expect(response.data.dailyBalanceReferenceKcal == nil)
    }

    @Test("without a calorie target the food and net balances are absent, not zero")
    func decodesAbsentBalancesWithoutCalorieTarget() throws {
        // packages/core daily-state: no calorie target -> the three balances
        // are null; exercise stays a number.
        let response = try BodyFlowTestFixtures.decodeToday { data in
            var targets = try #require(data["targets"] as? [String: Any])
            targets["calories_kcal"] = NSNull()
            targets["calories_source"] = "unavailable"
            data["targets"] = targets
            data["remaining_food_kcal"] = NSNull()
            data["food_excess_kcal"] = NSNull()
            data["daily_balance_kcal"] = NSNull()
        }

        #expect(response.data.targets.caloriesKcal == nil)
        #expect(response.data.remainingFoodKcal == nil)
        #expect(response.data.foodExcessKcal == nil)
        #expect(response.data.dailyBalanceKcal == nil)
        #expect(response.data.exerciseKcal == 419)
    }

    @Test("nullable calorie target and source remain absent")
    func preservesNullableCalorieTargetAndSource() throws {
        let response = try BodyFlowTestFixtures
            .decodeTodayWithoutCalorieTarget()

        #expect(response.data.targets.caloriesKcal == nil)
        #expect(response.data.targets.caloriesSource == nil)
    }

    @Test("server row and occurrence order is preserved")
    func preservesResponseOrder() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.meals.map(\.id) == ["meal-z", "meal-a"])
        #expect(response.data.workouts.map(\.id) == ["workout-z", "workout-a"])
        #expect(
            response.data.supplements.items[0].schedules.map(\.id)
                == ["rule-20", "rule-08"]
        )
        #expect(
            response.data.supplements.items[0].occurrences
                .map(\.reminderRuleID) == ["rule-20", "rule-08"]
        )
        #expect(
            response.data.pendingActions.registrations.map(\.id)
                == ["pending-z", "pending-a"]
        )
    }

    @Test("completion pending actions and source metadata remain server-authored")
    func decodesCompletionPendingActionsAndSources() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(response.data.completionStatus.status == "pending_information")
        #expect(!response.data.completionStatus.dayClosed)
        #expect(response.data.completionStatus.hasSufficientData == nil)
        #expect(response.data.pendingActions.registrations[1].mealType == nil)
        #expect(response.data.pendingActions.mealGaps.open == ["jantar"])
        #expect(response.data.pendingActions.mealGaps.activeDays == 10)
        #expect(response.data.sources.targets == "daily_snapshot")
        #expect(response.data.sources.hydrationTarget == "unavailable")
        #expect(response.data.sources.block7700 == "user_progress")
    }

    @Test("optional server block decodes without a local replacement")
    func preservesOptionalBlock() throws {
        let response = try BodyFlowTestFixtures.decodeInconsistentToday()
        let responseWithoutBlock = try BodyFlowTestFixtures
            .decodeTodayWithoutOptionalBlock()

        #expect(response.data.block7700?.currentKcal == 2_500)
        #expect(response.data.block7700?.totalCreditedKcal == 10_200)
        #expect(responseWithoutBlock.data.block7700 == nil)
    }

    @Test("provider exposes the shared Today response")
    func providerReturnsTodayResponse() async throws {
        let expected = try BodyFlowTestFixtures.decodeInconsistentToday()
        let provider: any TodayProviding = TodayProviderStub(response: expected)

        #expect(try await provider.today() == expected)
    }
}

private struct TodayProviderStub: TodayProviding {
    let response: TodayResponse

    func today() async throws -> TodayResponse {
        response
    }
}

@Suite("Today Weekly Strength Contract")
struct TodayWeeklyStrengthContractTests {
    static func section() -> [String: Any] {
        [
            "status": "available", "week_start": "2026-10-12",
            "as_of_local_date": "2026-10-14", "time_zone": "UTC",
            "observed_at": "2026-10-14T12:00:00.123457Z",
            "completed_strength_days": 2, "planned_days": 3,
            "target_source": "accepted_plan", "target_availability": "available", "percentage": 67,
        ]
    }

    static func response(_ section: [String: Any]) throws -> TodayResponse {
        try BodyFlowTestFixtures.decodeToday { $0["strength_training_week"] = section }
    }

    @Test("old and OFF servers retain the previous optional contract")
    func oldServerAndNull() throws {
        #expect(try BodyFlowTestFixtures.decodeInconsistentToday().data.strengthTrainingWeek == nil)
        let response = try BodyFlowTestFixtures.decodeToday { $0["strength_training_week"] = NSNull() }
        #expect(response.data.strengthTrainingWeek == nil)
        #expect(response.data.remainingFoodKcal == 731)
    }

    @Test("weekly dates, UTC6 and counts remain official independent literals")
    func officialWeeklyValues() throws {
        let response = try Self.response(Self.section())
        guard case let .available(value)? = response.data.strengthTrainingWeek else {
            Issue.record("Expected the official weekly section"); return
        }
        #expect(response.data.localDate == "2026-07-20")
        #expect(value.weekStart == "2026-10-12")
        #expect(value.asOfLocalDate == "2026-10-14")
        #expect(value.timeZone == "UTC")
        #expect(value.observedAt == "2026-10-14T12:00:00.123457Z")
        #expect(value.completedStrengthDays == 2 && value.plannedDays == 3 && value.percentage == 67)
        #expect(value.targetSource == .acceptedPlan && value.targetAvailability == .available)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response.data.strengthTrainingWeek)) as? [String: Any])
        #expect(encoded["observed_at"] as? String == value.observedAt)
        #expect(Set(encoded.keys) == Set(Self.section().keys))
    }

    @Test("X may exceed Y and the client never recomputes a supplied percentage")
    func noClientFormula() throws {
        var section = Self.section()
        section["completed_strength_days"] = 4; section["percentage"] = 100
        guard case let .available(over)? = try Self.response(section).data.strengthTrainingWeek else {
            Issue.record("Expected weekly values"); return
        }
        #expect(over.completedStrengthDays == 4 && over.plannedDays == 3 && over.percentage == 100)
        section["completed_strength_days"] = 2; section["percentage"] = 91
        guard case let .available(literal)? = try Self.response(section).data.strengthTrainingWeek else {
            Issue.record("Expected weekly values"); return
        }
        #expect(literal.percentage == 91)
    }

    @Test("zero and absence preserve X with explicit nullable fields", arguments: ["zero", "absent"])
    func nullableTargets(kind: String) throws {
        var section = Self.section()
        section["target_availability"] = kind
        if kind == "zero" { section["planned_days"] = 0 }
        else { section["planned_days"] = NSNull() }
        section["target_source"] = kind == "zero" ? "informed_frequency" : "absent"
        section["percentage"] = NSNull()
        let response = try Self.response(section)
        guard case let .available(value)? = response.data.strengthTrainingWeek else {
            Issue.record("Expected zero or absent target"); return
        }
        #expect(value.completedStrengthDays == 2)
        #expect(value.plannedDays == (kind == "zero" ? 0 : nil))
        #expect(value.percentage == nil)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response.data.strengthTrainingWeek)) as? [String: Any])
        #expect(encoded["percentage"] is NSNull)
        #expect(encoded["planned_days"] != nil)
    }

    @Test("negative and future statuses never acquire partial counters")
    func safeNegativeStates() throws {
        #expect(try Self.response(["status": "unavailable", "reason": "missing_scope", "completed_strength_days": 6]).data.strengthTrainingWeek == .unavailable(reason: "missing_scope"))
        #expect(try Self.response(["status": "conflict", "reason": "week_changed", "planned_days": 7]).data.strengthTrainingWeek == .conflict(reason: "week_changed"))
        #expect(try Self.response(["status": "future_status", "completed_strength_days": 7]).data.strengthTrainingWeek == .unsupported(status: "future_status"))
        #expect(throws: DecodingError.self) { try Self.response(["status": "unavailable"]) }
    }

    @Test("a UTC observation may belong to the previous local date")
    func localObservationBoundary() throws {
        var section = Self.section()
        section["time_zone"] = "America/Los_Angeles"
        section["as_of_local_date"] = "2026-10-13"
        section["observed_at"] = "2026-10-14T00:30:00.123457Z"
        guard case let .available(value)? = try Self.response(section).data.strengthTrainingWeek else {
            Issue.record("Expected local civil scope"); return
        }
        #expect(value.asOfLocalDate == "2026-10-13")
        #expect(value.observedAt == "2026-10-14T00:30:00.123457Z")
    }

    @Test("malformed available sections fail without coercion or zero fallback", arguments: [
        "fractionalX", "booleanX", "negativeX", "excessX", "stringY", "source", "missingY", "missingPercentage",
        "zeroPositiveTarget", "absentWithY", "missingObservation", "milliseconds", "newlineObservation",
        "impossibleDate", "notMonday", "outsideWeek", "unknownZone", "percentageRange", "booleanStatus",
    ])
    func malformed(kind: String) throws {
        var section = Self.section()
        switch kind {
        case "fractionalX": section["completed_strength_days"] = 2.5
        case "booleanX": section["completed_strength_days"] = true
        case "negativeX": section["completed_strength_days"] = -1
        case "excessX": section["completed_strength_days"] = 8
        case "stringY": section["planned_days"] = "3"
        case "source": section["target_source"] = "future_source"
        case "missingY": section.removeValue(forKey: "planned_days")
        case "missingPercentage": section.removeValue(forKey: "percentage")
        case "zeroPositiveTarget": section["planned_days"] = 0
        case "absentWithY": section["target_availability"] = "absent"
        case "missingObservation": section.removeValue(forKey: "observed_at")
        case "milliseconds": section["observed_at"] = "2026-10-14T12:00:00.123Z"
        case "newlineObservation": section["observed_at"] = "2026-10-14T12:00:00.123457Z\n"
        case "impossibleDate": section["as_of_local_date"] = "2026-02-30"
        case "notMonday": section["week_start"] = "2026-10-13"
        case "outsideWeek": section["as_of_local_date"] = "2026-10-19"
        case "unknownZone": section["time_zone"] = "Unknown/NoZone"
        case "percentageRange": section["percentage"] = 101
        default: section["status"] = true
        }
        #expect(throws: DecodingError.self) { try Self.response(section) }
    }
}
