import Foundation
import Testing

@testable import BodyFlow

@Suite("Plan and Progress Contracts")
struct PlanProgressContractTests {
    @Test("plan decodes only stable metadata and preserves nullable values")
    func decodesStablePlanMetadata() throws {
        let response = try decodePlan()
        let training = try #require(response.data.training)

        #expect(response.meta.apiVersion == "v1")
        #expect(response.meta.requestID == "request-plan-contract-0001")
        #expect(training.id == "training-plan-1")
        #expect(training.planType == "split")
        #expect(training.daysPerWeek == 4)
        #expect(training.equipmentSummary == "halteres e banco")
        #expect(training.generatedAt == timestamp("2026-07-20T12:34:56.789Z"))
        #expect(training.validUntil == nil)
        #expect(training.version == 7)
        #expect(training.notes == nil)

        #expect(response.data.nutrition.count == 2)
        #expect(response.data.nutrition[1].payload == nil)
        #expect(response.data.nutrition[1].validUntil == nil)
        #expect(response.data.nutrition[1].notes == nil)

        assertContract(response)
    }

    @Test("plan tolerates additive fields without exposing unstable training JSON")
    func ignoresAdditiveAndUnstablePlanFields() throws {
        let response = try decodePlan()
        let encoded = try JSONEncoder().encode(response.data)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let training = try #require(object["training"] as? [String: Any])

        #expect(Set(object.keys) == ["training", "nutrition"])
        #expect(
            Set(training.keys) == [
                "id",
                "plan_type",
                "days_per_week",
                "equipment_summary",
                "generated_at",
                "version",
            ]
        )
        #expect(training["weekly_schedule"] == nil)
        #expect(training["planned_sessions"] == nil)
        #expect(training["completed_sessions"] == nil)
    }

    @Test("nutrition prescription payload remains exact opaque JSON")
    func roundTripsOpaqueNutritionPayload() throws {
        let response = try decodePlan()
        let payload = try #require(response.data.nutrition[0].payload)
        let expected: JSONValue = .object([
            "boolean": .boolean(true),
            "decimal": .number(Decimal(string: "123.456789")!),
            "misleading_business_fields": .object([
                "planned_sessions": .number(99),
                "projected_weight": .number(61.25),
            ]),
            "nested": .array([
                .string("preserve-me"),
                .null,
                .object(["future_key": .string("future-value")]),
            ]),
        ])

        #expect(payload == expected)

        let encoded = try JSONEncoder().encode(payload)
        let roundTripped = try JSONDecoder().decode(JSONValue.self, from: encoded)
        #expect(roundTripped == expected)
    }

    @Test("plan preserves an absent active training plan")
    func preservesAbsentTrainingPlan() throws {
        let response = try JSONDecoder().decode(
            PlanResponse.self,
            from: Data(
                """
                {
                  "data": {"training": null, "nutrition": [], "future": true},
                  "meta": {"api_version": "v1", "request_id": "request-empty-plan"}
                }
                """.utf8
            )
        )

        #expect(response.data.training == nil)
        #expect(response.data.nutrition.isEmpty)
    }

    @Test("progress preserves every server value without normalization")
    func preservesProgressValues() throws {
        let response = try decodeProgress()
        let progress = try #require(response.data)

        #expect(response.meta.requestID == "request-progress-contract-0001")
        #expect(progress.xpTotal == 12_345)
        #expect(progress.level == 13)
        #expect(progress.currentStreak == 4)
        #expect(progress.longestStreak == 29)
        #expect(progress.blocksCompleted == 7)
        #expect(progress.deficitBlock == 611)
        #expect(progress.currentWeight == Decimal(string: "83.75"))
        #expect(progress.currentBodyFatPercent == Decimal(string: "18.25"))
        #expect(progress.badgesEarned == ["badge-z", "badge-a"])
        #expect(progress.lastActiveDate == "2026-07-28")
        #expect(progress.nextReevaluation == "2026-08-19")
        #expect(progress.updatedAt == timestamp("2026-07-29T22:15:16.123Z"))

        assertContract(response)
    }

    @Test("progress preserves nullable measurements and dates")
    func preservesNullableProgressValues() throws {
        let response = try JSONDecoder().decode(
            ProgressResponse.self,
            from: Data(
                """
                {
                  "data": {
                    "xp_total": 9,
                    "level": 2,
                    "current_streak": 0,
                    "longest_streak": 5,
                    "blocks_completed": 0,
                    "deficit_block": 0,
                    "current_weight": null,
                    "current_bf_percent": null,
                    "badges_earned": [],
                    "last_active_date": null,
                    "next_reevaluation": null,
                    "updated_at": "2026-07-29T22:15:16Z",
                    "future_progress_field": {"ignored": true}
                  },
                  "meta": {"api_version": "v1", "request_id": "request-null-progress"}
                }
                """.utf8
            )
        )

        let progress = try #require(response.data)
        #expect(progress.xpTotal == 9)
        #expect(progress.level == 2)
        #expect(progress.currentStreak == 0)
        #expect(progress.blocksCompleted == 0)
        #expect(progress.deficitBlock == 0)
        #expect(progress.currentWeight == nil)
        #expect(progress.currentBodyFatPercent == nil)
        #expect(progress.lastActiveDate == nil)
        #expect(progress.nextReevaluation == nil)
    }

    @Test("only a null progress payload is empty")
    func decodesEmptyProgress() throws {
        let response = try JSONDecoder().decode(
            ProgressResponse.self,
            from: Data(
                """
                {
                  "data": null,
                  "meta": {"api_version": "v1", "request_id": "request-empty-progress"}
                }
                """.utf8
            )
        )

        #expect(response.data == nil)
    }

    @Test("minimum persisted progress is non-null official data")
    func decodesMinimumProgress() throws {
        let response = try JSONDecoder().decode(
            ProgressResponse.self,
            from: Data(
                """
                {
                  "data": {
                    "xp_total": 0,
                    "level": 1,
                    "current_streak": 0,
                    "longest_streak": 0,
                    "blocks_completed": 0,
                    "deficit_block": 0,
                    "current_weight": null,
                    "current_bf_percent": null,
                    "badges_earned": [],
                    "last_active_date": null,
                    "next_reevaluation": null,
                    "updated_at": "2026-07-29T22:15:16Z"
                  },
                  "meta": {"api_version": "v1", "request_id": "request-minimum-progress"}
                }
                """.utf8
            )
        )
        let snapshot = try #require(response.data)

        #expect(snapshot.xpTotal == 0)
        #expect(snapshot.level == 1)
        #expect(snapshot.currentStreak == 0)
        #expect(snapshot.longestStreak == 0)
        #expect(snapshot.blocksCompleted == 0)
        #expect(snapshot.deficitBlock == 0)
        #expect(snapshot.currentWeight == nil)
        #expect(snapshot.currentBodyFatPercent == nil)
        #expect(snapshot.badgesEarned.isEmpty)
        #expect(snapshot.lastActiveDate == nil)
        #expect(snapshot.nextReevaluation == nil)
    }

    @Test("progress values stay independent from a divergent Today block")
    func keepsProgressSeparateFromTodayBlock() throws {
        let progress = try #require(decodeProgress().data)
        let todayBlock = TodayBlock7700(
            enabled: true,
            availability: "available",
            targetKcal: 7_701,
            currentKcal: 2_503,
            percentage: 31,
            completedBlocks: 41,
            totalCreditedKcal: 318_210,
            source: "today-user-progress-snapshot"
        )

        #expect(progress.deficitBlock == 611)
        #expect(progress.blocksCompleted == 7)
        #expect(progress.deficitBlock != todayBlock.currentKcal)
        #expect(progress.blocksCompleted != todayBlock.completedBlocks)

        let labels = Set(Mirror(reflecting: progress).children.compactMap(\.label))
        #expect(
            labels == [
                "xpTotal",
                "level",
                "currentStreak",
                "longestStreak",
                "blocksCompleted",
                "deficitBlock",
                "currentWeight",
                "currentBodyFatPercent",
                "badgesEarned",
                "lastActiveDate",
                "nextReevaluation",
                "updatedAt",
            ]
        )
        #expect(!labels.contains("percentage"))
        #expect(!labels.contains("projectedWeight"))
        #expect(!labels.contains("plannedSessions"))
        #expect(!labels.contains("completedSessions"))
    }

    @Test("providers return the shared response envelopes")
    func providersReturnSharedResponses() async throws {
        let expectedPlan = try decodePlan()
        let expectedProgress = try decodeProgress()
        let planProvider: any PlanProviding = PlanProviderStub(response: expectedPlan)
        let progressProvider: any ProgressProviding = ProgressProviderStub(response: expectedProgress)

        #expect(try await planProvider.plan() == expectedPlan)
        #expect(try await progressProvider.progress() == expectedProgress)
    }

    private func decodePlan() throws -> PlanResponse {
        try JSONDecoder().decode(PlanResponse.self, from: Data(Self.planJSON.utf8))
    }

    private func decodeProgress() throws -> ProgressResponse {
        try JSONDecoder().decode(ProgressResponse.self, from: Data(Self.progressJSON.utf8))
    }

    private func timestamp(_ value: String) -> APITimestamp {
        try! JSONDecoder().decode(APITimestamp.self, from: Data("\"\(value)\"".utf8))
    }

    private func assertContract<T: Codable & Equatable & Sendable>(_: T) {}

    private static let planJSON = """
        {
          "data": {
            "training": {
              "id": "training-plan-1",
              "plan_type": "split",
              "days_per_week": 4,
              "equipment_summary": "halteres e banco",
              "weekly_schedule": [
                {"day": "segunda", "planned_sessions": 99, "unknown": true}
              ],
              "generated_at": "2026-07-20T12:34:56.789Z",
              "valid_until": null,
              "version": 7,
              "notes": null,
              "future_training_field": "ignored"
            },
            "nutrition": [
              {
                "id": "prescription-1",
                "type": "diet",
                "payload": {
                  "boolean": true,
                  "decimal": 123.456789,
                  "misleading_business_fields": {
                    "planned_sessions": 99,
                    "projected_weight": 61.25
                  },
                  "nested": [
                    "preserve-me",
                    null,
                    {"future_key": "future-value"}
                  ]
                },
                "generated_at": "2026-07-20T13:00:00Z",
                "valid_until": "2026-08-20T13:00:00Z",
                "version": 3,
                "notes": "metadado literal",
                "future_prescription_field": 123
              },
              {
                "id": "prescription-2",
                "type": "shopping_list",
                "payload": null,
                "generated_at": "2026-07-21T13:00:00Z",
                "valid_until": null,
                "version": 1,
                "notes": null
              }
            ],
            "future_plan_field": [1, 2, 3]
          },
          "meta": {
            "api_version": "v1",
            "request_id": "request-plan-contract-0001",
            "future_meta_field": true
          },
          "future_envelope_field": "ignored"
        }
        """

    private static let progressJSON = """
        {
          "data": {
            "xp_total": 12345,
            "level": 13,
            "current_streak": 4,
            "longest_streak": 29,
            "blocks_completed": 7,
            "deficit_block": 611,
            "current_weight": 83.75,
            "current_bf_percent": 18.25,
            "badges_earned": ["badge-z", "badge-a"],
            "last_active_date": "2026-07-28",
            "next_reevaluation": "2026-08-19",
            "updated_at": "2026-07-29T22:15:16.123Z",
            "percentage": 88,
            "projected_weight": 77.7,
            "planned_sessions": 10,
            "completed_sessions": 8,
            "future_progress_field": {"ignored": true}
          },
          "meta": {
            "api_version": "v1",
            "request_id": "request-progress-contract-0001"
          }
        }
        """
}

private struct PlanProviderStub: PlanProviding {
    let response: PlanResponse

    func plan() async throws -> PlanResponse {
        response
    }
}

private struct ProgressProviderStub: ProgressProviding {
    let response: ProgressResponse

    func progress() async throws -> ProgressResponse {
        response
    }
}
