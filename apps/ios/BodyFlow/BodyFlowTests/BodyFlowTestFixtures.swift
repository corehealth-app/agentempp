import Foundation
import Testing

@testable import BodyFlow

enum BodyFlowTestFixtures {
    static let textMealDetectionInput = MealDetectionInput.text(
        "arroz integral e feijao"
    )

    static let registrationProposal = RegistrationProposalRequest.meal(
        MealProposalRequest(
            mealType: .lunch,
            items: [
                MealProposalItemRequest(
                    foodName: "arroz integral",
                    quantityG: 125,
                    userKcal: nil
                ),
            ],
            consumedAt: nil
        )
    )

    static let registrationEdit = RegistrationEditCommand(
        registrationID: "release-unavailable-registration",
        proposal: registrationProposal
    )

    static let registrationID = RegistrationIDCommand(
        registrationID: "release-unavailable-registration"
    )

    static func hydrationAttempt() throws -> MutationAttempt<HydrationCommand> {
        MutationAttempt(
            operation: .hydration,
            key: try IdempotencyKey(validating: "release-hydration-0001"),
            payload: try HydrationCommand(
                amountML: 250,
                occurredAt: APITimestamp(value: capabilityDate)
            ),
            createdAt: capabilityDate
        )
    }

    static func weightAttempt() throws -> MutationAttempt<WeightCommand> {
        MutationAttempt(
            operation: .weight,
            key: try IdempotencyKey(validating: "release-weight-0001"),
            payload: try WeightCommand(
                weightKG: 75,
                recordedAt: capabilityDate
            ),
            createdAt: capabilityDate
        )
    }

    static func routineAttempt() throws -> MutationAttempt<RoutineActionCommand> {
        MutationAttempt(
            operation: .routineAction,
            key: try IdempotencyKey(validating: "release-routine-0001"),
            payload: try RoutineActionCommand(
                kind: .supplement,
                itemID: "release-unavailable-supplement",
                status: .taken,
                reminderRuleID: "release-unavailable-reminder",
                scheduledFor: APITimestamp(value: capabilityDate),
                occurredAt: APITimestamp(value: capabilityDate),
                snoozedUntil: nil
            ),
            createdAt: capabilityDate
        )
    }

    private static let capabilityDate = Date(
        timeIntervalSince1970: 1_785_283_200
    )

    static func decodeHistoryWithMatchingRows() throws -> HistoryResponse {
        try decodeHistory(from: historyWithMatchingRowsData)
    }

    static func decodeHistoryMealsOnly() throws -> HistoryResponse {
        try decodeHistory(meals: nil, workouts: [])
    }

    static func decodeHistoryWorkoutsOnly() throws -> HistoryResponse {
        try decodeHistory(meals: [], workouts: nil)
    }

    static func decodeEmptyHistory() throws -> HistoryResponse {
        try decodeHistory(meals: [], workouts: [])
    }

    static func decodeInconsistentToday() throws -> TodayResponse {
        try JSONDecoder().decode(TodayResponse.self, from: inconsistentTodayData)
    }

    static func decodeTodayWithoutOptionalBlock() throws -> TodayResponse {
        var object = try #require(
            JSONSerialization.jsonObject(with: inconsistentTodayData)
                as? [String: Any]
        )
        var data = try #require(object["data"] as? [String: Any])
        data.removeValue(forKey: "block_7700")
        object["data"] = data

        return try JSONDecoder().decode(
            TodayResponse.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    static func decodeTodayWithoutCalorieTarget() throws -> TodayResponse {
        var object = try #require(
            JSONSerialization.jsonObject(with: inconsistentTodayData)
                as? [String: Any]
        )
        var data = try #require(object["data"] as? [String: Any])
        var targets = try #require(data["targets"] as? [String: Any])
        targets.removeValue(forKey: "calories_kcal")
        targets.removeValue(forKey: "calories_source")
        data["targets"] = targets
        object["data"] = data

        return try JSONDecoder().decode(
            TodayResponse.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private static func decodeHistory(
        meals: [[String: Any]]? = nil,
        workouts: [[String: Any]]? = nil
    ) throws -> HistoryResponse {
        var object = try #require(
            JSONSerialization.jsonObject(with: historyWithMatchingRowsData)
                as? [String: Any]
        )
        var data = try #require(object["data"] as? [String: Any])

        if let meals {
            data["meals"] = meals
        }
        if let workouts {
            data["workouts"] = workouts
        }
        object["data"] = data

        return try JSONDecoder().decode(
            HistoryResponse.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private static func decodeHistory(from data: Data) throws -> HistoryResponse {
        try JSONDecoder().decode(HistoryResponse.self, from: data)
    }

    private static let historyWithMatchingRowsData = Data(
        """
        {
          "data": {
            "meals": [
              {
                "id": "fixture-meal-row-1",
                "meal_type": "almoco",
                "food_name": "Arroz integral",
                "quantity_g": 125.50,
                "kcal": 407.25,
                "protein_g": 31.25,
                "carbs_g": 48.50,
                "fat_g": 9.75,
                "consumed_at": "2026-07-29T15:30:00.123Z",
                "future_meal_field": "ignored"
              },
              {
                "id": "fixture-meal-row-2",
                "meal_type": "almoco",
                "food_name": "Feijao carioca",
                "quantity_g": null,
                "kcal": null,
                "protein_g": null,
                "carbs_g": null,
                "fat_g": null,
                "consumed_at": "2026-07-29T15:30:00.123Z"
              }
            ],
            "workouts": [
              {
                "id": "fixture-workout-row-1",
                "workout_type": null,
                "duration_min": null,
                "estimated_kcal": null,
                "intensity": null,
                "performed_at": "2026-07-29T12:00:00Z",
                "future_workout_field": true
              }
            ],
            "pagination": {
              "limit": 2,
              "before": "2026-07-28T00:00:00Z",
              "future_pagination_field": "ignored"
            },
            "future_history_field": [1, 2, 3]
          },
          "meta": {
            "api_version": "v1",
            "request_id": "request-history-contract-0001"
          }
        }
        """.utf8
    )

    private static let inconsistentTodayData = Data(
        """
        {
          "data": {
            "local_date": "2026-07-20",
            "protocol": "recomposicao",
            "targets": {
              "calories_kcal": 1935,
              "protein_g": null,
              "source": "daily_snapshot",
              "calories_source": "daily_snapshot",
              "protein_source": null
            },
            "consumed": {
              "calories_kcal": 1200,
              "protein_g": 90.5,
              "carbs_g": 110.25,
              "fat_g": 42.75,
              "source": "daily_snapshot"
            },
            "remaining_food_kcal": 731,
            "food_excess_kcal": 17,
            "exercise_kcal": 419,
            "daily_balance_kcal": -83,
            "daily_balance_status": "provisional",
            "protein_status": {
              "consumed_g": 90.5,
              "target_g": null,
              "remaining_g": null,
              "percentage": null,
              "status": "unavailable"
            },
            "meals": [
              {
                "id": "meal-z",
                "meal_type": "jantar",
                "food_name": "Item sintético Z",
                "quantity_g": 125.5,
                "kcal": 407,
                "protein_g": 31.25,
                "carbs_g": 48.5,
                "fat_g": 9.75,
                "consumed_at": "2026-07-20T20:15:00.000Z",
                "nutrition_source": "future_catalog_v99"
              },
              {
                "id": "meal-a",
                "meal_type": "cafe",
                "food_name": "Item sintético A",
                "quantity_g": 80,
                "kcal": 211,
                "protein_g": 12,
                "carbs_g": 16,
                "fat_g": 11,
                "consumed_at": "2026-07-20T09:00:00.000Z",
                "nutrition_source": "canonical_exact"
              }
            ],
            "workouts": [
              {
                "id": "workout-z",
                "workout_type": "musculacao",
                "duration_min": 40,
                "estimated_kcal": 301,
                "intensity": "moderada",
                "performed_at": "2026-07-20T18:30:00.000Z"
              },
              {
                "id": "workout-a",
                "workout_type": "caminhada",
                "duration_min": 25,
                "estimated_kcal": 118,
                "intensity": "leve",
                "performed_at": "2026-07-20T07:30:00.000Z"
              }
            ],
            "hydration": {
              "consumed_ml": 1250,
              "target_ml": null,
              "remaining_ml": null,
              "percentage": null,
              "status": "tracked_without_target"
            },
            "supplements": {
              "availability": "available",
              "items": [
                {
                  "id": "supplement-1",
                  "name": "Item informado",
                  "dose_text": null,
                  "origin": null,
                  "reminders_enabled": true,
                  "schedules": [
                    {
                      "id": "rule-20",
                      "local_time": "20:00",
                      "weekdays": [1, 3, 5]
                    },
                    {
                      "id": "rule-08",
                      "local_time": "08:00",
                      "weekdays": [1, 3, 5]
                    }
                  ],
                  "occurrences": [
                    {
                      "reminder_rule_id": "rule-20",
                      "scheduled_for": "2026-07-20T23:00:00.000Z",
                      "status": "snoozed",
                      "last_action_at": "2026-07-20T23:01:00.000Z",
                      "snoozed_until": "2026-07-20T23:31:00.000Z"
                    },
                    {
                      "reminder_rule_id": "rule-08",
                      "scheduled_for": "2026-07-20T11:00:00.000Z",
                      "status": "pending",
                      "last_action_at": null,
                      "snoozed_until": null
                    }
                  ]
                }
              ]
            },
            "medications": {
              "availability": "not_configured",
              "items": []
            },
            "pending_actions": {
              "registrations": [
                {
                  "id": "pending-z",
                  "kind": "meal",
                  "meal_type": "jantar",
                  "created_at": "2026-07-20T14:02:00.000Z",
                  "expires_at": "2026-07-20T16:00:00.000Z"
                },
                {
                  "id": "pending-a",
                  "kind": "workout",
                  "meal_type": null,
                  "created_at": "2026-07-20T14:01:00.000Z",
                  "expires_at": "2026-07-20T16:01:00.000Z"
                }
              ],
              "meal_gaps": {
                "expected": ["cafe", "almoco", "jantar"],
                "registered": ["cafe", "almoco"],
                "skipped": [],
                "open": ["jantar"],
                "reliable": true,
                "source": "personalized_pattern",
                "active_days": 10
              }
            },
            "block_7700": {
              "enabled": true,
              "availability": "available",
              "target_kcal": 7700,
              "current_kcal": 2500,
              "percentage": 32,
              "completed_blocks": 1,
              "total_credited_kcal": 10200,
              "source": "user_progress"
            },
            "completion_status": {
              "status": "pending_information",
              "day_closed": false,
              "has_sufficient_data": null
            },
            "sources": {
              "targets": "daily_snapshot",
              "consumed": "daily_snapshot",
              "exercise": "daily_snapshot",
              "meals": "meal_logs",
              "workouts": "workout_logs",
              "hydration": "daily_snapshot",
              "hydration_target": "unavailable",
              "supplements": "routine_items_and_adherence_logs",
              "medications": "routine_items_and_adherence_logs",
              "pending_actions": "pending_registrations_and_meal_pattern",
              "block_7700": "user_progress"
            },
            "calculation_version": "bodyflow.daily-state.v2",
            "updated_at": null,
            "generated_at": "2026-07-20T15:00:00.000Z",
            "future_additive_key": {
              "ignored": true
            }
          },
          "meta": {
            "api_version": "v1",
            "request_id": "request-today-contract-0001"
          }
        }
        """.utf8
    )

    static func onboardingDraft(
        currentStep: OnboardingStep
    ) -> OnboardingDraft {
        OnboardingDraft(
            displayName: "Fixture User",
            localeIdentifier: "pt-BR",
            countryCode: "US",
            timeZoneIdentifier: "America/New_York",
            biologicalSex: .feminine,
            birthDate: Date(timeIntervalSince1970: 946_684_800),
            heightCM: 170,
            weightKG: 65,
            bodyFatPercent: 25,
            objective: .bodyRecomposition,
            activityLevel: .moderate,
            trainingFrequency: 3,
            waterIntake: .moderate,
            hungerLevel: .moderate,
            wakeTime: LocalTime(hour: 7, minute: 0),
            bedtime: LocalTime(hour: 23, minute: 0),
            foodOrganization: .yes,
            persona: .focus,
            consent: DevelopmentConsentAcceptance(
                documentIDs: [.terms, .privacy],
                acceptedAt: Date(timeIntervalSince1970: 946_684_800)
            ),
            currentStep: currentStep
        )
    }
}
