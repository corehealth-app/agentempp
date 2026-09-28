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
