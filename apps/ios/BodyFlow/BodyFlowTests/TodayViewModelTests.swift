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

    @Test("a day without records preserves its independent weekly section", arguments: [
        "available", "unavailable", "conflict",
    ])
    func noRecordsPreservesStrengthWeek(status: String) async throws {
        let response = try BodyFlowTestFixtures.decodeToday { data in
            data["meals"] = []
            data["workouts"] = []
            data["consumed"] = [
                "calories_kcal": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0,
                "source": "meal_logs",
            ] as [String: Any]
            data["exercise_kcal"] = 0
            data["completion_status"] = [
                "status": "no_records", "day_closed": false, "has_sufficient_data": false,
            ] as [String: Any]
            if status == "available" {
                data["strength_training_week"] = [
                    "status": "available",
                    "week_start": "2026-10-12",
                    "as_of_local_date": "2026-10-14",
                    "time_zone": "UTC",
                    "observed_at": "2026-10-14T12:00:00.123457Z",
                    "completed_strength_days": 2,
                    "planned_days": 3,
                    "target_source": "accepted_plan",
                    "target_availability": "available",
                    "percentage": 67,
                ] as [String: Any]
            } else {
                data["strength_training_week"] = [
                    "status": status,
                    "reason": status == "conflict" ? "week_changed" : "missing_scope",
                ]
            }
        }
        let model = TodayViewModel(provider: TodayQueueProvider([.success(response)]))

        await model.load(revision: 0)

        #expect(model.state == .loaded(response.data))
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

    @Test("retry exposes the prior snapshot while a controlled stale read is pending")
    func retryPublishesPriorSnapshotWhilePending() async throws {
        let response = try Self.snapshot(localDate: "2026-07-20")
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let initialLoad = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: response)
        await initialLoad.value

        let retry = Task { await model.retry() }
        await provider.waitUntilStarted(2)
        #expect(model.state == .loaded(response.data))
        #expect(await provider.callCount == 2)

        await provider.fail(call: 2, with: .offline)
        await retry.value
        #expect(model.state == .offline(previousValue: response.data))
        #expect(await provider.callCount == 2)
    }

    @Test("repeated manual Today refresh shares one in-flight read and preserves the prior snapshot")
    func repeatedManualRefreshIsDeduplicated() async throws {
        let previous = try Self.octoberFirstAudioSnapshot(confirmed: false)
        let current = try Self.octoberFirstAudioSnapshot(confirmed: true)
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)

        let initial = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: previous)
        await initial.value

        let firstRefresh = Task { await model.retry() }
        await provider.waitUntilStarted(2)
        #expect(model.state == .loaded(previous.data))
        #expect(model.isRefreshing)

        let probe = TodayRetryCompletionProbe()
        let duplicateRefresh = Task {
            await model.retry()
            probe.finished = true
        }
        for _ in 0..<1_000 {
            let calls = await provider.callCount
            if probe.finished || calls >= 3 { break }
            await Task.yield()
        }
        #expect(await provider.callCount == 2)
        #expect(model.state == .loaded(previous.data))

        await provider.succeed(call: 2, with: current)
        await firstRefresh.value
        for _ in 0..<1_000 {
            let calls = await provider.callCount
            if probe.finished || calls >= 3 { break }
            await Task.yield()
        }
        if await provider.callCount >= 3 {
            await provider.succeed(call: 3, with: previous)
        }
        await duplicateRefresh.value
        #expect(model.state == .loaded(current.data))
        #expect(!model.isRefreshing)
    }

    @Test("two pull refreshes during a suspended invalidation do not repeat independent reads")
    func refreshDuringInvalidationDoesNotDuplicateIndependentReads() async throws {
        let previous = try Self.octoberFirstAudioSnapshot(confirmed: false)
        let current = try Self.octoberFirstAudioSnapshot(confirmed: true)
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)
        let coordinator = TodayRefreshCoordinator()
        let initial = Task { await model.load(revision: 0) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: previous)
        await initial.value

        let invalidation = Task { await model.load(revision: 2) }
        await provider.waitUntilStarted(2)
        var contentReads = 0
        var coachReads = 0
        for _ in 0..<2 {
            await coordinator.run(isExternallyRefreshing: model.isRefreshing) {
                await model.retry()
                contentReads += 1
                coachReads += 1
            }
        }
        #expect(contentReads == 0)
        #expect(coachReads == 0)
        #expect(await provider.callCount == 2)
        #expect(model.state == .loaded(previous.data))
        await provider.succeed(call: 2, with: current)
        await invalidation.value
        #expect(model.state == .loaded(current.data))
        await coordinator.run(isExternallyRefreshing: model.isRefreshing) {
            contentReads += 1
            coachReads += 1
        }
        #expect(contentReads == 1)
        #expect(coachReads == 1)
    }

    @Test("a confirmation invalidation supersedes manual refresh without dropping the visible snapshot")
    func confirmationSupersedesManualRefresh() async throws {
        let previous = try Self.octoberFirstAudioSnapshot(confirmed: false)
        let current = try Self.octoberFirstAudioSnapshot(confirmed: true)
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)
        let center = FeatureInvalidationCenter()

        let initial = Task { await model.load(revision: center.revision(for: .today)) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: previous)
        await initial.value

        let manualRefresh = Task { await model.retry() }
        await provider.waitUntilStarted(2)
        center.record(.registrationConfirmed)
        let confirmationRead = Task { await model.load(revision: center.revision(for: .today)) }
        await provider.waitUntilStarted(3)
        #expect(model.state == .loaded(previous.data))
        #expect(model.isRefreshing)

        await provider.succeed(call: 3, with: current)
        await confirmationRead.value
        await provider.succeed(call: 2, with: previous)
        await manualRefresh.value

        #expect(model.state == .loaded(current.data))
        #expect(!model.isRefreshing)
        #expect(await provider.callCount == 3)
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
        #expect(!model.isRefreshing)
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
        #expect(!model.isRefreshing)
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

    // Physical staging, 2026-10-01: the six-second audio said
    // "No almoço eu comi 150 gramas de arroz branco cozido e 120 gramas de frango grelhado".
    // Registration 2777524f-c4e2-4a90-befc-8bea387092b5 was confirmed at
    // 14:54:19.051Z; Today still showed zero and 27/09 23:55 before manual refresh.
    // This characterizes the read model and invalidation with the observed figures;
    // it does not prove microphone capture, SwiftUI task delivery or device latency.
    @Test("the exact post-audio Today figures replace the old snapshot after confirmation invalidation without Retry")
    func exactOctoberFirstAudioConfirmationRead() async throws {
        let previous = try Self.octoberFirstAudioSnapshot(confirmed: false)
        let official = try Self.octoberFirstAudioSnapshot(confirmed: true)
        let provider = TodayControlledProvider()
        let model = TodayViewModel(provider: provider)
        let center = FeatureInvalidationCenter()

        let initialTask = Task { await model.load(revision: center.revision(for: .today)) }
        await provider.waitUntilStarted(1)
        await provider.succeed(call: 1, with: previous)
        await initialTask.value
        #expect(model.state == .loaded(previous.data))

        center.record(.registrationConfirmed)
        #expect(center.revision(for: .history) == 1)
        let confirmedRevision = center.revision(for: .today)
        let confirmationTask = Task { await model.load(revision: confirmedRevision) }
        await provider.waitUntilStarted(2)
        // An immediate capture can legitimately retain the old figures while
        // the server read is pending. The completed read must replace them.
        #expect(model.state == .loaded(previous.data))
        await provider.succeed(call: 2, with: official)
        await confirmationTask.value
        await model.load(revision: confirmedRevision)

        #expect(model.state == .loaded(official.data))
        #expect(await provider.callCount == 2)
        let visible = TodayPresentation(snapshot: official.data)
        #expect(official.data.consumed.caloriesKcal == 383)
        #expect(official.data.consumed.proteinG == Decimal(string: "42.22"))
        #expect(visible.energy.remainingFoodKcal == 2978)
        #expect(visible.protein.targetG == Decimal(string: "186.1"))
        #expect(official.data.meals.map(\.id) == [
            "a29a59a5-7050-4e3c-bb19-84d37c4fc7c5",
            "10c3250a-f072-48b3-9e87-b4a8ae6555ba",
        ])
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

    private static func octoberFirstAudioSnapshot(confirmed: Bool) throws -> TodayResponse {
        let base = try snapshot(localDate: "2026-10-01")
        func decimal(_ value: String) throws -> Decimal { try #require(Decimal(string: value)) }
        func timestamp(_ value: String) throws -> APITimestamp {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return APITimestamp(value: try #require(formatter.date(from: value)))
        }
        let consumedAt = try timestamp("2026-10-01T14:52:24.051Z")
        // Build Decimal from the recorded decimal text, avoiding a Double
        // round-trip in JSONSerialization that would change 42.22 itself.
        let consumedProtein = try decimal(confirmed ? "42.22" : "0")
        let targetProtein = try decimal("186.1")
        let meals: [TodayMeal] = confirmed ? [
            TodayMeal(
                id: "a29a59a5-7050-4e3c-bb19-84d37c4fc7c5", mealType: "almoco",
                foodName: "arroz branco cozido", quantityG: 150, kcal: try decimal("192.4"),
                proteinG: try decimal("3.78"), carbsG: try decimal("42.09"), fatG: try decimal("0.35"),
                consumedAt: consumedAt, nutritionSource: "canonical_exact"
            ),
            TodayMeal(
                id: "10c3250a-f072-48b3-9e87-b4a8ae6555ba", mealType: "almoco",
                foodName: "frango grelhado", quantityG: 120, kcal: 191,
                proteinG: try decimal("38.44"), carbsG: 0, fatG: try decimal("2.98"),
                consumedAt: consumedAt, nutritionSource: "canonical_exact"
            ),
        ] : []
        return TodayResponse(data: TodaySnapshot(
            localDate: "2026-10-01", protocolName: "ganho_massa",
            targets: TodayTargets(caloriesKcal: 3361, proteinG: targetProtein,
                                  source: "daily_snapshot", caloriesSource: "daily_snapshot", proteinSource: "daily_snapshot"),
            consumed: TodayConsumed(caloriesKcal: confirmed ? 383 : 0, proteinG: consumedProtein,
                                    carbsG: try decimal(confirmed ? "42.09" : "0"), fatG: try decimal(confirmed ? "3.33" : "0"),
                                    source: "daily_snapshot"),
            remainingFoodKcal: confirmed ? 2978 : 3361, foodExcessKcal: nil,
            exerciseKcal: 0, dailyBalanceKcal: confirmed ? -2978 : -3361, dailyBalanceStatus: "provisional",
            proteinStatus: TodayProteinStatus(consumedG: consumedProtein, targetG: targetProtein,
                                              remainingG: try decimal(confirmed ? "143.88" : "186.1"),
                                              percentage: confirmed ? 23 : 0, status: "below_target"),
            meals: meals, workouts: [],
            hydration: TodayHydration(consumedML: 0, targetML: nil, remainingML: nil, percentage: nil, status: "not_recorded"),
            supplements: TodayRoutineSection(availability: "not_configured", items: []),
            medications: TodayRoutineSection(availability: "not_configured", items: []),
            pendingActions: TodayPendingActions(registrations: [], mealGaps: base.data.pendingActions.mealGaps),
            block7700: nil, completionStatus: base.data.completionStatus,
            sources: base.data.sources, calculationVersion: base.data.calculationVersion,
            updatedAt: try timestamp(confirmed ? "2026-10-01T14:54:19.051Z" : "2026-09-28T02:55:00.000Z"),
            generatedAt: try timestamp("2026-10-01T14:55:00.000Z")
        ), meta: base.meta)
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

@MainActor
private final class TodayRetryCompletionProbe {
    var finished = false
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
