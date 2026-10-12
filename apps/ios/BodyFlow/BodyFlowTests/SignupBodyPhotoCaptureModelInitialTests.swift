#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@Suite("Signup capture model initial causal contracts")
@MainActor
struct SignupBodyPhotoCaptureModelInitialTests {
    @Test("An outcome or cleanup error waiting for cleanup cannot replace a newer document", arguments: [false, true])
    func lateOutcomeCannotReplaceNewerRead(failCleanup: Bool) async throws {
        let h = CaptureModelHarness(holdCleanup: true, failCleanupOnce: failCleanup)
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        let capturing = Task {
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.cleanupGate.operationFinished()
        }
        #expect(await h.cleanupGate.entryOrOperationEnd())
        await h.peer.changeDocument()
        await h.model.load()
        await h.cleanupGate.release()
        await capturing.value
        #expect(h.model.state?.consent?.version == "test-v2")
        #expect(h.model.state?.consent?.acceptedAt == nil)
        #expect(!h.model.hasAcceptedConsent)
        #expect(h.model.phase == .awaitingConsent)
    }

    @Test("A failed older pipeline GET cannot overwrite a newer read's phase")
    func lateReadErrorCannotReplaceNewerRead() async throws {
        let h = CaptureModelHarness()
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        await h.peer.holdNextState(fail: true)
        let capturing = Task {
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.stateGate.operationFinished()
        }
        #expect(await h.stateGate.entryOrOperationEnd())
        await h.peer.changeDocument()
        await h.model.load()
        await h.stateGate.release()
        await capturing.value
        #expect(h.model.state?.consent?.version == "test-v2")
        #expect(!h.model.hasAcceptedConsent)
        #expect(h.model.phase == .awaitingConsent)
    }

    @Test("A confirmed complete followed by a failed GET retries only the read")
    func confirmedPostRetriesOnlyRead() async throws {
        let h = CaptureModelHarness(failStateAfterComplete: true)
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        #expect(h.model.phase == .failed(.offline))
        let before = await h.peer.snapshot()
        await h.model.retry(pose: .front)
        let after = await h.peer.snapshot()
        #expect(after.creates == before.creates && after.completes == before.completes)
        #expect(after.count(.stage) == 1 && after.count(.put) == 1)
        #expect(after.count(.state) == before.count(.state) + 1)
        #expect(h.model.phase == .ready)
    }

    @Test("A failed local cleanup is reported and its exact file can be retried")
    func localCleanupFailureRetainsOwnFile() async throws {
        let h = CaptureModelHarness(failOnceAt: .create, failCleanupOnce: true)
        defer { h.clean() }
        let unrelated = try h.staging.stage(Data("other capture".utf8), fileExtension: "jpg")
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        h.model.invalidate()
        await #expect(throws: SignupBodyPhotoFailure.unavailable) { try await h.model.waitForLocalCleanup() }
        let afterFailure = try FileManager.default.contentsOfDirectory(at: h.staging.root, includingPropertiesForKeys: nil)
        #expect(afterFailure.count == 2)
        try await h.model.waitForLocalCleanup()
        let afterRetry = try FileManager.default.contentsOfDirectory(at: h.staging.root, includingPropertiesForKeys: nil)
        #expect(afterRetry.map(\.path) == [unrelated.deletingLastPathComponent().path])
        #expect(await h.cleanupPeer.calls == 2)
        #expect(h.model.state == nil && !h.model.isActive && h.model.phase == .idle)
        #expect(await h.peer.snapshot().count(.delete) == 0)
    }

    @Test("An old consent receipt cannot authorize a newer unaccepted document")
    func newerDocumentRefusesOldReceipt() async throws {
        let h = CaptureModelHarness(holdConsent: true)
        defer { h.clean() }
        await h.model.load()
        let accepting = Task {
            await h.model.acceptConsent(birthDate: "1990-01-01")
            await h.gate.operationFinished()
        }
        let entered = await h.gate.entryOrOperationEnd()
        #expect(entered)
        await h.peer.changeDocument()
        await h.model.load()
        await h.gate.release()
        await accepting.value
        #expect(!h.model.hasAcceptedConsent)
        #expect(h.model.phase == .awaitingConsent)
        #expect(h.model.state?.consent?.version == "test-v2")
        #expect(h.model.state?.consent?.acceptedAt == nil)
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        let trace = await h.peer.snapshot()
        #expect(trace.count(.stage) == 0 && trace.count(.create) == 0 && trace.count(.put) == 0 && trace.count(.complete) == 0)
    }

    @Test("An earlier GET or its error cannot erase a later official consent receipt", arguments: [false, true])
    func oldReadCannotUndoConsent(fail: Bool) async throws {
        let h = CaptureModelHarness()
        defer { h.clean() }
        await h.model.load()
        await h.peer.holdNextState(fail: fail)
        let loading = Task { await h.model.load(); await h.stateGate.operationFinished() }
        #expect(await h.stateGate.entryOrOperationEnd())
        await h.model.acceptConsent(birthDate: "1990-01-01")
        #expect(h.model.hasAcceptedConsent)
        await h.stateGate.release()
        await loading.value
        #expect(h.model.hasAcceptedConsent)
        #expect(h.model.state?.consent?.acceptedAt != nil)
        #expect(h.model.phase == .idle)
        #expect(await h.peer.snapshot().consents.count == 1)
    }

    @Test("Caller cancellation during cooperative or late stage frees input and only its own file", arguments: [false, true])
    func cancelledLateStageReleasesInput(cooperative: Bool) async throws {
        let h = CaptureModelHarness(holdStage: true, cooperativeStage: cooperative)
        defer { h.clean() }
        let unrelated = try h.staging.stage(Data("other capture".utf8), fileExtension: "jpg")
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        let capturing = Task {
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
            await h.stageGate.operationFinished()
        }
        #expect(await h.stageGate.entryOrOperationEnd())
        capturing.cancel()
        await h.stageGate.release()
        await capturing.value
        try await h.model.waitForLocalCleanup()
        #expect(h.model.retainedInputBytes == 0)
        let files = try FileManager.default.contentsOfDirectory(at: h.staging.root, includingPropertiesForKeys: nil)
        #expect(files.map(\.path) == [unrelated.deletingLastPathComponent().path])
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        let trace = await h.peer.snapshot()
        #expect(trace.count(.create) == 0 && trace.count(.put) == 0 && trace.count(.complete) == 0)
    }
    @Test("An offline create leaves a staged file which teardown must discard", arguments: [false, true])
    func stoppedPipelineDiscardsItsOwnFile(decline: Bool) async throws {
        let h = CaptureModelHarness(failOnceAt: .create)
        defer { h.clean() }
        let unrelated = try h.staging.stage(Data("other capture".utf8), fileExtension: "jpg")
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        #expect(h.model.phase == .failed(.offline))
        let before = try FileManager.default.contentsOfDirectory(at: h.staging.root, includingPropertiesForKeys: nil)
        #expect(before.count == 2)
        #expect(h.model.retainedInputBytes == 0)
        if decline { h.model.declineConsent() } else { h.model.invalidate() }
        try await h.model.waitForLocalCleanup()
        let after = try FileManager.default.contentsOfDirectory(at: h.staging.root, includingPropertiesForKeys: nil)
        #expect(after.map(\.path) == [unrelated.deletingLastPathComponent().path])
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(h.model.retainedInputBytes == 0)
        let trace = await h.peer.snapshot()
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
    }
    @Test("T01 absent choice, decline or unavailable performs zero sending", arguments: CaptureConsentScenario.allCases)
    func declinedConsentSendsNothing(scenario: CaptureConsentScenario) async throws {
        let unavailable = scenario == .unavailable
        let h = CaptureModelHarness(available: !unavailable)
        defer { h.clean() }
        await h.model.load()
        if scenario == .declined { h.model.declineConsent() }
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        let s = await h.peer.snapshot()
        #expect(s.count(.state) >= 1)
        #expect(s.mutationAndStageSteps.isEmpty)
        #expect(!h.model.hasAcceptedConsent)
        #expect(h.model.state?.available == !unavailable)
    }

    @Test("T02 consent barrier precedes every capture effect; phase keys and payloads are exact")
    func consentBeforePipelineOrder() async throws {
        let h = CaptureModelHarness(holdConsent: true)
        defer { h.clean() }
        await h.model.load()
        let accepting = Task {
            await h.model.acceptConsent(birthDate: "1990-01-01")
            await h.gate.operationFinished()
        }
        let entered = await h.gate.entryOrOperationEnd()
        let before = await h.peer.snapshot()
        #expect(entered)
        #expect(!h.model.hasAcceptedConsent)
        #expect(before.mutationAndStageSteps == [.consent])
        #expect(before.count(.stage) == 0 && before.count(.create) == 0 && before.count(.put) == 0 && before.count(.complete) == 0)
        // Release before throwing guards so a RED cannot leave a blocked Task.
        await h.gate.release()
        await accepting.value
        #expect(h.model.hasAcceptedConsent)
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
        let s = await h.peer.snapshot()
        #expect(s.mutationAndStageSteps == [.consent, .stage, .create, .put, .complete])
        #expect(s.count(.state) >= 2)
        #expect(s.calls.last?.step == .state)
        let consent = try #require(s.consents.first)
        let create = try #require(s.creates.first)
        let complete = try #require(s.completes.first)
        #expect(consent.payload == SignupBodyPhotoConsentRequest(version: "test-v1", bodyHash: String(repeating: "a", count: 64), birthDate: "1990-01-01"))
        #expect(create.payload == SignupBodyPhotoCreateRequest(pose: .front, mimeType: "image/jpeg", sizeBytes: CaptureModelHarness.data.count))
        #expect(Set([consent.key, create.key, complete.key]).count == 3)
        let state = try #require(h.model.state)
        let front = try #require(state.poses.first(where: { $0.pose == .front })?.photo)
        #expect(complete.payload.assetID == front.id)
        #expect(front.status == "read")
        #expect(h.model.phase == .ready)
        #expect(s.count(.delete) == 0 && s.count(.repair) == 0)
    }

    @Test("T03 an uncertain applied mutation retries its entire ORIGINAL attempt", arguments: CaptureFailurePoint.allCases)
    func uncertainMutationKeepsAttempt(point: CaptureFailurePoint) async throws {
        let h = CaptureModelHarness(failOnceAt: point)
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        if point == .consent {
            #expect(h.model.phase == .failed(.offline))
            await h.model.acceptConsent(birthDate: "1990-01-01")
            let s = await h.peer.snapshot()
            try #require(s.consents.count == 2)
            #expect(s.consents[0] == s.consents[1])
            #expect(h.model.hasAcceptedConsent)
            #expect(s.count(.stage) == 0 && s.count(.create) == 0 && s.count(.put) == 0 && s.count(.complete) == 0)
            return
        }
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        #expect(h.model.phase == .failed(.offline))
        await h.model.retry(pose: .front)
        let s = await h.peer.snapshot()
        if point == .create {
            try #require(s.creates.count == 2)
            #expect(s.creates[0] == s.creates[1])
            #expect(s.completes.count == 1)
        } else {
            try #require(s.completes.count == 2)
            #expect(s.completes[0] == s.completes[1])
            #expect(s.creates.count == 1)
        }
        #expect(s.count(.stage) == 1 && s.count(.put) == 1)
        #expect(h.model.phase == .ready)
    }

    @Test("T04 reading failure retake has a NEW identity and leaves other poses alone")
    func newCaptureAfterReadingFailure() async throws {
        let h = CaptureModelHarness(readingFailsOnce: true, otherPosesPresent: true)
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        let initial = try #require(h.model.state)
        let side = try #require(initial.poses.first(where: { $0.pose == .side })?.photo)
        let back = try #require(initial.poses.first(where: { $0.pose == .back })?.photo)
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        #expect(h.model.phase == .failed(.readingFailed))
        // Deliberately same bytes: it is a new user capture, not retry uncertainty.
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        let s = await h.peer.snapshot()
        try #require(s.creates.count == 2 && s.completes.count == 2)
        #expect(s.creates[0].key != s.creates[1].key)
        #expect(s.completes[0].key != s.completes[1].key)
        #expect(s.completes[0].payload.assetID != s.completes[1].payload.assetID)
        let final = try #require(h.model.state)
        #expect(final.poses.first(where: { $0.pose == .side })?.photo == side)
        #expect(final.poses.first(where: { $0.pose == .back })?.photo == back)
        #expect(h.model.phase == .ready)
        #expect(s.count(.delete) == 0 && s.count(.repair) == 0)
    }

    @Test("T05 upload-null replay reconsults state and never fabricates a PUT", arguments: [false, true])
    func replayWithoutTicketUsesState(pendingWithoutTicket: Bool) async throws {
        let h = CaptureModelHarness(replay: pendingWithoutTicket ? .pendingWithoutTicket : .stored)
        defer { h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        let s = await h.peer.snapshot()
        #expect(s.creates.count == 1)
        #expect(s.count(.put) == 0 && s.count(.complete) == 0)
        #expect(s.count(.state) >= 2)
        let createdIndex = try #require(s.calls.firstIndex(where: { $0.step == .create }))
        #expect(s.calls.dropFirst(createdIndex + 1).contains(where: { $0.step == .state }))
        if pendingWithoutTicket {
            #expect(h.model.phase != .ready)
        } else {
            #expect(h.model.phase == .ready)
            let state = try #require(h.model.state)
            #expect(state.poses.first(where: { $0.pose == .front })?.photo?.status == "read")
        }
        #expect(s.count(.delete) == 0 && s.count(.repair) == 0)
    }
}
#endif
