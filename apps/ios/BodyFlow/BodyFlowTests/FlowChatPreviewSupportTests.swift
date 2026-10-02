#if DEBUG
import Foundation
import Testing

@testable import BodyFlow

@Suite("Flow Debug preview support")
struct FlowChatPreviewSupportTests {
    @Test
    func exactArgumentsRequireExistingDemoBoundaryAndSingleValidScene() {
        for scenario in FlowPreviewScenario.allCases {
            let flag = "--ui-testing-flow-\(scenario.rawValue)"
            #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", flag]) == scenario)
            #expect(FlowPreviewScenario.resolve(arguments: [flag]) == nil)
        }
        #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", "--ui-testing-flow-unknown"]) == nil)
        #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", "--ui-testing-flow-empty", "--ui-testing-flow-response"]) == nil)
        #expect(FlowPreviewScenario.resolve(arguments: ["--ui-testing", "--ui-testing-flow-empty", "--ui-testing-flow-empty"]) == nil)
        #expect(AppLaunchConfiguration.resolve(arguments: ["--ui-testing", "--ui-testing-flow-response"], buildFlavor: .release).mode == .releaseUnavailable)
        let reduceMotionArguments = ["--ui-testing", "--ui-testing-flow-longHistory", "--ui-testing-prompt13-reduce-motion"]
        #expect(FlowPreviewScenario.resolve(arguments: reduceMotionArguments) == .longHistory)
        #expect(AppLaunchConfiguration.resolve(arguments: reduceMotionArguments, buildFlavor: .debug).accessibilityReduceMotionOverride == true)
        #expect(AppLaunchConfiguration.resolve(arguments: reduceMotionArguments, buildFlavor: .release).accessibilityReduceMotionOverride == nil)
    }

    @Test
    func mockReplyIsLocalDeterministicAndExactKeyReplayDoesNotDuplicateHistory() async throws {
        let repository = FlowPreviewRepository(scenario: .empty)
        let key = try IdempotencyKey(validating: "flow-preview-test-key")
        let response = try await repository.send(text: "QA message", idempotencyKey: key)
        let replay = try await repository.send(text: "QA message", idempotencyKey: key)
        #expect(replay == response)
        let history = try await repository.history(limit: 50)
        #expect(history.messages.count == 2)
        #expect(history.messages.last == response.message)
        #expect(response.message.content.contains("QA"))
        #expect(response.message.content.contains("local"))
        #expect(await repository.sendCallCount == 2)
    }

    @Test
    func retryOnceRequiresExplicitRetryWithSameKey() async throws {
        let repository = FlowPreviewRepository(scenario: .retryOnce)
        let key = try IdempotencyKey(validating: "flow-preview-retry-key")
        await #expect(throws: URLError.self) {
            try await repository.send(text: "QA retry", idempotencyKey: key)
        }
        #expect(try await repository.history(limit: 50).messages.isEmpty)
        let response = try await repository.send(text: "QA retry", idempotencyKey: key)
        #expect(response.message.state == .completed)
        #expect(await repository.sentKeys == [key.value, key.value])
    }

    @Test
    func cancellationFixtureStaysPendingPastThirtyAndSixtyVirtualSeconds() async throws {
        let clock = FlowPreviewReplyClock()
        let repository = FlowPreviewRepository(scenario: .pendingCancellation) {
            try await clock.wait($0)
        }
        let key = try IdempotencyKey(validating: "flow-preview-pending-key")
        let send = Task { try await repository.send(text: "QA", idempotencyKey: key) }
        defer { send.cancel() }
        await clock.waitForRegistrations(1)
        #expect(await clock.pendingCount == 1)

        // The unchanged UI case can inspect Cancel only after a 60-second
        // XCTest idle wait. Advancing this clock does not consume wall time.
        await clock.advance(by: .seconds(30))
        #expect(await clock.pendingCount == 1)
        await clock.advance(by: .seconds(30))
        #expect(await clock.pendingCount == 1)
        #expect(try await repository.history(limit: 50).messages.isEmpty)
        send.cancel()
        await #expect(throws: CancellationError.self) { try await send.value }
        #expect(await clock.pendingCount == 0)
        #expect(try await repository.history(limit: 50).messages.isEmpty)

        #expect(await repository.sentKeys == [key.value])
        #expect(await repository.sendCallCount == 1)
    }

    @Test
    func defaultCancellationWaitExitsWithoutPublishingAReply() async throws {
        let entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        let repository = FlowPreviewRepository(scenario: .pendingCancellation) { duration in
            entered.continuation.yield(())
            try await FlowPreviewRepository.waitForReply(duration)
        }
        let key = try IdempotencyKey(validating: "flow-preview-default-cancel-key")
        let send = Task { try await repository.send(text: "QA", idempotencyKey: key) }
        defer { send.cancel() }
        var iterator = entered.stream.makeAsyncIterator()
        _ = await iterator.next()
        send.cancel()
        await #expect(throws: CancellationError.self) { try await send.value }
        #expect(try await repository.history(limit: 50).messages.isEmpty)
        #expect(await repository.sendCallCount == 1)
    }

    @Test
    func suppliedProcessingLongRawHistoryAndOfflineStayDistinct() async throws {
        let processing = try await FlowPreviewRepository(scenario: .processing).history(limit: 50)
        #expect(processing.messages.last?.state == .processing)
        let long = try await FlowPreviewRepository(scenario: .longHistory).history(limit: 50)
        #expect(long.messages.count == 40)
        #expect(Set(long.messages.map(\.role)) == [.user, .assistant])
        let response = try await FlowPreviewRepository(scenario: .response).history(limit: 50)
        #expect(response.messages.last?.content.contains("**QA literal**") == true)
        #expect((response.messages.last?.content.count ?? 0) > 2_000)
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await FlowPreviewRepository(scenario: .offline).history(limit: 50)
        }
    }
}

/// A test-only virtual clock. Registration is an explicit barrier; advancing
/// time and cancellation remove a waiter before resuming it exactly once.
private actor FlowPreviewReplyClock {
    private struct Waiter {
        let deadline: Duration?
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var now = Duration.zero
    private var registrations = 0
    private var waiters: [UUID: Waiter] = [:]
    private var registrationBarriers: [(Int, CheckedContinuation<Void, Never>)] = []
    var pendingCount: Int { waiters.count }

    func wait(_ duration: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[id] = Waiter(deadline: duration.map { now + $0 }, continuation: continuation)
                registrations += 1
                let ready = registrationBarriers.filter { $0.0 <= registrations }
                registrationBarriers.removeAll { $0.0 <= registrations }
                for (_, barrier) in ready { barrier.resume() }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func waitForRegistrations(_ count: Int) async {
        if registrations >= count { return }
        await withCheckedContinuation { registrationBarriers.append((count, $0)) }
    }

    func advance(by duration: Duration) {
        now += duration
        let ready = waiters.compactMap { id, waiter in
            waiter.deadline.map { $0 <= now } == true ? id : nil
        }
        for id in ready { waiters.removeValue(forKey: id)?.continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}
#endif
