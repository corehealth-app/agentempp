#if DEBUG
import Foundation
import Observation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup explicit delete + presentation + real Flow composition", .serialized)
struct SignupBodyPhotoDeleteCompositionTests {
    @Test("C01 explicit deletion revokes photo proof before await and preserves independently typed BF",
        arguments: SignupCompositionOrigin.allCases)
    func pendingPrefixPreservesTypedAndRevokesPhoto(_ origin: SignupCompositionOrigin) async throws {
        let h = try await SignupDeleteCompositionHarness(holdPUT: true)
        defer { h.removeFolder() }
        try await h.prepare()
        if origin == .photos {
            let confirmed = h.model.confirmEstimate()
            try #require(confirmed)
        }
        let before = h.flow.draft, capture = try #require(h.model.capture)
        let control = try h.staging.stage(Data("composition-control".utf8), fileExtension: "jpg")
        let sending = Task {
            await capture.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.putGate.operationFinished()
        }
        let putEntered = await h.putGate.entryOrOperationEnd()
        try #require(putEntered)
        let drain = CaptureConsentGate()
        withObservationTracking { _ = capture.isActive } onChange: { Task { await drain.enter() } }
        let deleting = h.begin(ending: [drain])
        let drainEntered = await drain.entryOrOperationEnd()
        #expect(drainEntered, "Composition must reach the real D0 before waiting for the old PUT")
        #expect(h.model.deletion?.phase == .draining)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(h.flow.draft.bodyFatPercent == (origin == .typed ? before.bodyFatPercent : nil))
        #expect(h.flow.draft.bodyFatOrigin == (origin == .typed ? .typed : nil))
        #expect(h.flow.draft.heightCM == before.heightCM && h.flow.draft.weightKG == before.weightKG)
        let sent = await h.photos.report()
        #expect(sent.attempts.isEmpty)
        let oldStep = h.flow.step, calls = await h.flowPeer.report()
        await h.flow.continueFromCurrentStep()
        let blocked = await h.flowPeer.report()
        #expect(h.flow.step == oldStep && blocked == calls, "No advance while deletion is draining, even with no photo origin")
        await h.putGate.release()
        await sending.value
        await deleting.value
        #expect(h.model.deletion?.phase == .ready)
        #expect(FileManager.default.fileExists(atPath: control.path))
        try await h.drain()
    }

    @Test("C02 guards actual Flow advance/eligibility/complete; saving excludes beginning DELETE",
        arguments: SignupCompositionFlowAction.allCases)
    func actualFlowOperationsAreBlocked(_ action: SignupCompositionFlowAction) async throws {
        let step: OnboardingStep = action == .eligibility ? .objective : (action == .completion ? .completion : .bodyData)
        let h = try await SignupDeleteCompositionHarness(step: step)
        defer { h.removeFolder() }
        try await h.prepare()
        try #require(h.flow.step == step, "Valid Flow stage is a prerequisite, never a zero-call proof")
        if action == .completion { try #require(h.flow.hasCurrentEligibilityDecision) }
        if action == .saving {
            let save = CaptureConsentGate(holds: true)
            await h.flowPeer.holdSave(save)
            let advancing = Task { await h.flow.continueFromCurrentStep(); await save.operationFinished() }
            let entered = await save.entryOrOperationEnd()
            try #require(entered)
            #expect(h.flow.operationState == .saving)
            await h.model.deletePhotos()
            let report = await h.photos.report()
            #expect(report.attempts.isEmpty && h.flow.operationState == .saving)
            await save.release(); await advancing.value
            try await h.drain()
            return
        }
        let gate = CaptureConsentGate(holds: true)
        await h.photos.holdDelete(gate)
        let deleting = h.begin(ending: [gate])
        let entered = await gate.entryOrOperationEnd()
        if !entered { await deleting.value; try await h.drain() }
        try #require(entered, "Missing composition action is semantic RED, not a fake repository zero-call")
        let before = await h.flowPeer.report(), oldStep = h.flow.step
        switch action {
        case .advance: await h.flow.continueFromCurrentStep()
        case .eligibility: await h.flow.prepareObjectiveIfNeeded()
        case .completion: await h.flow.complete()
        case .saving: break
        }
        let pending = await h.flowPeer.report()
        #expect(pending == before && h.flow.step == oldStep)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        await gate.release(); await deleting.value
        #expect(h.model.deletion?.phase == .ready)
        switch action {
        case .advance: await h.flow.continueFromCurrentStep()
        case .eligibility: await h.flow.prepareObjectiveIfNeeded()
        case .completion: await h.flow.complete()
        case .saving: break
        }
        let control = await h.flowPeer.report()
        switch action {
        case .advance: #expect(control.saves == before.saves + 1 && h.flow.step != oldStep)
        case .eligibility: #expect(control.eligibility == before.eligibility + 1 && h.flow.hasCurrentEligibilityDecision)
        case .completion: #expect(control.completions == before.completions + 1, "Rejecting boundary is reached; no success ACK fabricated")
        case .saving: break
        }
        try await h.drain()
    }

    @Test("C03 failed cleanup/DELETE/GET retains pending state; exact retry never ACKs cleanup debt",
        arguments: SignupCompositionRecovery.allCases)
    func failedRecoveryRetainsBlockerAndReceiptRules(_ recovery: SignupCompositionRecovery) async throws {
        let h = try await SignupDeleteCompositionHarness(recovery: recovery)
        defer { h.removeFolder() }
        try await h.prepare()
        let capture = try #require(h.model.capture)
        if recovery == .cleanup {
            await capture.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            try #require(capture.phase == .failed(.offline))
        }
        let store = h.cleanup.store, owner = h.owner.userID
        try store.mutate(for: owner) { queue in
            _ = try queue.observePending(CleanupProcessorHarness.g1, newRevision: UUID())
            _ = queue.rememberUnbound(CleanupProcessorHarness.marker)
        }
        let queueBefore = try store.load(for: owner)
        if recovery == .reload {
            let heldRead = CaptureConsentGate(holds: true)
            await h.photos.holdReload(heldRead)
            let deleting = h.begin(ending: [heldRead])
            let entered = await heldRead.entryOrOperationEnd()
            if !entered { await deleting.value; try await h.drain() }
            try #require(entered)
            #expect(h.model.deletion?.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
            #expect(h.model.deletion?.phase == .awaitingReload)
            let before = await h.flowPeer.report(), oldStep = h.flow.step
            await h.flow.continueFromCurrentStep()
            let unchanged = await h.flowPeer.report()
            #expect(unchanged == before && h.flow.step == oldStep, "A known receipt does not finish GET recovery")
            await heldRead.release(); await deleting.value
        } else { await h.model.deletePhotos() }
        let d1 = try #require(h.model.deletion, "D1 composition must exist once an explicit action was made")
        if case .failed = d1.phase {} else { Issue.record("Recovery must expose the actual failure") }
        let failed = await h.photos.report(), before = await h.flowPeer.report(), step = h.flow.step
        await h.flow.continueFromCurrentStep()
        let stillBlocked = await h.flowPeer.report()
        #expect(stillBlocked == before && h.flow.step == step)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        if recovery == .cleanup { #expect(failed.attempts.isEmpty) }
        if recovery == .reload { #expect(d1.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0)) }
        await h.model.retryDeletion()
        let completed = await h.photos.report(), fileCalls = await h.filePeer.attemptedFiles()
        #expect(h.model.deletion === d1 && d1.phase == .ready)
        let queueAfter = try store.load(for: owner)
        #expect(completed.repairs == 0 && queueAfter == queueBefore)
        switch recovery {
        case .cleanup:
            #expect(completed.attempts.count == 1 && fileCalls.count == 2)
            if fileCalls.count == 2 { #expect(fileCalls[0] == fileCalls[1]) }
        case .deleteReply:
            #expect(completed.attempts.count == 2 && completed.attempts.first == completed.attempts.last)
        case .reload:
            #expect(completed.attempts == failed.attempts && completed.postDeleteReads == failed.postDeleteReads + 1)
        }
        #expect(d1.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
        try await h.drain()
    }

    @Test("C04 adopt D1 Capture once; no lease/load duplication and real manual-clock poll reaches observer")
    func replacementKeepsOneScopeClockAndObserver() async throws {
        let h = try await SignupDeleteCompositionHarness(readingAfterDelete: true)
        defer { h.removeFolder() }
        try await h.prepare()
        let confirmedBeforeDeletion = h.model.confirmEstimate()
        try #require(confirmedBeforeDeletion)
        let old = try #require(h.model.capture)
        let initial = await h.photos.report()
        await h.model.deletePhotos()
        let d1 = try #require(h.model.deletion)
        let adopted = try #require(h.model.capture)
        #expect(d1.phase == .ready && adopted === d1.captureModel && adopted !== old && !old.isActive)
        let calls = await h.factory.snapshot(), after = await h.photos.report()
        #expect(calls == [h.owner.userID] && after.stateReads == initial.stateReads + 1)
        #expect(after.attempts.count == 1 && after.repairs == 0)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        // Model event proves the task actually armed; it does not claim registration.
        let armed = await adopted.waitForPollingEvent()
        try #require(armed)
        let registered = await h.clock.waitForRegistrations(1)
        try #require(registered, "D1 must forward the injected clock, not silently use live timing")
        let sleepers = await h.clock.pendingCount
        #expect(sleepers == 1)
        await h.clock.advance(by: .milliseconds(1_500))
        let stopped = await adopted.waitForPollingEvent(untilStopped: true)
        try #require(stopped)
        let terminal = await h.photos.report()
        #expect(terminal.stateReads == after.stateReads + 1 && adopted.phase == .ready)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        let confirmedAfterPoll = h.model.confirmEstimate()
        #expect(confirmedAfterPoll, "Actual terminal publication must authorize the adopted presentation capture")
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
        #expect(h.flow.draft.bodyPhotoConfirmation?.sourceIDs.front == "00000000-0000-4000-8000-000000002001")
        // A later explicit Core refresh keeps canonical24 but changes IDs.
        // Only the forwarded real observer can reconcile this proof; no
        // Presentation/Flow control or callback is invoked manually here.
        await h.photos.restoreOriginalReadIDs()
        await adopted.load()
        #expect(adopted.state?.estimate?.sourceIDs?.front == PresentationPhotoPeer.ids[0])
        #expect(h.flow.draft.bodyPhotoConfirmation == nil && h.flow.draft.bodyFatPercent == nil)
        #expect(h.flow.draft.bodyFatOrigin == nil)
        let refreshed = await h.photos.report()
        #expect(refreshed.stateReads == terminal.stateReads + 1)
        let active = await h.cleanup.registry.activeCount
        #expect(active == 0)
        try await h.drain()
    }

    @Test("C05 old delayed GET is inert for A→B and A→B→A; new owner remains blocked",
        arguments: SignupCompositionOwnerChange.allCases)
    func obsoleteRestoreCannotAdoptOrUnblockAnotherFlow(_ change: SignupCompositionOwnerChange) async throws {
        let h = try await SignupDeleteCompositionHarness()
        defer { h.removeFolder() }
        try await h.prepare()
        let oldCapture = try #require(h.model.capture), oldDraft = h.flow.draft
        let oldRead = CaptureConsentGate(holds: true)
        await h.photos.holdReload(oldRead)
        let oldDelete = h.begin(ending: [oldRead])
        let entered = await oldRead.entryOrOperationEnd()
        if !entered { await oldDelete.value; try await h.drain() }
        try #require(entered)
        let b = OnboardingOwnerToken(userID: CleanupProcessorHarness.b, restoreGeneration: 2)
        h.ownerBox.current = b
        let nextOwner: OnboardingOwnerToken
        if change == .restore {
            nextOwner = .init(userID: h.owner.userID, restoreGeneration: 3)
            h.ownerBox.current = nextOwner
        } else { nextOwner = b }
        if change == .restore {
            let repository = SignupCompositionOnboardingPeer()
            let newFlow = SignupDeleteCompositionHarness.makeFlow(owner: nextOwner, peer: repository, step: .bodyData)
            let factory = PresentationFactoryPeer(scope: h.scope)
            let newModel = SignupDeleteCompositionHarness.makeModel(flow: newFlow, owner: nextOwner,
                box: h.ownerBox, factory: factory, clock: h.clock, prefix: "composition-restored")
            await newModel.load(); newModel.select(.photos); await newModel.acceptConsent()
            let gate = CaptureConsentGate(holds: true)
            await h.photos.holdDelete(gate)
            let fresh = Task { await newModel.deletePhotos(); await gate.operationFinished() }
            let freshEntered = await gate.entryOrOperationEnd()
            if !freshEntered {
                await oldRead.release(); await oldDelete.value; await fresh.value
                newModel.invalidate(); try await h.drain()
            }
            try #require(freshEntered)
            await oldRead.release(); await oldDelete.value
            let before = await repository.report(), step = newFlow.step
            await newFlow.continueFromCurrentStep()
            let unchanged = await repository.report()
            #expect(unchanged == before && newFlow.step == step)
            #expect(newFlow.draft.bodyFatPercent == 24 && newFlow.draft.bodyFatOrigin == .typed)
            await gate.release(); await fresh.value
            newModel.invalidate()
            if let capture = newModel.capture { await capture.invalidateAndWaitForOwnedCaptureWork(); try await capture.waitForLocalCleanup() }
        } else {
            await oldRead.release(); await oldDelete.value
        }
        #expect(h.model.capture === oldCapture && !oldCapture.isActive)
        let obsoleteConfirmation = h.model.confirmEstimate()
        #expect(h.flow.draft == oldDraft && !obsoleteConfirmation)
        let factoryCalls = await h.factory.snapshot()
        #expect(factoryCalls == [h.owner.userID])
        try await h.drain()
    }

    @Test("C06 mode refresh retains uncertain D1 attempt; nil producer/select never compensate with DELETE")
    func pendingModeRefreshDoesNotResetAttempt() async throws {
        let h = try await SignupDeleteCompositionHarness(recovery: .deleteReply)
        defer { h.removeFolder() }
        try await h.prepare()
        h.model.select(.typed)
        let idle = await h.photos.report()
        #expect(idle.attempts.isEmpty && idle.repairs == 0)
        h.model.select(.photos)
        await h.model.load(); await h.model.acceptConsent()
        await h.model.deletePhotos()
        let d1 = try #require(h.model.deletion)
        let failed = await h.photos.report()
        #expect(failed.attempts.count == 1 && d1.receipt == nil)
        await d1.producePhoto(pose: .front, channel: .gallery) { nil }
        h.model.select(.typed)
        await h.model.load()
        let refreshed = await h.photos.report()
        #expect(h.model.deletion === d1 && refreshed.attempts == failed.attempts)
        #expect(refreshed.stateReads == failed.stateReads && refreshed.repairs == 0)
        let before = await h.flowPeer.report(), step = h.flow.step
        await h.flow.continueFromCurrentStep()
        let blocked = await h.flowPeer.report()
        #expect(blocked == before && h.flow.step == step)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        await h.model.retryDeletion()
        let final = await h.photos.report()
        #expect(final.attempts.count == 2 && final.attempts.first == final.attempts.last)
        #expect(h.model.deletion === d1 && d1.phase == .ready && final.repairs == 0)
        try await h.drain()
    }
}
#endif
