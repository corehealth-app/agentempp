import Foundation
import Testing

@testable import BodyFlow

@Suite("Meal Registration Model")
@MainActor
struct MealRegistrationModelTests {
    @Test("The direct detection path carries the selected slot without changing the detected foods")
    func directDetectionKeepsSelectedBreakfast() async throws {
        let harness = try Self.makeHarness(selectedMealType: .breakfast)
        await harness.model.submit(.text("Refeição"))
        let attempt = try #require(await harness.service.proposeAttempts.first)
        guard case let .meal(meal) = attempt.payload,
              case let .meal(original) = Self.detectedMealRequest else {
            Issue.record("Expected meal request"); return
        }
        #expect(meal.mealType == .breakfast)
        #expect(meal.items == original.items)
        #expect(meal.source == original.source)
        #expect(meal.consumedAt == original.consumedAt)
    }

    @Test("An edit in the review remains authoritative even when the sheet started from breakfast")
    func reviewedMealTypeIsNotOverriddenByTheInitialSlot() async throws {
        let harness = try Self.makeHarness(selectedMealType: .breakfast)
        let reviewed = MealProposalRequest(mealType: .dinner, items: Self.editedMealRequest.items,
            consumedAt: Self.editedMealRequest.consumedAt, source: Self.editedMealRequest.source)
        await harness.model.propose(reviewed: reviewed)
        #expect(await harness.service.proposeAttempts.first?.payload == .meal(reviewed))
    }
    @Test("Text always detects then creates a pending proposal without confirming")
    func textDetectionPrecedesProposal() async throws {
        let harness = try Self.makeHarness()

        await harness.model.submit(.text("Arroz, feijão e frango"))

        #expect(await harness.service.calls == [
            .detect(.text("Arroz, feijão e frango")),
            .propose,
        ])
        #expect(harness.model.detectedDraft == Self.detectedMealRequest)
        #expect(harness.model.currentProposal == Self.pendingResponse.data)
        #expect(harness.model.phase == .proposal)
    }

    @Test("Photo demonstration detects then creates a pending proposal without a permission or media dependency")
    func photoDetectionPrecedesProposalWithoutMediaDependency() async throws {
        let harness = try Self.makeHarness()

        await harness.model.submit(
            .photoDemonstration(label: "Amostra fotográfica local")
        )

        #expect(await harness.service.calls == [
            .detect(.photoSample(label: "Amostra fotográfica local")),
            .propose,
        ])
        #expect(harness.model.currentProposal?.status == "pending")
        #expect(harness.model.phase == .proposal)
    }

    @Test("Audio demonstration detects then creates a pending proposal without a permission or media dependency")
    func audioDetectionPrecedesProposalWithoutMediaDependency() async throws {
        let harness = try Self.makeHarness()

        await harness.model.submit(
            .audioDemonstration(label: "Amostra de áudio local")
        )

        #expect(await harness.service.calls == [
            .detect(.audioSample(label: "Amostra de áudio local")),
            .propose,
        ])
        #expect(harness.model.currentProposal?.status == "pending")
        #expect(harness.model.phase == .proposal)
    }

    @Test(
        "Debug preview and UI-test demonstration text guard rejects 0 and 1001 String.count characters and is not an API contract",
        arguments: [0, 1_001]
    )
    func demonstrationTextRejectsOutOfRangeLength(length: Int) async throws {
        let harness = try Self.makeHarness()

        await harness.model.submit(.text(String(repeating: "á", count: length)))

        #expect(await harness.service.calls.isEmpty)
        #expect(harness.model.captureError == .invalidInput)
        #expect(harness.model.detectedDraft == nil)
        #expect(harness.model.currentProposal == nil)
    }

    @Test(
        "Debug preview and UI-test demonstration text guard accepts 1 and 1000 String.count characters and is not an API contract",
        arguments: [1, 1_000]
    )
    func demonstrationTextAcceptsInclusiveBoundaries(length: Int) async throws {
        let harness = try Self.makeHarness()
        let text = String(repeating: "á", count: length)

        await harness.model.submit(.text(text))

        #expect(await harness.service.calls == [
            .detect(.text(text)),
            .propose,
        ])
        #expect(harness.model.currentProposal == Self.pendingResponse.data)
    }

    @Test("Text demonstration guard measures the visible String without trimming")
    func demonstrationTextIsNotTrimmed() async throws {
        let harness = try Self.makeHarness()

        await harness.model.submit(.text(" "))

        #expect(await harness.service.calls == [
            .detect(.text(" ")),
            .propose,
        ])
    }

    @Test("removing a Debug demonstration policy must let a 1001-character text reach the unavailable provider in Release")
    func releaseTextBeyondDemonstrationLimitReachesUnavailableProvider() async throws {
        let service = MealRegistrationServiceSpy(
            detectedRequest: Self.detectedMealRequest,
            proposalResponse: Self.pendingResponse,
            proposeOutcomes: [.failure(.operationUnavailable)]
        )
        let model = MealRegistrationModel(
            detector: service,
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "release"),
            invalidationCenter: FeatureInvalidationCenter()
        )
        let text = String(repeating: "a", count: 1_001)

        await model.submit(.text(text))

        #expect(await service.calls == [.detect(.text(text)), .propose])
        #expect(model.captureError == .operationUnavailable)
        #expect(model.mutationState == .unavailable)
    }

    @Test("initial consumed time and proposal attempt time come from the fixed provider")
    func fixedTimeDefaults() async throws {
        let harness = try Self.makeHarness()

        #expect(harness.model.initialConsumedAt == Self.fixedDate)
        await harness.model.submit(.text("Refeição"))

        let attempt = try #require(await harness.service.proposeAttempts.first)
        #expect(attempt.createdAt == Self.fixedDate)
        #expect(attempt.operation == .proposalCreate)
        guard case let .succeeded(.propose(receipt)) = harness.model.mutationState else {
            Issue.record("Expected typed proposal receipt")
            return
        }
        #expect(receipt == Self.pendingResponse)
    }

    @Test("failed proposal preserves source and detected draft then Retry reuses the exact typed attempt")
    func failedProposalRetriesExactAttempt() async throws {
        let harness = try Self.makeHarness(
            proposeOutcomes: [
                .failure(.serviceUnavailable),
                .success(Self.pendingResponse),
            ]
        )
        let source = MealCaptureSource.text("Refeição para retry")

        await harness.model.submit(source)

        let failedAttempt: MutationAttempt<RegistrationProposalRequest>
        guard case let .failed(.propose(attempt), error) = harness.model.mutationState else {
            Issue.record("Expected a retained typed proposal attempt")
            return
        }
        failedAttempt = attempt
        #expect(error == .serviceUnavailable)
        #expect(harness.model.captureSource == source)
        #expect(harness.model.detectedDraft == Self.detectedMealRequest)
        #expect(harness.model.currentProposal == nil)
        #expect(harness.model.accessibilityFocusTarget == .operationSummary)

        await harness.model.retry()

        #expect(await harness.service.proposeAttempts == [
            failedAttempt,
            failedAttempt,
        ])
        #expect(harness.model.currentProposal == Self.pendingResponse.data)
        guard case let .succeeded(.propose(receipt)) = harness.model.mutationState else {
            Issue.record("Expected the matching proposal receipt")
            return
        }
        #expect(receipt == Self.pendingResponse)
    }

    @Test("pending edit sends only approved request fields and replaces the complete response")
    func editReplacesWholeProposal() async throws {
        let harness = try Self.makeHarness(
            editOutcomes: [.success(Self.editedResponse)]
        )
        await harness.model.submit(.text("Refeição"))
        let edit = Self.editedMealRequest

        await harness.model.saveEdit(edit)

        let attempt = try #require(await harness.service.editAttempts.first)
        #expect(attempt.operation == .proposalEdit)
        #expect(attempt.payload == RegistrationEditCommand(
            registrationID: Self.pendingResponse.data.id,
            proposal: .meal(edit)
        ))
        #expect(harness.model.currentProposal == Self.editedResponse.data)
        guard case let .succeeded(.edit(receipt)) = harness.model.mutationState else {
            Issue.record("Expected typed edit receipt")
            return
        }
        #expect(receipt == Self.editedResponse)
    }

    @Test("failed edit preserves the complete pending proposal and exact attempt")
    func failedEditPreservesPending() async throws {
        let harness = try Self.makeHarness(
            editOutcomes: [.failure(.serviceUnavailable)]
        )
        await harness.model.submit(.text("Refeição"))

        await harness.model.saveEdit(Self.editedMealRequest)

        #expect(harness.model.currentProposal == Self.pendingResponse.data)
        guard case let .failed(.edit(attempt), error) = harness.model.mutationState else {
            Issue.record("Expected retained edit attempt")
            return
        }
        #expect(attempt.payload.proposal == .meal(Self.editedMealRequest))
        #expect(error == .serviceUnavailable)
    }

    @Test("failed confirmation preserves the pending proposal")
    func failedConfirmPreservesPending() async throws {
        let harness = try Self.makeHarness(
            confirmOutcomes: [.failure(.serviceUnavailable)]
        )
        await harness.model.submit(.text("Refeição"))

        await harness.model.confirm()

        #expect(harness.model.currentProposal == Self.pendingResponse.data)
        #expect(harness.model.phase == .proposal)
        guard case let .failed(.confirm(attempt), error) = harness.model.mutationState else {
            Issue.record("Expected retained confirm attempt")
            return
        }
        #expect(attempt.payload.registrationID == Self.pendingResponse.data.id)
        #expect(error == .serviceUnavailable)
    }

    @Test("failed cancellation preserves the pending proposal")
    func failedCancelPreservesPending() async throws {
        let harness = try Self.makeHarness(
            cancelOutcomes: [.failure(.serviceUnavailable)]
        )
        await harness.model.submit(.text("Refeição"))

        await harness.model.cancel()

        #expect(harness.model.currentProposal == Self.pendingResponse.data)
        #expect(harness.model.phase == .proposal)
        guard case let .failed(.cancel(attempt), error) = harness.model.mutationState else {
            Issue.record("Expected retained cancel attempt")
            return
        }
        #expect(attempt.payload.registrationID == Self.pendingResponse.data.id)
        #expect(error == .serviceUnavailable)
    }

    @Test("changed edit payload creates a new intention and idempotency key")
    func changedPayloadCreatesNewKey() async throws {
        let harness = try Self.makeHarness(
            editOutcomes: [
                .failure(.serviceUnavailable),
                .failure(.serviceUnavailable),
            ]
        )
        await harness.model.submit(.text("Refeição"))

        await harness.model.saveEdit(Self.editedMealRequest)
        var second = Self.editedMealRequest
        second = MealProposalRequest(
            mealType: .dinner,
            items: [
                MealProposalItemRequest(
                    foodName: "Outra intenção",
                    quantityG: 250,
                    userKcal: 600
                ),
            ],
            consumedAt: second.consumedAt
        )
        await harness.model.saveEdit(second)

        let attempts = await harness.service.editAttempts
        #expect(attempts.count == 2)
        #expect(attempts[0].key != attempts[1].key)
        #expect(attempts[0].payload != attempts[1].payload)
    }

    @Test("proposal create edit and cancel each invalidate Today only")
    func proposalChangesInvalidateTodayOnly() async throws {
        let harness = try Self.makeHarness(
            editOutcomes: [.success(Self.editedResponse)],
            cancelOutcomes: [.success(Self.cancelledResponse)]
        )

        await harness.model.submit(.text("Refeição"))
        #expect(harness.invalidationCenter.revision(for: .today) == 1)
        #expect(harness.invalidationCenter.revision(for: .history) == 0)

        await harness.model.saveEdit(Self.editedMealRequest)
        #expect(harness.invalidationCenter.revision(for: .today) == 2)
        #expect(harness.invalidationCenter.revision(for: .history) == 0)

        await harness.model.cancel()
        #expect(harness.invalidationCenter.revision(for: .today) == 3)
        #expect(harness.invalidationCenter.revision(for: .history) == 0)
        #expect(harness.model.phase == .cancelled)
        #expect(harness.model.currentProposal == nil)
    }

    @Test("confirmation invalidates Today and History without patching the provider receipt")
    func confirmationInvalidatesTodayAndHistory() async throws {
        let harness = try Self.makeHarness(
            confirmOutcomes: [.success(Self.confirmedResponse)]
        )
        await harness.model.submit(.text("Refeição"))

        await harness.model.confirm()

        #expect(harness.invalidationCenter.revision(for: .today) == 2)
        #expect(harness.invalidationCenter.revision(for: .history) == 1)
        #expect(harness.model.phase == .confirmed)
        #expect(harness.model.currentProposal == nil)
        #expect(harness.model.confirmedRegistration
            == Self.confirmedResponse.data.registration)
        guard case let .succeeded(.confirm(receipt)) = harness.model.mutationState else {
            Issue.record("Expected typed confirmation receipt")
            return
        }
        #expect(receipt == Self.confirmedResponse)
    }

    @Test("proposal network failure does not contaminate a new draft review after start over")
    func failedProposalThenNewDraftPresentation() async throws {
        let harness = try Self.makeHarness(proposeOutcomes: [.failure(.offline)])
        await harness.model.submit(.text("Refeição"))
        guard case .failed(.propose, .offline) = harness.model.mutationState else {
            Issue.record("Expected the exact retained network failure of the proposal")
            return
        }
        // Starting capture over resets the capture model, not this retained
        // mutation. A successful new draft review must query its own phase.
        #expect(PerformeRegistrationProjection.meal(
            intent: .draftText("Nova refeição"), draft: .review,
            mutation: harness.model.mutationState,
            captureError: harness.model.captureError
        ) == .ready)
        #expect(PerformeRegistrationProjection.meal(
            intent: .confirm, draft: .review,
            mutation: harness.model.mutationState,
            captureError: harness.model.captureError
        ) == .failed)
    }

    @Test("expired or no longer pending errors discard only the invalid pending and offer a new proposal", arguments: [
        BodyFlowCapabilityError.registrationExpired,
        BodyFlowCapabilityError.registrationNotPending,
    ])
    func invalidPendingIsDiscarded(error: BodyFlowCapabilityError) async throws {
        let harness = try Self.makeHarness(confirmOutcomes: [.failure(error)])
        let source = MealCaptureSource.text("Refeição preservada")
        await harness.model.submit(source)

        await harness.model.confirm()

        #expect(harness.model.currentProposal == nil)
        #expect(harness.model.detectedDraft == Self.detectedMealRequest)
        #expect(harness.model.captureSource == source)
        #expect(harness.model.phase == .capture)
        #expect(harness.model.canCreateNewProposal)
        #expect(harness.model.mutationState == .idle)

        await harness.model.createNewProposalFromDraft()
        let attempts = await harness.service.proposeAttempts
        #expect(attempts.count == 2)
        #expect(attempts[0].key != attempts[1].key)
    }

    /// docs/mobile/api-v1.md, "Ciclo do pending" item 4 and "Erros do
    /// pending": `409 registration_already_confirmed` means the record of
    /// this proposal is already saved. The sheet ends confirmed; proposing
    /// the same meal again would add it a second time.
    @Test("an edit or a cancellation refused because the record is already saved ends confirmed, with no new proposal", arguments: [
        AlreadySavedOperation.edit,
        AlreadySavedOperation.cancel,
    ])
    func alreadySavedRecordEndsConfirmed(operation: AlreadySavedOperation) async throws {
        let harness = try Self.makeHarness(
            editOutcomes: [.failure(.registrationAlreadyConfirmed)],
            cancelOutcomes: [.failure(.registrationAlreadyConfirmed)]
        )
        await harness.model.submit(.text("Refeição já salva"))
        #expect(harness.invalidationCenter.revision(for: .today) == 1)

        switch operation {
        case .edit: await harness.model.saveEdit(Self.editedMealRequest)
        case .cancel: await harness.model.cancel()
        }

        // The same end state as a normal confirmation.
        #expect(harness.model.phase == .confirmed)
        #expect(harness.model.currentProposal == nil)
        #expect(harness.model.captureError == nil)
        #expect(harness.model.mutationState == .succeeded(
            .alreadyConfirmed(registrationID: Self.pendingResponse.data.id)
        ))
        #expect(harness.model.accessibilityFocusTarget == .operationSummary)
        // Today and History refresh exactly as a confirmation makes them.
        #expect(harness.invalidationCenter.revision(for: .today) == 2)
        #expect(harness.invalidationCenter.revision(for: .history) == 1)

        for language in SupportedAppLanguage.allCases {
            let descriptor = RegistrationOperationSummaryDescriptor(
                state: harness.model.mutationState,
                captureError: harness.model.captureError,
                language: language
            )
            // The record is saved, but what the patient just asked for was
            // not applied: its own sentence, never the normal success.
            #expect(descriptor.message == (language == .portugueseBrazil
                ? "Este registro já estava salvo. A alteração não foi aplicada."
                : "This record was already saved. The change was not applied."))
            #expect(descriptor.message != (language == .portugueseBrazil
                ? "Registro confirmado." : "Record confirmed."))
            #expect(descriptor.action == nil)
            // A warning line: no burst and no success haptic.
            #expect(descriptor.kind == .warning)
            #expect(descriptor.kind != .success)
            #expect(RegistrationOperationSummaryDescriptor.celebration(for: descriptor.kind) == nil)
            #expect(RegistrationOperationSummaryDescriptor.feedback(for: descriptor.kind) == nil)
        }
        let outcome = PerformeRegistrationProjection.meal(
            intent: operation == .edit ? .edit(Self.editedMealRequest) : .cancel,
            draft: .review,
            mutation: harness.model.mutationState,
            captureError: harness.model.captureError
        )
        #expect(outcome == .confirmed)
        #expect(harness.model.mutationState.receipt?.confirmedRegistrationID
            == Self.pendingResponse.data.id)
        // The sheet's brand stays quiet: no confirmed state, no success
        // haptic, because no confirmation was answered for this operation.
        let confirmation = PerformeRegistrationProjection.confirmation(
            for: harness.model.mutationState
        )
        #expect(confirmation == nil)
        let presentation = PerformeOperationPresentation()
        let token = presentation.begin()
        presentation.finish(token, outcome: outcome, confirmation: confirmation, isCancelled: false)
        #expect(presentation.state == .active)
        #expect(presentation.feedback == nil)
        #expect(presentation.successToken == nil)

        // Nothing offers or sends the draft again.
        #expect(!harness.model.canCreateNewProposal)
        #expect(harness.model.detectedDraft == nil)
        await harness.model.createNewProposalFromDraft()
        await RegistrationOperationCoordinator(model: harness.model).perform(.newProposal)
        await harness.model.retry()
        await harness.model.propose(reviewed: Self.editedMealRequest)
        #expect(await harness.service.calls == [
            .detect(.text("Refeição já salva")),
            .propose,
            operation == .edit ? .edit : .cancel,
        ])
        #expect(await harness.service.proposeAttempts.count == 1)
        #expect(harness.model.phase == .confirmed)
    }

    /// Review finding of 04/10/2026: a patient who edits 200 g to 100 g and
    /// gets `409 registration_already_confirmed` must not believe 100 g was
    /// saved. The sheet ends confirmed and says the change was not applied.
    @Test("editing 200 g to 100 g after the record was already saved says the change was not applied")
    func editOf200gTo100gOnAnAlreadySavedRecordIsNotShownAsSaved() async throws {
        let harness = try Self.makeHarness(
            proposeOutcomes: [.success(Self.pending200gResponse)],
            editOutcomes: [.failure(.registrationAlreadyConfirmed)]
        )
        await harness.model.submit(.text("200 g de arroz"))
        #expect(harness.model.currentProposal == Self.pending200gResponse.data)

        await harness.model.saveEdit(Self.editTo100gRequest)

        let attempt = try #require(await harness.service.editAttempts.first)
        #expect(attempt.payload.registrationID == Self.pending200gResponse.data.id)
        #expect(attempt.payload.proposal == .meal(Self.editTo100gRequest))
        #expect(harness.model.phase == .confirmed)
        #expect(harness.model.currentProposal == nil)
        #expect(harness.model.confirmedRegistration == nil)
        #expect(harness.model.detectedDraft == nil)
        #expect(harness.model.mutationState == .succeeded(
            .alreadyConfirmed(registrationID: Self.pending200gResponse.data.id)
        ))
        #expect(harness.invalidationCenter.revision(for: .today) == 2)
        #expect(harness.invalidationCenter.revision(for: .history) == 1)

        let portuguese = RegistrationOperationSummaryDescriptor(
            state: harness.model.mutationState,
            captureError: harness.model.captureError,
            language: .portugueseBrazil
        )
        #expect(portuguese.message
            == "Este registro já estava salvo. A alteração não foi aplicada.")
        #expect(portuguese.kind == .warning)
        #expect(portuguese.action == nil)
        let english = RegistrationOperationSummaryDescriptor(
            state: harness.model.mutationState,
            captureError: harness.model.captureError,
            language: .englishUnitedStates
        )
        #expect(english.message
            == "This record was already saved. The change was not applied.")
        #expect(english.kind == .warning)
        #expect(RegistrationOperationSummaryDescriptor.celebration(for: portuguese.kind) == nil)
        #expect(RegistrationOperationSummaryDescriptor.feedback(for: portuguese.kind) == nil)
        #expect(PerformeRegistrationProjection.confirmation(
            for: harness.model.mutationState
        ) == nil)

        // No path sends the 100 g again.
        #expect(!harness.model.canCreateNewProposal)
        await harness.model.retry()
        await harness.model.createNewProposalFromDraft()
        await harness.model.propose(reviewed: Self.editTo100gRequest)
        #expect(await harness.service.calls == [
            .detect(.text("200 g de arroz")),
            .propose,
            .edit,
        ])
    }

    /// Second update (2026-10-10). After "Calcular refeição" fails the review
    /// comes back from the top and the error with "Tentar novamente" is below
    /// it, off the screen: a message that asks something of the patient must
    /// be seen, and only such a message moves the sheet.
    @Test("a failure with something to do asks to be seen; nothing else does")
    func aFailureWithSomethingToDoAsksToBeSeen() async throws {
        func asks(
            _ state: RegistrationMutationState,
            _ captureError: BodyFlowCapabilityError? = nil
        ) -> Bool {
            RegistrationOperationSummaryDescriptor(state: state, captureError: captureError).asksToBeSeen
        }

        // A failed operation that can be tried again.
        let failed = try Self.makeHarness(confirmOutcomes: [.failure(.serviceUnavailable)])
        await failed.model.submit(.text("Refeição preservada"))
        await failed.model.confirm()
        #expect(RegistrationOperationSummaryDescriptor(
            state: failed.model.mutationState, captureError: failed.model.captureError
        ).action == .retry)
        #expect(asks(failed.model.mutationState, failed.model.captureError))

        // A proposal that expired: a new one can be made.
        let expired = try Self.makeHarness(confirmOutcomes: [.failure(.registrationExpired)])
        await expired.model.submit(.text("Refeição preservada"))
        await expired.model.confirm()
        #expect(RegistrationOperationSummaryDescriptor(
            state: expired.model.mutationState, captureError: expired.model.captureError
        ).action == .newProposal)
        #expect(asks(expired.model.mutationState, expired.model.captureError))

        // A capture that failed and can be tried again.
        #expect(asks(.idle, .serviceUnavailable))

        // Locks: nothing else moves the sheet.
        #expect(!asks(.idle))
        #expect(!asks(.unavailable))
        #expect(!asks(.idle, .operationUnavailable))
        #expect(!asks(.succeeded(.confirm(Self.confirmedResponse))), "Never on success")
        #expect(!asks(.succeeded(.alreadyConfirmed(registrationID: Self.pendingResponse.data.id))))
        guard case let .failed(attempt, _) = failed.model.mutationState else {
            Issue.record("Expected a failed state to borrow its attempt from")
            return
        }
        #expect(!asks(.submitting(attempt)))
        #expect(!asks(.failed(attempt, .operationUnavailable)))
        #expect(!asks(.failed(attempt, .registrationAlreadyConfirmed)))
    }

    @Test("a confirmation the server answered keeps the normal success, in both languages",
          arguments: SupportedAppLanguage.allCases)
    func answeredConfirmationStillCelebrates(_ language: SupportedAppLanguage) {
        let state = RegistrationMutationState.succeeded(.confirm(Self.confirmedResponse))
        let descriptor = RegistrationOperationSummaryDescriptor(
            state: state,
            captureError: nil,
            language: language
        )
        #expect(descriptor.message == (language == .portugueseBrazil
            ? "Registro confirmado." : "Record confirmed."))
        #expect(descriptor.kind == .success)
        #expect(RegistrationOperationSummaryDescriptor.celebration(for: descriptor.kind) == .energy)
        #expect(RegistrationOperationSummaryDescriptor.feedback(for: descriptor.kind) == .success)
        #expect(PerformeRegistrationProjection.confirmation(for: state)
            == .registration(Self.confirmedResponse.data.registration.id))
    }

    @Test("a cancelled or expired proposal still offers a new proposal after the already-saved code exists", arguments: [
        BodyFlowCapabilityError.registrationExpired,
        BodyFlowCapabilityError.registrationNotPending,
    ])
    func notPendingStillOffersNewProposalOnEdit(error: BodyFlowCapabilityError) async throws {
        let harness = try Self.makeHarness(editOutcomes: [.failure(error)])
        await harness.model.submit(.text("Refeição preservada"))

        await harness.model.saveEdit(Self.editedMealRequest)

        #expect(harness.model.phase == .capture)
        #expect(harness.model.canCreateNewProposal)
        #expect(RegistrationOperationSummaryDescriptor(
            state: harness.model.mutationState,
            captureError: harness.model.captureError
        ).action == .newProposal)
        #expect(harness.invalidationCenter.revision(for: .history) == 0)
    }

    @Test("expired pending recovery uses the sheet summary descriptor to create a fresh proposal without redetecting")
    func expiredPendingSummaryActionCreatesNewProposalFromPreservedDraft() async throws {
        let harness = try Self.makeHarness(
            confirmOutcomes: [.failure(.registrationExpired)]
        )
        await harness.model.submit(.text("Refeição preservada"))
        await harness.model.confirm()

        let descriptor = RegistrationOperationSummaryDescriptor(
            state: harness.model.mutationState,
            captureError: harness.model.captureError
        )
        #expect(descriptor.action == .newProposal)
        #expect(descriptor.action != .retry)

        await RegistrationOperationCoordinator(model: harness.model)
            .perform(descriptor.action)

        #expect(await harness.service.calls == [
            .detect(.text("Refeição preservada")),
            .propose,
            .confirm,
            .propose,
        ])
        let attempts = await harness.service.proposeAttempts
        #expect(attempts.count == 2)
        #expect(attempts[0].key != attempts[1].key)
    }

    @Test("removing the pending-status guard would permit editing a confirmed snapshot")
    func editRejectsNonPendingSnapshot() async throws {
        let service = MealRegistrationServiceSpy(
            detectedRequest: Self.detectedMealRequest,
            proposalResponse: Self.confirmedStatusProposalResponse
        )
        let model = MealRegistrationModel(
            detector: service,
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "non-pending"),
            invalidationCenter: FeatureInvalidationCenter()
        )
        await model.submit(.text("Refeição"))

        await model.saveEdit(Self.editedMealRequest)

        #expect(await service.editAttempts.isEmpty)
        #expect(model.currentProposal?.status == "confirmed")
    }

    @Test("success and recoverable error expose then consume only the bounded operation summary focus target")
    func operationSummaryFocusTargetIsBounded() async throws {
        let success = try Self.makeHarness()
        await success.model.submit(.text("Refeição"))
        #expect(success.model.accessibilityFocusTarget == .operationSummary)
        success.model.consumeAccessibilityFocus()
        #expect(success.model.accessibilityFocusTarget == nil)

        let failure = try Self.makeHarness(
            proposeOutcomes: [.failure(.serviceUnavailable)]
        )
        await failure.model.submit(.text("Refeição"))
        #expect(failure.model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("double submission while a proposal attempt is in flight is disabled")
    func doubleSubmissionIsDisabled() async throws {
        let registration = SuspendingMealRegistrationService(
            response: Self.pendingResponse
        )
        let detector = ImmediateMealDetector(request: Self.detectedMealRequest)
        let center = FeatureInvalidationCenter()
        let model = MealRegistrationModel(
            detector: detector,
            registration: registration,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "double-submit"
            ),
            invalidationCenter: center
        )

        let first = Task { await model.submit(.text("Primeira")) }
        await registration.waitUntilProposeStarted(1)
        #expect(model.isSubmitting)
        await model.submit(.text("Segunda"))
        #expect(await registration.proposeCallCount == 1)
        #expect(await detector.inputs == [.text("Primeira")])

        await registration.succeedPropose(call: 1)
        await first.value
        #expect(model.currentProposal == Self.pendingResponse.data)
    }

    @Test("a superseded detection cannot publish a late draft proposal or navigation")
    func supersededDetectionCannotPublish() async throws {
        let detector = ControlledMealDetector()
        let service = MealRegistrationServiceSpy(
            detectedRequest: Self.detectedMealRequest,
            proposalResponse: Self.pendingResponse
        )
        let model = MealRegistrationModel(
            detector: detector,
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "supersede-detect"
            ),
            invalidationCenter: FeatureInvalidationCenter()
        )
        let firstRequest = Self.detectedMealRequest
        let secondRequest = Self.alternateDetectedMealRequest

        let first = Task { await model.submit(.text("Primeira")) }
        await detector.waitUntilStarted(1)
        let second = Task { await model.submit(.text("Segunda")) }
        await detector.waitUntilStarted(2)
        await detector.succeed(call: 2, with: secondRequest)
        await second.value
        await detector.succeed(call: 1, with: firstRequest)
        await first.value

        #expect(await service.proposeAttempts.map(\.payload) == [secondRequest])
        #expect(model.detectedDraft == secondRequest)
        #expect(model.currentProposal == Self.pendingResponse.data)
        #expect(model.phase == .proposal)
    }

    @Test("removing identical-capture deduplication would start two detectors for the same suspended text")
    func identicalSuspendedDetectionIsIgnored() async throws {
        let detector = ReentrantMealDetector(request: Self.detectedMealRequest)
        let service = MealRegistrationServiceSpy(
            detectedRequest: Self.detectedMealRequest,
            proposalResponse: Self.pendingResponse
        )
        let model = MealRegistrationModel(
            detector: detector,
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "duplicate-detect"),
            invalidationCenter: FeatureInvalidationCenter()
        )

        await detector.setDuplicateSubmission {
            await model.submit(.text("Igual"))
        }
        await model.submit(.text("Igual"))

        #expect(await detector.inputs == [.text("Igual")])
    }

    @Test("a cancelled detection cannot publish a late draft error or navigation")
    func cancelledDetectionCannotPublish() async throws {
        let detector = ControlledMealDetector()
        let service = MealRegistrationServiceSpy(
            detectedRequest: Self.detectedMealRequest,
            proposalResponse: Self.pendingResponse
        )
        let model = MealRegistrationModel(
            detector: detector,
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "cancel-detect"
            ),
            invalidationCenter: FeatureInvalidationCenter()
        )

        let task = Task { await model.submit(.text("Cancelada")) }
        await detector.waitUntilStarted(1)
        task.cancel()
        await detector.fail(call: 1, with: .serviceUnavailable)
        await task.value

        #expect(await service.proposeAttempts.isEmpty)
        #expect(model.detectedDraft == nil)
        #expect(model.captureError == nil)
        #expect(model.currentProposal == nil)
        #expect(model.phase == .capture)
    }

    @Test("discarding the sheet invalidates a suspended operation before its late result can publish")
    func discardInvalidatesSuspendedOperation() async throws {
        let detector = ControlledMealDetector()
        let service = MealRegistrationServiceSpy(
            detectedRequest: Self.detectedMealRequest,
            proposalResponse: Self.pendingResponse
        )
        let center = FeatureInvalidationCenter()
        let model = MealRegistrationModel(
            detector: detector,
            registration: service,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "discard"),
            invalidationCenter: center
        )

        let task = Task { await model.submit(.text("Refeição")) }
        await detector.waitUntilStarted(1)

        model.discardSheet()
        await detector.succeed(call: 1, with: Self.detectedMealRequest)
        await task.value

        #expect(model.currentProposal == nil)
        #expect(model.detectedDraft == nil)
        #expect(model.phase == .capture)
        #expect(model.mutationState == .idle)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    @Test("discarding the sheet invalidates a suspended mutation before its late receipt can publish")
    func discardInvalidatesSuspendedMutation() async throws {
        let registration = SuspendingMealRegistrationService(
            response: Self.pendingResponse
        )
        let center = FeatureInvalidationCenter()
        let model = MealRegistrationModel(
            detector: ImmediateMealDetector(request: Self.detectedMealRequest),
            registration: registration,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "discard-mutation"),
            invalidationCenter: center
        )

        let task = Task { await model.submit(.text("Refeição")) }
        await registration.waitUntilProposeStarted(1)

        model.discardSheet()
        await registration.succeedPropose(call: 1)
        await task.value

        #expect(model.currentProposal == nil)
        #expect(model.phase == .capture)
        #expect(model.captureError == nil)
        #expect(model.accessibilityFocusTarget == nil)
        #expect(model.mutationState == .idle)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    @Test("reset supersedes a mutation so its late receipt cannot publish navigate focus or invalidate")
    func supersededMutationCannotPublish() async throws {
        let registration = SuspendingMealRegistrationService(
            response: Self.pendingResponse
        )
        let center = FeatureInvalidationCenter()
        let model = MealRegistrationModel(
            detector: ImmediateMealDetector(request: Self.detectedMealRequest),
            registration: registration,
            timeProvider: FixedTimeProvider(value: Self.fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "supersede-mutation"
            ),
            invalidationCenter: center
        )

        let task = Task { await model.submit(.text("Refeição")) }
        await registration.waitUntilProposeStarted(1)
        model.startNewProposal()
        await registration.succeedPropose(call: 1)
        await task.value

        #expect(model.currentProposal == nil)
        #expect(model.detectedDraft == nil)
        #expect(model.phase == .capture)
        #expect(model.accessibilityFocusTarget == nil)
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }

    private static func makeHarness(
        proposeOutcomes: [MealServiceOutcome<RegistrationProposalResponse>]? = nil,
        editOutcomes: [MealServiceOutcome<RegistrationProposalResponse>] = [],
        confirmOutcomes: [MealServiceOutcome<RegistrationConfirmationResponse>] = [],
        cancelOutcomes: [MealServiceOutcome<RegistrationCancellationResponse>] = [],
        selectedMealType: MealType? = nil
    ) throws -> MealModelHarness {
        let service = MealRegistrationServiceSpy(
            detectedRequest: detectedMealRequest,
            proposalResponse: pendingResponse,
            proposeOutcomes: proposeOutcomes ?? [.success(pendingResponse)],
            editOutcomes: editOutcomes,
            confirmOutcomes: confirmOutcomes,
            cancelOutcomes: cancelOutcomes
        )
        let center = FeatureInvalidationCenter()
        let model = MealRegistrationModel(
            detector: service,
            registration: service,
            timeProvider: FixedTimeProvider(value: fixedDate),
            keyProvider: DeterministicIdempotencyKeyProvider(
                prefix: "meal-model-key"
            ),
            invalidationCenter: center,
            demonstrationTextLimit: 1...1_000,
            selectedMealType: selectedMealType
        )
        return MealModelHarness(
            model: model,
            service: service,
            invalidationCenter: center
        )
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_784_589_300)

    private static let detectedMealRequest = RegistrationProposalRequest.meal(
        MealProposalRequest(
            mealType: .lunch,
            items: [
                MealProposalItemRequest(
                    foodName: "Refeição detectada",
                    quantityG: 180,
                    userKcal: nil
                ),
            ],
            consumedAt: APITimestamp(value: fixedDate)
        )
    )

    private static let alternateDetectedMealRequest = RegistrationProposalRequest.meal(
        MealProposalRequest(
            mealType: .snack,
            items: [
                MealProposalItemRequest(
                    foodName: "Segunda detecção",
                    quantityG: 95,
                    userKcal: nil
                ),
            ],
            consumedAt: APITimestamp(value: fixedDate)
        )
    )

    private static let editedMealRequest = MealProposalRequest(
        mealType: .dinner,
        items: [
            MealProposalItemRequest(
                foodName: "Refeição editada",
                quantityG: 205,
                userKcal: 512
            ),
        ],
        consumedAt: APITimestamp(value: fixedDate.addingTimeInterval(600))
    )

    private static let editTo100gRequest = MealProposalRequest(
        mealType: .lunch,
        items: [
            MealProposalItemRequest(
                foodName: "Arroz",
                quantityG: 100,
                userKcal: nil
            ),
        ],
        consumedAt: APITimestamp(value: fixedDate)
    )

    private static let pending200gResponse = RegistrationProposalResponse(
        data: RegistrationSnapshot(
            id: "meal-pending-200g",
            status: "pending",
            createdAt: APITimestamp(value: fixedDate),
            expiresAt: APITimestamp(
                value: fixedDate.addingTimeInterval(3_600)
            ),
            resolvedAt: nil,
            proposal: .meal(
                MealProposalSnapshot(
                    mealType: "almoco",
                    items: [
                        MealProposalItemSnapshot(
                            name: "Arroz",
                            quantityG: 200,
                            kcal: 260,
                            proteinG: 5,
                            carbsG: 56,
                            fatG: 0.4
                        ),
                    ],
                    totals: MealProposalTotalsSnapshot(
                        kcal: 260,
                        proteinG: 5,
                        carbsG: 56,
                        fatG: 0.4
                    ),
                    warnings: []
                )
            )
        ),
        meta: MobileResponseMetadata(
            apiVersion: "v1",
            requestID: "meal-pending-200g-request"
        )
    )

    private static let pendingResponse = RegistrationProposalResponse(
        data: RegistrationSnapshot(
            id: "meal-pending-1",
            status: "pending",
            createdAt: APITimestamp(value: fixedDate),
            expiresAt: APITimestamp(
                value: fixedDate.addingTimeInterval(3_600)
            ),
            resolvedAt: nil,
            proposal: .meal(
                MealProposalSnapshot(
                    mealType: "almoco",
                    items: [
                        MealProposalItemSnapshot(
                            name: "Refeição detectada",
                            quantityG: 180,
                            kcal: 389,
                            proteinG: 27,
                            carbsG: 45,
                            fatG: 11
                        ),
                    ],
                    totals: MealProposalTotalsSnapshot(
                        kcal: 389,
                        proteinG: 27,
                        carbsG: 45,
                        fatG: 11
                    ),
                    warnings: ["Confirme antes de registrar."]
                )
            )
        ),
        meta: MobileResponseMetadata(
            apiVersion: "v1",
            requestID: "meal-pending-request"
        )
    )

    private static let editedResponse = RegistrationProposalResponse(
        data: RegistrationSnapshot(
            id: pendingResponse.data.id,
            status: "pending",
            createdAt: pendingResponse.data.createdAt,
            expiresAt: pendingResponse.data.expiresAt,
            resolvedAt: nil,
            proposal: .meal(
                MealProposalSnapshot(
                    mealType: "jantar",
                    items: [
                        MealProposalItemSnapshot(
                            name: "Substituição completa",
                            quantityG: 205,
                            kcal: 512,
                            proteinG: 33,
                            carbsG: 52,
                            fatG: 19
                        ),
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
        ),
        meta: MobileResponseMetadata(
            apiVersion: "v1",
            requestID: "meal-edited-request"
        )
    )

    private static let cancelledResponse = RegistrationCancellationResponse(
        data: RegistrationSnapshot(
            id: pendingResponse.data.id,
            status: "cancelled",
            createdAt: pendingResponse.data.createdAt,
            expiresAt: pendingResponse.data.expiresAt,
            resolvedAt: APITimestamp(value: fixedDate.addingTimeInterval(120)),
            proposal: pendingResponse.data.proposal
        ),
        meta: MobileResponseMetadata(
            apiVersion: "v1",
            requestID: "meal-cancelled-request"
        )
    )

    private static let confirmedResponse = DemoBodyFlowFixtures
        .confirmedMealRegistration

    private static let confirmedStatusProposalResponse = RegistrationProposalResponse(
        data: RegistrationSnapshot(
            id: pendingResponse.data.id,
            status: "confirmed",
            createdAt: pendingResponse.data.createdAt,
            expiresAt: pendingResponse.data.expiresAt,
            resolvedAt: APITimestamp(value: fixedDate),
            proposal: pendingResponse.data.proposal
        ),
        meta: MobileResponseMetadata(apiVersion: "v1", requestID: "confirmed-status")
    )
}

@MainActor
private struct MealModelHarness {
    let model: MealRegistrationModel
    let service: MealRegistrationServiceSpy
    let invalidationCenter: FeatureInvalidationCenter
}

private enum MealServiceOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(BodyFlowCapabilityError)

    func get() throws -> Value {
        switch self {
        case let .success(value):
            value
        case let .failure(error):
            throw error
        }
    }
}

private actor MealRegistrationServiceSpy:
    MealDetectionProviding,
    RegistrationProviding
{
    enum Call: Equatable, Sendable {
        case detect(MealDetectionInput)
        case propose
        case edit
        case confirm
        case cancel
    }

    private let detectedRequest: RegistrationProposalRequest
    private let proposalResponse: RegistrationProposalResponse
    private var proposeOutcomes: [MealServiceOutcome<RegistrationProposalResponse>]
    private var editOutcomes: [MealServiceOutcome<RegistrationProposalResponse>]
    private var confirmOutcomes: [MealServiceOutcome<RegistrationConfirmationResponse>]
    private var cancelOutcomes: [MealServiceOutcome<RegistrationCancellationResponse>]
    private(set) var calls: [Call] = []
    private(set) var proposeAttempts: [MutationAttempt<RegistrationProposalRequest>] = []
    private(set) var editAttempts: [MutationAttempt<RegistrationEditCommand>] = []
    private(set) var confirmAttempts: [MutationAttempt<RegistrationIDCommand>] = []
    private(set) var cancelAttempts: [MutationAttempt<RegistrationIDCommand>] = []

    init(
        detectedRequest: RegistrationProposalRequest,
        proposalResponse: RegistrationProposalResponse,
        proposeOutcomes: [MealServiceOutcome<RegistrationProposalResponse>]? = nil,
        editOutcomes: [MealServiceOutcome<RegistrationProposalResponse>] = [],
        confirmOutcomes: [MealServiceOutcome<RegistrationConfirmationResponse>] = [],
        cancelOutcomes: [MealServiceOutcome<RegistrationCancellationResponse>] = []
    ) {
        self.detectedRequest = detectedRequest
        self.proposalResponse = proposalResponse
        self.proposeOutcomes = proposeOutcomes ?? [.success(proposalResponse)]
        self.editOutcomes = editOutcomes
        self.confirmOutcomes = confirmOutcomes
        self.cancelOutcomes = cancelOutcomes
    }

    func detect(
        _ input: MealDetectionInput
    ) async throws -> RegistrationProposalRequest {
        calls.append(.detect(input))
        return detectedRequest
    }

    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws -> RegistrationProposalResponse {
        calls.append(.propose)
        proposeAttempts.append(attempt)
        guard !proposeOutcomes.isEmpty else { return proposalResponse }
        return try proposeOutcomes.removeFirst().get()
    }

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws -> RegistrationProposalResponse {
        calls.append(.edit)
        editAttempts.append(attempt)
        guard !editOutcomes.isEmpty else { return proposalResponse }
        return try editOutcomes.removeFirst().get()
    }

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationConfirmationResponse {
        calls.append(.confirm)
        confirmAttempts.append(attempt)
        guard !confirmOutcomes.isEmpty else {
            throw BodyFlowCapabilityError.invalidInput
        }
        return try confirmOutcomes.removeFirst().get()
    }

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationCancellationResponse {
        calls.append(.cancel)
        cancelAttempts.append(attempt)
        guard !cancelOutcomes.isEmpty else { return proposalResponse }
        return try cancelOutcomes.removeFirst().get()
    }
}

private actor ImmediateMealDetector: MealDetectionProviding {
    private let request: RegistrationProposalRequest
    private(set) var inputs: [MealDetectionInput] = []

    init(request: RegistrationProposalRequest) {
        self.request = request
    }

    func detect(
        _ input: MealDetectionInput
    ) async throws -> RegistrationProposalRequest {
        inputs.append(input)
        return request
    }
}

private actor ControlledMealDetector: MealDetectionProviding {
    private var continuations: [
        Int: CheckedContinuation<RegistrationProposalRequest, Error>
    ] = [:]
    private(set) var inputs: [MealDetectionInput] = []

    func detect(
        _ input: MealDetectionInput
    ) async throws -> RegistrationProposalRequest {
        inputs.append(input)
        let call = inputs.count
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitUntilStarted(_ count: Int) async {
        while inputs.count < count {
            await Task.yield()
        }
    }

    func succeed(
        call: Int,
        with request: RegistrationProposalRequest
    ) {
        continuations.removeValue(forKey: call)?.resume(returning: request)
    }

    func fail(call: Int, with error: BodyFlowCapabilityError) {
        continuations.removeValue(forKey: call)?.resume(throwing: error)
    }
}

private actor ReentrantMealDetector: MealDetectionProviding {
    private let request: RegistrationProposalRequest
    private var duplicateSubmission: (@MainActor @Sendable () async -> Void)?
    private(set) var inputs: [MealDetectionInput] = []

    init(request: RegistrationProposalRequest) {
        self.request = request
    }

    func setDuplicateSubmission(
        _ duplicateSubmission: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.duplicateSubmission = duplicateSubmission
    }

    func detect(
        _ input: MealDetectionInput
    ) async throws -> RegistrationProposalRequest {
        inputs.append(input)
        if inputs.count == 1, let duplicateSubmission {
            await duplicateSubmission()
        }
        return request
    }
}

private actor SuspendingMealRegistrationService: RegistrationProviding {
    private let response: RegistrationProposalResponse
    private var proposeContinuations: [
        Int: CheckedContinuation<RegistrationProposalResponse, Error>
    ] = [:]
    private(set) var proposeAttempts: [
        MutationAttempt<RegistrationProposalRequest>
    ] = []

    init(response: RegistrationProposalResponse) {
        self.response = response
    }

    var proposeCallCount: Int {
        proposeAttempts.count
    }

    func propose(
        _ attempt: MutationAttempt<RegistrationProposalRequest>
    ) async throws -> RegistrationProposalResponse {
        proposeAttempts.append(attempt)
        let call = proposeAttempts.count
        return try await withCheckedThrowingContinuation { continuation in
            proposeContinuations[call] = continuation
        }
    }

    func waitUntilProposeStarted(_ count: Int) async {
        while proposeAttempts.count < count {
            await Task.yield()
        }
    }

    func succeedPropose(call: Int) {
        proposeContinuations.removeValue(forKey: call)?.resume(returning: response)
    }

    func edit(
        _ attempt: MutationAttempt<RegistrationEditCommand>
    ) async throws -> RegistrationProposalResponse {
        throw BodyFlowCapabilityError.invalidInput
    }

    func confirm(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationConfirmationResponse {
        throw BodyFlowCapabilityError.invalidInput
    }

    func cancel(
        _ attempt: MutationAttempt<RegistrationIDCommand>
    ) async throws -> RegistrationCancellationResponse {
        throw BodyFlowCapabilityError.invalidInput
    }
}

extension MealRegistrationModelTests {
    @Test("A reviewed meal is proposed as it is, without detection, and is not confirmed")
    func reviewedMealIsProposedWithoutDetection() async throws {
        let harness = try Self.makeHarness()
        let reviewed = MealProposalRequest(
            mealType: .snack,
            items: [MealProposalItemRequest(
                foodName: "iogurte natural", quantityG: 170, userKcal: nil,
                quantityBasis: .visualEstimate, candidateID: "c1-0a1b2c3d"
            )],
            consumedAt: nil,
            source: MealProposalSource(
                channel: .gallery,
                mediaAssetID: "0a0a0a0a-1111-4222-8333-444455556666"
            )
        )

        await harness.model.propose(reviewed: reviewed)

        #expect(await harness.service.calls == [.propose])
        #expect(harness.model.detectedDraft == .meal(reviewed))
        #expect(harness.model.currentProposal?.status == "pending")
        #expect(harness.model.phase == .proposal)
        #expect(harness.model.confirmedRegistration == nil)
    }
}

extension MealRegistrationModelTests {
    private static var reviewedMeal: MealProposalRequest {
        MealProposalRequest(
            mealType: .lunch,
            items: [MealProposalItemRequest(
                foodName: "arroz", quantityG: 120, userKcal: nil, quantityBasis: .stated
            )],
            consumedAt: nil,
            source: MealProposalSource(channel: .text, mediaAssetID: nil)
        )
    }

    @Test("After a cancelled proposal the same sheet proposes the reviewed meal again")
    func reviewedMealAfterCancelledProposal() async throws {
        let harness = try Self.makeHarness(
            proposeOutcomes: [.success(Self.pendingResponse), .success(Self.pendingResponse)],
            cancelOutcomes: [.success(Self.pendingResponse)]
        )
        await harness.model.propose(reviewed: Self.reviewedMeal)
        await harness.model.cancel()
        #expect(harness.model.phase == .cancelled)

        await harness.model.propose(reviewed: Self.reviewedMeal)

        #expect(await harness.service.calls == [.propose, .cancel, .propose])
        #expect(harness.model.phase == .proposal)
    }

    @Test("The same reviewed meal sent again after a failure is the same request")
    func reviewedMealResentKeepsItsKey() async throws {
        let harness = try Self.makeHarness(
            proposeOutcomes: [.failure(.offline), .success(Self.pendingResponse)]
        )
        await harness.model.propose(reviewed: Self.reviewedMeal)
        #expect(harness.model.phase == .capture)

        await harness.model.propose(reviewed: Self.reviewedMeal)

        let keys = await harness.service.proposeAttempts.map(\.key)
        #expect(keys.count == 2)
        #expect(Set(keys).count == 1)
        #expect(harness.model.phase == .proposal)
    }
}

enum AlreadySavedOperation: Sendable {
    case edit
    case cancel
}
