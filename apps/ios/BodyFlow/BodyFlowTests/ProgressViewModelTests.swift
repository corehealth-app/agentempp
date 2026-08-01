import Foundation
import Testing

@testable import BodyFlow

@Suite("Progress View Model")
@MainActor
struct ProgressViewModelTests {
    @Test("complete progress response becomes loaded content")
    func loaded() async {
        let model = ProgressViewModel(
            provider: ProgressQueueProvider([.success(BodyFlowTestFixtures.progressResponse)])
        )

        await model.load()

        #expect(model.state == .loaded(BodyFlowTestFixtures.progressSnapshot))
    }

    @Test("an all-absent progress snapshot is the feature empty state")
    func empty() async {
        let empty = ProgressResponse(
            data: ProgressSnapshot(
                xpTotal: 0, level: 0, currentStreak: 0, longestStreak: 0,
                blocksCompleted: 0, deficitBlock: nil, currentWeight: nil,
                currentBodyFatPercent: nil, badgesEarned: [], lastActiveDate: nil,
                nextReevaluation: nil, updatedAt: BodyFlowTestFixtures.progressSnapshot.updatedAt
            ),
            meta: BodyFlowTestFixtures.progressResponse.meta
        )
        let model = ProgressViewModel(provider: ProgressQueueProvider([.success(empty)]))

        await model.load()

        #expect(model.state == .empty)
    }

    @Test("offline and recoverable failures retain exactly the received snapshot")
    func staleStates() async {
        let provider = ProgressQueueProvider([
            .success(BodyFlowTestFixtures.progressResponse), .failure(.offline),
            .failure(.serviceUnavailable),
        ])
        let model = ProgressViewModel(provider: provider)

        await model.load()
        await model.retry()
        #expect(model.state == .offline(previousValue: BodyFlowTestFixtures.progressSnapshot))

        await model.retry()
        #expect(model.state == .failed(
            previousValue: BodyFlowTestFixtures.progressSnapshot,
            error: .serviceUnavailable
        ))
    }

    @Test("initial capability outcomes map to every non-content read state")
    func initialStates() async {
        let offline = ProgressViewModel(provider: ProgressQueueProvider([.failure(.offline)]))
        await offline.load()
        #expect(offline.state == .offline(previousValue: nil))

        let failed = ProgressViewModel(provider: ProgressQueueProvider([.failure(.serviceUnavailable)]))
        await failed.load()
        #expect(failed.state == .failed(previousValue: nil, error: .serviceUnavailable))

        let unavailable = ProgressViewModel(provider: ProgressQueueProvider([.failure(.operationUnavailable)]))
        await unavailable.load()
        #expect(unavailable.state == .unavailable)
    }

    @Test("cancelled progress load cannot publish its late response or error")
    func cancellation() async {
        let provider = ProgressControlledProvider()
        let model = ProgressViewModel(provider: provider)

        let load = Task { await model.load() }
        await provider.waitUntilStarted(1)
        load.cancel()
        await provider.succeed(call: 1, with: BodyFlowTestFixtures.progressResponse)
        await load.value
        #expect(model.state == .idle)
    }

    @Test("newer progress load suppresses late results and errors")
    func supersession() async {
        let provider = ProgressControlledProvider()
        let model = ProgressViewModel(provider: provider)

        let older = Task { await model.load() }
        await provider.waitUntilStarted(1)
        let newer = Task { await model.load() }
        await provider.waitUntilStarted(2)
        await provider.succeed(call: 2, with: BodyFlowTestFixtures.progressResponse)
        await newer.value
        await provider.fail(call: 1, with: .serviceUnavailable)
        await older.value

        #expect(model.state == .loaded(BodyFlowTestFixtures.progressSnapshot))
    }
}

private actor ProgressQueueProvider: ProgressProviding {
    enum Outcome: Sendable { case success(ProgressResponse), failure(BodyFlowCapabilityError) }
    private var outcomes: [Outcome]
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    func progress() async throws -> ProgressResponse {
        guard !outcomes.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch outcomes.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}

private actor ProgressControlledProvider: ProgressProviding {
    private var calls = 0
    private var continuations: [Int: CheckedContinuation<ProgressResponse, Error>] = [:]
    func progress() async throws -> ProgressResponse {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }
    func waitUntilStarted(_ count: Int) async { while calls < count { await Task.yield() } }
    func succeed(call: Int, with response: ProgressResponse) { continuations.removeValue(forKey: call)?.resume(returning: response) }
    func fail(call: Int, with error: BodyFlowCapabilityError) { continuations.removeValue(forKey: call)?.resume(throwing: error) }
}
