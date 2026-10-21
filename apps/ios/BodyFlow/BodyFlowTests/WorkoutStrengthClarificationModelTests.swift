import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Owned workout strength question model")
struct WorkoutStrengthClarificationModelTests {
    @Test("only an official current unanswered question enables a choice", arguments: ["unanswered", "answered", "notApplicable", "unavailable"])
    func initialStates(_ state: String) async throws {
        let value: WorkoutStrengthClarification = switch state {
        case "answered": try receipt()
        case "notApplicable": .notApplicable(try question().scope)
        case "unavailable": .unavailable
        default: .unanswered(try question())
        }
        let h = try harness(reads: [.value(value)])
        await h.model.load()
        await h.model.load()
        #expect(h.model.snapshot == value)
        #expect(h.model.canAnswer == (state == "unanswered"))
        #expect(!h.model.isBusy)
        #expect(h.model.failure == nil)
        #expect(await h.provider.reads == [workout])
        #expect(h.center.revision(for: .history) == 0)
    }

    @Test("read error retries only GET and keeps the prior snapshot")
    func readRetry() async throws {
        let q = try question()
        let h = try harness(reads: [.value(.unanswered(q)), .error(.offline), .value(.unanswered(q))])
        await h.model.load()
        await h.model.reload()
        #expect(h.model.snapshot == .unanswered(q))
        #expect(h.model.failure == .capability(.offline))
        #expect(!h.model.canAnswer)
        await h.model.reload()
        #expect(h.model.failure == nil)
        #expect(h.model.canAnswer)
        #expect(await h.provider.reads == [workout, workout, workout])
        #expect(await h.provider.attempts.isEmpty)
    }

    @Test("a foreign workout cannot authorize an answer")
    func foreignRead() async throws {
        let h = try harness(reads: [.value(.unanswered(try question(workoutID: other)))])
        await h.model.load()
        await h.model.answer(.yes)
        #expect(h.model.snapshot == nil)
        #expect(h.model.failure == .capability(.serviceUnavailable))
        #expect(await h.provider.attempts.isEmpty)
    }

    @Test("held initial load is deduplicated; reverse reads cannot publish old success or error", arguments: [false, true])
    func invertedReads(oldFails: Bool) async throws {
        let h = try harness(reads: [.hold, .hold])
        let old = Task { await h.model.load() }
        await h.provider.waitForCalls(1)
        await h.model.load()
        #expect(await h.provider.reads.count == 1)
        let current = Task { await h.model.reload() }
        await h.provider.waitForCalls(2)
        await h.provider.release(0, oldFails ? .error(.offline) : .value(try receipt()))
        await old.value
        #expect(h.model.isLoading)
        #expect(h.model.snapshot == nil)
        #expect(h.model.failure == nil)
        let expected = WorkoutStrengthClarification.unanswered(try question())
        await h.provider.release(1, .value(expected))
        await current.value
        #expect(h.model.snapshot == expected)
        #expect(!h.model.isBusy)
        #expect(h.center.revision(for: .today) == 0)
    }

    @Test("yes and no publish the official POST without GET and invalidate once", arguments: [WorkoutStrengthAnswer.yes, .no])
    func officialPost(answer: WorkoutStrengthAnswer) async throws {
        let official = try receipt(answer: answer)
        let h = try harness(reads: [.value(.unanswered(try question()))], writes: [.value(official)])
        await h.model.load()
        await h.model.answer(answer)
        await h.model.retryAnswer()
        await h.model.answer(answer == .yes ? .no : .yes)
        let attempts = await h.provider.attempts
        #expect(attempts.count == 1)
        let attempt = try #require(attempts.first)
        #expect(attempt.operation == .workoutStrengthAnswer)
        #expect(attempt.key.value == key)
        #expect(attempt.createdAt == instant)
        #expect(try attempt.payload.question == question())
        #expect(attempt.payload.answer == answer)
        #expect(h.model.snapshot == official)
        #expect(h.model.pendingAttempt == nil)
        #expect(!h.model.canAnswer && !h.model.canRetryAnswer)
        #expect(h.center.revision(for: .today) == 1)
        #expect(h.center.revision(for: .history) == 1)
        #expect(await h.provider.reads.count == 1)
        #expect(h.keys.calls == 1)
    }

    @Test("double tap and timeout retry preserve the original immutable attempt", arguments: [WorkoutStrengthAnswer.yes, .no])
    func uncertainRetry(answer: WorkoutStrengthAnswer) async throws {
        let h = try harness(reads: [.value(.unanswered(try question()))], writes: [.hold, .value(try receipt(answer: answer))])
        await h.model.load()
        let send = Task { await h.model.answer(answer) }
        await h.provider.waitForCalls(2)
        let original = try #require(h.model.pendingAttempt)
        await h.model.answer(answer)
        await h.model.answer(answer == .yes ? .no : .yes)
        await h.model.retryAnswer()
        #expect(h.model.isSubmitting)
        #expect(await h.provider.attempts == [original])
        await h.provider.release(1, .error(.offline))
        await send.value
        #expect(h.model.failure == .capability(.offline))
        #expect(h.model.pendingAttempt == original)
        #expect(h.model.canRetryAnswer)
        await h.model.answer(answer == .yes ? .no : .yes)
        #expect(await h.provider.attempts.count == 1)
        await h.model.retryAnswer()
        #expect(await h.provider.attempts == [original, original])
        #expect(h.keys.calls == 1)
        #expect(h.center.revision(for: .history) == 1)
    }

    @Test("explicit read can recover lost acknowledgement; ordinary answered reads never loop invalidation")
    func readRecovery() async throws {
        let q = try question()
        let accepted = try receipt()
        let h = try harness(reads: [.value(.unanswered(q)), .value(.unanswered(q)), .value(accepted), .value(accepted)], writes: [.error(.offline)])
        await h.model.load()
        await h.model.answer(.yes)
        let original = try #require(h.model.pendingAttempt)
        await h.model.reload()
        #expect(h.model.pendingAttempt == original)
        #expect(h.model.canRetryAnswer)
        #expect(!h.model.canAnswer)
        #expect(h.center.revision(for: .today) == 0)
        await h.model.reload()
        #expect(h.model.snapshot == accepted)
        #expect(h.model.pendingAttempt == nil)
        #expect(h.center.revision(for: .today) == 1)
        await h.model.reload()
        #expect(h.center.revision(for: .today) == 1)
        #expect(h.center.revision(for: .history) == 1)
        #expect(await h.provider.attempts == [original])
    }

    @Test("divergent official GET never rebases an uncertain answer", arguments: ["answer", "lifecycle", "question", "unansweredLifecycle", "unansweredQuestion", "unavailable", "notApplicable"])
    func divergentRecovery(_ variant: String) async throws {
        let changed = try question(lifecycle: ["lifecycle", "unansweredLifecycle"].contains(variant) ? other : lifecycle,
                                   questionID: ["question", "unansweredQuestion"].contains(variant) ? other : questionID)
        let value: WorkoutStrengthClarification = switch variant {
        case "unavailable": .unavailable
        case "notApplicable": .notApplicable(changed.scope)
        case "unansweredLifecycle", "unansweredQuestion": .unanswered(changed)
        default: try receipt(q: changed, answer: variant == "answer" ? .no : .yes)
        }
        let h = try harness(reads: [.value(.unanswered(try question())), .value(value)], writes: [.error(.offline)])
        await h.model.load()
        await h.model.answer(.yes)
        let original = try #require(h.model.pendingAttempt)
        await h.model.reload()
        #expect(h.model.pendingAttempt == original)
        #expect(!h.model.canAnswer && !h.model.canRetryAnswer)
        #expect(h.model.failure != nil)
        await h.model.retryAnswer()
        await h.model.answer(.no)
        #expect(await h.provider.attempts == [original])
        #expect(h.center.revision(for: .history) == 0)
    }

    @Test("definitive errors stay distinct and GET cannot unlock that write", arguments: [WorkoutStrengthClarificationError.contextUnavailable, .answerConflict, .disabled])
    func definitiveErrors(_ error: WorkoutStrengthClarificationError) async throws {
        let q = try question()
        let h = try harness(reads: [.value(.unanswered(q)), .value(.unanswered(q))], writes: [.local(error)])
        await h.model.load()
        await h.model.answer(.yes)
        let expected: WorkoutStrengthClarificationFailure = switch error {
        case .contextUnavailable: .contextUnavailable
        case .answerConflict: .answerConflict
        case .disabled: .disabled
        }
        #expect(h.model.failure == expected)
        let original = try #require(h.model.pendingAttempt)
        #expect(!h.model.canRetryAnswer)
        await h.model.reload()
        await h.model.retryAnswer()
        await h.model.answer(.no)
        #expect(h.model.pendingAttempt == original)
        #expect(!h.model.canAnswer && !h.model.canRetryAnswer)
        #expect(await h.provider.attempts == [original])
    }

    @Test("official matching GET resolves a blocked attempt without reauthorizing any POST", arguments: [WorkoutStrengthClarificationError.contextUnavailable, .answerConflict, .disabled])
    func officialReadAfterDefinitiveError(_ error: WorkoutStrengthClarificationError) async throws {
        let accepted = try receipt()
        let h = try harness(reads: [.value(.unanswered(try question())), .value(accepted), .value(accepted)], writes: [.local(error)])
        await h.model.load()
        await h.model.answer(.yes)
        let original = try #require(h.model.pendingAttempt)
        #expect(!h.model.canRetryAnswer)
        await h.model.reload()
        #expect(h.model.snapshot == accepted)
        #expect(h.model.pendingAttempt == nil)
        #expect(h.model.failure == nil)
        #expect(!h.model.canAnswer && !h.model.canRetryAnswer)
        #expect(h.center.revision(for: .today) == 1)
        #expect(h.center.revision(for: .history) == 1)
        await h.model.reload()
        await h.model.retryAnswer()
        await h.model.answer(.no)
        #expect(h.center.revision(for: .today) == 1)
        #expect(h.center.revision(for: .history) == 1)
        #expect(await h.provider.attempts == [original])
        #expect(h.keys.calls == 1)
    }

    @Test("an injected POST must match workout, lifecycle, question and answer", arguments: ["workout", "lifecycle", "question", "answer", "unanswered", "unavailable"])
    func incoherentPost(_ variant: String) async throws {
        let q = try question(workoutID: variant == "workout" ? other : workout,
                             lifecycle: ["lifecycle", "unansweredLifecycle"].contains(variant) ? other : lifecycle,
                             questionID: ["question", "unansweredQuestion"].contains(variant) ? other : questionID)
        let result: WorkoutStrengthClarification = switch variant {
        case "unanswered": .unanswered(q)
        case "unavailable": .unavailable
        default: try receipt(q: q, answer: variant == "answer" ? .no : .yes)
        }
        let h = try harness(reads: [.value(.unanswered(try question()))], writes: [.value(result)])
        await h.model.load()
        await h.model.answer(.yes)
        #expect(h.model.snapshot == .unanswered(try question()))
        #expect(h.model.failure == .capability(.serviceUnavailable))
        #expect(h.model.pendingAttempt != nil)
        #expect(h.center.revision(for: .history) == 0)
    }

    @Test("local cancel frees only its busy; late POST cannot clear or publish over retry", arguments: [false, true])
    func cancelThenRetry(oldFails: Bool) async throws {
        let h = try harness(reads: [.value(.unanswered(try question()))], writes: [.hold, .hold])
        await h.model.load()
        let old = Task { await h.model.answer(.yes) }
        await h.provider.waitForCalls(2)
        let original = try #require(h.model.pendingAttempt)
        h.model.cancel()
        #expect(!h.model.isBusy)
        #expect(h.model.pendingAttempt == original)
        #expect(h.model.canRetryAnswer && !h.model.canAnswer)
        let current = Task { await h.model.retryAnswer() }
        await h.provider.waitForCalls(3)
        await h.provider.release(1, oldFails ? .error(.offline) : .value(try receipt()))
        await old.value
        #expect(h.model.isSubmitting)
        #expect(h.model.pendingAttempt == original)
        #expect(h.model.failure == nil)
        #expect(h.center.revision(for: .history) == 0)
        await h.provider.release(2, .value(try receipt()))
        await current.value
        #expect(h.model.pendingAttempt == nil)
        #expect(!h.model.isBusy)
        #expect(h.center.revision(for: .history) == 1)
        #expect(await h.provider.attempts == [original, original])
    }

    @Test("task cancellation or retired original A ticket suppresses late success and error", arguments: ["task", "session", "ABA"], [false, true])
    func retiredOperations(boundary: String, fails: Bool) async throws {
        let h = try harness(reads: [.value(.unanswered(try question()))], writes: [.hold])
        await h.model.load()
        let send = Task { await h.model.answer(.yes) }
        await h.provider.waitForCalls(2)
        if boundary == "task" { send.cancel() }
        else { h.session.ticket = boundary == "ABA" ? 3 : 2 }
        await h.provider.release(1, fails ? .error(.offline) : .value(try receipt()))
        await send.value
        #expect(h.model.snapshot == .unanswered(try question()))
        #expect(h.model.failure == nil)
        #expect(!h.model.isBusy)
        #expect(h.model.pendingAttempt != nil)
        #expect(h.center.revision(for: .history) == 0)
        if boundary != "task" {
            await h.model.retryAnswer()
            await h.model.reload()
            #expect(await h.provider.reads.count == 1)
            #expect(await h.provider.attempts.count == 1)
        }
    }

    @Test("read cancellation allows a new read without the old finalizer clearing its busy")
    func cancelRead() async throws {
        let h = try harness(reads: [.hold, .hold])
        let old = Task { await h.model.load() }
        await h.provider.waitForCalls(1)
        h.model.cancel()
        #expect(h.model.pendingAttempt == nil)
        let current = Task { await h.model.load() }
        await h.provider.waitForCalls(2)
        await h.provider.release(0, .error(.offline))
        await old.value
        #expect(h.model.isLoading)
        #expect(h.model.failure == nil)
        await h.provider.release(1, .value(.unavailable))
        await current.value
        #expect(h.model.snapshot == .unavailable)
        #expect(!h.model.isBusy)
    }

    @Test("invalid workout and key never reach a provider")
    func invalidIdentityAndKey() async throws {
        let h = try harness(reads: [.value(.unanswered(try question()))], keyValue: "mobile-not-a-uuid")
        #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try WorkoutStrengthClarificationModel(workoutID: "pending-id", provider: h.provider,
                timeProvider: StrengthModelClock(), keyProvider: h.keys, invalidationCenter: h.center,
                isSessionActive: { true })
        }
        await h.model.load()
        await h.model.answer(.yes)
        #expect(h.model.failure == .capability(.invalidIdempotencyKey))
        #expect(h.model.pendingAttempt == nil)
        #expect(await h.provider.attempts.isEmpty)
    }
}

private let workout = "b2800000-0000-4000-8000-000000000001"
private let lifecycle = "c3900000-0000-4000-8000-000000000001"
private let questionID = "d4a00000-0000-4000-8000-000000000001"
private let other = "f6c00000-0000-4000-8000-000000000001"
private let key = "e5b00000-0000-4000-8000-000000000001"
private let instant = Date(timeIntervalSince1970: 1_792_500_000)
private func question(workoutID: String = workout, lifecycle: String = lifecycle, questionID: String = questionID) throws -> WorkoutStrengthQuestion {
    try #require(WorkoutStrengthQuestion(workoutID: workoutID, lifecycleKey: lifecycle, factRevision: 0, questionKey: questionID))
}
private func receipt(q: WorkoutStrengthQuestion? = nil, answer: WorkoutStrengthAnswer = .yes) throws -> WorkoutStrengthClarification {
    let q = try q ?? question()
    return .answered(try #require(WorkoutStrengthAnswerReceipt(scope: q.scope, questionKey: q.questionKey,
        answer: answer, acceptedAt: "2026-10-21T01:02:03.123456Z")))
}
private struct StrengthModelClock: TimeProviding { var now: Date { instant } }
private final class StrengthModelKeys: @unchecked Sendable, IdempotencyKeyProviding {
    private let lock = NSLock()
    private var count = 0
    let value: String
    init(value: String = key) { self.value = value }
    var calls: Int { lock.withLock { count } }
    func nextKey() throws -> IdempotencyKey {
        lock.withLock { count += 1 }
        return try IdempotencyKey(validating: value)
    }
}
@MainActor
private final class StrengthModelSession { var ticket = 1 }
@MainActor
private struct StrengthModelHarness {
    let model: WorkoutStrengthClarificationModel
    let provider: StrengthModelProvider
    let keys: StrengthModelKeys
    let center: FeatureInvalidationCenter
    let session: StrengthModelSession
}
@MainActor
private func harness(reads: [StrengthModelReply], writes: [StrengthModelReply] = [], keyValue: String = key) throws -> StrengthModelHarness {
    let provider = StrengthModelProvider(reads: reads, writes: writes)
    let keys = StrengthModelKeys(value: keyValue)
    let center = FeatureInvalidationCenter()
    let session = StrengthModelSession()
    let model = try WorkoutStrengthClarificationModel(workoutID: workout.uppercased(), provider: provider,
        timeProvider: StrengthModelClock(), keyProvider: keys, invalidationCenter: center,
        isSessionActive: { session.ticket == 1 })
    return StrengthModelHarness(model: model, provider: provider, keys: keys, center: center, session: session)
}
private enum StrengthModelReply: Sendable {
    case value(WorkoutStrengthClarification)
    case error(BodyFlowCapabilityError)
    case local(WorkoutStrengthClarificationError)
    case hold
    func response() throws -> WorkoutStrengthClarificationResponse {
        switch self {
        case let .value(value): MobileResponse(data: value, meta: MobileResponseMetadata(apiVersion: "v1", requestID: "synthetic-model"))
        case let .error(error): throw error
        case let .local(error): throw error
        case .hold: throw BodyFlowCapabilityError.serviceUnavailable
        }
    }
}
private actor StrengthModelProvider: WorkoutStrengthClarificationProviding {
    var readReplies: [StrengthModelReply]
    var writeReplies: [StrengthModelReply]
    private(set) var reads: [String] = []
    private(set) var attempts: [MutationAttempt<WorkoutStrengthAnswerCommand>] = []
    private var calls = 0
    private var waits: [(Int, CheckedContinuation<Void, Never>)] = []
    private var held: [Int: CheckedContinuation<StrengthModelReply, Never>] = [:]
    init(reads: [StrengthModelReply], writes: [StrengthModelReply]) { readReplies = reads; writeReplies = writes }
    func load(workoutID: String) async throws -> WorkoutStrengthClarificationResponse {
        reads.append(workoutID)
        return try await next(readReplies.isEmpty ? .error(.serviceUnavailable) : readReplies.removeFirst())
    }
    func answer(_ attempt: MutationAttempt<WorkoutStrengthAnswerCommand>) async throws -> WorkoutStrengthClarificationResponse {
        attempts.append(attempt)
        return try await next(writeReplies.isEmpty ? .error(.serviceUnavailable) : writeReplies.removeFirst())
    }
    private func next(_ reply: StrengthModelReply) async throws -> WorkoutStrengthClarificationResponse {
        let index = calls
        calls += 1
        if case .hold = reply {
            let result: StrengthModelReply = await withCheckedContinuation { continuation in
                held[index] = continuation
                releaseWaiters()
            }
            return try result.response()
        }
        releaseWaiters()
        return try reply.response()
    }
    private func releaseWaiters() {
        let ready = waits.filter { calls >= $0.0 }
        waits.removeAll { calls >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
    func waitForCalls(_ target: Int) async {
        if calls >= target { return }
        await withCheckedContinuation { waits.append((target, $0)) }
    }
    func release(_ index: Int, _ reply: StrengthModelReply) { held.removeValue(forKey: index)?.resume(returning: reply) }
}
