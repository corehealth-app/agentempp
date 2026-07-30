#if DEBUG
import Foundation
import Testing

@testable import BodyFlow

@Suite("Demo BodyFlow Complete Reads")
struct DemoBodyFlowReadTests {
    @Test("Loaded scenario returns every complete pre-authored snapshot")
    func loadedScenarioReturnsCompleteSnapshots() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)

        let today = try await repository.today()
        let plan = try await repository.plan()
        let progress = try await repository.progress()
        let history = try await repository.history(.firstPage)
        let supplements = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )
        let medications = try await repository.list(
            kind: .medication,
            includeArchived: false
        )
        let supplementHistory = try await repository.history(
            kind: .supplement,
            itemID: "supplement-1",
            cursor: nil,
            limit: 20
        )

        #expect(today == DemoBodyFlowFixtures.loadedToday)
        #expect(plan == DemoBodyFlowFixtures.loadedPlan)
        #expect(progress == DemoBodyFlowFixtures.loadedProgress)
        #expect(history == DemoBodyFlowFixtures.loadedHistory)
        #expect(supplements == DemoBodyFlowFixtures.loadedSupplementList)
        #expect(medications == DemoBodyFlowFixtures.loadedMedicationList)
        #expect(supplementHistory == DemoBodyFlowFixtures.loadedSupplementHistory)

        #expect(today.data.meals.map(\.id) == ["meal-z", "meal-a"])
        #expect(plan.data.training?.daysPerWeek == 4)
        #expect(progress.data.xpTotal == 7_420)
        #expect(history.data.meals.map(\.id) == ["demo-history-meal-row-1", "demo-history-meal-row-2"])
        #expect(supplements.data.items.map(\.id) == ["supplement-1"])
        #expect(medications.data.items.isEmpty)
    }

    @Test("Loaded Today and routine snapshots resolve as one coherent graph")
    func loadedRoutineSnapshotsResolveAgainstToday() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let today = try await repository.today()
        let supplements = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )
        let supplementHistory = try await repository.history(
            kind: .supplement,
            itemID: "supplement-1",
            cursor: nil,
            limit: 20
        )

        #expect(today.data.localDate == "2026-07-20")
        #expect(supplements.data.localDate == today.data.localDate)

        let todayIDs = Set(today.data.supplements.items.map(\.id))
        let listIDs = Set(supplements.data.items.map(\.id))
        #expect(todayIDs == Set(["supplement-1"]))
        #expect(listIDs == todayIDs)

        let todayItem = try #require(today.data.supplements.items.first)
        let listItem = try #require(supplements.data.items.first)
        #expect(listItem.name == todayItem.name)
        #expect(listItem.remindersEnabled == todayItem.remindersEnabled)
        #expect(listItem.schedules.map(\.id) == todayItem.schedules.map(\.id))
        #expect(listItem.schedules.map(\.localTime) == todayItem.schedules.map(\.localTime))
        #expect(listItem.schedules.map(\.weekdays) == todayItem.schedules.map(\.weekdays))

        for occurrence in todayItem.occurrences {
            let schedule = try #require(
                listItem.schedules.first {
                    $0.id == occurrence.reminderRuleID
                }
            )
            let detailOccurrence = try #require(schedule.occurrence)
            #expect(detailOccurrence.scheduledFor == occurrence.scheduledFor)
            #expect(detailOccurrence.status == occurrence.status)
            #expect(detailOccurrence.lastActionAt == occurrence.lastActionAt)
            #expect(detailOccurrence.snoozedUntil == occurrence.snoozedUntil)
        }

        for historyItem in supplementHistory.items {
            let resolvedItem = try #require(
                supplements.data.items.first {
                    $0.id == historyItem.routineItemID
                }
            )
            _ = try #require(
                resolvedItem.schedules.first {
                    $0.id == historyItem.reminderRuleID
                }
            )
            let todayOccurrence = try #require(
                todayItem.occurrences.first {
                    $0.reminderRuleID == historyItem.reminderRuleID
                }
            )
            #expect(historyItem.scheduledFor == todayOccurrence.scheduledFor)
            #expect(historyItem.status == todayOccurrence.status)
            #expect(historyItem.occurredAt == todayOccurrence.lastActionAt)
            #expect(historyItem.snoozedUntil == todayOccurrence.snoozedUntil)
        }
    }

    @Test("Not-configured Today medication resolves to empty list and history")
    func notConfiguredMedicationHasNoInventedRoutine() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)
        let today = try await repository.today()
        let medications = try await repository.list(
            kind: .medication,
            includeArchived: false
        )
        let medicationHistory = try await repository.history(
            kind: .medication,
            itemID: "absent-medication",
            cursor: nil,
            limit: 20
        )

        #expect(today.data.medications.availability == "not_configured")
        #expect(today.data.medications.items.isEmpty)
        #expect(medications.data.localDate == today.data.localDate)
        #expect(medications.data.items.isEmpty)
        #expect(medicationHistory.items.isEmpty)
    }

    @Test("Loaded Today preserves deliberately inconsistent official values")
    func loadedTodayPreservesInconsistentOfficialValues() async throws {
        let today = try await DemoBodyFlowRepository(scenario: .loaded).today()
        let task2Fixture = try BodyFlowTestFixtures.decodeInconsistentToday()

        #expect(today == task2Fixture)
        #expect(today.data.targets.caloriesKcal == 1_935)
        #expect(today.data.consumed.caloriesKcal == 1_200)
        #expect(today.data.remainingFoodKcal == 731)
        #expect(today.data.foodExcessKcal == 17)
        #expect(today.data.exerciseKcal == 419)
        #expect(today.data.dailyBalanceKcal == -83)
        #expect(today.data.dailyBalanceStatus == "provisional")
    }

    @Test("Empty scenario returns complete empty snapshots")
    func emptyScenarioReturnsCompleteEmptySnapshots() async throws {
        let repository = DemoBodyFlowRepository(scenario: .empty)

        let today = try await repository.today()
        let plan = try await repository.plan()
        let progress = try await repository.progress()
        let history = try await repository.history(.firstPage)
        let routines = try await repository.list(
            kind: .supplement,
            includeArchived: false
        )

        #expect(today == DemoBodyFlowFixtures.emptyToday)
        #expect(today.data.meals.isEmpty)
        #expect(today.data.workouts.isEmpty)
        #expect(today.data.pendingActions.registrations.isEmpty)
        #expect(plan == DemoBodyFlowFixtures.emptyPlan)
        #expect(plan.data.training == nil)
        #expect(plan.data.nutrition.isEmpty)
        #expect(progress == DemoBodyFlowFixtures.emptyProgress)
        #expect(history == DemoBodyFlowFixtures.emptyHistory)
        #expect(history.data.meals.isEmpty && history.data.workouts.isEmpty)
        #expect(routines.data.items.isEmpty)
    }

    @Test("Incomplete day is a successful complete Today value")
    func incompleteDayIsSuccessfulContent() async throws {
        let repository = DemoBodyFlowRepository(scenario: .incompleteDay)

        let today = try await repository.today()

        #expect(today == DemoBodyFlowFixtures.incompleteToday)
        #expect(today.data.completionStatus.status == "insufficient_data")
        #expect(!today.data.completionStatus.dayClosed)
        #expect(today.data.completionStatus.hasSufficientData == false)
    }

    @Test("Initial offline and error scenarios fail deterministically")
    func initialFailureScenariosFailDeterministically() async {
        let offline = DemoBodyFlowRepository(scenario: .initialOffline)
        let error = DemoBodyFlowRepository(scenario: .initialError)

        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await offline.today()
        }
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await offline.plan()
        }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await error.today()
        }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await error.progress()
        }
    }

    @Test("Stale scenarios return one complete snapshot before their deterministic failure")
    func staleScenariosReturnContentThenFail() async throws {
        let staleOffline = DemoBodyFlowRepository(scenario: .staleOffline)
        let staleError = DemoBodyFlowRepository(scenario: .staleError)

        #expect(try await staleOffline.today() == DemoBodyFlowFixtures.loadedToday)
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await staleOffline.today()
        }
        #expect(try await staleError.today() == DemoBodyFlowFixtures.loadedToday)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await staleError.today()
        }
    }

    @Test("Stale read counters are independent across capabilities")
    func staleReadCountersAreIndependent() async throws {
        let repository = DemoBodyFlowRepository(scenario: .staleOffline)

        #expect(try await repository.today() == DemoBodyFlowFixtures.loadedToday)
        #expect(try await repository.plan() == DemoBodyFlowFixtures.loadedPlan)
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await repository.today()
        }
        await #expect(throws: BodyFlowCapabilityError.offline) {
            try await repository.plan()
        }
    }

    @Test("Loading scenario delays before returning the complete loaded snapshot")
    func loadingScenarioDelaysCompleteSnapshot() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loadingDelay)
        let clock = ContinuousClock()
        let start = clock.now

        let response = try await repository.today()

        #expect(response == DemoBodyFlowFixtures.loadedToday)
        #expect(start.duration(to: clock.now) >= .milliseconds(50))
    }

    @Test("Cancelling a loading read throws without publishing a late read")
    func loadingReadCancellationStopsBeforeSnapshot() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loadingDelay)
        let read = Task {
            try await repository.today()
        }

        try await Task.sleep(for: .milliseconds(10))
        read.cancel()

        await #expect(throws: CancellationError.self) {
            try await read.value
        }
        #expect(try await repository.today() == DemoBodyFlowFixtures.loadedToday)
    }

    @Test("Unavailable presentation fails every read closed")
    func unavailablePresentationFailsClosed() async {
        let repository = DemoBodyFlowRepository(scenario: .unavailablePresentation)

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await repository.today()
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await repository.history(.firstPage)
        }
        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await repository.list(kind: .medication, includeArchived: false)
        }
    }

    @Test("Routine mutation remains unavailable until Task 11")
    func routineMutationRemainsUnavailable() async throws {
        let repository = DemoBodyFlowRepository(scenario: .loaded)

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await repository.record(BodyFlowTestFixtures.routineAttempt())
        }
    }
}
#endif
