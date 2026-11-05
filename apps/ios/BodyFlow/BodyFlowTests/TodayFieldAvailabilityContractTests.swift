import Foundation
import Testing
@testable import BodyFlow

@Suite("Today v4 preserves each independently proved field")
struct TodayFieldAvailabilityContractTests {
    @Test func unknownExerciseRetainsFoodProteinHydrationAndPriorBlock() throws {
        let response = try TodayFieldAvailabilityFixture.response()
        #expect(response.data.targets.caloriesKcal == 1900)
        #expect(response.data.consumed.caloriesKcal == 1200)
        #expect(response.data.remainingFoodKcal == 700)
        #expect(response.data.targets.proteinG == 130)
        #expect(response.data.proteinStatus.consumedG == Decimal(string: "90.5"))
        #expect(response.data.hydration.consumedML == 750)
        #expect(response.data.block7700?.currentKcal == 300)
        #expect(response.data.block7700?.completedBlocks == 2)
        #expect(response.data.workouts[0].estimatedKcal == 120)
        #expect(response.data.workouts[1].estimatedKcal == nil)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response.data)) as? [String: Any])
        #expect(encoded["exercise_kcal"] is NSNull)
        #expect(encoded["daily_balance_includes_exercise"] is NSNull)
        #expect((encoded["exercise_energy"] as? [String: String]) == ["status":"unavailable", "reason":"unknown_workout_energy"])
        #expect(!response.data.dailyBalanceCountsExercise)
    }

    @Test(arguments: ["ganho_massa", "manutencao"])
    func independentBalanceRemainsAnOfficialLiteral(_ objective: String) throws {
        let response = try TodayFieldAvailabilityFixture.response { data in
            data["protocol"] = objective
            data["current_protocol"] = objective
            data["daily_balance_kcal"] = 142
            data["daily_balance_reference_kcal"] = 2838
            data["daily_balance_includes_exercise"] = false
            data["daily_balance_energy"] = ["status":"available"]
        }
        #expect(response.data.dailyBalanceKcal == 142)
        #expect(response.data.dailyBalanceReferenceKcal == 2838)
        #expect(!response.data.dailyBalanceCountsExercise)
    }

    @Test func knownZeroIsPreservedAsAValue() throws {
        let response = try TodayFieldAvailabilityFixture.response { data in
            data["exercise_kcal"] = 0
            data["exercise_energy"] = ["status":"available"]
            data["daily_balance_kcal"] = -700
            data["daily_balance_reference_kcal"] = 1900
            data["daily_balance_includes_exercise"] = true
            data["daily_balance_energy"] = ["status":"available"]
            data["workouts"] = []
        }
        #expect(response.data.exerciseKcal == 0)
        #expect(response.data.dailyBalanceCountsExercise)
    }

    @Test(arguments: ["exercise_kcal", "exercise_energy", "daily_balance_kcal", "daily_balance_reference_kcal", "daily_balance_includes_exercise", "daily_balance_energy", "clinical_policy"])
    func v4RequiresItsNullableKeysAndPolicy(_ key: String) {
        #expect(throws: DecodingError.self) {
            try TodayFieldAvailabilityFixture.response { $0.removeValue(forKey: key) }
        }
    }

    @Test(arguments: 0..<15)
    func contradictionsAndUnsupportedAvailabilityAreRefused(_ defect: Int) {
        #expect(throws: DecodingError.self) {
            try TodayFieldAvailabilityFixture.response { data in
                switch defect {
                case 0: data["exercise_kcal"] = 120
                case 1: data["exercise_energy"] = ["status":"available"]
                case 2: data["exercise_energy"] = ["status":"unavailable", "reason":"source_unavailable"]
                case 3: data["exercise_energy"] = ["status":"available", "reason":"unknown_workout_energy"]
                case 4: data["exercise_energy"] = ["status":"unavailable", "reason":"unknown_workout_energy", "extra":"ignored"]
                case 5: data["daily_balance_energy"] = ["status":"available"]
                case 6: data["daily_balance_kcal"] = -700
                case 7: data["daily_balance_reference_kcal"] = 1900
                case 8: data["daily_balance_includes_exercise"] = true
                case 9: data["daily_balance_energy"] = ["status":"protected"]
                case 10: data["daily_balance_energy"] = ["status":"unavailable", "reason":"target_unavailable"]
                case 11: data["daily_balance_energy"] = ["status":"guessed"]
                case 12: data["exercise_energy"] = NSNull()
                case 13: data["daily_balance_energy"] = NSNull()
                default:
                    data["daily_balance_energy"] = ["status":"available"]
                    data["daily_balance_kcal"] = -700
                    data["daily_balance_reference_kcal"] = 1900
                    data["daily_balance_includes_exercise"] = true
                }
            }
        }
    }

    @Test func absentCalorieTargetDoesNotEraseProteinOrConsumption() throws {
        let response = try TodayFieldAvailabilityFixture.response { data in
            data["targets"] = ["calories_kcal":NSNull(), "protein_g":130, "source":"mixed", "calories_source":"unavailable", "protein_source":"daily_snapshot"]
            data["remaining_food_kcal"] = NSNull()
            data["food_excess_kcal"] = NSNull()
            data["daily_balance_energy"] = ["status":"unavailable", "reason":"target_unavailable"]
        }
        #expect(response.data.targets.caloriesKcal == nil && response.data.remainingFoodKcal == nil)
        #expect(response.data.consumed.caloriesKcal == 1200 && response.data.targets.proteinG == 130)
        #expect(response.data.block7700?.currentKcal == 300)
    }

    @Test func protectedBalanceCannotExposeValuesAndHidesThePriorBlock() throws {
        let response = try TodayFieldAvailabilityFixture.response { data in
            var policy = data["clinical_policy"] as! [String: Any]
            var hide = policy["hide"] as! [String: Bool]
            hide["balance"] = true
            hide["block"] = true
            policy["hide"] = hide
            data["clinical_policy"] = policy
            data["daily_balance_energy"] = ["status":"protected"]
        }
        #expect(response.data.dailyBalanceKcal == nil)
        #expect(!response.data.blockPresentationPolicy.showsBlock)
        #expect(response.data.targets.proteinG == 130 && response.data.consumed.caloriesKcal == 1200)
    }

    @Test func knownV3StaysNumericWithoutReceivingNewAvailabilityFields() throws {
        let response = try TodayFieldAvailabilityFixture.response { data in
            data["calculation_version"] = "bodyflow.daily-state.v3"
            data["exercise_kcal"] = 419
            data["daily_balance_kcal"] = -83
            data.removeValue(forKey: "exercise_energy")
            data.removeValue(forKey: "daily_balance_energy")
            data.removeValue(forKey: "daily_balance_includes_exercise")
            data.removeValue(forKey: "daily_balance_reference_kcal")
        }
        #expect(response.data.exerciseKcal == 419 && response.data.dailyBalanceCountsExercise)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(response.data)) as? [String: Any])
        #expect(encoded["exercise_energy"] == nil && encoded["daily_balance_energy"] == nil)
        #expect(encoded["exercise_kcal"] as? Int == 419)
        #expect(try JSONDecoder().decode(TodaySnapshot.self, from: JSONEncoder().encode(response.data)) == response.data)
    }
}
