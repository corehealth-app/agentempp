#if DEBUG
import Foundation
import Observation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup composition caller cancellation before D1 and before adoption", .serialized)
struct SignupBodyPhotoDeleteCompositionCancellationPrefixTests {
    @Test("CC01 a canceled caller retains a recoverable intent; ready recovery only adopts",
        arguments: SignupDeleteCompositionCancelPrefix.allCases)
    func callerCancellationHasRecoverableParentIntent(_ prefix: SignupDeleteCompositionCancelPrefix) async throws {
        let h = try await SignupDeleteCompositionHarness()
        defer { h.removeFolder() }
        try await h.prepare()
        let oldCapture = try #require(h.model.capture)
        let baseline = await h.photos.report()
        let callerBox = SignupDeleteCompositionCancelCallerBox()
        let reloadGate: CaptureConsentGate? = prefix == .ready ? CaptureConsentGate(holds: true) : nil

        if prefix == .idle {
            // This callback cancels synchronously while beginBodyPhotoDeletion
            // publishes the Flow blocker, before the retained parent work runs.
            withObservationTracking { _ = h.flow.hasPendingBodyPhotoDeletion } onChange: {
                callerBox.cancel()
            }
        } else if let reloadGate {
            await h.photos.holdReload(reloadGate)
        }

        let caller = Task { @MainActor in
            await h.model.deletePhotos()
            await reloadGate?.operationFinished()
        }
        // There is no await between creating this MainActor task and installing
        // it. The observer cannot run before the locked box owns its caller.
        callerBox.install(caller)

        do {
            if let reloadGate {
                let entered = await reloadGate.entryOrOperationEnd()
                if !entered { await reloadGate.release(); await caller.value }
                try #require(entered, "Ready control must hold the actual post-DELETE GET")
                let controller = try #require(h.model.deletion)
                #expect(controller.phase == .awaitingReload)
                // Register only after D1 started. The next phase publication
                // cancels the parent at ready, before it can adopt the capture.
                withObservationTracking { _ = controller.phase } onChange: {
                    callerBox.cancel()
                }
                await reloadGate.release()
                await caller.value
            } else {
                await caller.value
            }

            let controller = try #require(h.model.deletion)
            #expect(callerBox.cancellationCount == 1)
            #expect(h.flow.hasPendingBodyPhotoDeletion)
            #expect(h.model.capture === oldCapture)
            let beforeRetry = await h.photos.report()
            switch prefix {
            case .idle:
                #expect(controller.phase == .idle && controller.receipt == nil)
                #expect(controller.captureModel === oldCapture && oldCapture.isActive)
                #expect(beforeRetry.attempts.isEmpty && beforeRetry.postDeleteReads == 0)
                #expect(beforeRetry.stateReads == baseline.stateReads)
            case .ready:
                #expect(controller.phase == .ready)
                #expect(controller.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
                #expect(controller.captureModel.state != nil)
                #expect(controller.captureModel !== oldCapture && !oldCapture.isActive)
                #expect(beforeRetry.attempts.count == 1 && beforeRetry.postDeleteReads == 1)
                #expect(beforeRetry.stateReads == baseline.stateReads + 1)
            }
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            #expect(await h.factory.snapshot() == [h.owner.userID])

            await h.model.retryDeletion()
            let adopted = try #require(h.model.capture)
            #expect(h.model.deletion === controller && controller.phase == .ready)
            #expect(adopted === controller.captureModel && adopted !== oldCapture)
            #expect(adopted.isActive && adopted.state != nil)
            #expect(controller.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
            #expect(!h.flow.hasPendingBodyPhotoDeletion)
            let afterRetry = await h.photos.report()
            #expect(afterRetry.attempts.count == 1 && afterRetry.postDeleteReads == 1)
            #expect(afterRetry.stateReads == baseline.stateReads + 1)
            #expect(afterRetry.repairs == 0)
            if prefix == .ready {
                #expect(afterRetry.attempts == beforeRetry.attempts)
                #expect(afterRetry.stateReads == beforeRetry.stateReads)
                #expect(afterRetry.postDeleteReads == beforeRetry.postDeleteReads)
            }
            #expect(await h.factory.snapshot() == [h.owner.userID])
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            try await h.drain()
        } catch {
            await reloadGate?.release()
            caller.cancel()
            await caller.value
            try await h.drain()
            throw error
        }
    }
}
#endif
