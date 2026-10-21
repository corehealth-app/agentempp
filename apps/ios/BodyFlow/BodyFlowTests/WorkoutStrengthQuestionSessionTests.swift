import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Workout strength question presentation ownership")
struct WorkoutStrengthQuestionSessionTests {
    @Test("confirmation to history retains uncertain intent and only reads on reentry")
    func reentryKeepsIntent() async throws {
        let h = SessionQuestionHarness()
        let first = try h.attach()
        await first.refresh()
        await first.answer(.yes)
        let attempt = try #require(first.model.pendingAttempt)
        first.end()
        #expect(h.session.retainedCount == 1)
        let history = try h.attach()
        #expect(history.model === first.model)
        await history.refresh()
        #expect(history.model.pendingAttempt == attempt)
        #expect(await h.provider.attempts == [attempt])
        #expect(await h.provider.reads == [sessionWorkout, sessionWorkout])
        await h.provider.accept(sessionWorkout, .yes)
        await history.refresh()
        #expect(history.model.pendingAttempt == nil)
        #expect(h.center.revision(for: .history) == 1)
        await history.refresh()
        #expect(h.center.revision(for: .history) == 1)
        first.end()
        #expect(history.isCurrent)
        history.end()
        #expect(h.session.retainedCount == 0)
    }

    @Test("an old host cannot cancel, answer, read or end a new host's operation")
    func oldPresentationCannotControlNewHost() async throws {
        let h = SessionQuestionHarness()
        let first = try h.attach()
        await first.refresh()
        let second = try h.attach()
        #expect(!first.isCurrent && second.isCurrent)
        await second.refresh()
        await h.provider.holdNextAnswer()
        let sending = Task { await second.answer(.yes); await h.provider.noteAnswerCompletion() }
        do {
        let entered = await h.provider.waitUntilHeldOrCompleted()
        try #require(entered, "SETUP_FAIL: answer returned without entering the controlled hold")
        let original = try #require(second.model.pendingAttempt)
        first.cancelWait()
        first.end()
        await first.answer(.no)
        await first.retryAnswer()
        await first.refresh()
        #expect(second.model.isSubmitting)
        #expect(second.isCurrent)
        #expect(await h.provider.attempts == [original])
        #expect(await h.provider.reads == [sessionWorkout, sessionWorkout])
        await h.provider.releaseAnswer()
        await sending.value
        #expect(second.model.pendingAttempt == original)
        #expect(second.model.canRetryAnswer)
        second.end()
        } catch { await h.provider.releaseAnswer(); await sending.value; throw error }
    }

    @Test("transfer cancels only the old wait; its late result cannot finish the new read")
    func transferDoesNotPublishOldAnswer() async throws {
        let h = SessionQuestionHarness()
        let first = try h.attach()
        await first.refresh()
        await h.provider.holdNextAnswer()
        let sending = Task { await first.answer(.yes); await h.provider.noteAnswerCompletion() }
        do {
        let entered = await h.provider.waitUntilHeldOrCompleted()
        try #require(entered, "SETUP_FAIL: answer returned without entering the controlled hold")
        let original = try #require(first.model.pendingAttempt)
        let history = try h.attach()
        #expect(!history.model.isBusy)
        #expect(history.model.pendingAttempt == original)
        await history.refresh()
        await h.provider.releaseAnswer()
        await sending.value
        #expect(history.model.pendingAttempt == original)
        #expect(h.center.revision(for: .history) == 0)
        history.end()
        } catch { await h.provider.releaseAnswer(); await sending.value; throw error }
    }

    @Test("capacity preserves all uncertain attempts, then a resolved entry releases its slot")
    func boundedUncertainRetention() async throws {
        let h = SessionQuestionHarness()
        var original: [MutationAttempt<WorkoutStrengthAnswerCommand>] = []
        for index in 1...16 {
            let lease = try h.attach(id: sessionID(index))
            await lease.refresh()
            await lease.answer(.yes)
            original.append(try #require(lease.model.pendingAttempt))
            lease.end()
        }
        #expect(h.session.retainedCount == 16)
        #expect(throws: WorkoutStrengthQuestionSessionError.capacityUnavailable) { try h.attach(id: sessionID(17)) }
        #expect(await h.provider.attempts == original)
        let first = try h.attach(id: sessionID(1))
        #expect(first.model.pendingAttempt == original[0])
        await h.provider.accept(sessionID(1), .yes)
        await first.refresh()
        first.end()
        #expect(h.session.retainedCount == 15)
        let next = try h.attach(id: sessionID(17))
        #expect(next.isCurrent)
        #expect(await h.provider.attempts == original)
        h.session.close()
        #expect(h.session.retainedCount == 0)
        #expect(!next.isCurrent)
    }

    @Test("retired activation and close revoke every action without renewing a session")
    func teardownRetiresPresentations() async throws {
        let h = SessionQuestionHarness()
        let presentation = try h.attach()
        await presentation.refresh()
        h.activation.current = false
        #expect(!presentation.isCurrent)
        await presentation.answer(.yes)
        await presentation.refresh()
        #expect(await h.provider.reads.count == 1)
        #expect(await h.provider.attempts.isEmpty)
        h.session.close()
        h.activation.current = true // a new A must never revive the old coordinator
        #expect(throws: WorkoutStrengthQuestionSessionError.inactive) { try h.attach() }
        #expect(!presentation.isCurrent)
        #expect(h.session.retainedCount == 0)
    }

    @Test("new presentation cannot answer the cached question before its own GET")
    func cachedQuestionIsNotNewReadAuthority() async throws {
        let h = SessionQuestionHarness()
        let first = try h.attach()
        await first.refresh()
        let second = try h.attach()
        await second.answer(.yes)
        #expect(await h.provider.attempts.isEmpty)
        #expect(second.model.pendingAttempt == nil)
        await second.refresh()
        await second.answer(.yes)
        #expect(await h.provider.attempts.count == 1)
        second.end()
    }

    @Test("cancelling the entry GET cannot enable the old cached unanswered snapshot")
    func cancelledEntryReadDoesNotAuthorizeAnswer() async throws {
        let h = SessionQuestionHarness()
        let first = try h.attach()
        await first.refresh()
        let second = try h.attach()
        await h.provider.holdNextRead()
        let reading = Task { await second.refresh(); await h.provider.noteReadCompletion() }
        do {
        let entered = await h.provider.waitUntilReadHeldOrCompleted()
        try #require(entered, "SETUP_FAIL: read returned without entering the controlled hold")
        second.cancelWait()
        await second.answer(.no)
        #expect(await h.provider.attempts.isEmpty)
        #expect(second.model.pendingAttempt == nil)
        await h.provider.releaseRead()
        await reading.value
        await second.answer(.yes)
        #expect(await h.provider.attempts.isEmpty)
        second.end()
        } catch { await h.provider.releaseRead(); await reading.value; throw error }
    }

    @Test("queued capacity recovery cannot attach or read after host departure")
    func capacityRetryIsRetiredOnDeparture() async throws {
        let h = SessionQuestionHarness()
        for index in 1...16 {
            let lease = try h.attach(id: sessionID(index))
            await lease.refresh()
            await lease.answer(.yes)
            lease.end()
        }
        let state = WorkoutStrengthQuestionHostState(configuration: h.configuration(id: sessionID(17)))
        await state.open()
        #expect(state.capacityUnavailable)
        let reads = await h.provider.reads
        let writes = await h.provider.attempts
        let queued = state.retryAttachment()
        state.close() // no await between enqueue and departure
        await queued?.value
        #expect(state.presentation == nil)
        #expect(!state.capacityUnavailable)
        #expect(await h.provider.reads == reads)
        #expect(await h.provider.attempts == writes)
        #expect(h.session.retainedCount == 16)
        h.session.close()
    }

    @Test("host actions use the captured presentation; reopening never submits from the old callback")
    func hostActionsRemainScopedToTheirPresentation() async throws {
        let h = SessionQuestionHarness()
        let state = WorkoutStrengthQuestionHostState(configuration: h.configuration())
        await state.open()
        let first = try #require(state.presentation)
        let sending = state.perform(.answer(.yes), lease: first)
        await sending?.value
        let original = try #require(first.model.pendingAttempt)
        state.close()
        await state.open()
        let current = try #require(state.presentation)
        #expect(current !== first)
        #expect(current.model === first.model)
        #expect(state.perform(.answer(.no), lease: first) == nil)
        #expect(state.perform(.cancelWait, lease: first) == nil)
        #expect(current.isCurrent)
        let retry = state.perform(.retry, lease: current)
        await retry?.value
        #expect(await h.provider.attempts == [original, original])
        state.close()
        h.session.close()
    }

    @Test("invalid UUID cannot allocate an entry or read")
    func invalidID() throws {
        let h = SessionQuestionHarness()
        #expect(throws: BodyFlowCapabilityError.invalidInput) { try h.attach(id: "pending-id") }
        #expect(h.session.retainedCount == 0)
    }
}

private let sessionWorkout = "b2800000-0000-4000-8000-000000000001"
private func sessionID(_ index: Int) -> String { String(format: "b2800000-0000-4000-8000-%012d", index) }
@MainActor private final class QuestionActivation { var current = true }
@MainActor
private struct SessionQuestionHarness {
    let provider: SessionQuestionProvider
    let activation: QuestionActivation
    let center: FeatureInvalidationCenter
    let session: WorkoutStrengthQuestionSession
    let keys = SessionQuestionKeys()
    init() {
        let provider = SessionQuestionProvider()
        let activation = QuestionActivation()
        self.provider = provider
        self.activation = activation
        center = FeatureInvalidationCenter()
        session = WorkoutStrengthQuestionSession(provider: provider, isSessionActive: { activation.current })
    }
    func configuration(id: String = sessionWorkout) -> WorkoutStrengthQuestionConfiguration {
        WorkoutStrengthQuestionConfiguration(workoutID: id,
            identity: .init(context: ObjectIdentifier(session), workoutID: id), session: session,
            timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1_792_500_000)),
            keyProvider: keys, invalidationCenter: center)
    }
    func attach(id: String = sessionWorkout) throws -> WorkoutStrengthQuestionPresentation {
        try session.attach(workoutID: id, timeProvider: FixedTimeProvider(value: Date(timeIntervalSince1970: 1_792_500_000)),
            keyProvider: keys, invalidationCenter: center)
    }
}
private actor SessionQuestionProvider: WorkoutStrengthClarificationProviding {
    private(set) var reads: [String] = []
    private(set) var attempts: [MutationAttempt<WorkoutStrengthAnswerCommand>] = []
    private var accepted: [String: WorkoutStrengthAnswer] = [:]
    private var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Bool, Never>] = []
    private var answerCompleted = false
    private var holdRead = false
    private var readHold: CheckedContinuation<Void, Never>?
    private var readWaiters: [CheckedContinuation<Bool, Never>] = []
    private var readCompleted = false
    func load(workoutID: String) async throws -> WorkoutStrengthClarificationResponse {
        reads.append(workoutID)
        if holdRead {
            holdRead = false
            await withCheckedContinuation { continuation in
                readHold = continuation
                let waiters = readWaiters; readWaiters.removeAll(); waiters.forEach { $0.resume(returning: true) }
            }
        }
        let q = try #require(WorkoutStrengthQuestion(workoutID: workoutID,
            lifecycleKey: "c3900000-0000-4000-8000-000000000001", factRevision: 0,
            questionKey: "d4a00000-0000-4000-8000-000000000001"))
        let value: WorkoutStrengthClarification
        if let answer = accepted[workoutID] {
            value = .answered(try #require(WorkoutStrengthAnswerReceipt(scope: q.scope, questionKey: q.questionKey,
                answer: answer, acceptedAt: "2026-10-21T01:02:03.123456Z")))
        } else { value = .unanswered(q) }
        return MobileResponse(data: value, meta: MobileResponseMetadata(apiVersion: "v1", requestID: "synthetic-session"))
    }
    func answer(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) async throws -> WorkoutStrengthClarificationResponse {
        attempts.append(attempt)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { continuation in
                held = continuation
                let waiters = heldWaiters; heldWaiters.removeAll(); waiters.forEach { $0.resume(returning: true) }
            }
        }
        throw BodyFlowCapabilityError.offline
    }
    func holdNextRead() { holdRead = true; readCompleted = false }
    func waitUntilReadHeldOrCompleted() async -> Bool {
        if readHold != nil { return true }
        if readCompleted { return false }
        return await withCheckedContinuation { readWaiters.append($0) }
    }
    func noteReadCompletion() {
        readCompleted = true
        let waiters = readWaiters; readWaiters.removeAll()
        waiters.forEach { $0.resume(returning: false) }
    }
    func releaseRead() { readHold?.resume(); readHold = nil }
    func holdNextAnswer() { holdNext = true; answerCompleted = false }
    func waitUntilHeldOrCompleted() async -> Bool {
        if held != nil { return true }
        if answerCompleted { return false }
        return await withCheckedContinuation { heldWaiters.append($0) }
    }
    func noteAnswerCompletion() {
        answerCompleted = true
        let waiters = heldWaiters; heldWaiters.removeAll()
        waiters.forEach { $0.resume(returning: false) }
    }
    func releaseAnswer() { held?.resume(); held = nil }
    func accept(_ id: String, _ answer: WorkoutStrengthAnswer) { accepted[id] = answer }
}

private final class SessionQuestionKeys: @unchecked Sendable, IdempotencyKeyProviding {
    private let lock = NSLock()
    private var sequence = 0
    func nextKey() throws -> IdempotencyKey {
        let value = lock.withLock { sequence += 1; return sequence }
        return try IdempotencyKey(validating: String(format: "e5b00000-0000-4000-8000-%012d", value))
    }
}
