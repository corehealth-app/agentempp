#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

// Tests-only addon: R2's runtime scaffold/support/six methods are unchanged.
@Suite("Signup explicit deletion remaining causal gates R3")
@MainActor
struct SignupBodyPhotoExplicitDeletionRemainingTests {
    @Test("Failed own cleanup prevents first DELETE; retry uses the same URL and finishes")
    func localCleanupBlocksDeleteAndRetriesExactOwnedFile() async throws {
        let h = ExplicitDeleteR3Harness(failCreateOnce: true, failCleanupOnce: true)
        defer { h.clean() }
        await h.prepare()
        let control = try h.staging.stage(Data("unrelated-owned-control".utf8), fileExtension: "jpg")
        await h.original.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        #expect(h.original.phase == .failed(.offline))
        let staged = try FileManager.default.contentsOfDirectory(at: h.staging.root, includingPropertiesForKeys: nil)
        #expect(staged.count == 2)
        await h.model.deletePhotos()
        #expect(h.model.phase == .failed(.unavailable) && !h.model.canCapture && h.model.receipt == nil)
        let beforeRetry = await h.photos.attempts(), failedFiles = await h.cleanup.attemptedFiles()
        #expect(beforeRetry.isEmpty && failedFiles.count == 1)
        let ownedFile = try #require(failedFiles.first)
        #expect(FileManager.default.fileExists(atPath: ownedFile.path))
        #expect(FileManager.default.fileExists(atPath: control.path))
        await h.model.retryDeletion()
        let files = await h.cleanup.attemptedFiles(), sent = await h.photos.attempts()
        #expect(files == [ownedFile, ownedFile], "Retry must discard the same retained URL, without a global purge")
        #expect(!FileManager.default.fileExists(atPath: ownedFile.path))
        #expect(FileManager.default.fileExists(atPath: control.path))
        #expect(sent.count == 1 && h.model.receipt == SignupBodyPhotoDeleteReceipt(deleted: 3))
        #expect(h.model.phase == .ready && h.model.canCapture)
        let reads = await h.inner.report(), work = await h.registry.report()
        #expect(reads.postDeleteReads == 1 && reads.repairCalls == 0)
        #expect(work.active.isEmpty && work.finished == work.begun)
    }

    @Test("Concurrent delete/retry do not create another live DELETE", arguments: ExplicitDeleteR3LiveRequest.allCases)
    func concurrentCallsShareOneLiveRequest(_ mode: ExplicitDeleteR3LiveRequest) async throws {
        let h = ExplicitDeleteR3Harness(uncertainFirst: mode == .retryAfterUncertain ? .offline : nil)
        defer { h.clean() }
        await h.prepare()
        if mode == .retryAfterUncertain {
            await h.model.deletePhotos()
            #expect(h.model.phase == .failed(.offline) && h.model.receipt == nil)
        }
        let previous = await h.photos.attempts()
        let heldDelete = CaptureConsentGate(holds: true), completion = ExplicitDeleteCompletion()
        await h.photos.armNextDelete(heldDelete)
        let first = h.begin(retry: mode == .retryAfterUncertain, completion: completion, ended: heldDelete)
        let requestEntered = await heldDelete.entryOrOperationEnd()
        #expect(requestEntered && !completion.finished && !h.model.canCapture)
        let deleteCaller = CaptureConsentGate(), retryCaller = CaptureConsentGate()
        let concurrentDelete = h.beginConcurrent(retry: false, entered: deleteCaller)
        let concurrentRetry = h.beginConcurrent(retry: true, entered: retryCaller)
        _ = await deleteCaller.entryOrOperationEnd()
        _ = await retryCaller.entryOrOperationEnd()
        let held = await h.photos.attempts(), active = await h.registry.report()
        #expect(held.count == previous.count + 1 && active.active.count == 1)
        #expect(h.model.receipt == nil && !h.model.canCapture)
        await heldDelete.release()
        await first.value
        await concurrentDelete.value
        await concurrentRetry.value
        let done = await h.photos.attempts(), reads = await h.inner.report(), work = await h.registry.report()
        #expect(done.count == previous.count + 1, "Busy calls may join or return, never schedule a second DELETE afterwards")
        if let old = previous.first { #expect(done.last == old) }
        #expect(reads.postDeleteReads == 1 && reads.repairCalls == 0)
        #expect(h.model.phase == .ready && h.model.canCapture && completion.finished)
        #expect(work.active.isEmpty && work.finished == work.begun)
    }

    @Test("Receipt and GET remain unpublished until registry finish; late obsolete owners stay inert",
        arguments: ExplicitDeleteR3FinishOutcome.allCases)
    func receiptWaitsForRegistryFinish(_ outcome: ExplicitDeleteR3FinishOutcome) async throws {
        let h = ExplicitDeleteR3Harness()
        defer { h.clean() }
        await h.prepare()
        let baseline = await h.registry.report()
        let finish = CaptureConsentGate(holds: true), completion = ExplicitDeleteCompletion()
        await h.registry.armNextFinish(finish)
        let deleting = h.begin(retry: false, completion: completion, ended: finish)
        let finishEntered = await finish.entryOrOperationEnd()
        #expect(finishEntered)
        let received = await h.inner.report(), held = await h.registry.report()
        #expect(received.attempts.count == 1 && received.postDeleteReads == 0)
        #expect(held.active.count == 1 && held.begun.count == baseline.begun.count + 1)
        #expect(held.finished == baseline.finished, "Provider receipt is not finished authority")
        #expect(h.model.receipt == nil && h.model.phase == .requesting && !h.model.canCapture && !completion.finished)
        switch outcome {
        case .unchanged: break
        case .newUIRestore:
            h.ownerBox.current = OnboardingOwnerToken(userID: h.owner.userID, restoreGeneration: h.owner.restoreGeneration + 1)
        case .supersededLease:
            await h.registry.supersedeLease()
        }
        await finish.release()
        await deleting.value
        let finished = await h.registry.report(), reads = await h.inner.report()
        #expect(completion.finished && finished.active.isEmpty && finished.finished == finished.begun)
        if outcome == .unchanged {
            #expect(h.model.receipt == SignupBodyPhotoDeleteReceipt(deleted: 3))
            #expect(h.model.phase == .ready && h.model.canCapture && reads.postDeleteReads == 1)
            #expect(h.model.captureModel !== h.original)
        } else {
            #expect(h.model.receipt == nil && h.model.phase != .ready && !h.model.canCapture)
            #expect(reads.postDeleteReads == 0 && h.model.captureModel === h.original)
        }
        #expect(reads.repairCalls == 0)
    }
}
#endif
