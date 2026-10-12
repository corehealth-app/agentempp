#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo shared polling — private P01/P02 scaffold")
struct SignupBodyPhotoCaptureModelPollingTests {
    @Test("Failed retake keeps the old official photo's age and the other photo's later anchor")
    func failedRetakeDoesNotRestartExistingReadingAge() async throws {
        let waiting = CapturePollingHarness.waiting()
        let h = CapturePollingHarness(script: [CapturePollingHarness.frontWaitingOnly(), waiting, waiting, waiting])
        defer { h.model.invalidate() }
        await h.model.load()
        try #require(await h.model.waitForPollingEvent())
        try #require(await h.clock.waitForRegistrations(1))
        await h.clock.advance(by: .seconds(60))
        try #require(await h.clock.waitForRegistrations(2))
        await h.clock.advance(by: .milliseconds(60_001))
        try #require(await h.clock.waitForRegistrations(3))
        #expect(h.model.hasExceededReadingWait)
        // Front has waited120.001s; side only60.001s. The side cannot mask
        // a reset of front's original anchor in the combined waiting flag.
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        #expect(h.model.phase == .failed(.unavailable))
        await h.model.waitForStoppedPollingWork()
        await h.model.load()
        #expect(h.model.state == waiting && h.model.phase == .reading)
        #expect(h.model.hasExceededReadingWait)
        #expect(await h.peer.stateCalls == 4)
        #expect(await h.peer.nonReadCalls == 1) // failed stage, zero create/PUT/complete
    }

    @Test("Retry retains reading age and original mutations; retake resets only its photo identity")
    func retryPreservesAgeAndRetakeChangesIdentity() async throws {
        let clock = CapturePollingClock()
        let h = CaptureModelHarness(otherPosesPresent: true, returnsReading: true,
            pollingTiming: SignupBodyPhotoPollingTiming(elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }))
        defer { h.model.invalidate(); h.clean() }
        await h.model.load()
        await h.model.acceptConsent(birthDate: "1990-01-01")
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        try #require(await h.model.waitForPollingEvent())
        try #require(await clock.waitForRegistrations(1))
        let first = try #require(h.model.state)
        let firstID = try #require(first.poses.first(where: { $0.pose == .front })?.photo?.id)
        let original = await h.peer.snapshot()
        await clock.advance(by: .milliseconds(119_999))
        await h.model.retry(pose: .front)
        await h.model.waitForStoppedPollingWork()
        #expect(!h.model.hasExceededReadingWait)
        await clock.advance(by: .milliseconds(2))
        await h.model.retry(pose: .front)
        await h.model.waitForStoppedPollingWork()
        #expect(h.model.hasExceededReadingWait && h.model.phase == .reading)
        let retried = await h.peer.snapshot()
        #expect(retried.creates == original.creates && retried.completes == original.completes)
        #expect(retried.count(.stage) == 1 && retried.count(.put) == 1)
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        await h.model.waitForStoppedPollingWork()
        let retaken = try #require(h.model.state)
        #expect(retaken.poses.first(where: { $0.pose == .front })?.photo?.id != firstID)
        #expect(retaken.poses.first(where: { $0.pose == .side })?.photo == first.poses.first(where: { $0.pose == .side })?.photo)
        #expect(retaken.poses.first(where: { $0.pose == .back })?.photo == first.poses.first(where: { $0.pose == .back })?.photo)
        #expect(!h.model.hasExceededReadingWait && h.model.phase == .reading)
        let trace = await h.peer.snapshot()
        try #require(trace.creates.count == 2 && trace.completes.count == 2)
        #expect(trace.creates[0].key != trace.creates[1].key)
        #expect(trace.completes[0].key != trace.completes[1].key)
        #expect(trace.count(.stage) == 2 && trace.count(.put) == 2)
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
    }

    @Test("A newer explicit read supersedes a held poll result and its error", arguments: [false, true])
    func newerReadRejectsOldPoll(fails: Bool) async throws {
        let latest = CapturePollingHarness.inactive(.disabled)
        let h = CapturePollingHarness(holdSecondState: true,
            script: [CapturePollingHarness.waiting(), CapturePollingHarness.terminal(), latest], failsSecondState: fails)
        defer { h.model.invalidate(); Task { await h.readGate.release() } }
        await h.model.load()
        try #require(await h.model.waitForPollingEvent())
        try #require(await h.clock.waitForRegistrations(1))
        await h.clock.advance(by: .milliseconds(1_500))
        try #require(await h.readGate.waitUntilEntered())
        await h.model.load()
        #expect(h.model.state == latest)
        #expect(h.model.phase == .failed(.unavailable))
        await h.readGate.release()
        await h.model.waitForStoppedPollingWork()
        #expect(h.model.state == latest && h.model.phase == .failed(.unavailable))
        #expect(!h.model.hasAcceptedConsent)
        await h.clock.advance(by: .seconds(15))
        #expect(await h.peer.stateCalls == 3)
        #expect(await h.peer.nonReadCalls == 0)
    }

    @Test("Retake invalidates a held poll before the capture's first GET", arguments: [false, true])
    func captureRejectsOldPollBeforeItsRead(fails: Bool) async throws {
        let h = CapturePollingHarness(holdSecondState: true,
            script: [CapturePollingHarness.waiting(), CapturePollingHarness.terminal()], failsSecondState: fails)
        defer { h.model.invalidate(); Task { await h.readGate.release() } }
        await h.model.load()
        try #require(await h.model.waitForPollingEvent())
        try #require(await h.clock.waitForRegistrations(1))
        await h.clock.advance(by: .milliseconds(1_500))
        try #require(await h.readGate.waitUntilEntered())
        // This peer rejects staging, so the new operation has no GET yet.
        // The old poll still cannot replace its current error with old success.
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .camera)
        #expect(h.model.phase == .failed(.unavailable))
        let snapshot = h.model.state
        await h.readGate.release()
        await h.model.waitForStoppedPollingWork()
        #expect(h.model.state == snapshot && h.model.phase == .failed(.unavailable))
        #expect(await h.peer.stateCalls == 2)
        #expect(await h.peer.nonReadCalls == 1) // stage only
    }

    @Test("A stopped poll's late result or error is inert across decline and A to B to A", arguments: CapturePollingStopCase.allCases, [false, true])
    func lateStoppedPollCannotPublish(scenario: CapturePollingStopCase, fails: Bool) async throws {
        let h = CapturePollingHarness(holdSecondState: true,
            script: [CapturePollingHarness.waiting(), CapturePollingHarness.terminal()], failsSecondState: fails)
        defer {
            h.model.invalidate()
            Task { await h.readGate.release() }
        }
        await h.model.load()
        try #require(await h.model.waitForPollingEvent())
        try #require(await h.clock.waitForRegistrations(1))
        await h.clock.advance(by: .milliseconds(1_500))
        try #require(await h.readGate.waitUntilEntered())
        let oldOwner = h.ownerBox.current
        switch scenario {
        case .invalidate: h.model.invalidate()
        case .decline: h.model.declineConsent()
        case .otherOwner:
            h.ownerBox.current = OnboardingOwnerToken(userID: "00000000-0000-4000-8000-000000c70602", restoreGeneration: 2)
            h.model.invalidate()
        case .sameOwnerNewGeneration:
            h.ownerBox.current = OnboardingOwnerToken(userID: "00000000-0000-4000-8000-000000c70602", restoreGeneration: 2)
            h.ownerBox.current = OnboardingOwnerToken(userID: oldOwner.userID, restoreGeneration: 3)
            h.model.invalidate()
        }
        let snapshot = h.model.state
        let phase = h.model.phase
        await h.readGate.release()
        // Observe the model's own completion, including scope.finish and its
        // final guards; producer-end is not evidence of publication.
        await h.model.waitForStoppedPollingWork()
        #expect(h.model.state == snapshot && h.model.phase == phase)
        #expect(!h.model.hasAcceptedConsent && !h.model.hasExceededReadingWait)
        #expect(await h.clock.pendingCount == 0)
        await h.clock.advance(by: .seconds(15))
        #expect(await h.peer.stateCalls == 2)
        #expect(await h.peer.nonReadCalls == 0)
    }

    @Test("A successful consent receipt resumes the single poll for existing waiting photos")
    func acceptedConsentResumesWaitingPhotos() async throws {
        let h = CapturePollingHarness(allowsConsent: true)
        defer { h.model.invalidate() }
        await h.model.load()
        try #require(await h.model.waitForPollingEvent())
        try #require(await h.clock.waitForRegistrations(1))
        await h.model.acceptConsent(birthDate: "1990-01-01")
        #expect(h.model.hasAcceptedConsent)
        #expect(h.model.phase == .reading)
        try #require(await h.model.waitForPollingEvent())
        try #require(await h.clock.waitForRegistrations(2))
        #expect(await h.clock.pendingCount == 1)
        #expect(await h.peer.stateCalls == 1)
        #expect(await h.peer.nonReadCalls == 1) // consent only; no create/PUT/complete
    }

    @Test("Terminal, unknown, absent, disabled or unaccepted photos never arm a poll", arguments: CapturePollingInactiveCase.allCases)
    func inactiveSnapshotsDoNotPoll(scenario: CapturePollingInactiveCase) async throws {
        let snapshot = CapturePollingHarness.inactive(scenario)
        let h = CapturePollingHarness(script: [snapshot])
        defer { h.model.invalidate() }
        await h.model.load()
        #expect(!h.model.hasExceededReadingWait)
        #expect(h.model.phase != .reading)
        #expect(!(await h.model.waitForPollingEvent()))
        #expect(h.model.state == snapshot)
        #expect(await h.clock.registrations == 0)
        let reads = await h.peer.stateCalls
        let nonReads = await h.peer.nonReadCalls
        #expect(reads == 1 && nonReads == 0)
    }

    @Test("P01 two waiting poses use one poll with exact virtual 1.5s cadence")
    func oneSharedPollHasExactVirtualCadence() async throws {
        let h = CapturePollingHarness()
        defer { h.model.invalidate() }
        await h.model.load()
        #expect(h.model.phase == .reading)
        #expect(!h.model.hasExceededReadingWait)
        let armed = await h.model.waitForPollingEvent()
        // The neutral model returns false: fail here by assertion, never hang
        // waiting for a sleeper from an absent polling implementation.
        try #require(armed)
        let firstSleep = await h.clock.waitForRegistrations(1)
        try #require(firstSleep)
        #expect(await h.clock.pendingCount == 1)
        #expect(await h.clock.durations == [.milliseconds(1_500)])
        #expect(await h.peer.stateCalls == 1)
        await h.clock.advance(by: .milliseconds(1_499))
        #expect(await h.peer.stateCalls == 1)
        await h.clock.advance(by: .milliseconds(1))
        let secondRead = await h.peer.waitForStateCalls(2)
        try #require(secondRead)
        let secondSleep = await h.clock.waitForRegistrations(2)
        try #require(secondSleep)
        #expect(await h.peer.stateCalls == 2)
        #expect(await h.clock.pendingCount == 1)
        #expect(await h.clock.durations == [.milliseconds(1_500), .milliseconds(1_500)])
        await h.clock.advance(by: .milliseconds(1_500))
        let thirdRead = await h.peer.waitForStateCalls(3)
        try #require(thirdRead)
        let stopped = await h.model.waitForPollingEvent(untilStopped: true)
        try #require(stopped)
        #expect(h.model.state == CapturePollingHarness.terminal())
        #expect(h.model.phase == .ready)
        #expect(!h.model.hasExceededReadingWait)
        #expect(await h.clock.pendingCount == 0)
        await h.clock.advance(by: .seconds(15))
        #expect(await h.peer.stateCalls == 3)
        #expect(await h.peer.nonReadCalls == 0)
    }

    @Test("P02 GET latency counts toward known reading wait without timeout or resend")
    func readingBeyondTwoMinutesRemainsWaiting() async throws {
        let h = CapturePollingHarness(holdSecondState: true)
        defer { h.model.invalidate() }
        await h.model.load()
        #expect(h.model.phase == .reading)
        let armed = await h.model.waitForPollingEvent()
        try #require(armed)
        let firstSleep = await h.clock.waitForRegistrations(1)
        try #require(firstSleep)
        await h.clock.advance(by: .milliseconds(1_500))
        let entered = await h.readGate.waitUntilEntered()
        try #require(entered)
        // GET2 stays held from t=1.5s through t=120.001s. Advancing beyond
        // many intervals cannot produce a second GET while it is in flight.
        await h.clock.advance(by: .milliseconds(118_499))
        #expect(await h.peer.stateCalls == 2)
        #expect(await h.clock.pendingCount == 0)
        #expect(!h.model.hasExceededReadingWait)
        #expect(h.model.phase == .reading)
        await h.clock.advance(by: .milliseconds(2))
        // A held GET does not start another poll GET, even past the threshold.
        #expect(await h.peer.stateCalls == 2)
        await h.readGate.release()
        let secondSleep = await h.clock.waitForRegistrations(2)
        try #require(secondSleep)
        #expect(h.model.hasExceededReadingWait)
        #expect(h.model.phase == .reading)
        #expect(h.model.state == CapturePollingHarness.waiting())
        #expect(await h.peer.nonReadCalls == 0)
        #expect(await h.clock.pendingCount == 1)
        // It keeps consulting; no automatic processingTimedOut/POST retry.
        await h.clock.advance(by: .milliseconds(1_500))
        let thirdRead = await h.peer.waitForStateCalls(3)
        try #require(thirdRead)
        let stopped = await h.model.waitForPollingEvent(untilStopped: true)
        try #require(stopped)
        #expect(h.model.state == CapturePollingHarness.terminal())
        #expect(h.model.phase == .ready)
        #expect(!h.model.hasExceededReadingWait)
        #expect(await h.clock.pendingCount == 0)
        #expect(await h.peer.nonReadCalls == 0)
    }
}
#endif
