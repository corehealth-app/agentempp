#if DEBUG
import Foundation
import Testing

@testable import BodyFlow

@Suite("Demo Registration Repository")
struct DemoRegistrationRepositoryTests {
    @Test("materially different bounded text returns one authored text draft")
    func textDetectionUsesSourceFixtureWithoutParsingNutrition() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let shortInput = MealDetectionInput.text("x")
        let longText = String(repeating: "x", count: 1_000)
        let unrelatedLongInput = MealDetectionInput.text(longText)

        #expect(longText.count == 1_000)

        let first = try await repository.detect(shortInput)
        let second = try await repository.detect(unrelatedLongInput)

        #expect(first == expectedTextDetectionRequest)
        #expect(second == expectedTextDetectionRequest)
    }

    @Test("photo and audio labels select byte-free authored source drafts")
    func labelledSamplesSelectSourceFixturesOnly() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)

        let photo = try await repository.detect(
            .photoSample(label: "Amostra local A, sem URL")
        )
        let otherPhoto = try await repository.detect(
            .photoSample(label: "Rótulo completamente diferente")
        )
        let audio = try await repository.detect(
            .audioSample(label: "Amostra local de áudio, sem serviço")
        )
        let otherAudio = try await repository.detect(
            .audioSample(label: "Outro rótulo sem gravação")
        )

        #expect(photo == expectedPhotoDetectionRequest)
        #expect(otherPhoto == expectedPhotoDetectionRequest)
        #expect(audio == expectedAudioDetectionRequest)
        #expect(otherAudio == expectedAudioDetectionRequest)
    }

    @Test("detection creates no pending record and mutates no official snapshot")
    func detectionIsReadOnly() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let todayBefore = try await repository.today()
        let historyBefore = try await repository.history(.firstPage)

        _ = try await repository.detect(.text("qualquer texto bounded"))
        _ = try await repository.detect(.photoSample(label: "foto local"))
        _ = try await repository.detect(.audioSample(label: "áudio local"))

        #expect(try await repository.today() == todayBefore)
        #expect(try await repository.history(.firstPage) == historyBefore)
    }

    @Test("meal and workout confirmation require an open pending proposal")
    func confirmationRequiresPendingForBothKinds() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)

        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.confirm(confirmAttempt(
                id: mealRegistrationID,
                key: "no-pending-meal-0001"
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.confirm(confirmAttempt(
                id: workoutRegistrationID,
                key: "no-pending-workout-0001"
            ))
        }
    }

    @Test("meal and workout proposal responses are complete authored pending values")
    func proposeReturnsCompletePendingResponses() async throws {
        let mealRepository = DemoBodyFlowRepository(scenario: .loaded)
        let workoutRepository = DemoBodyFlowRepository(scenario: .loaded)

        let meal = try await mealRepository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "propose-meal-0001"
        ))
        let workout = try await workoutRepository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "propose-workout-0001"
        ))

        #expect(meal.data.id == mealRegistrationID)
        #expect(meal.data.status == "pending")
        #expect(meal.data.resolvedAt == nil)
        #expect(meal.data.proposal == expectedPendingMealProposal)
        #expect(workout.data.id == workoutRegistrationID)
        #expect(workout.data.status == "pending")
        #expect(workout.data.resolvedAt == nil)
        #expect(workout.data.proposal == expectedPendingWorkoutProposal)
    }

    @Test("meal and workout edits replace the entire authored pending response")
    func editStoresWholePredefinedReplacement() async throws {
        let mealRepository = DemoBodyFlowRepository(scenario: .loaded)
        let mealPending = try await mealRepository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "replace-meal-propose-0001"
        ))
        let arbitraryMealEdit = RegistrationProposalRequest.meal(
            MealProposalRequest(
                mealType: .breakfast,
                items: [
                    MealProposalItemRequest(
                        foodName: "Não deve ser copiado para a resposta",
                        quantityG: 999,
                        userKcal: 1
                    )
                ],
                consumedAt: nil
            )
        )
        let mealEdited = try await mealRepository.edit(editAttempt(
            id: mealPending.data.id,
            proposal: arbitraryMealEdit,
            key: "replace-meal-edit-0001"
        ))
        #expect(mealEdited.data.proposal == expectedEditedMealProposal)

        let mealConfirmed = try await mealRepository.confirm(confirmAttempt(
            id: mealPending.data.id,
            key: "replace-meal-confirm-0001"
        ))
        #expect(mealConfirmed.data.registration.proposal == expectedEditedMealProposal)

        let workoutRepository = DemoBodyFlowRepository(scenario: .loaded)
        let workoutPending = try await workoutRepository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "replace-workout-propose-0001"
        ))
        let arbitraryWorkoutEdit = RegistrationProposalRequest.workout(
            WorkoutProposalRequest(
                workoutType: "não copiar",
                durationMin: 1,
                intensity: .light,
                performedAt: nil
            )
        )
        let workoutEdited = try await workoutRepository.edit(editAttempt(
            id: workoutPending.data.id,
            proposal: arbitraryWorkoutEdit,
            key: "replace-workout-edit-0001"
        ))
        #expect(workoutEdited.data.proposal == expectedEditedWorkoutProposal)

        let workoutConfirmed = try await workoutRepository.confirm(confirmAttempt(
            id: workoutPending.data.id,
            key: "replace-workout-confirm-0001"
        ))
        #expect(
            workoutConfirmed.data.registration.proposal
                == expectedEditedWorkoutProposal
        )
    }

    @Test("only the exact open pending id can be cancelled or edited")
    func onlyExactOpenPendingCanChange() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let pending = try await repository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "exact-open-propose-0001"
        ))

        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.cancel(cancelAttempt(
                id: "another-registration",
                key: "exact-open-wrong-cancel-0001"
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.edit(editAttempt(
                id: "another-registration",
                proposal: expectedTextDetectionRequest,
                key: "exact-open-wrong-edit-0001"
            ))
        }

        let cancelled = try await repository.cancel(cancelAttempt(
            id: pending.data.id,
            key: "exact-open-cancel-0001"
        ))
        #expect(cancelled.data.status == "cancelled")
        #expect(cancelled.data.id == pending.data.id)

        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.confirm(confirmAttempt(
                id: pending.data.id,
                key: "exact-open-after-cancel-0001"
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.edit(editAttempt(
                id: pending.data.id,
                proposal: expectedTextDetectionRequest,
                key: "exact-open-edit-after-cancel-0001"
            ))
        }
    }

    @Test("expired and missing pending registrations use distinct typed errors")
    func expiredAndMissingErrorsAreTyped() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let pending = try await repository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "expiration-propose-0001"
        ))

        await #expect(throws: BodyFlowCapabilityError.registrationExpired) {
            try await repository.confirm(confirmAttempt(
                id: pending.data.id,
                key: "expiration-confirm-0001",
                createdAt: expiredAttemptDate
            ))
        }
        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.cancel(cancelAttempt(
                id: pending.data.id,
                key: "expiration-cancel-after-0001"
            ))
        }
    }

    @Test("meal and workout pending registrations coexist and resolve by exact id")
    func pendingRegistrationsCoexistByID() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let meal = try await repository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "coexist-meal-propose-0001"
        ))
        let workout = try await repository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "coexist-workout-propose-0001"
        ))

        let editedMeal = try await repository.edit(editAttempt(
            id: meal.data.id,
            proposal: expectedTextDetectionRequest,
            key: "coexist-meal-edit-0001"
        ))
        let cancelledWorkout = try await repository.cancel(cancelAttempt(
            id: workout.data.id,
            key: "coexist-workout-cancel-0001"
        ))
        let confirmedMeal = try await repository.confirm(confirmAttempt(
            id: meal.data.id,
            key: "coexist-meal-confirm-0001"
        ))

        #expect(editedMeal.data.proposal == expectedEditedMealProposal)
        #expect(cancelledWorkout.data.id == workoutRegistrationID)
        #expect(confirmedMeal.data.registration.id == mealRegistrationID)
        #expect(
            confirmedMeal.data.registration.proposal == expectedEditedMealProposal
        )
    }

    @Test("expiration removes only the exact expired pending registration")
    func expirationIsScopedToExactID() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let meal = try await repository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "scoped-expiry-meal-propose-0001"
        ))
        let workout = try await repository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "scoped-expiry-workout-propose-0001"
        ))

        await #expect(throws: BodyFlowCapabilityError.registrationExpired) {
            try await repository.confirm(confirmAttempt(
                id: meal.data.id,
                key: "scoped-expiry-meal-confirm-0001",
                createdAt: expiredAttemptDate
            ))
        }

        let workoutReceipt = try await repository.confirm(confirmAttempt(
            id: workout.data.id,
            key: "scoped-expiry-workout-confirm-0001"
        ))
        #expect(workoutReceipt.data.registration.id == workoutRegistrationID)
    }

    @Test("edited authored proposal persists into receipt Today and History")
    func editedVariantPersistsAcrossOfficialSnapshots() async throws {
        let mealRepository = DemoBodyFlowRepository(scenario: .loaded)
        let meal = try await mealRepository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "edited-snapshot-meal-propose-0001"
        ))
        _ = try await mealRepository.edit(editAttempt(
            id: meal.data.id,
            proposal: expectedTextDetectionRequest,
            key: "edited-snapshot-meal-edit-0001"
        ))
        let mealReceipt = try await mealRepository.confirm(confirmAttempt(
            id: meal.data.id,
            key: "edited-snapshot-meal-confirm-0001"
        ))
        let mealToday = try await mealRepository.today()
        let mealHistory = try await mealRepository.history(.firstPage)

        #expect(mealReceipt.data.registration.proposal == expectedEditedMealProposal)
        #expect(
            mealToday == DemoBodyFlowFixtures.postEditedMealConfirmationToday
        )
        #expect(
            mealHistory == DemoBodyFlowFixtures.postEditedMealConfirmationHistory
        )
        #expect(mealToday.data.meals.first?.mealType == "jantar")
        #expect(mealToday.data.meals.first?.quantityG == 205)
        #expect(mealToday.data.meals.first?.kcal == 512)
        #expect(mealHistory.data.meals.first?.mealType == "jantar")
        #expect(mealHistory.data.meals.first?.quantityG == 205)
        #expect(mealHistory.data.meals.first?.kcal == 512)

        let workoutRepository = DemoBodyFlowRepository(scenario: .loaded)
        let workout = try await workoutRepository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "edited-snapshot-workout-propose-0001"
        ))
        _ = try await workoutRepository.edit(editAttempt(
            id: workout.data.id,
            proposal: workoutRequest,
            key: "edited-snapshot-workout-edit-0001"
        ))
        let workoutReceipt = try await workoutRepository.confirm(confirmAttempt(
            id: workout.data.id,
            key: "edited-snapshot-workout-confirm-0001"
        ))
        let workoutToday = try await workoutRepository.today()
        let workoutHistory = try await workoutRepository.history(.firstPage)

        #expect(
            workoutReceipt.data.registration.proposal
                == expectedEditedWorkoutProposal
        )
        #expect(
            workoutToday == DemoBodyFlowFixtures.postEditedWorkoutConfirmationToday
        )
        #expect(
            workoutHistory
                == DemoBodyFlowFixtures.postEditedWorkoutConfirmationHistory
        )
        #expect(workoutToday.data.workouts.first?.workoutType == "ciclismo")
        #expect(workoutToday.data.workouts.first?.durationMin == 61)
        #expect(workoutToday.data.workouts.first?.estimatedKcal == 444)
        #expect(workoutHistory.data.workouts.first?.workoutType == "ciclismo")
        #expect(workoutHistory.data.workouts.first?.durationMin == 61)
        #expect(workoutHistory.data.workouts.first?.estimatedKcal == 444)
    }

    @Test("all meal and workout authored variants accumulate without losing baseline state")
    func sequentialConfirmationsSelectCompleteCumulativeFixtures() async throws {
        let combinations: [(mealEdited: Bool, workoutEdited: Bool)] = [
            (false, false),
            (true, false),
            (false, true),
            (true, true),
        ]

        for (index, combination) in combinations.enumerated() {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            let meal = try await repository.propose(proposeAttempt(
                payload: expectedTextDetectionRequest,
                key: "cumulative-meal-propose-000\(index)"
            ))
            let workout = try await repository.propose(proposeAttempt(
                payload: workoutRequest,
                key: "cumulative-workout-propose-000\(index)"
            ))

            if combination.mealEdited {
                _ = try await repository.edit(editAttempt(
                    id: meal.data.id,
                    proposal: expectedTextDetectionRequest,
                    key: "cumulative-meal-edit-000\(index)"
                ))
            }
            if combination.workoutEdited {
                _ = try await repository.edit(editAttempt(
                    id: workout.data.id,
                    proposal: workoutRequest,
                    key: "cumulative-workout-edit-000\(index)"
                ))
            }

            _ = try await repository.confirm(confirmAttempt(
                id: meal.data.id,
                key: "cumulative-meal-confirm-000\(index)"
            ))
            let afterMeal = try await repository.today()
            let expectedAfterMeal = combination.mealEdited
                ? DemoBodyFlowFixtures.postEditedMealConfirmationToday
                : DemoBodyFlowFixtures.postMealConfirmationToday
            #expect(afterMeal == expectedAfterMeal)
            #expect(afterMeal.data.meals.count == 3)
            #expect(afterMeal.data.workouts.count == 2)

            _ = try await repository.confirm(confirmAttempt(
                id: workout.data.id,
                key: "cumulative-workout-confirm-000\(index)"
            ))
            let today = try await repository.today()
            let history = try await repository.history(.firstPage)
            let expectedToday: TodayResponse
            let expectedHistory: HistoryResponse
            switch (combination.mealEdited, combination.workoutEdited) {
            case (false, false):
                expectedToday = DemoBodyFlowFixtures
                    .postInitialMealInitialWorkoutConfirmationToday
                expectedHistory = DemoBodyFlowFixtures
                    .postInitialMealInitialWorkoutConfirmationHistory
            case (true, false):
                expectedToday = DemoBodyFlowFixtures
                    .postEditedMealInitialWorkoutConfirmationToday
                expectedHistory = DemoBodyFlowFixtures
                    .postEditedMealInitialWorkoutConfirmationHistory
            case (false, true):
                expectedToday = DemoBodyFlowFixtures
                    .postInitialMealEditedWorkoutConfirmationToday
                expectedHistory = DemoBodyFlowFixtures
                    .postInitialMealEditedWorkoutConfirmationHistory
            case (true, true):
                expectedToday = DemoBodyFlowFixtures
                    .postEditedMealEditedWorkoutConfirmationToday
                expectedHistory = DemoBodyFlowFixtures
                    .postEditedMealEditedWorkoutConfirmationHistory
            }

            #expect(today == expectedToday)
            #expect(history == expectedHistory)
            #expect(today.data.meals.count == 3)
            #expect(today.data.workouts.count == 3)
            #expect(history.data.meals.count == 3)
            #expect(history.data.workouts.count == 2)
            #expect(
                today.data.meals.first?.id
                    == (combination.mealEdited
                        ? "demo-confirmed-meal-edited-row-1"
                        : "demo-confirmed-meal-row-1")
            )
            #expect(
                today.data.workouts.first?.id
                    == (combination.workoutEdited
                        ? "demo-confirmed-workout-edited-1"
                        : "demo-confirmed-workout-1")
            )
            #expect(history.data.meals.first?.id == today.data.meals.first?.id)
            #expect(
                history.data.workouts.first?.id
                    == today.data.workouts.first?.id
            )
            #expect(
                today.data.meals.first?.mealType
                    == (combination.mealEdited ? "jantar" : "almoco")
            )
            #expect(
                today.data.workouts.first?.workoutType
                    == (combination.workoutEdited ? "ciclismo" : "musculacao")
            )
            #expect(
                history.data.meals.first?.mealType
                    == (combination.mealEdited ? "jantar" : "almoco")
            )
            #expect(
                history.data.workouts.first?.workoutType
                    == (combination.workoutEdited ? "ciclismo" : "musculacao")
            )
            #expect(
                today.data.pendingActions
                    == DemoBodyFlowFixtures.loadedToday.data.pendingActions
            )
            #expect(
                today.data.pendingActions.registrations.map(\.id)
                    == ["pending-z", "pending-a"]
            )
            #expect(
                today.data.supplements
                    == DemoBodyFlowFixtures.loadedToday.data.supplements
            )
            #expect(
                today.data.medications
                    == DemoBodyFlowFixtures.loadedToday.data.medications
            )
            #expect(
                today.data.localDate
                    == DemoBodyFlowFixtures.loadedToday.data.localDate
            )
            #expect(
                history.data.pagination
                    == DemoBodyFlowFixtures.loadedHistory.data.pagination
            )
            #expect(HistoryQuery.firstPage.before == nil)
            #expect(HistoryQuery.firstPage.limit == 30)
            #expect(
                try await repository.list(
                    kind: .supplement,
                    includeArchived: false
                ) == DemoBodyFlowFixtures.loadedSupplementList
            )
            #expect(
                try await repository.history(
                    kind: .supplement,
                    itemID: "supplement-1",
                    cursor: nil,
                    limit: 30
                ) == DemoBodyFlowFixtures.loadedSupplementHistory
            )
        }
    }

    @Test("proposal edit confirmation and cancellation retain baseline pending actions")
    func lifecycleDoesNotClearUnrelatedBaselinePendingActions() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let baseline = DemoBodyFlowFixtures.loadedToday.data.pendingActions
        let meal = try await repository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "baseline-pending-meal-propose-0001"
        ))
        let workout = try await repository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "baseline-pending-workout-propose-0001"
        ))

        #expect(try await repository.today().data.pendingActions == baseline)
        _ = try await repository.edit(editAttempt(
            id: meal.data.id,
            proposal: expectedTextDetectionRequest,
            key: "baseline-pending-meal-edit-0001"
        ))
        #expect(try await repository.today().data.pendingActions == baseline)
        _ = try await repository.cancel(cancelAttempt(
            id: workout.data.id,
            key: "baseline-pending-workout-cancel-0001"
        ))
        #expect(try await repository.today().data.pendingActions == baseline)
        _ = try await repository.confirm(confirmAttempt(
            id: meal.data.id,
            key: "baseline-pending-meal-confirm-0001"
        ))
        #expect(try await repository.today().data.pendingActions == baseline)
    }

    @Test("meal confirmation selects one complete predefined Today and History transition")
    func mealConfirmationMovesCompleteSnapshots() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let pending = try await repository.propose(proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "transition-meal-propose-0001"
        ))

        let receipt = try await repository.confirm(confirmAttempt(
            id: pending.data.id,
            key: "transition-meal-confirm-0001"
        ))

        #expect(receipt == DemoBodyFlowFixtures.confirmedMealRegistration)
        #expect(
            try await repository.today()
                == DemoBodyFlowFixtures.postMealConfirmationToday
        )
        #expect(
            try await repository.history(.firstPage)
                == DemoBodyFlowFixtures.postMealConfirmationHistory
        )
        #expect(receipt.data.registration.status == "confirmed")
    }

    @Test("workout confirmation selects one complete predefined Today and History transition")
    func workoutConfirmationMovesCompleteSnapshots() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let pending = try await repository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "transition-workout-propose-0001"
        ))

        let receipt = try await repository.confirm(confirmAttempt(
            id: pending.data.id,
            key: "transition-workout-confirm-0001"
        ))

        #expect(receipt == DemoBodyFlowFixtures.confirmedWorkoutRegistration)
        #expect(
            try await repository.today()
                == DemoBodyFlowFixtures.postWorkoutConfirmationToday
        )
        #expect(
            try await repository.history(.firstPage)
                == DemoBodyFlowFixtures.postWorkoutConfirmationHistory
        )
        #expect(receipt.data.registration.status == "confirmed")
    }

    @Test("all registration operations replay their exact first typed result")
    func exactAttemptsReplayWithoutSecondMutation() async throws {
        let confirmRepository = DemoBodyFlowRepository(scenario: .loaded)
        let propose = try proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "replay-propose-0001"
        )
        let firstProposal = try await confirmRepository.propose(propose)
        #expect(try await confirmRepository.propose(propose) == firstProposal)

        let edit = try editAttempt(
            id: firstProposal.data.id,
            proposal: expectedTextDetectionRequest,
            key: "replay-edit-0001"
        )
        let firstEdit = try await confirmRepository.edit(edit)
        #expect(try await confirmRepository.edit(edit) == firstEdit)

        let confirm = try confirmAttempt(
            id: firstProposal.data.id,
            key: "replay-confirm-0001"
        )
        let firstConfirmation = try await confirmRepository.confirm(confirm)
        let firstToday = try await confirmRepository.today()
        let firstHistory = try await confirmRepository.history(.firstPage)
        #expect(try await confirmRepository.confirm(confirm) == firstConfirmation)
        #expect(try await confirmRepository.today() == firstToday)
        #expect(try await confirmRepository.history(.firstPage) == firstHistory)

        let cancelRepository = DemoBodyFlowRepository(scenario: .loaded)
        let cancelPending = try await cancelRepository.propose(proposeAttempt(
            payload: workoutRequest,
            key: "replay-cancel-propose-0001"
        ))
        let cancel = try cancelAttempt(
            id: cancelPending.data.id,
            key: "replay-cancel-0001"
        )
        let firstCancellation = try await cancelRepository.cancel(cancel)
        #expect(try await cancelRepository.cancel(cancel) == firstCancellation)
    }

    @Test("a reused key conflicts on changed payload createdAt or operation")
    func globalLedgerRejectsChangedAttemptIdentity() async throws {
        let payloadRepository = DemoBodyFlowRepository(scenario: .loaded)
        let first = try proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "conflict-payload-0001"
        )
        _ = try await payloadRepository.propose(first)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await payloadRepository.propose(proposeAttempt(
                payload: workoutRequest,
                key: first.key.value
            ))
        }

        let dateRepository = DemoBodyFlowRepository(scenario: .loaded)
        let dated = try proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "conflict-created-at-0001"
        )
        _ = try await dateRepository.propose(dated)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await dateRepository.propose(proposeAttempt(
                payload: dated.payload,
                key: dated.key.value,
                createdAt: Date(timeIntervalSince1970: 1_784_589_301)
            ))
        }

        let operationRepository = DemoBodyFlowRepository(scenario: .loaded)
        let operation = try proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "conflict-operation-0001"
        )
        let pending = try await operationRepository.propose(operation)
        await #expect(throws: BodyFlowCapabilityError.idempotencyConflict) {
            try await operationRepository.confirm(confirmAttempt(
                id: pending.data.id,
                key: operation.key.value
            ))
        }
    }

    @Test("one-shot registration failure mutates nothing and exact retry succeeds")
    func oneShotFailureIsDeterministic() async throws {
        let repository = DemoBodyFlowRepository(scenario: .registrationFailureOnce)
        let attempt = try proposeAttempt(
            payload: expectedTextDetectionRequest,
            key: "failure-once-propose-0001"
        )

        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await repository.propose(attempt)
        }
        await #expect(throws: BodyFlowCapabilityError.registrationNotPending) {
            try await repository.confirm(confirmAttempt(
                id: mealRegistrationID,
                key: "failure-once-before-retry-0001"
            ))
        }

        let retry = try await repository.propose(attempt)
        #expect(retry.data.id == mealRegistrationID)
        #expect(try await repository.propose(attempt) == retry)
    }
}

private let expectedTextDetectionRequest = RegistrationProposalRequest.meal(
    MealProposalRequest(
        mealType: .lunch,
        items: [
            MealProposalItemRequest(
                foodName: "Refeição textual de demonstração",
                quantityG: 180,
                userKcal: nil
            )
        ],
        consumedAt: APITimestamp(
            value: Date(timeIntervalSince1970: 1_784_589_300)
        )
    )
)

private let expectedPhotoDetectionRequest = RegistrationProposalRequest.meal(
    MealProposalRequest(
        mealType: .dinner,
        items: [
            MealProposalItemRequest(
                foodName: "Amostra fotográfica de demonstração",
                quantityG: 210,
                userKcal: nil
            )
        ],
        consumedAt: APITimestamp(
            value: Date(timeIntervalSince1970: 1_784_589_300)
        )
    )
)

private let expectedAudioDetectionRequest = RegistrationProposalRequest.meal(
    MealProposalRequest(
        mealType: .snack,
        items: [
            MealProposalItemRequest(
                foodName: "Amostra de áudio de demonstração",
                quantityG: 95,
                userKcal: nil
            )
        ],
        consumedAt: APITimestamp(
            value: Date(timeIntervalSince1970: 1_784_589_300)
        )
    )
)

private let mealRegistrationID = "demo-registration-meal-1"
private let workoutRegistrationID = "demo-registration-workout-1"
private let registrationAttemptDate = Date(timeIntervalSince1970: 1_784_589_300)
private let expiredAttemptDate = Date(timeIntervalSince1970: 1_784_596_500)

private let workoutRequest = RegistrationProposalRequest.workout(
    WorkoutProposalRequest(
        workoutType: "musculacao",
        durationMin: 40,
        intensity: .moderate,
        performedAt: APITimestamp(value: registrationAttemptDate)
    )
)

private let expectedPendingMealProposal = RegistrationProposalSnapshot.meal(
    MealProposalSnapshot(
        mealType: "almoco",
        items: [
            MealProposalItemSnapshot(
                name: "Refeição textual de demonstração",
                quantityG: 180,
                kcal: 389,
                proteinG: 27,
                carbsG: 45,
                fatG: 11
            )
        ],
        totals: MealProposalTotalsSnapshot(
            kcal: 389,
            proteinG: 27,
            carbsG: 45,
            fatG: 11
        ),
        warnings: ["Valores sintéticos; confirme antes de registrar."]
    )
)

private let expectedEditedMealProposal = RegistrationProposalSnapshot.meal(
    MealProposalSnapshot(
        mealType: "jantar",
        items: [
            MealProposalItemSnapshot(
                name: "Substituição completa predefinida",
                quantityG: 205,
                kcal: 512,
                proteinG: 33,
                carbsG: 52,
                fatG: 19
            )
        ],
        totals: MealProposalTotalsSnapshot(
            kcal: 512,
            proteinG: 33,
            carbsG: 52,
            fatG: 19
        ),
        warnings: ["Resposta completa substituída."]
    )
)

private let expectedPendingWorkoutProposal = RegistrationProposalSnapshot.workout(
    WorkoutProposalSnapshot(
        workoutType: "musculacao",
        durationMin: 47,
        estimatedKcal: 333,
        intensity: "moderada"
    )
)

private let expectedEditedWorkoutProposal = RegistrationProposalSnapshot.workout(
    WorkoutProposalSnapshot(
        workoutType: "ciclismo",
        durationMin: 61,
        estimatedKcal: 444,
        intensity: "alta"
    )
)

private func proposeAttempt(
    payload: RegistrationProposalRequest,
    key: String,
    createdAt: Date = registrationAttemptDate
) throws -> MutationAttempt<RegistrationProposalRequest> {
    MutationAttempt(
        operation: .proposalCreate,
        key: try IdempotencyKey(validating: key),
        payload: payload,
        createdAt: createdAt
    )
}

private func editAttempt(
    id: String,
    proposal: RegistrationProposalRequest,
    key: String,
    createdAt: Date = registrationAttemptDate
) throws -> MutationAttempt<RegistrationEditCommand> {
    MutationAttempt(
        operation: .proposalEdit,
        key: try IdempotencyKey(validating: key),
        payload: RegistrationEditCommand(
            registrationID: id,
            proposal: proposal
        ),
        createdAt: createdAt
    )
}

private func confirmAttempt(
    id: String,
    key: String,
    createdAt: Date = registrationAttemptDate
) throws -> MutationAttempt<RegistrationIDCommand> {
    MutationAttempt(
        operation: .proposalConfirm,
        key: try IdempotencyKey(validating: key),
        payload: RegistrationIDCommand(registrationID: id),
        createdAt: createdAt
    )
}

private func cancelAttempt(
    id: String,
    key: String,
    createdAt: Date = registrationAttemptDate
) throws -> MutationAttempt<RegistrationIDCommand> {
    MutationAttempt(
        operation: .proposalCancel,
        key: try IdempotencyKey(validating: key),
        payload: RegistrationIDCommand(registrationID: id),
        createdAt: createdAt
    )
}
#endif
