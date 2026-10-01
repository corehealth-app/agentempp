import Foundation
import Testing

@testable import BodyFlow

@Suite("Today Refresh Coordinator")
@MainActor
struct TodayRefreshCoordinatorTests {
    @Test("two overlapping refresh gestures run all providers only once")
    func overlappingRefreshIsOneOperation() async {
        let coordinator = TodayRefreshCoordinator()
        let probe = ControlledTodayRefresh()

        let first = Task { await coordinator.run { await probe.suspend() } }
        for _ in 0..<1_000 where probe.calls == 0 { await Task.yield() }
        #expect(probe.calls == 1)

        let second = Task { await coordinator.run { await probe.suspend() } }
        for _ in 0..<1_000 {
            if probe.calls > 1 { break }
            await Task.yield()
        }
        #expect(probe.calls == 1)
        #expect(coordinator.isRunning)

        probe.releaseAll()
        await first.value
        await second.value
        #expect(!coordinator.isRunning)

        await coordinator.run { probe.recordCompletedCall() }
        #expect(probe.calls == 2)
    }

    @Test("failure and cancellation release the next manual refresh")
    func failureAndCancellationReleaseGate() async {
        let coordinator = TodayRefreshCoordinator()
        await #expect(throws: RefreshFailure.self) {
            try await coordinator.run { throw RefreshFailure() }
        }
        #expect(!coordinator.isRunning)

        let waiting = Task {
            await coordinator.run {
                try? await Task.sleep(for: .seconds(60))
            }
        }
        for _ in 0..<1_000 where !coordinator.isRunning { await Task.yield() }
        #expect(coordinator.isRunning)
        waiting.cancel()
        await waiting.value
        #expect(!coordinator.isRunning)

        var didRun = false
        await coordinator.run { didRun = true }
        #expect(didRun)
    }
}

private struct RefreshFailure: Error {}

@MainActor
private final class ControlledTodayRefresh {
    private(set) var calls = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var shouldSuspend = true

    func suspend() async {
        calls += 1
        guard shouldSuspend else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseAll() {
        shouldSuspend = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func recordCompletedCall() { calls += 1 }
}
