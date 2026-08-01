import Foundation
import Testing

@testable import BodyFlow

@Suite("Main history view model")
@MainActor
struct HistoryViewModelTests {
    @Test("revision zero reads exactly the bounded first page once")
    func initialRevisionIsBoundedAndDeduplicated() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryQueueProvider([.success(response)])
        let model = HistoryViewModel(provider: provider)

        await model.load(revision: 0)
        await model.load(revision: 0)

        #expect(model.state == .loaded(response.data))
        #expect(await provider.queries == [.firstPage])
    }

    @Test("duplicate active revision starts only one bounded History read")
    func activeRevisionIsDeduplicated() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryControlledProvider()
        let model = HistoryViewModel(provider: provider)

        let firstTask = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        let duplicateTask = Task { await model.load(revision: 0) }
        await duplicateTask.value

        #expect(await provider.queries == [.firstPage])

        await provider.succeed(call: 1, with: response)
        await firstTask.value

        #expect(model.state == .loaded(response.data))
        #expect(await provider.queries == [.firstPage])
    }

    @Test("retry creates one further bounded first-page request")
    func retryUsesFirstPageAgain() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryQueueProvider([
            .failure(.serviceUnavailable),
            .success(response),
        ])
        let model = HistoryViewModel(provider: provider)

        await model.load(revision: 0)
        #expect(model.state == .failed(
            previousValue: nil,
            error: .serviceUnavailable
        ))
        await model.retry()

        #expect(model.state == .loaded(response.data))
        #expect(await provider.queries == [.firstPage, .firstPage])
    }

    @Test("offline and service failures retain the complete previous snapshot")
    func staleResponsesPreserveSnapshot() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryQueueProvider([
            .success(response),
            .failure(.offline),
            .failure(.serviceUnavailable),
        ])
        let model = HistoryViewModel(provider: provider)

        await model.load(revision: 0)
        await model.retry()
        #expect(model.state == .offline(previousValue: response.data))

        await model.retry()
        #expect(model.state == .failed(
            previousValue: response.data,
            error: .serviceUnavailable
        ))
    }

    @Test("unavailable capability stays unavailable")
    func unavailable() async {
        let model = HistoryViewModel(
            provider: HistoryQueueProvider([.failure(.operationUnavailable)])
        )

        await model.load(revision: 0)

        #expect(model.state == .unavailable)
    }

    @Test("initial offline response remains a literal offline state")
    func initialOffline() async {
        let model = HistoryViewModel(
            provider: HistoryQueueProvider([.failure(.offline)])
        )

        await model.load(revision: 0)

        #expect(model.state == .offline(previousValue: nil))
    }

    @Test("cancelled revision zero cannot publish its late snapshot")
    func cancelledRevisionZeroSuppressesLateSnapshot() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryControlledProvider()
        let model = HistoryViewModel(provider: provider)

        let task = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        task.cancel()
        await provider.succeed(call: 1, with: response)
        await task.value

        #expect(model.state == .loading)
    }

    @Test("cancelled revision zero cannot publish its late error")
    func cancelledRevisionZeroSuppressesLateError() async {
        let provider = HistoryControlledProvider()
        let model = HistoryViewModel(provider: provider)

        let task = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        task.cancel()
        await provider.fail(call: 1, with: .serviceUnavailable)
        await task.value

        #expect(model.state == .loading)
    }

    @Test("newer history revision wins over a late older snapshot")
    func newerRevisionSuppressesLateOlderSnapshot() async throws {
        let older = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let newer = try BodyFlowTestFixtures.decodeHistoryMealsOnly()
        let provider = HistoryControlledProvider()
        let model = HistoryViewModel(provider: provider)

        let oldTask = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        let newTask = Task { await model.load(revision: 1) }
        guard await provider.waitUntilStarted(2) else { return }
        await provider.succeed(call: 1, with: older)
        await oldTask.value
        #expect(model.state == .loading)
        await provider.succeed(call: 2, with: newer)
        await newTask.value

        #expect(model.state == .loaded(newer.data))
        #expect(await provider.queries == [.firstPage, .firstPage])
    }

    @Test("newer history revision suppresses a late older error")
    func newerRevisionSuppressesLateOlderError() async throws {
        let newer = try BodyFlowTestFixtures.decodeHistoryMealsOnly()
        let provider = HistoryControlledProvider()
        let model = HistoryViewModel(provider: provider)

        let oldTask = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        let newTask = Task { await model.load(revision: 1) }
        guard await provider.waitUntilStarted(2) else { return }
        await provider.fail(call: 1, with: .serviceUnavailable)
        await oldTask.value
        #expect(model.state == .loading)
        await provider.succeed(call: 2, with: newer)
        await newTask.value

        #expect(model.state == .loaded(newer.data))
    }

    @Test("pre-cancelled newer revision preserves the valid revision for retry")
    func preCancelledNewerRevisionDoesNotAdvanceModelRevision() async throws {
        let initial = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let refreshed = try BodyFlowTestFixtures.decodeHistoryMealsOnly()
        let provider = HistoryControlledProvider()
        let model = HistoryViewModel(provider: provider)

        let initialTask = Task { await model.load(revision: 0) }
        guard await provider.waitUntilStarted(1) else { return }
        await provider.succeed(call: 1, with: initial)
        await initialTask.value

        let cancelledTask = Task { await model.load(revision: 1) }
        cancelledTask.cancel()
        await cancelledTask.value

        #expect(model.state == .loaded(initial.data))

        let retryTask = Task { await model.retry() }
        guard await provider.waitUntilStarted(2) else { return }
        await provider.succeed(call: 2, with: refreshed)
        await retryTask.value

        #expect(model.state == .loaded(refreshed.data))
        #expect(await provider.queries == [.firstPage, .firstPage])
    }

    @Test("pre-cancelled initial load leaves idle state unchanged")
    func preCancelledInitialLoadDoesNotPublishLoading() async {
        let provider = HistoryControlledProvider()
        let model = HistoryViewModel(provider: provider)

        let cancelledTask = Task { await model.load(revision: 0) }
        cancelledTask.cancel()
        await cancelledTask.value

        #expect(model.state == .idle)
        #expect(await provider.queries.isEmpty)
    }

    @Test("a newer history revision replaces rather than locally patches rows")
    func revisionReloadsCompleteSnapshot() async throws {
        let first = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let second = try BodyFlowTestFixtures.decodeHistoryMealsOnly()
        let provider = HistoryQueueProvider([.success(first), .success(second)])
        let model = HistoryViewModel(provider: provider)

        await model.load(revision: 0)
        await model.load(revision: 1)

        #expect(model.state == .loaded(second.data))
        #expect(await provider.queries == [.firstPage, .firstPage])
    }

    @Test("History invalidation reloads once and unrelated invalidation does not reload")
    func invalidationCenterDrivesOneCompleteHistoryReload() async throws {
        let initial = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let replacement = try BodyFlowTestFixtures.decodeHistoryMealsOnly()
        let provider = HistoryQueueProvider([
            .success(initial),
            .success(replacement),
        ])
        let model = HistoryViewModel(provider: provider)
        let invalidationCenter = FeatureInvalidationCenter()

        let initialRevision = invalidationCenter.revision(for: .history)
        await model.load(revision: initialRevision)
        #expect(model.state == .loaded(initial.data))

        invalidationCenter.record(.registrationConfirmed)
        let confirmedRevision = invalidationCenter.revision(for: .history)
        #expect(confirmedRevision == initialRevision + 1)
        await model.load(revision: confirmedRevision)

        #expect(model.state == .loaded(replacement.data))
        #expect(model.workoutLogRow(id: "fixture-workout-row-1") == nil)

        await model.load(revision: confirmedRevision)

        invalidationCenter.record(.hydrationRecorded)
        let unrelatedRevision = invalidationCenter.revision(for: .history)
        #expect(unrelatedRevision == confirmedRevision)
        await model.load(revision: unrelatedRevision)

        #expect(model.state == .loaded(replacement.data))
        #expect(await provider.queries == [.firstPage, .firstPage])
    }

    @Test("opening individual row detail uses only the loaded snapshot")
    func mealDetailUsesLoadedSnapshot() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryQueueProvider([.success(response)])
        let model = HistoryViewModel(provider: provider)

        await model.load(revision: 0)
        let first = try #require(model.mealLogRow(id: "fixture-meal-row-1"))
        let second = try #require(model.mealLogRow(id: "fixture-meal-row-2"))
        let workout = try #require(model.workoutLogRow(id: "fixture-workout-row-1"))

        #expect(first.foodName != second.foodName)
        #expect(workout.id == "fixture-workout-row-1")
        #expect(await provider.queries == [.firstPage])
    }

    @Test("offline and failed snapshots remain eligible for immutable detail lookup")
    func staleSnapshotDetailsDoNotFetch() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryQueueProvider([
            .success(response), .failure(.offline), .failure(.serviceUnavailable),
        ])
        let model = HistoryViewModel(provider: provider)

        await model.load(revision: 0)
        await model.retry()
        #expect(model.mealLogRow(id: "fixture-meal-row-1")?.id == "fixture-meal-row-1")
        await model.retry()
        #expect(model.workoutLogRow(id: "fixture-workout-row-1")?.id == "fixture-workout-row-1")
        #expect(await provider.queries == [.firstPage, .firstPage, .firstPage])
    }

    @Test("coordinator resolves identifier-only history routes from the model snapshot")
    func coordinatorUsesSnapshotOnly() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryQueueProvider([.success(response)])
        let model = HistoryViewModel(provider: provider)
        let coordinator = HistoryFeatureCoordinator(model: model)

        await model.load(revision: 0)

        #expect(coordinator.mealLogRow(for: .historyMealLog(rowID: "fixture-meal-row-2"))?.foodName == "Feijao carioca")
        #expect(coordinator.workoutLogRow(for: .historyWorkout(logID: "fixture-workout-row-1"))?.id == "fixture-workout-row-1")
        #expect(await provider.queries == [.firstPage])
    }

    @Test("missing History row identifiers resolve to nil without fetching")
    func missingRowIdentifiersUseBoundedSnapshotOnly() async throws {
        let response = try BodyFlowTestFixtures.decodeHistoryWithMatchingRows()
        let provider = HistoryQueueProvider([.success(response)])
        let model = HistoryViewModel(provider: provider)
        let coordinator = HistoryFeatureCoordinator(model: model)

        await model.load(revision: 0)
        #expect(await provider.queries == [.firstPage])

        #expect(model.mealLogRow(id: "missing-meal-row") == nil)
        #expect(model.workoutLogRow(id: "missing-workout-row") == nil)
        #expect(coordinator.mealLogRow(
            for: .historyMealLog(rowID: "missing-meal-row")
        ) == nil)
        #expect(coordinator.workoutLogRow(
            for: .historyWorkout(logID: "missing-workout-row")
        ) == nil)

        #expect(await provider.queries == [.firstPage])
    }
}

private actor HistoryControlledProvider: HistoryProviding {
    private var continuations: [Int: CheckedContinuation<HistoryResponse, Error>] = [:]
    private var calls = 0
    private(set) var queries: [HistoryQuery] = []

    func history(_ query: HistoryQuery) async throws -> HistoryResponse {
        calls += 1
        let call = calls
        queries.append(query)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    @discardableResult
    func waitUntilStarted(
        _ count: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while calls < count {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for \(count) History loads; started: \(calls)")
                return false
            }

            await Task.yield()
        }

        return true
    }

    func succeed(call: Int, with response: HistoryResponse) {
        continuations.removeValue(forKey: call)?.resume(returning: response)
    }

    func fail(call: Int, with error: BodyFlowCapabilityError) {
        continuations.removeValue(forKey: call)?.resume(throwing: error)
    }
}

private actor HistoryQueueProvider: HistoryProviding {
    enum Outcome: Sendable {
        case success(HistoryResponse)
        case failure(BodyFlowCapabilityError)
    }

    private var outcomes: [Outcome]
    private(set) var queries: [HistoryQuery] = []

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func history(_ query: HistoryQuery) async throws -> HistoryResponse {
        queries.append(query)
        guard !outcomes.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch outcomes.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }
}
