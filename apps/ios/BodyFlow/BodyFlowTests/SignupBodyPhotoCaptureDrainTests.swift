#if DEBUG
import Foundation
import Observation
import Testing
@testable import BodyFlow

// D0 only: existing real CaptureModel + existing peer/barrier types.
// No network, UI activation, Storage ticket or deletion ACK is claimed.
@Suite("Signup capture drain causal contracts")
@MainActor
struct SignupBodyPhotoCaptureDrainTests {
    @Test("Drain remains suspended until a cancelled noncooperative PUT really returns")
    func drainWaitsForNonCooperativePUT() async throws {
        let h = CaptureDrainHarness()
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        let capture = Task {
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.putGate.operationFinished()
        }
        let entered = await h.putGate.entryOrOperationEnd()
        #expect(entered)
        let result = CaptureDrainCompletion()
        let started = CaptureConsentGate()
        let drain = beginDrain(h.model, result: result, started: started)
        let drainEntered = await started.entryOrOperationEnd()
        #expect(drainEntered)
        #expect(!h.model.isActive)
        #expect(!result.finished, "Task.cancel is not PUT completion or permission for explicit DELETE")
        await h.putGate.release()
        await capture.value
        await drain.value
        #expect(result.finished)
        try await h.model.waitForLocalCleanup()
        let report = await h.peer.snapshot()
        #expect(report.count(.create) == 1 && report.count(.put) == 1)
        #expect(report.count(.complete) == 0)
        #expect(report.count(.delete) == 0 && report.count(.repair) == 0)
    }

    @Test("An obsolete retake consumer survives a newer boundary failing before previous-task join")
    func drainRetainsObsoleteRetakeBeforeJoin() async throws {
        let h = CaptureDrainHarness()
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        let old = Task {
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.putGate.operationFinished()
        }
        let oldEntered = await h.putGate.entryOrOperationEnd()
        #expect(oldEntered)
        // Hold the very first boundary of start(new), before it joins old.
        let newBoundary = CaptureConsentGate(holds: true)
        await h.validation.armNext(newBoundary)
        let retake = Task {
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
            await newBoundary.operationFinished()
        }
        let retakeEntered = await newBoundary.entryOrOperationEnd()
        #expect(retakeEntered)
        // Decline increments epoch/cancels latest task while keeping the model
        // active: release makes boundary throw before await previous.value.
        h.model.declineConsent()
        await newBoundary.release()
        await retake.value
        #expect(h.model.isActive)
        #expect(!h.model.hasAcceptedConsent)
        let beforeDrain = await h.peer.snapshot()
        #expect(beforeDrain.count(.stage) == 1 && beforeDrain.count(.put) == 1)
        let result = CaptureDrainCompletion()
        let started = CaptureConsentGate()
        let drain = beginDrain(h.model, result: result, started: started)
        let drainEntered = await started.entryOrOperationEnd()
        #expect(drainEntered)
        #expect(!result.finished, "Latest-per-pose task is finished; the obsolete PUT is still owned")
        await h.putGate.release()
        await old.value
        await drain.value
        #expect(result.finished)
        try await h.model.waitForLocalCleanup()
        let final = await h.peer.snapshot()
        #expect(final.count(.stage) == 1 && final.count(.create) == 1 && final.count(.put) == 1)
        #expect(final.count(.complete) == 0 && final.count(.delete) == 0 && final.count(.repair) == 0)
    }

    @Test("A new failed consent cannot release ownership of its still-suspended predecessor")
    func drainRetainsObsoleteConsent() async throws {
        let h = CaptureDrainHarness(strandOldConsent: true)
        defer { h.clean() }
        await h.model.load()
        let old = Task {
            await h.model.acceptConsent(birthDate: "1990-01-01")
            await h.oldConsentGate.operationFinished()
        }
        let entered = await h.oldConsentGate.entryOrOperationEnd()
        #expect(entered)
        // The provider rejects the second request immediately; the first one
        // ignores cancellation behind its independent barrier.
        await h.model.acceptConsent(birthDate: "1990-01-01")
        #expect(h.model.isActive)
        #expect(!h.model.hasAcceptedConsent)
        let result = CaptureDrainCompletion()
        let started = CaptureConsentGate()
        let drain = beginDrain(h.model, result: result, started: started)
        let drainEntered = await started.entryOrOperationEnd()
        #expect(drainEntered)
        #expect(!result.finished, "The old consent task remains owned after consentTask is replaced")
        await h.oldConsentGate.release()
        await old.value
        await drain.value
        #expect(result.finished)
        #expect(!h.model.hasAcceptedConsent && h.model.state == nil)
        let report = await h.peer.snapshot()
        #expect(report.mutationAndStageSteps == [.consent])
    }

    @Test("Late cancelled staging producer is awaited and only its own file is discarded")
    func drainWaitsForLateStagingProducer() async throws {
        let h = CaptureDrainHarness(holdStage: true)
        defer { h.clean() }
        let control = try h.staging.stage(Data("other-owned-control".utf8), fileExtension: "jpg")
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        let capturing = Task {
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
            await h.stageGate.operationFinished()
        }
        let entered = await h.stageGate.entryOrOperationEnd()
        #expect(entered)
        let result = CaptureDrainCompletion()
        let started = CaptureConsentGate()
        let drain = beginDrain(h.model, result: result, started: started)
        let drainEntered = await started.entryOrOperationEnd()
        #expect(drainEntered)
        #expect(!result.finished)
        await h.stageGate.release()
        await capturing.value
        await drain.value
        try await h.model.waitForLocalCleanup()
        #expect(result.finished)
        #expect(FileManager.default.fileExists(atPath: control.path))
        let report = await h.peer.snapshot()
        #expect(report.count(.stage) == 1 && report.count(.create) == 0 && report.count(.put) == 0)
        #expect(report.count(.delete) == 0 && report.count(.repair) == 0)
    }

    // Observes the actual synchronous invalidation at the start of drain.
    // The existing gate also returns false if the operation exits before the
    // event: neutral scaffold fails by assertion and never hangs a waiter.
    // MainActor cannot resume this test until the drain yields or returns.
    private func beginDrain(_ model: SignupBodyPhotoCaptureModel,
                            result: CaptureDrainCompletion,
                            started: CaptureConsentGate) -> Task<Void, Never> {
        withObservationTracking { _ = model.isActive } onChange: {
            Task { await started.enter() }
        }
        return Task {
            await model.invalidateAndWaitForOwnedCaptureWork()
            result.finished = true
            await started.operationFinished()
        }
    }
}

@MainActor
private final class CaptureDrainCompletion { var finished = false }

private actor CaptureDrainValidation {
    private var next: CaptureConsentGate?
    func armNext(_ gate: CaptureConsentGate) { next = gate }
    func validate() async throws {
        try Task.checkCancellation()
        let gate = next; next = nil
        // Deliberately returns despite cancellation during this boundary;
        // CaptureModel must do its own checks after the suspension.
        await gate?.enter()
    }
}

private struct CaptureDrainUploader: StorageUploading {
    let peer: CaptureServerPeer
    let gate: CaptureConsentGate
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        try await peer.upload(media, with: ticket)
        // Noncooperative PUT: task cancellation cannot release this wait.
        await gate.enter()
    }
}

private actor CaptureDrainPhotos: SignupBodyPhotosProviding {
    let peer: CaptureServerPeer
    let oldConsent: CaptureConsentGate?
    private var consentCount = 0
    init(peer: CaptureServerPeer, oldConsent: CaptureConsentGate?) {
        self.peer = peer; self.oldConsent = oldConsent
    }
    func state() async throws -> SignupBodyPhotoState { try await peer.state() }
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt {
        consentCount += 1
        if let oldConsent {
            if consentCount == 1 { await oldConsent.enter() }
            else { throw SignupBodyPhotoFailure.unavailable }
        }
        return try await peer.consent(attempt)
    }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await peer.create(attempt) }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await peer.complete(attempt) }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await peer.delete(attempt) }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await peer.repair(attempt) }
}

@MainActor
private struct CaptureDrainHarness {
    let model: SignupBodyPhotoCaptureModel
    let peer: CaptureServerPeer
    let validation: CaptureDrainValidation
    let putGate: CaptureConsentGate
    let stageGate: CaptureConsentGate
    let oldConsentGate: CaptureConsentGate
    let staging: MediaStagingStore
    let base: URL

    init(strandOldConsent: Bool = false, holdStage: Bool = false) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signup-drain-\(UUID().uuidString)", isDirectory: true)
        let staging = MediaStagingStore(temporaryDirectory: base)
        let putGate = CaptureConsentGate(holds: true)
        let stageGate = CaptureConsentGate(holds: holdStage)
        let oldConsentGate = CaptureConsentGate(holds: true)
        let consentGate = CaptureConsentGate()
        let cleanupGate = CaptureConsentGate()
        let cleanup = CaptureCleanupPeer(gate: cleanupGate, failOnce: false)
        let peer = CaptureServerPeer(staging: staging, consentGate: consentGate, stageGate: stageGate)
        let photos = CaptureDrainPhotos(peer: peer, oldConsent: strandOldConsent ? oldConsentGate : nil)
        let validation = CaptureDrainValidation()
        let owner = OnboardingOwnerToken(userID: CaptureModelHarness.owner, restoreGeneration: 1)
        let scope = SignupBodyPhotoCaptureScope(userID: owner.userID, photos: photos,
            uploader: CaptureDrainUploader(peer: peer, gate: putGate), staging: staging, camera: .unavailable,
            validateSession: { try await validation.validate() },
            stagePhoto: { data, channel in try await peer.stage(data, channel: channel) },
            performWork: { work in try await work() },
            discardStaged: { file in try await cleanup.discard(file, staging: staging) },
            rememberUnboundCreate: { _ in })
        model = SignupBodyPhotoCaptureModel(scope: scope, ownerToken: owner,
            timeProvider: CaptureAttemptTime(), keyProvider: DeterministicIdempotencyKeyProvider(prefix: "signup-drain-key"),
            isCurrentOwner: { $0 == owner })
        self.peer = peer; self.validation = validation; self.putGate = putGate
        self.stageGate = stageGate; self.oldConsentGate = oldConsentGate
        self.staging = staging; self.base = base
    }
    func clean() { model.invalidate(); try? FileManager.default.removeItem(at: base) }
}
#endif
