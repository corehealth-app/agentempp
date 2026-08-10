import Foundation
import Testing

@testable import BodyFlow

@Suite("Routine action model")
@MainActor
struct RoutineActionModelTests {
    @Test("action configuration changes when one schedule ID refreshes its occurrence")
    func actionConfigurationChangesForARefreshedOccurrenceWithSameScheduleID() throws {
        let earlierSnoozed = Self.schedule(
            id: "rule-snoozed",
            status: "snoozed",
            scheduledFor: Self.occurredAt.addingTimeInterval(-3_600)
        )
        let initialPending = Self.schedule(
            id: "rule-shared",
            status: "pending",
            scheduledFor: Self.occurredAt
        )
        let snoozedOccurrence = Self.schedule(
            id: "rule-shared",
            status: "snoozed",
            scheduledFor: Self.occurredAt
        )
        let takenOccurrence = Self.schedule(
            id: "rule-shared",
            status: "taken",
            scheduledFor: Self.occurredAt
        )

        let initial = RoutineActionConfiguration(
            kind: .supplement,
            itemID: "supplement-1",
            schedules: [earlierSnoozed, initialPending]
        )
        let snoozed = RoutineActionConfiguration(
            kind: .supplement,
            itemID: "supplement-1",
            schedules: [snoozedOccurrence]
        )
        let taken = RoutineActionConfiguration(
            kind: .supplement,
            itemID: "supplement-1",
            schedules: [takenOccurrence]
        )

        #expect(initial.context?.reminderRuleID == "rule-shared")
        #expect(snoozed.context == initial.context)
        #expect(snoozed != initial)
        #expect(snoozed.shouldApply(over: initial, isSubmitting: false))
        #expect(!snoozed.shouldApply(over: initial, isSubmitting: true))
        #expect(taken.context == nil)
        #expect(taken.shouldApply(over: snoozed, isSubmitting: false))
    }

    @Test("taken uses the injected occurrence time and omits snooze")
    func takenUsesExactOccurrence() async throws {
        let provider = RoutineActionProvider(results: [.success(Self.receipt(.taken))])
        let invalidation = FeatureInvalidationCenter()
        let model = Self.model(provider: provider, invalidation: invalidation)

        await model.submit(status: .taken)

        let attempt = try #require(await provider.attempts.first)
        #expect(attempt.payload.occurredAt.value == Self.occurredAt)
        #expect(attempt.payload.snoozedUntil == nil)
        #expect(model.mutationState.receipt == Self.receipt(.taken))
        #expect(model.accessibilityFocusTarget == .operationSummary)
        #expect(invalidation.revision(for: .today) == 1)
        #expect(invalidation.revision(for: .routineList(kind: .supplement)) == 1)
        #expect(invalidation.revision(for: .routineHistory(kind: .supplement, itemID: "supplement-1")) == 1)
    }

    @Test("skipped also omits snooze while snoozed needs a same-day time")
    func skippedAndSnoozedStructure() async throws {
        let provider = RoutineActionProvider(results: [
            .success(Self.receipt(.skipped)),
            .success(Self.receipt(.snoozed)),
        ])
        let model = Self.model(provider: provider)

        await model.submit(status: .skipped)
        await model.submit(status: .snoozed, selection: .minutes(30))

        let attempts = await provider.attempts
        #expect(attempts[0].payload.snoozedUntil == nil)
        #expect(attempts[1].payload.snoozedUntil == APITimestamp(value: Self.occurredAt.addingTimeInterval(1_800)))
    }

    @Test("snooze offers only 15, 30 and 60 minute values that stay on the local date")
    func snoozePolicyIsExposedByActionModel() {
        let model = Self.model(provider: RoutineActionProvider())

        #expect(model.snoozeDate(for: .minutes(15)) == Self.occurredAt.addingTimeInterval(900))
        #expect(model.snoozeDate(for: .minutes(30)) == Self.occurredAt.addingTimeInterval(1_800))
        #expect(model.snoozeDate(for: .minutes(60)) == Self.occurredAt.addingTimeInterval(3_600))
        #expect(model.snoozeDate(for: .minutes(45)) == nil)
        #expect(model.snoozeDate(for: .custom(Self.occurredAt.addingTimeInterval(3_600))) == Self.occurredAt.addingTimeInterval(3_600))
    }

    @Test("a recoverable failure keeps the exact idempotent attempt for retry")
    func retryKeepsAttempt() async throws {
        let provider = RoutineActionProvider(results: [
            .failure(.offline),
            .success(Self.receipt(.taken)),
        ])
        let model = Self.model(provider: provider)

        await model.submit(status: .taken)
        let failedAttempt = try #require(model.mutationState.attempt)
        await model.retry()

        let attempts = await provider.attempts
        #expect(attempts.count == 2)
        #expect(attempts[1] == failedAttempt)
        #expect(model.mutationState.receipt == Self.receipt(.taken))
    }

    @Test("a conflict retry reuses its exact attempt and idempotency key")
    func conflictRetryKeepsAttempt() async throws {
        let provider = RoutineActionProvider(results: [
            .failure(.idempotencyConflict),
            .success(Self.receipt(.taken)),
        ])
        let model = Self.model(provider: provider)

        await model.submit(status: .taken)
        let failedAttempt = try #require(model.mutationState.attempt)
        await model.retry()

        let attempts = await provider.attempts
        #expect(attempts.count == 2)
        #expect(attempts[1] == failedAttempt)
        #expect(model.mutationState.receipt == Self.receipt(.taken))
    }

    @Test("unavailable action never publishes a receipt or invalidation")
    func unavailableDoesNotSimulateOccurrence() async {
        let invalidation = FeatureInvalidationCenter()
        let model = Self.model(
            provider: RoutineActionProvider(results: [.failure(.operationUnavailable)]),
            invalidation: invalidation
        )

        await model.submit(status: .taken)

        #expect(model.mutationState == .unavailable)
        #expect(model.mutationState.receipt == nil)
        #expect(invalidation.revision(for: .today) == 0)
        #expect(model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("a snooze that crosses the patient local date is unavailable")
    func crossingDateSnoozeIsUnavailable() {
        let late = Date(timeIntervalSince1970: 10_200)
        let model = Self.model(
            provider: RoutineActionProvider(),
            occurredAt: late
        )

        #expect(model.snoozeDate(for: .minutes(15)) == nil)
        #expect(model.snoozeDate(for: .custom(late.addingTimeInterval(900))) == nil)
        #expect(model.snoozeDate(for: .custom(late)) == nil)
    }

    @Test("failure moves focus to the operation summary without an optimistic receipt")
    func failureMovesFocusWithoutOptimism() async {
        let model = Self.model(
            provider: RoutineActionProvider(results: [.failure(.offline)])
        )

        await model.submit(status: .taken)

        #expect(model.mutationState.receipt == nil)
        #expect(model.mutationState.attempt != nil)
        #expect(model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("conflict advances only its exact list and item history revisions")
    func conflictInvalidatesOnlyExactRoutineReads() async {
        let invalidation = FeatureInvalidationCenter()
        let model = Self.model(
            provider: RoutineActionProvider(results: [.failure(.idempotencyConflict)]),
            invalidation: invalidation
        )

        await model.submit(status: .taken)

        #expect(invalidation.revision(for: .today) == 0)
        #expect(invalidation.revision(for: .routineList(kind: .supplement)) == 1)
        #expect(invalidation.revision(for: .routineHistory(kind: .supplement, itemID: "supplement-1")) == 1)
        #expect(invalidation.revision(for: .routineList(kind: .medication)) == 0)
        #expect(invalidation.revision(for: .routineHistory(kind: .supplement, itemID: "other")) == 0)
        #expect(model.mutationState.receipt == nil)
    }

    @Test("routine transition conflict from the fixture reloads only its exact read owners")
    func routineTransitionInvalidReloadsExactReadOwners() async throws {
        let provider = DemoBodyFlowRepository(scenario: .routineConflictOnce)
        let invalidation = FeatureInvalidationCenter()
        let list = RoutineListViewModel(kind: .supplement, provider: provider)
        let history = RoutineHistoryViewModel(kind: .supplement, itemID: "supplement-1", provider: provider)
        await list.load(revision: 0)
        await history.load(revision: 0)
        let action = RoutineActionModel(
            provider: provider,
            timeProvider: FixedTimeProvider(value: Self.occurredAt),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "routine-conflict"),
            invalidationCenter: invalidation,
            patientTimeZone: PatientTimeZoneContext(documentedIANAIdentifier: "America/Sao_Paulo"),
            context: RoutineOccurrenceContext(
                kind: .supplement,
                itemID: "supplement-1",
                reminderRuleID: "rule-08",
                scheduledFor: APITimestamp(value: Date(timeIntervalSince1970: 1_784_545_200))
            )
        )

        await action.submit(status: .taken)

        #expect(invalidation.revision(for: .today) == 0)
        #expect(invalidation.revision(for: .routineList(kind: .supplement)) == 1)
        #expect(invalidation.revision(for: .routineHistory(kind: .supplement, itemID: "supplement-1")) == 1)
        #expect(invalidation.revision(for: .routineList(kind: .medication)) == 0)

        await list.load(revision: invalidation.revision(for: .routineList(kind: .supplement)))
        await history.load(revision: invalidation.revision(for: .routineHistory(kind: .supplement, itemID: "supplement-1")))

        #expect(list.snapshot == DemoBodyFlowFixtures.routineConflictSupplementList.data)
        #expect(history.items == DemoBodyFlowFixtures.routineConflictSupplementHistory.items)
    }

    @Test("a cancelled action cannot publish its late receipt or summary focus")
    func cancelledActionSuppressesLatePublication() async {
        let model = Self.model(provider: LateRoutineActionProvider())

        let action = Task { await model.submit(status: .taken) }
        try? await Task.sleep(for: .milliseconds(20))
        action.cancel()
        await action.value

        #expect(model.mutationState == .idle)
        #expect(model.mutationState.receipt == nil)
        #expect(model.accessibilityFocusTarget == nil)
    }

    @Test("conflict reloads one exact list and history and detail follows the new list snapshot")
    func conflictReloadsExactReadOwnersAndRefreshesDetail() async throws {
        let provider = RoutineActionProvider(
            results: [.failure(.idempotencyConflict)],
            lists: [DemoBodyFlowFixtures.loadedSupplementList, DemoBodyFlowFixtures.routineConflictSupplementList],
            histories: [DemoBodyFlowFixtures.loadedSupplementHistory, DemoBodyFlowFixtures.routineConflictSupplementHistory]
        )
        let invalidation = FeatureInvalidationCenter()
        let list = RoutineListViewModel(kind: .supplement, provider: provider)
        let history = RoutineHistoryViewModel(kind: .supplement, itemID: "supplement-1", provider: provider)
        await list.load(revision: 0)
        await history.load(revision: 0)
        let detail = RoutineDetailViewModel(kind: .supplement, itemID: "supplement-1", listModel: list)
        let action = Self.model(provider: provider, invalidation: invalidation)

        await action.submit(status: .taken)
        await list.load(revision: invalidation.revision(for: .routineList(kind: .supplement)))
        await history.load(revision: invalidation.revision(for: .routineHistory(kind: .supplement, itemID: "supplement-1")))

        #expect(detail.item?.version == 2)
        #expect(await provider.listRequests == [
            RoutineListRequest(kind: .supplement, includeArchived: false),
            RoutineListRequest(kind: .supplement, includeArchived: false),
        ])
        #expect(await provider.historyRequests == [
            RoutineHistoryRequest(kind: .supplement, itemID: "supplement-1", cursor: nil, limit: 20),
            RoutineHistoryRequest(kind: .supplement, itemID: "supplement-1", cursor: nil, limit: 20),
        ])
        #expect(invalidation.revision(for: .today) == 0)
    }

    @Test("success leaves loaded snapshots unchanged until their exact revisions reload")
    func successInvalidatesTodayAndExactReadOwnersWithoutOptimisticPatch() async throws {
        let provider = RoutineActionProvider(
            results: [.success(Self.receipt(.taken))],
            lists: [DemoBodyFlowFixtures.loadedSupplementList, DemoBodyFlowFixtures.postRoutineTakenSupplementList],
            histories: [DemoBodyFlowFixtures.loadedSupplementHistory, DemoBodyFlowFixtures.postRoutineTakenSupplementHistory]
        )
        let invalidation = FeatureInvalidationCenter()
        let list = RoutineListViewModel(kind: .supplement, provider: provider)
        let history = RoutineHistoryViewModel(kind: .supplement, itemID: "supplement-1", provider: provider)
        await list.load(revision: 0)
        await history.load(revision: 0)
        let beforeList = try #require(list.snapshot)
        let beforeHistory = history.items
        let action = Self.model(provider: provider, invalidation: invalidation)

        await action.submit(status: .taken)

        #expect(list.snapshot == beforeList)
        #expect(history.items == beforeHistory)
        #expect(invalidation.revision(for: .today) == 1)
        await list.load(revision: invalidation.revision(for: .routineList(kind: .supplement)))
        await history.load(revision: invalidation.revision(for: .routineHistory(kind: .supplement, itemID: "supplement-1")))
        #expect(list.snapshot == DemoBodyFlowFixtures.postRoutineTakenSupplementList.data)
        #expect(history.items == DemoBodyFlowFixtures.postRoutineTakenSupplementHistory.items)
        #expect(await provider.listRequests.count == 2)
        #expect(await provider.historyRequests.count == 2)
    }

    @Test("a distinct action intention is ignored while an action is in flight")
    func distinctActionIsIgnoredWhileActionIsInFlight() async {
        let provider = SupersedingRoutineActionProvider()
        let model = Self.model(provider: provider)
        let old = Task { await model.submit(status: .taken) }
        try? await Task.sleep(for: .milliseconds(20))

        await model.submit(status: .skipped)
        await old.value

        #expect(await provider.callCount == 1)
        #expect(model.mutationState.receipt?.data.status == "taken")
        #expect(model.accessibilityFocusTarget == .operationSummary)
    }

    @Test("an identical in-flight action is deduplicated before a second key is created")
    func identicalActionIsDeduplicatedWhileInFlight() async {
        let provider = SupersedingRoutineActionProvider()
        let model = Self.model(provider: provider)
        let first = Task { await model.submit(status: .taken) }
        try? await Task.sleep(for: .milliseconds(20))
        await model.submit(status: .taken)
        await first.value

        #expect(await provider.callCount == 1)
        #expect(model.mutationState.receipt?.data.status == "taken")
    }

    @Test("different snooze presets share one in-flight mutation key")
    func differentSnoozePresetsAreBlockedWhileActionIsInFlight() async {
        let provider = SupersedingRoutineActionProvider()
        let model = Self.model(provider: provider)
        let first = Task { await model.submit(status: .snoozed, selection: .minutes(15)) }
        try? await Task.sleep(for: .milliseconds(20))

        await model.submit(status: .snoozed, selection: .minutes(30))
        await first.value

        #expect(await provider.callCount == 1)
        #expect(await provider.keys.count == 1)
    }

    private static func model(
        provider: any RoutineProviding,
        invalidation: FeatureInvalidationCenter = FeatureInvalidationCenter(),
        occurredAt: Date = occurredAt
    ) -> RoutineActionModel {
        RoutineActionModel(
            provider: provider,
            timeProvider: FixedTimeProvider(value: occurredAt),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "routine-action"),
            invalidationCenter: invalidation,
            patientTimeZone: PatientTimeZoneContext(documentedIANAIdentifier: "America/Sao_Paulo"),
            context: RoutineOccurrenceContext(
                kind: .supplement,
                itemID: "supplement-1",
                reminderRuleID: "rule-1",
                scheduledFor: APITimestamp(value: occurredAt)
            )
        )
    }

    private static func receipt(_ status: RoutineActionStatus) -> RoutineActionResponse {
        RoutineActionResponse(
            data: RoutineActionReceipt(
                adherenceLogID: "log-1",
                occurrenceKey: "server-occurrence-key",
                kind: .supplement,
                status: status.rawValue
            ),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "action")
        )
    }

    private static func schedule(
        id: String,
        status: String,
        scheduledFor: Date = occurredAt
    ) -> RoutineScheduleSnapshot {
        RoutineScheduleSnapshot(
            id: id,
            localTime: "08:00",
            weekdays: [0, 1, 2, 3, 4, 5, 6],
            occurrence: RoutineOccurrenceSnapshot(
                scheduledFor: APITimestamp(value: scheduledFor),
                status: status,
                lastActionAt: nil,
                snoozedUntil: nil
            )
        )
    }

    private static let occurredAt = Date(timeIntervalSince1970: 1_784_589_300)
}

actor LateRoutineActionProvider: RoutineProviding {
    func record(_ attempt: MutationAttempt<RoutineActionCommand>) async throws -> RoutineActionResponse {
        try? await Task.sleep(for: .milliseconds(100))
        return RoutineActionResponse(
            data: RoutineActionReceipt(
                adherenceLogID: "late-log",
                occurrenceKey: "late-occurrence-key",
                kind: .supplement,
                status: "taken"
            ),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "late")
        )
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func history(kind: RoutineItemKind, itemID: String, cursor: String?, limit: Int) async throws -> RoutineHistoryPage {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

actor SupersedingRoutineActionProvider: RoutineProviding {
    private(set) var callCount = 0
    private(set) var keys: [IdempotencyKey] = []

    func record(_ attempt: MutationAttempt<RoutineActionCommand>) async throws -> RoutineActionResponse {
        callCount += 1
        keys.append(attempt.key)
        let call = callCount
        if call == 1 { try? await Task.sleep(for: .milliseconds(100)) }
        return RoutineActionResponse(
            data: RoutineActionReceipt(adherenceLogID: "log-\(call)", occurrenceKey: "server-key-\(call)", kind: .supplement, status: call == 1 ? "taken" : "skipped"),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "supersede-\(call)")
        )
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse { throw BodyFlowCapabilityError.operationUnavailable }
    func history(kind: RoutineItemKind, itemID: String, cursor: String?, limit: Int) async throws -> RoutineHistoryPage { throw BodyFlowCapabilityError.operationUnavailable }
}

actor RoutineActionProvider: RoutineProviding {
    enum Result: Sendable {
        case success(RoutineActionResponse)
        case failure(BodyFlowCapabilityError)
    }

    private var results: [Result]
    private var lists: [RoutineListResponse]
    private var histories: [RoutineHistoryPage]
    private(set) var attempts: [MutationAttempt<RoutineActionCommand>] = []
    private(set) var listRequests: [RoutineListRequest] = []
    private(set) var historyRequests: [RoutineHistoryRequest] = []

    init(
        results: [Result] = [],
        lists: [RoutineListResponse] = [],
        histories: [RoutineHistoryPage] = []
    ) {
        self.results = results
        self.lists = lists
        self.histories = histories
    }

    func record(_ attempt: MutationAttempt<RoutineActionCommand>) async throws -> RoutineActionResponse {
        attempts.append(attempt)
        guard !results.isEmpty else { throw BodyFlowCapabilityError.operationUnavailable }
        switch results.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse {
        listRequests.append(RoutineListRequest(kind: kind, includeArchived: includeArchived))
        guard !lists.isEmpty else { throw BodyFlowCapabilityError.operationUnavailable }
        return lists.removeFirst()
    }

    func history(kind: RoutineItemKind, itemID: String, cursor: String?, limit: Int) async throws -> RoutineHistoryPage {
        historyRequests.append(RoutineHistoryRequest(kind: kind, itemID: itemID, cursor: cursor, limit: limit))
        guard !histories.isEmpty else { throw BodyFlowCapabilityError.operationUnavailable }
        return histories.removeFirst()
    }
}
