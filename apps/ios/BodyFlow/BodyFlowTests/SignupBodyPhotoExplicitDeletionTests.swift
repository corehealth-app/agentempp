#if DEBUG
import Foundation
import Observation
import Testing
@testable import BodyFlow

@Suite("Signup explicit deletion UI composition causal contracts")
@MainActor
struct SignupBodyPhotoExplicitDeletionTests {
    @Test("Explicit DELETE waits for real D0 completion and then its own known receipt")
    func waitsForNonCooperativePUTAndReceipt() async throws {
        let h = ExplicitDeleteHarness(holdPUT: true, holdDelete: true)
        defer { h.clean() }
        await h.prepare()
        #expect(h.model.canCapture)
        let control = try h.staging.stage(Data("not-owned-by-this-capture".utf8), fileExtension: "jpg")
        let capture = Task {
            await h.original.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.putGate.operationFinished()
        }
        let putEntered = await h.putGate.entryOrOperationEnd()
        #expect(putEntered)
        let drainStarted = CaptureConsentGate(), completion = ExplicitDeleteCompletion()
        withObservationTracking { _ = h.original.isActive } onChange: {
            Task { await drainStarted.enter() }
        }
        let deleting = h.beginDeletion(completion: completion, operationEnded: [drainStarted])
        let invalidated = await drainStarted.entryOrOperationEnd()
        #expect(invalidated, "D1 must compose the real D0 consumer drain")
        #expect(!h.model.canCapture && !completion.finished)
        #expect(h.model.phase == .draining)
        let held = await h.photos.report()
        #expect(held.attempts.isEmpty && held.postDeleteReads == 0)
        await h.putGate.release()
        await capture.value
        let deleteEntered = await h.deleteGate.entryOrOperationEnd()
        #expect(deleteEntered)
        #expect(!completion.finished && h.model.receipt == nil && !h.model.canCapture)
        let requested = await h.photos.report()
        #expect(requested.attempts.count == 1 && requested.postDeleteReads == 0)
        await h.deleteGate.release()
        await deleting.value
        #expect(completion.finished && h.model.receipt == SignupBodyPhotoDeleteReceipt(deleted: 3))
        #expect(h.model.phase == .ready && h.model.canCapture)
        #expect(h.model.captureModel !== h.original && !h.original.isActive)
        #expect(FileManager.default.fileExists(atPath: control.path))
        let done = await h.photos.report(), pipeline = await h.peer.snapshot()
        #expect(done.attempts.count == 1 && done.postDeleteReads == 1 && done.repairCalls == 0)
        #expect(pipeline.count(.complete) == 0)
    }

    @Test("A replaced noncooperative UI producer remains owned until DELETE can proceed")
    func drainsObsoleteUIProducerAndOldConsumer() async throws {
        let h = ExplicitDeleteHarness(holdPUT: true)
        defer { h.clean() }
        await h.prepare()
        let oldCapture = Task {
            await h.original.capture(CaptureModelHarness.data, pose: .back, channel: .camera)
            await h.putGate.operationFinished()
        }
        let putEntered = await h.putGate.entryOrOperationEnd()
        #expect(putEntered)
        let gallery = CaptureConsentGate(holds: true)
        let data = CaptureModelHarness.data // copy on MainActor before the Sendable producer closure
        let producer = Task {
            await h.model.producePhoto(pose: .front, channel: .gallery) {
                await gallery.enter()
                return data
            }
            await gallery.operationFinished()
        }
        let producerEntered = await gallery.entryOrOperationEnd()
        #expect(producerEntered)
        // New result is cancelled before reaching capture. It cannot release
        // ownership of the superseded, noncooperative picker producer.
        await h.model.producePhoto(pose: .front, channel: .gallery) { nil }
        let drainStarted = CaptureConsentGate(), completion = ExplicitDeleteCompletion()
        withObservationTracking { _ = h.original.isActive } onChange: { Task { await drainStarted.enter() } }
        let deleting = h.beginDeletion(completion: completion, operationEnded: [drainStarted])
        let invalidated = await drainStarted.entryOrOperationEnd()
        #expect(invalidated && !completion.finished && !h.model.canCapture)
        let waitingBoth = await h.photos.report()
        #expect(waitingBoth.attempts.isEmpty)
        await h.putGate.release()
        await oldCapture.value
        let consumerDone = await h.photos.report()
        #expect(consumerDone.attempts.isEmpty && !completion.finished,
            "A finished old consumer does not finish an obsolete UI producer")
        await gallery.release()
        await producer.value
        await deleting.value
        let done = await h.photos.report(), pipeline = await h.peer.snapshot()
        #expect(done.attempts.count == 1 && done.postDeleteReads == 1 && done.repairCalls == 0)
        #expect(pipeline.count(.stage) == 1 && pipeline.count(.create) == 1 && pipeline.count(.put) == 1)
        #expect(pipeline.count(.complete) == 0, "Late gallery data must not enter the pipeline after deletion epoch")
        #expect(h.model.phase == .ready && h.model.canCapture)
    }

    @Test("Lost DELETE reply retries the exact immutable attempt and preserves failure", arguments: ExplicitDeleteUncertainFailure.allCases)
    func uncertainReplyRetriesOriginalAttempt(_ failure: ExplicitDeleteUncertainFailure) async throws {
        let h = ExplicitDeleteHarness(uncertainFirst: failure)
        defer { h.clean() }
        await h.prepare()
        let marker = UUID(uuidString: "00000000-0000-4000-8000-000000d10101")!
        await h.markers.remember(marker)
        await h.model.deletePhotos()
        #expect(h.model.phase == .failed(failure.failure))
        #expect(h.model.receipt == nil && !h.model.canCapture)
        let first = await h.photos.report()
        #expect(first.attempts.count == 1 && first.postDeleteReads == 0)
        let data = CaptureModelHarness.data
        await h.model.producePhoto(pose: .front, channel: .gallery) { data }
        #expect(h.model.phase == .failed(failure.failure), "Retained presentation state cannot hide uncertain deletion")
        let stillFailed = await h.photos.report()
        #expect(stillFailed.attempts == first.attempts && stillFailed.postDeleteReads == 0)
        await h.model.retryDeletion()
        let second = await h.photos.report()
        #expect(second.attempts.count == 2)
        let a = try #require(second.attempts.first), b = try #require(second.attempts.last)
        #expect(a == b, "Equality covers operation/key/payload/createdAt, not just an empty body")
        #expect(a.operation == .mediaDelete && a.payload == SignupBodyPhotoDeleteCommand())
        #expect(second.postDeleteReads == 1 && second.repairCalls == 0)
        #expect(h.model.receipt == SignupBodyPhotoDeleteReceipt(deleted: 3) && h.model.canCapture)
        let preserved = await h.markers.snapshot()
        #expect(preserved == [marker], "Explicit DELETE does not acknowledge C07 or completion-G debt")
    }

    @Test("Known receipt plus failed GET retries only GET, including deleted0 / OFF", arguments: [true, false])
    func knownReceiptReadRetryOnly(_ available: Bool) async throws {
        let h = ExplicitDeleteHarness(failReloadOnce: true, deleted: 0, reloadAvailable: available)
        defer { h.clean() }
        await h.prepare()
        await h.model.deletePhotos()
        #expect(h.model.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
        #expect(h.model.phase == .failed(.offline) && !h.model.canCapture)
        let failed = await h.photos.report()
        #expect(failed.attempts.count == 1 && failed.postDeleteReads == 1)
        await h.model.retryDeletion()
        let recovered = await h.photos.report()
        #expect(recovered.attempts == failed.attempts && recovered.postDeleteReads == 2 && recovered.repairCalls == 0)
        #expect(h.model.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0) && h.model.phase == .ready)
        #expect(h.model.captureModel !== h.original && !h.original.isActive)
        #expect(h.model.captureModel.state?.available == available && h.model.canCapture == available)
        // OFF is an authoritative gate, not evidence of Storage absence or G3 ACK.
    }

    @Test("Owner changes during validation / DELETE / GET cannot publish or continue old work",
        arguments: ExplicitDeleteOwnerStage.allCases, ExplicitDeleteOwnerTransition.allCases)
    func obsoleteOwnerCannotContinue(_ stage: ExplicitDeleteOwnerStage, _ transition: ExplicitDeleteOwnerTransition) async throws {
        let h = ExplicitDeleteHarness(holdDelete: stage == .receipt, holdReload: stage == .reload)
        defer { h.clean() }
        await h.prepare()
        let control = try h.staging.stage(Data("other-owner-control".utf8), fileExtension: "jpg")
        let validationGate = CaptureConsentGate(holds: true)
        if stage == .validation { await h.validation.armNext(validationGate) }
        let blocked: CaptureConsentGate
        switch stage {
        case .validation: blocked = validationGate
        case .receipt: blocked = h.deleteGate
        case .reload: blocked = h.reloadGate
        }
        let completion = ExplicitDeleteCompletion()
        let deleting = h.beginDeletion(completion: completion, operationEnded: [blocked])
        let entered = await blocked.entryOrOperationEnd()
        #expect(entered)
        switch transition {
        case .foreign:
            h.ownerBox.current = OnboardingOwnerToken(userID: "00000000-0000-4000-8000-000000d10202", restoreGeneration: 2)
        case .sameAccountNewRestore:
            h.ownerBox.current = OnboardingOwnerToken(userID: "00000000-0000-4000-8000-000000d10202", restoreGeneration: 2)
            h.ownerBox.current = OnboardingOwnerToken(userID: h.owner.userID, restoreGeneration: 3)
        }
        await blocked.release()
        await deleting.value
        #expect(completion.finished && !h.model.canCapture)
        #expect(h.model.phase != .ready && h.model.captureModel === h.original)
        let report = await h.photos.report()
        #expect(report.attempts.count == (stage == .validation ? 0 : 1))
        #expect(report.postDeleteReads == (stage == .reload ? 1 : 0) && report.repairCalls == 0)
        if stage != .reload { #expect(h.model.receipt == nil) }
        #expect(FileManager.default.fileExists(atPath: control.path))
    }

    @Test("Local cancellation / decline / retake / route exit never automatically DELETE", arguments: ExplicitDeleteLocalExit.allCases)
    func noAutomaticDelete(_ action: ExplicitDeleteLocalExit) async throws {
        let h = ExplicitDeleteHarness()
        defer { h.clean() }
        await h.prepare()
        let data = CaptureModelHarness.data
        switch action {
        case .cancelledProducer: await h.model.producePhoto(pose: .front, channel: .gallery) { nil }
        case .declineConsent: h.original.declineConsent()
        case .retake:
            await h.model.producePhoto(pose: .front, channel: .camera) { data }
            await h.model.producePhoto(pose: .front, channel: .camera) { data }
        case .invalidate: h.model.invalidate()
        }
        await h.original.invalidateAndWaitForOwnedCaptureWork()
        try await h.original.waitForLocalCleanup()
        let report = await h.photos.report(), pipeline = await h.peer.snapshot()
        #expect(report.attempts.isEmpty && report.postDeleteReads == 0 && report.repairCalls == 0)
        #expect(pipeline.count(.delete) == 0 && pipeline.count(.repair) == 0)
        if action == .retake { #expect(pipeline.count(.create) == 2 && pipeline.count(.put) == 2) }
    }
}
#endif
