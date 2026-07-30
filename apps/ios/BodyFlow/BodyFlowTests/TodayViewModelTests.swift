import Foundation
import Testing

@testable import BodyFlow

@Suite("Today View Model")
@MainActor
struct TodayViewModelTests {
    @Test("revision zero loads one complete official snapshot")
    func initialLoad() async throws {
        let snapshot = try Self.snapshot(localDate: "2026-07-20")
        let provider = TodayQueueProvider([.success(snapshot)])
        let model = TodayViewModel(provider: provider)

        await model.load(revision: 0)

        #expect(model.state == .loaded(snapshot.data))
        #expect(await provider.callCount == 1)
    }

    @Test("no-records response becomes the feature empty state")
    func empty() async throws {
        let response = try Self.snapshot(
            localDate: "2026-07-20",
            completionStatus: "no_records"
        )
        let model = TodayViewModel(
            provider: TodayQueueProvider([.success(response)])
        )

        await model.load(revision: 0)

        #expect(model.state == .empty)
    }

    @Test("initial offline is retryable without invented content")
    func initialOffline() async {
        let model = TodayViewModel(
            provider: TodayQueueProvider([.failure(.offline)])
        )

        await model.load(revision: 0)

        #expect(model.state == .offline(previousValue: nil))
    }

    @Test("initial recoverable error has no invented previous snapshot")
    func initialRecoverableError() async {
        let model = TodayViewModel(
            provider: TodayQueueProvider([.failure(.serviceUnavailable)])
        )

        await model.load(revision: 0)

        #expect(model.state == .failed(
            previousValue: nil,
            error: .serviceUnavailable
        ))
    }

    @Test("offline retry preserves the exact previously loaded snapshot")
    func staleOffline() async throws {
        let response = try Self.snapshot(localDate: "2026-07-20")
        let provider = TodayQueueProvider([
            .success(response),
            .failure(.offline),
        ])
        let model = TodayViewModel(provider: provider)

        await model.load(revision: 0)
        await model.retry()

        #expect(model.state == .offline(previousValue: response.data))
        #expect(await provider.callCount == 2)
    }

    @Test("recoverable retry preserves the exact previously loaded snapshot")
    func staleRecoverableError() async throws {
        let response = try Self.snapshot(localDate: "2026-07-20")
        let provider = TodayQueueProvider([
            .success(response),
            .failure(.serviceUnavailable),
        ])
        let model = TodayViewModel(provider: provider)

        await model.load(revision: 0)
        await model.retry()

        #expect(model.state == .failed(
            previousValue: response.data,
            error: .serviceUnavailable
        ))
    }

    @Test("cancelled retry restores offline with the exact previous snapshot")
    func cancelledRetryRestoresStaleOffline() async throws {
        let response = try Self.snapshot(localDate: "2026-07-20")
        let late = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let initialLoad = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: response)
        await initialLoad.value

        let offlineRetry = Task { await model.retry() }
        await provider.waitUntilStarted(2)
        await provider.fail(call: 2, with: .offline)
        await offlineRetry.value
        #expect(model.state == .offline(previousValue: response.data))

        let cancelledRetry = Task { await model.retry() }
        await provider.waitUntilStarted(3)
        cancelledRetry.cancel()
        await provider.succeed(call: 3, with: late)
        await cancelledRetry.value

        #expect(model.state == .offline(previousValue: response.data))
    }

    @Test("cancelled retry restores failed with the exact previous snapshot")
    func cancelledRetryRestoresStaleFailure() async throws {
        let response = try Self.snapshot(localDate: "2026-07-20")
        let late = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let initialLoad = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: response)
        await initialLoad.value

        let failedRetry = Task { await model.retry() }
        await provider.waitUntilStarted(2)
        await provider.fail(call: 2, with: .serviceUnavailable)
        await failedRetry.value
        let expected = FeatureReadState<TodaySnapshot>.failed(
            previousValue: response.data,
            error: .serviceUnavailable
        )
        #expect(model.state == expected)

        let cancelledRetry = Task { await model.retry() }
        await provider.waitUntilStarted(3)
        cancelledRetry.cancel()
        await provider.succeed(call: 3, with: late)
        await cancelledRetry.value

        #expect(model.state == expected)
    }

    @Test("cancelled retry restores failed without inventing a snapshot")
    func cancelledRetryRestoresInitialFailure() async throws {
        let late = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let initialLoad = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        await provider.fail(call: 1, with: .serviceUnavailable)
        await initialLoad.value
        let expected = FeatureReadState<TodaySnapshot>.failed(
            previousValue: nil,
            error: .serviceUnavailable
        )
        #expect(model.state == expected)

        let cancelledRetry = Task { await model.retry() }
        await provider.waitUntilStarted(2)
        cancelledRetry.cancel()
        await provider.succeed(call: 2, with: late)
        await cancelledRetry.value

        #expect(model.state == expected)
    }

    @Test("Retry is a new read intention after an initial failure")
    func retry() async throws {
        let response = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayQueueProvider([
            .failure(.serviceUnavailable),
            .success(response),
        ])
        let model = TodayViewModel(provider: provider)

        await model.load(revision: 0)
        await model.retry()

        #expect(model.state == .loaded(response.data))
        #expect(await provider.callCount == 2)
    }

    @Test("unavailable capability maps to the Release unavailable state")
    func unavailable() async {
        let model = TodayViewModel(
            provider: TodayQueueProvider([.failure(.operationUnavailable)])
        )

        await model.load(revision: 0)

        #expect(model.state == .unavailable)
    }

    @Test("completed revision and unrelated revision do not reload")
    func deduplicatesCompletedAndUnrelatedRevision() async throws {
        let response = try Self.snapshot(localDate: "2026-07-20")
        let provider = TodayQueueProvider([.success(response)])
        let model = TodayViewModel(provider: provider)
        let center = FeatureInvalidationCenter()

        await model.load(revision: center.revision(for: .today))
        await model.load(revision: center.revision(for: .today))
        center.record(.weightRecorded)
        await model.load(revision: center.revision(for: .today))

        #expect(await provider.callCount == 1)
        #expect(model.state == .loaded(response.data))
    }

    @Test("provider pending state is loading and active revision is deduplicated")
    func activeRevisionIsLoadingAndDeduplicated() async throws {
        let response = try Self.snapshot(localDate: "2026-07-20")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let load = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        #expect(model.state == .loading)

        await model.load(revision: 0)
        #expect(await provider.callCount == 1)

        await provider.succeed(call: 1, with: response)
        await load.value
        #expect(model.state == .loaded(response.data))
    }

    @Test("refresh keeps the complete prior snapshot until replacement arrives")
    func refreshPreservesCompleteSnapshot() async throws {
        let initial = try Self.snapshot(localDate: "2026-07-20")
        let replacement = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let initialLoad = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: initial)
        await initialLoad.value

        let refresh = Task { await model.load(revision: 1) }
        await provider.waitUntilStarted(2)
        #expect(model.state == .loaded(initial.data))

        await provider.succeed(call: 2, with: replacement)
        await refresh.value
        #expect(model.state == .loaded(replacement.data))
    }

    @Test("one Today invalidation adopts exactly one new complete response")
    func relevantInvalidationReloadsOnce() async throws {
        let initial = try Self.snapshot(localDate: "2026-07-20")
        let replacement = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayQueueProvider([
            .success(initial),
            .success(replacement),
        ])
        let model = TodayViewModel(provider: provider)
        let center = FeatureInvalidationCenter()

        await model.load(revision: center.revision(for: .today))
        center.record(.hydrationRecorded)
        let revision = center.revision(for: .today)
        await model.load(revision: revision)
        await model.load(revision: revision)

        #expect(await provider.callCount == 2)
        #expect(model.state == .loaded(replacement.data))
    }

    @Test("newer revision suppresses a late response from the older load")
    func newerRevisionWins() async throws {
        let older = try Self.snapshot(localDate: "2026-07-20")
        let newer = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let olderTask = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        let newerTask = Task { await model.load(revision: 1) }
        await provider.waitUntilStarted(2)

        await provider.succeed(call: 2, with: newer)
        await newerTask.value
        await provider.succeed(call: 1, with: older)
        await olderTask.value

        #expect(model.state == .loaded(newer.data))
        #expect(await provider.callCount == 2)
    }

    @Test("newer revision suppresses a late error from the older load")
    func newerRevisionSuppressesLateError() async throws {
        let newer = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let olderTask = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        let newerTask = Task { await model.load(revision: 1) }
        await provider.waitUntilStarted(2)

        await provider.succeed(call: 2, with: newer)
        await newerTask.value
        await provider.fail(call: 1, with: .serviceUnavailable)
        await olderTask.value

        #expect(model.state == .loaded(newer.data))
    }

    @Test("cancelled incomplete revision can reappear without late publication")
    func cancelledRevisionCanReappear() async throws {
        let late = try Self.snapshot(localDate: "2026-07-20")
        let visibleAgain = try Self.snapshot(localDate: "2026-07-21")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let cancelledTask = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        cancelledTask.cancel()
        await provider.succeed(call: 1, with: late)
        await cancelledTask.value
        #expect(model.state == .idle)

        let visibleTask = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(2)
        await provider.succeed(call: 2, with: visibleAgain)
        await visibleTask.value

        #expect(model.state == .loaded(visibleAgain.data))
        #expect(await provider.callCount == 2)
    }

    private static func snapshot(
        localDate: String,
        completionStatus: String = "pending_information"
    ) throws -> TodayResponse {
        let original = try BodyFlowTestFixtures.decodeInconsistentToday()
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original))
                as? [String: Any]
        )
        var data = try #require(object["data"] as? [String: Any])
        data["local_date"] = localDate
        var completion = try #require(
            data["completion_status"] as? [String: Any]
        )
        completion["status"] = completionStatus
        data["completion_status"] = completion
        object["data"] = data
        return try JSONDecoder().decode(
            TodayResponse.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}

private actor TodayQueueProvider: TodayProviding {
    enum Outcome: Sendable {
        case success(TodayResponse)
        case failure(BodyFlowCapabilityError)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func today() async throws -> TodayResponse {
        callCount += 1
        guard !outcomes.isEmpty else {
            throw BodyFlowCapabilityError.serviceUnavailable
        }
        switch outcomes.removeFirst() {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }
}

private actor TodayControlledProvider: TodayProviding {
    private var continuations: [Int: CheckedContinuation<TodayResponse, Error>] = [:]
    private(set) var callCount = 0

    func today() async throws -> TodayResponse {
        callCount += 1
        let call = callCount
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func waitUntilStarted(_ count: Int) async {
        while callCount < count {
            await Task.yield()
        }
    }

    func succeed(call: Int, with response: TodayResponse) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }

    func fail(call: Int, with error: BodyFlowCapabilityError) {
        continuations.removeValue(forKey: call)?.resume(throwing: error)
    }
}
