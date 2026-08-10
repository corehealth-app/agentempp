import Foundation
import Testing

@testable import BodyFlow

@Suite("Registration Contract")
struct RegistrationContractTests {
    @Test("meal request encodes only documented patient-editable fields")
    func mealRequestEncodesOnlyEditableFields() throws {
        let request = RegistrationProposalRequest.meal(
            MealProposalRequest(
                mealType: .dinner,
                items: [
                    MealProposalItemRequest(
                        foodName: "arroz branco cozido",
                        quantityG: 120,
                        userKcal: 155
                    )
                ],
                consumedAt: try timestamp("2026-07-21T00:15:00Z")
            )
        )

        let object = try encodedObject(request)
        let expected: NSDictionary = [
            "kind": "meal",
            "meal_type": "jantar",
            "items": [
                [
                    "food_name": "arroz branco cozido",
                    "quantity_g": 120,
                    "user_kcal": 155,
                ]
            ],
            "consumed_at": "2026-07-21T00:15:00Z",
        ]

        #expect(object == expected)

        let encodedText = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        for forbiddenKey in [
            "protein_g", "carbs_g", "fat_g", "totals", "total_kcal",
            "estimated_kcal", "nutrition_source", "provider_source",
            "source_provider_message_id", "confirmed_reference", "reference_id",
        ] {
            #expect(!encodedText.contains("\"\(forbiddenKey)\""))
        }
    }

    @Test("meal request omits optional patient kcal and supported time")
    func mealRequestOmitsAbsentOptionalFields() throws {
        let request = RegistrationProposalRequest.meal(
            MealProposalRequest(
                mealType: .lunch,
                items: [
                    MealProposalItemRequest(
                        foodName: "feijao carioca",
                        quantityG: 90,
                        userKcal: nil
                    )
                ],
                consumedAt: nil
            )
        )

        let object = try encodedObject(request)
        let expected: NSDictionary = [
            "kind": "meal",
            "meal_type": "almoco",
            "items": [
                [
                    "food_name": "feijao carioca",
                    "quantity_g": 90,
                ]
            ],
        ]

        #expect(object == expected)
    }

    @Test("workout request encodes its discriminator without client calories")
    func workoutRequestEncodesDocumentedFields() throws {
        let request = RegistrationProposalRequest.workout(
            WorkoutProposalRequest(
                workoutType: "musculacao",
                durationMin: 40,
                intensity: .moderate,
                performedAt: try timestamp("2026-07-20T22:30:00Z")
            )
        )

        let object = try encodedObject(request)
        let expected: NSDictionary = [
            "kind": "workout",
            "workout_type": "musculacao",
            "duration_min": 40,
            "intensity": "moderada",
            "performed_at": "2026-07-20T22:30:00Z",
        ]

        #expect(object == expected)
        #expect(object["estimated_kcal"] == nil)
        #expect(object["kcal"] == nil)
    }

    @Test("workout request accepts and preserves an omitted defaultable intensity")
    func workoutRequestOmitsDefaultableIntensity() throws {
        let request = try decode(
            RegistrationProposalRequest.self,
            from: """
            {
              "kind": "workout",
              "workout_type": "caminhada",
              "duration_min": 35
            }
            """
        )

        guard case let .workout(workout) = request else {
            Issue.record("Expected a workout request")
            return
        }
        #expect(workout.intensity == nil)

        let object = try encodedObject(request)
        let expected: NSDictionary = [
            "kind": "workout",
            "workout_type": "caminhada",
            "duration_min": 35,
        ]
        #expect(object == expected)
    }

    @Test("meal detection inputs carry text or labelled samples without media bytes")
    func mealDetectionInputsAreByteFree() {
        let inputs: [MealDetectionInput] = [
            .text("jantar com arroz e frango"),
            .photoSample(label: "foto do prato do jantar"),
            .audioSample(label: "audio descrevendo o cafe"),
        ]

        let labels = inputs.map { input in
            switch input {
            case let .text(text):
                return "text:\(text)"
            case let .photoSample(label):
                return "photo:\(label)"
            case let .audioSample(label):
                return "audio:\(label)"
            }
        }

        #expect(
            labels == [
                "text:jantar com arroz e frango",
                "photo:foto do prato do jantar",
                "audio:audio descrevendo o cafe",
            ]
        )
    }

    @Test("complete pending meal decodes warnings expiry and additive fields")
    func decodesPendingMealResponse() throws {
        let response = try decode(
            RegistrationProposalResponse.self,
            from: """
            {
              "data": {
                "id": "registration-meal-1",
                "status": "pending",
                "created_at": "2026-07-20T12:00:00.000Z",
                "expires_at": "2026-07-21T12:00:00.000Z",
                "resolved_at": null,
                "future_pending_field": "additive",
                "proposal": {
                  "kind": "meal",
                  "meal_type": "jantar",
                  "items": [{
                    "name": "arroz branco cozido",
                    "quantity_g": 120,
                    "kcal": 154,
                    "protein_g": 3.0,
                    "carbs_g": 33.6,
                    "fat_g": 0.2,
                    "future_item_field": true
                  }],
                  "totals": {
                    "kcal": 154,
                    "protein_g": 3.0,
                    "carbs_g": 33.6,
                    "fat_g": 0.2
                  },
                  "warnings": ["Confirme o preparo antes de registrar."],
                  "future_proposal_field": {"version": 2}
                }
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-meal-1"
              },
              "future_envelope_field": true
            }
            """
        )

        let expected = try mealRegistrationSnapshot(
            status: "pending",
            resolvedAt: nil,
            warnings: ["Confirme o preparo antes de registrar."]
        )

        #expect(response.meta.apiVersion == "v1")
        #expect(response.meta.requestID == "request-registration-meal-1")
        #expect(response.data == expected)
    }

    @Test("complete pending workout remains semantically distinct from a meal")
    func decodesPendingWorkoutResponse() throws {
        let response = try decode(
            RegistrationProposalResponse.self,
            from: """
            {
              "data": {
                "id": "registration-workout-1",
                "status": "pending",
                "created_at": "2026-07-20T18:31:00.000Z",
                "expires_at": "2026-07-21T18:31:00.000Z",
                "resolved_at": null,
                "proposal": {
                  "kind": "workout",
                  "workout_type": "musculacao",
                  "duration_min": 40,
                  "estimated_kcal": 280,
                  "intensity": "moderada"
                }
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-workout-1"
              }
            }
            """
        )

        let expected = try workoutRegistrationSnapshot(
            status: "pending",
            resolvedAt: nil,
            workoutType: "musculacao",
            durationMin: 40,
            estimatedKcal: 280,
            intensity: "moderada"
        )

        #expect(response.data == expected)
    }

    @Test("sanitized workout nullable fields remain absent")
    func decodesNullableWorkoutSnapshot() throws {
        let response = try decode(
            RegistrationProposalResponse.self,
            from: """
            {
              "data": {
                "id": "registration-workout-1",
                "status": "pending",
                "created_at": "2026-07-20T18:31:00.000Z",
                "expires_at": "2026-07-21T18:31:00.000Z",
                "resolved_at": null,
                "proposal": {
                  "kind": "workout",
                  "workout_type": null,
                  "duration_min": null,
                  "estimated_kcal": null,
                  "intensity": null
                }
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-workout-nullable-1"
              }
            }
            """
        )

        guard case let .workout(proposal) = response.data.proposal else {
            Issue.record("Expected a workout proposal")
            return
        }
        #expect(proposal.workoutType == nil)
        #expect(proposal.durationMin == nil)
        #expect(proposal.estimatedKcal == nil)
        #expect(proposal.intensity == nil)
    }

    @Test("sanitized workout preserves finite non-integral numbers")
    func decodesFiniteNonIntegralWorkoutNumbers() throws {
        let response = try decode(
            RegistrationProposalResponse.self,
            from: """
            {
              "data": {
                "id": "registration-workout-1",
                "status": "pending",
                "created_at": "2026-07-20T18:31:00.000Z",
                "expires_at": "2026-07-21T18:31:00.000Z",
                "resolved_at": null,
                "proposal": {
                  "kind": "workout",
                  "workout_type": "corrida",
                  "duration_min": 40.5,
                  "estimated_kcal": 280.25,
                  "intensity": "alta"
                }
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-workout-decimal-1"
              }
            }
            """
        )

        guard case let .workout(proposal) = response.data.proposal else {
            Issue.record("Expected a workout proposal")
            return
        }
        #expect(proposal.durationMin == 40.5)
        #expect(proposal.estimatedKcal == 280.25)
    }

    @Test("sanitized unknown proposal remains a decodable response case")
    func decodesUnknownProposalSnapshot() throws {
        let response = try decode(
            RegistrationProposalResponse.self,
            from: """
            {
              "data": {
                "id": "registration-legacy-1",
                "status": "pending",
                "created_at": "2026-07-20T18:31:00.000Z",
                "expires_at": "2026-07-21T18:31:00.000Z",
                "resolved_at": null,
                "proposal": {"kind": "unknown"}
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-unknown-1"
              }
            }
            """
        )

        #expect(response.data.proposal == .unknown)
    }

    @Test("confirmation decodes the returned complete proposal and flags")
    func decodesConfirmationResponse() throws {
        let response = try decode(
            RegistrationConfirmationResponse.self,
            from: """
            {
              "data": {
                "id": "registration-workout-1",
                "status": "confirmed",
                "created_at": "2026-07-20T18:31:00.000Z",
                "expires_at": "2026-07-21T18:31:00.000Z",
                "resolved_at": "2026-07-20T18:32:00.000Z",
                "proposal": {
                  "kind": "workout",
                  "workout_type": "musculacao",
                  "duration_min": 40,
                  "estimated_kcal": 280,
                  "intensity": "moderada"
                },
                "already_confirmed": false,
                "deduped": false,
                "future_confirmation_field": 3
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-confirm-1"
              }
            }
            """
        )

        let expected = try workoutRegistrationSnapshot(
            status: "confirmed",
            resolvedAt: "2026-07-20T18:32:00Z",
            workoutType: "musculacao",
            durationMin: 40,
            estimatedKcal: 280,
            intensity: "moderada"
        )

        #expect(response.data.registration == expected)
        #expect(!response.data.alreadyConfirmed)
        #expect(response.data.deduped == false)
    }

    @Test("confirmation replay permits the documented absent dedupe flag")
    func decodesConfirmationReplay() throws {
        let response = try decode(
            RegistrationConfirmationResponse.self,
            from: """
            {
              "data": {
                "id": "registration-meal-1",
                "status": "confirmed",
                "created_at": "2026-07-20T12:00:00.000Z",
                "expires_at": "2026-07-21T12:00:00.000Z",
                "resolved_at": "2026-07-20T12:01:00.000Z",
                "proposal": {
                  "kind": "meal",
                  "meal_type": "jantar",
                  "items": [{
                    "name": "arroz branco cozido",
                    "quantity_g": 120,
                    "kcal": 154,
                    "protein_g": 3,
                    "carbs_g": 33.6,
                    "fat_g": 0.2
                  }],
                  "totals": null,
                  "warnings": []
                },
                "already_confirmed": true
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-confirm-replay-1"
              }
            }
            """
        )

        #expect(response.data.alreadyConfirmed)
        #expect(response.data.deduped == nil)
    }

    @Test("cancellation decodes the complete cancelled proposal snapshot")
    func decodesCancellationResponse() throws {
        let response = try decode(
            RegistrationCancellationResponse.self,
            from: """
            {
              "data": {
                "id": "registration-meal-1",
                "status": "cancelled",
                "created_at": "2026-07-20T12:00:00.000Z",
                "expires_at": "2026-07-21T12:00:00.000Z",
                "resolved_at": "2026-07-20T12:05:00.000Z",
                "proposal": {
                  "kind": "meal",
                  "meal_type": "jantar",
                  "items": [{
                    "name": "arroz branco cozido",
                    "quantity_g": 120,
                    "kcal": 154,
                    "protein_g": 3,
                    "carbs_g": 33.6,
                    "fat_g": 0.2
                  }],
                  "totals": {
                    "kcal": 154,
                    "protein_g": 3,
                    "carbs_g": 33.6,
                    "fat_g": 0.2
                  },
                  "warnings": []
                }
              },
              "meta": {
                "api_version": "v1",
                "request_id": "request-registration-cancel-1"
              }
            }
            """
        )

        let expected = try mealRegistrationSnapshot(
            status: "cancelled",
            resolvedAt: "2026-07-20T12:05:00Z",
            warnings: []
        )

        #expect(response.data == expected)
    }

    @Test("detection and registration capabilities exchange structured nominal values")
    func capabilitiesExposeStructuredCommands() async throws {
        let proposal = RegistrationProposalRequest.meal(
            MealProposalRequest(
                mealType: .dinner,
                items: [
                    MealProposalItemRequest(
                        foodName: "arroz branco cozido",
                        quantityG: 120,
                        userKcal: nil
                    )
                ],
                consumedAt: nil
            )
        )
        let detector: any MealDetectionProviding = MealDetectorStub(output: proposal)
        let provider: any RegistrationProviding = RegistrationProviderStub(
            proposalResponse: try decode(
                RegistrationProposalResponse.self,
                from: pendingMealResponseFixture
            ),
            confirmationResponse: try decode(
                RegistrationConfirmationResponse.self,
                from: confirmedMealResponseFixture
            ),
            cancellationResponse: try decode(
                RegistrationCancellationResponse.self,
                from: cancelledMealResponseFixture
            )
        )

        let detected = try await detector.detect(
            .photoSample(label: "amostra rotulada sem bytes")
        )
        #expect(detected == proposal)

        let editCommand = RegistrationEditCommand(
            registrationID: "registration-meal-1",
            proposal: detected
        )
        let idCommand = RegistrationIDCommand(registrationID: "registration-meal-1")
        let createdAt = Date(timeIntervalSince1970: 1_784_548_800)

        #expect(try await provider.propose(MutationAttempt(
            operation: .proposalCreate,
            key: try IdempotencyKey(validating: "contract-propose-0001"),
            payload: detected,
            createdAt: createdAt
        )).data.status == "pending")
        #expect(try await provider.edit(MutationAttempt(
            operation: .proposalEdit,
            key: try IdempotencyKey(validating: "contract-edit-0001"),
            payload: editCommand,
            createdAt: createdAt
        )).data.proposal == proposalSnapshot)
        #expect(try await provider.confirm(MutationAttempt(
            operation: .proposalConfirm,
            key: try IdempotencyKey(validating: "contract-confirm-0001"),
            payload: idCommand,
            createdAt: createdAt
        )).data.alreadyConfirmed == false)
        #expect(try await provider.cancel(MutationAttempt(
            operation: .proposalCancel,
            key: try IdempotencyKey(validating: "contract-cancel-0001"),
            payload: idCommand,
            createdAt: createdAt
        )).data.status == "cancelled")
    }

    @Test("registration capability forwards each complete immutable attempt")
    func registrationCapabilityForwardsCompleteAttempts() async throws {
        let spy = RegistrationAttemptSpy()
        let provider: any RegistrationProviding = spy
        let createdAt = Date(timeIntervalSince1970: 1_784_548_800)
        let proposal = RegistrationProposalRequest.meal(
            MealProposalRequest(
                mealType: .lunch,
                items: [
                    MealProposalItemRequest(
                        foodName: "fixture",
                        quantityG: 111,
                        userKcal: nil
                    )
                ],
                consumedAt: nil
            )
        )
        let idCommand = RegistrationIDCommand(registrationID: "registration-meal-1")
        let proposeAttempt = MutationAttempt(
            operation: .proposalCreate,
            key: try IdempotencyKey(validating: "forward-propose-0001"),
            payload: proposal,
            createdAt: createdAt
        )
        let editAttempt = MutationAttempt(
            operation: .proposalEdit,
            key: try IdempotencyKey(validating: "forward-edit-0001"),
            payload: RegistrationEditCommand(
                registrationID: idCommand.registrationID,
                proposal: proposal
            ),
            createdAt: createdAt
        )
        let confirmAttempt = MutationAttempt(
            operation: .proposalConfirm,
            key: try IdempotencyKey(validating: "forward-confirm-0001"),
            payload: idCommand,
            createdAt: createdAt
        )
        let cancelAttempt = MutationAttempt(
            operation: .proposalCancel,
            key: try IdempotencyKey(validating: "forward-cancel-0001"),
            payload: idCommand,
            createdAt: createdAt
        )

        await #expect(throws: RegistrationProbeError.recorded) {
            try await provider.propose(proposeAttempt)
        }
        await #expect(throws: RegistrationProbeError.recorded) {
            try await provider.edit(editAttempt)
        }
        await #expect(throws: RegistrationProbeError.recorded) {
            try await provider.confirm(confirmAttempt)
        }
        await #expect(throws: RegistrationProbeError.recorded) {
            try await provider.cancel(cancelAttempt)
        }

        #expect(await spy.proposeAttempts == [proposeAttempt])
        #expect(await spy.editAttempts == [editAttempt])
        #expect(await spy.confirmAttempts == [confirmAttempt])
        #expect(await spy.cancelAttempts == [cancelAttempt])
    }
}

private struct MealDetectorStub: MealDetectionProviding {
    let output: RegistrationProposalRequest

    func detect(_ input: MealDetectionInput) async throws -> RegistrationProposalRequest {
        output
    }
}

private struct RegistrationProviderStub: RegistrationProviding {
    let proposalResponse: RegistrationProposalResponse
    let confirmationResponse: RegistrationConfirmationResponse
    let cancellationResponse: RegistrationCancellationResponse

    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws
        -> RegistrationProposalResponse
    {
        proposalResponse
    }

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws
        -> RegistrationProposalResponse
    {
        proposalResponse
    }

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws
        -> RegistrationConfirmationResponse
    {
        confirmationResponse
    }

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws
        -> RegistrationCancellationResponse
    {
        cancellationResponse
    }
}

private enum RegistrationProbeError: Error {
    case recorded
}

private actor RegistrationAttemptSpy: RegistrationProviding {
    private(set) var proposeAttempts: [MutationAttempt<RegistrationProposalRequest>] = []
    private(set) var editAttempts: [MutationAttempt<RegistrationEditCommand>] = []
    private(set) var confirmAttempts: [MutationAttempt<RegistrationIDCommand>] = []
    private(set) var cancelAttempts: [MutationAttempt<RegistrationIDCommand>] = []

    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws -> RegistrationProposalResponse {
        proposeAttempts.append(attempt)
        throw RegistrationProbeError.recorded
    }

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws -> RegistrationProposalResponse {
        editAttempts.append(attempt)
        throw RegistrationProbeError.recorded
    }

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationConfirmationResponse {
        confirmAttempts.append(attempt)
        throw RegistrationProbeError.recorded
    }

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationCancellationResponse {
        cancelAttempts.append(attempt)
        throw RegistrationProbeError.recorded
    }
}

private func mealRegistrationSnapshot(
    status: String,
    resolvedAt: String?,
    warnings: [String]
) throws -> RegistrationSnapshot {
    RegistrationSnapshot(
        id: "registration-meal-1",
        status: status,
        createdAt: try timestamp("2026-07-20T12:00:00Z"),
        expiresAt: try timestamp("2026-07-21T12:00:00Z"),
        resolvedAt: try resolvedAt.map(timestamp),
        proposal: .meal(
            MealProposalSnapshot(
                mealType: "jantar",
                items: [
                    MealProposalItemSnapshot(
                        name: "arroz branco cozido",
                        quantityG: 120,
                        kcal: 154,
                        proteinG: 3,
                        carbsG: 33.6,
                        fatG: 0.2
                    )
                ],
                totals: MealProposalTotalsSnapshot(
                    kcal: 154,
                    proteinG: 3,
                    carbsG: 33.6,
                    fatG: 0.2
                ),
                warnings: warnings
            )
        )
    )
}

private func workoutRegistrationSnapshot(
    status: String,
    resolvedAt: String?,
    workoutType: String?,
    durationMin: Decimal?,
    estimatedKcal: Decimal?,
    intensity: String?
) throws -> RegistrationSnapshot {
    RegistrationSnapshot(
        id: "registration-workout-1",
        status: status,
        createdAt: try timestamp("2026-07-20T18:31:00Z"),
        expiresAt: try timestamp("2026-07-21T18:31:00Z"),
        resolvedAt: try resolvedAt.map(timestamp),
        proposal: .workout(
            WorkoutProposalSnapshot(
                workoutType: workoutType,
                durationMin: durationMin,
                estimatedKcal: estimatedKcal,
                intensity: intensity
            )
        )
    )
}

private var proposalSnapshot: RegistrationProposalSnapshot {
    .meal(
        MealProposalSnapshot(
            mealType: "jantar",
            items: [
                MealProposalItemSnapshot(
                    name: "arroz branco cozido",
                    quantityG: 120,
                    kcal: 154,
                    proteinG: 3,
                    carbsG: 33.6,
                    fatG: 0.2
                )
            ],
            totals: MealProposalTotalsSnapshot(
                kcal: 154,
                proteinG: 3,
                carbsG: 33.6,
                fatG: 0.2
            ),
            warnings: []
        )
    )
}

private func encodedObject<Value: Encodable>(_ value: Value) throws -> NSDictionary {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

private func timestamp(_ value: String) throws -> APITimestamp {
    try JSONDecoder().decode(APITimestamp.self, from: Data("\"\(value)\"".utf8))
}

private let pendingMealResponseFixture = """
{
  "data": {
    "id": "registration-meal-1",
    "status": "pending",
    "created_at": "2026-07-20T12:00:00.000Z",
    "expires_at": "2026-07-21T12:00:00.000Z",
    "resolved_at": null,
    "proposal": {
      "kind": "meal",
      "meal_type": "jantar",
      "items": [{
        "name": "arroz branco cozido",
        "quantity_g": 120,
        "kcal": 154,
        "protein_g": 3,
        "carbs_g": 33.6,
        "fat_g": 0.2
      }],
      "totals": {
        "kcal": 154,
        "protein_g": 3,
        "carbs_g": 33.6,
        "fat_g": 0.2
      },
      "warnings": []
    }
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-registration-propose-1"
  }
}
"""

private let confirmedMealResponseFixture = """
{
  "data": {
    "id": "registration-meal-1",
    "status": "confirmed",
    "created_at": "2026-07-20T12:00:00.000Z",
    "expires_at": "2026-07-21T12:00:00.000Z",
    "resolved_at": "2026-07-20T12:01:00.000Z",
    "proposal": {
      "kind": "meal",
      "meal_type": "jantar",
      "items": [{
        "name": "arroz branco cozido",
        "quantity_g": 120,
        "kcal": 154,
        "protein_g": 3,
        "carbs_g": 33.6,
        "fat_g": 0.2
      }],
      "totals": {
        "kcal": 154,
        "protein_g": 3,
        "carbs_g": 33.6,
        "fat_g": 0.2
      },
      "warnings": []
    },
    "already_confirmed": false,
    "deduped": false
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-registration-confirm-1"
  }
}
"""

private let cancelledMealResponseFixture = """
{
  "data": {
    "id": "registration-meal-1",
    "status": "cancelled",
    "created_at": "2026-07-20T12:00:00.000Z",
    "expires_at": "2026-07-21T12:00:00.000Z",
    "resolved_at": "2026-07-20T12:05:00.000Z",
    "proposal": {
      "kind": "meal",
      "meal_type": "jantar",
      "items": [{
        "name": "arroz branco cozido",
        "quantity_g": 120,
        "kcal": 154,
        "protein_g": 3,
        "carbs_g": 33.6,
        "fat_g": 0.2
      }],
      "totals": {
        "kcal": 154,
        "protein_g": 3,
        "carbs_g": 33.6,
        "fat_g": 0.2
      },
      "warnings": []
    }
  },
  "meta": {
    "api_version": "v1",
    "request_id": "request-registration-cancel-1"
  }
}
"""
