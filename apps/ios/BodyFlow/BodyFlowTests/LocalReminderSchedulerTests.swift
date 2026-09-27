import Foundation
import Testing
import UserNotifications
@testable import BodyFlow

private extension Date {
    func rounded(toMinute _: Void) -> Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / 60).rounded(.down) * 60)
    }
}

/// A notification center model for tests: the real center is exercised by
/// the UI tests on the Simulator; delivery on a physical iPhone is not
/// proven by either.
actor FakeNotificationCenter: LocalNotificationCentering {
    var status: LocalNotificationAuthorization
    let grantsOnRequest: Bool
    private(set) var requestCount = 0
    private(set) var pending: [String] = []
    private(set) var delivered: [String] = []
    private(set) var addedUserInfo: [String: [String: String]] = [:]
    private(set) var contents: [String: String] = [:]
    var refused: Set<String> = []
    var dropped: Set<String> = []
    var ignoresRemoval = false
    private var holdsAdds = false
    private var heldAdds: [CheckedContinuation<Void, Never>] = []
    private(set) var suspendedAdds = 0

    init(status: LocalNotificationAuthorization = .authorized, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    func setStatus(_ value: LocalNotificationAuthorization) { status = value }
    func seedPending(_ identifiers: [String]) { pending.append(contentsOf: identifiers) }
    func seedDelivered(_ identifiers: [String]) { delivered.append(contentsOf: identifiers) }
    func refuse(_ identifiers: Set<String>) { refused = identifiers }
    func drop(_ identifiers: Set<String>) { dropped = identifiers }
    func setIgnoresRemoval(_ value: Bool) { ignoresRemoval = value }
    func holdAdds() { holdsAdds = true }

    func releaseAdds() {
        holdsAdds = false
        let held = heldAdds
        heldAdds = []
        held.forEach { $0.resume() }
    }

    func authorization() async -> LocalNotificationAuthorization { status }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        if status == .notDetermined { status = grantsOnRequest ? .authorized : .denied }
        return status == .authorized
    }

    func pendingIdentifiers() async -> [String] { pending }
    func deliveredIdentifiers() async -> [String] { delivered }

    func add(_ reminder: PlannedLocalReminder, ownerKey: String) async throws {
        if holdsAdds {
            suspendedAdds += 1
            await withCheckedContinuation { heldAdds.append($0) }
        }
        if refused.contains(reminder.identifier) { throw BodyFlowCapabilityError.operationUnavailable }
        addedUserInfo[reminder.identifier] = SystemLocalNotificationCenter.userInfo(for: reminder, ownerKey: ownerKey)
        contents[reminder.identifier] = "\(reminder.title)|\(reminder.body)"
        guard !dropped.contains(reminder.identifier) else { return }
        pending.removeAll { $0 == reminder.identifier }
        pending.append(reminder.identifier)
    }

    func removePending(_ identifiers: [String]) async {
        guard !ignoresRemoval else { return }
        pending.removeAll { identifiers.contains($0) }
    }

    func removeDelivered(_ identifiers: [String]) async {
        guard !ignoresRemoval else { return }
        delivered.removeAll { identifiers.contains($0) }
    }
}

func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@Suite("Local reminder scheduler")
struct LocalReminderSchedulerTests {
    static let ownerA = LocalReminderPlanner.ownerKey(for: "user-a")
    static let ownerB = LocalReminderPlanner.ownerKey(for: "user-b")

    static func reminder(_ owner: String, _ suffix: String, minutes: Double, renewal: Bool = false) -> PlannedLocalReminder {
        PlannedLocalReminder(
            identifier: "\(LocalReminderPlanner.identifierPrefix(ownerKey: owner))\(suffix)",
            fireDate: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60),
            title: "Lembrete da rotina",
            body: "Toque para ver o que está programado.",
            destination: renewal ? .today : .routineItem(kind: .medication, itemID: "item-1"),
            isRenewal: renewal
        )
    }

    static func plan(_ owner: String, count: Int = 2) -> LocalReminderPlan {
        let reminders = (0..<count).map { reminder(owner, "medication.s.\($0)", minutes: Double($0)) }
        return LocalReminderPlan(
            reminders: reminders + [reminder(owner, "renewal.\(count)", minutes: Double(count), renewal: true)],
            coverageEnd: reminders.last?.fireDate,
            skipped: [:]
        )
    }

    @Test("apply schedules the plan and reports what the system holds, read back")
    func appliesAndReadsBack() async {
        let center = FakeNotificationCenter()
        let scheduler = LocalReminderScheduler(center: center)
        let plan = Self.plan(Self.ownerA)

        let outcome = await scheduler.apply(plan, ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())

        #expect(outcome == .applied(LocalReminderApplyResult(
            scheduledCount: 2, renewalScheduled: true, notAccepted: 0,
            coverageEnd: plan.coverageEnd
        )))
        #expect(await center.pending == plan.reminders.map(\.identifier))
        let userInfo = await center.addedUserInfo[plan.reminders[0].identifier]
        #expect(userInfo == ["pai.owner": Self.ownerA, "pai.kind": "medication", "pai.item": "item-1"])
    }

    @Test("stale reminders of this app are removed; other identifiers are left alone")
    func removesStaleKeepsOthers() async {
        let center = FakeNotificationCenter()
        await center.seedPending(["\(LocalReminderPlanner.identifierPrefix(ownerKey: Self.ownerA))meal.old.1", "com.other.feature"])
        let scheduler = LocalReminderScheduler(center: center)

        _ = await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())

        let pending = await center.pending
        #expect(pending.contains("com.other.feature"))
        #expect(!pending.contains { $0.hasSuffix("meal.old.1") })
    }

    @Test("requests the system refuses or drops are never reported as scheduled")
    func refusedAndDropped() async {
        let center = FakeNotificationCenter()
        let plan = Self.plan(Self.ownerA, count: 3)
        await center.refuse([plan.reminders[0].identifier])
        await center.drop([plan.reminders[2].identifier])
        let scheduler = LocalReminderScheduler(center: center)

        let outcome = await scheduler.apply(plan, ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())

        guard case let .applied(result) = outcome else { Issue.record("not applied"); return }
        #expect(result.scheduledCount == 1)
        #expect(result.notAccepted == 2)
        #expect(result.coverageEnd == plan.reminders[1].fireDate)
    }

    @Test("a sync of an invalidated session schedules nothing")
    func supersededBeforeApply() async {
        let center = FakeNotificationCenter()
        let scheduler = LocalReminderScheduler(center: center)
        let epoch = scheduler.currentEpoch()
        scheduler.invalidate()

        let outcome = await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: epoch)

        #expect(outcome == .superseded)
        #expect(await center.pending.isEmpty)
    }

    @Test("a late response: invalidated while adding, it removes what it added")
    func invalidatedDuringAdds() async {
        let center = FakeNotificationCenter()
        await center.holdAdds()
        let scheduler = LocalReminderScheduler(center: center)
        let epoch = scheduler.currentEpoch()
        let applying = Task { await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: epoch) }
        await waitUntil { await center.suspendedAdds == 1 }

        scheduler.invalidate()
        await center.releaseAdds()

        #expect(await applying.value == .superseded)
        #expect(await center.pending.isEmpty)
    }

    @Test("clearing waits for a running sync, then leaves no reminder of this app, pending or delivered")
    func clearAllIsSerializedAndVerified() async {
        let center = FakeNotificationCenter()
        await center.seedDelivered(["\(LocalReminderPlanner.identifierPrefix(ownerKey: Self.ownerA))meal.x.1", "com.other.feature"])
        await center.holdAdds()
        let scheduler = LocalReminderScheduler(center: center)
        let applying = Task {
            await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())
        }
        await waitUntil { await center.suspendedAdds == 1 }
        let clearing = Task { await scheduler.clearAll() }
        await center.releaseAdds()

        #expect(await applying.value == .superseded)
        #expect(await clearing.value == true)
        #expect(await center.pending.isEmpty)
        #expect(await center.delivered == ["com.other.feature"])
    }

    @Test("clearing is not reported done when the system still holds reminders")
    func clearAllReportsFailure() async {
        let center = FakeNotificationCenter()
        await center.seedPending(["\(LocalReminderPlanner.identifierPrefix(ownerKey: Self.ownerA))meal.x.1"])
        await center.setIgnoresRemoval(true)
        let scheduler = LocalReminderScheduler(center: center)

        #expect(await scheduler.clearAll() == false)
    }

    @Test("clearing one owner leaves another owner's reminders; applying removes another owner's leftovers")
    func ownerIsolation() async {
        let center = FakeNotificationCenter()
        let scheduler = LocalReminderScheduler(center: center)
        _ = await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())
        await center.seedDelivered(["\(LocalReminderPlanner.identifierPrefix(ownerKey: Self.ownerA))medication.s.9"])

        _ = await scheduler.apply(Self.plan(Self.ownerB), ownerKey: Self.ownerB, epoch: scheduler.currentEpoch())
        let prefixA = LocalReminderPlanner.identifierPrefix(ownerKey: Self.ownerA)
        #expect(await center.pending.allSatisfy { !$0.hasPrefix(prefixA) })
        #expect(await center.delivered.allSatisfy { !$0.hasPrefix(prefixA) })

        #expect(await scheduler.clearOwner(Self.ownerA) == true)
        #expect(await center.pending == Self.plan(Self.ownerB).reminders.map(\.identifier))
    }

    @Test("the sign-out clearer ends the session and removes every reminder")
    func sessionClearer() async {
        let center = FakeNotificationCenter()
        let scheduler = LocalReminderScheduler(center: center)
        let epoch = scheduler.currentEpoch()
        _ = await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: epoch)

        await CompositeSensitiveStateClearer(clearers: [LocalReminderSessionClearer(scheduler: scheduler)])
            .clearSensitiveState()

        #expect(await center.pending.isEmpty)
        #expect(scheduler.currentEpoch() != epoch)
        #expect(await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: epoch) == .superseded)
    }

    @Test("a new sync replaces the text of reminders already pending (privacy mode, dose or language changed)")
    func replacesPendingContent() async {
        let center = FakeNotificationCenter()
        let scheduler = LocalReminderScheduler(center: center)
        let first = Self.plan(Self.ownerA)
        _ = await scheduler.apply(first, ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())
        let changed = LocalReminderPlan(
            reminders: first.reminders.map {
                PlannedLocalReminder(
                    identifier: $0.identifier, fireDate: $0.fireDate, title: "Lembrete da rotina",
                    body: "Texto novo", destination: $0.destination, isRenewal: $0.isRenewal
                )
            },
            coverageEnd: first.coverageEnd, skipped: [:]
        )

        _ = await scheduler.apply(changed, ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())

        let contents = await center.contents
        #expect(first.reminders.allSatisfy { contents[$0.identifier] == "Lembrete da rotina|Texto novo" })
        #expect(await center.pending.count == first.reminders.count)
    }

    @Test("an owner clean-up of a superseded session does nothing; foreign owners are removed at session start")
    func ownerCleanupBoundToEpoch() async {
        let center = FakeNotificationCenter()
        let scheduler = LocalReminderScheduler(center: center)
        let oldEpoch = scheduler.currentEpoch()
        scheduler.invalidate()
        _ = await scheduler.apply(Self.plan(Self.ownerA), ownerKey: Self.ownerA, epoch: scheduler.currentEpoch())

        #expect(await scheduler.clearOwner(Self.ownerA, ifEpoch: oldEpoch) == true)
        #expect(await center.pending.count == 3)

        await center.seedDelivered(["\(LocalReminderPlanner.identifierPrefix(ownerKey: Self.ownerB))meal.x.1"])
        #expect(await scheduler.clearForeignOwners(keeping: Self.ownerB) == true)
        #expect(await center.pending.isEmpty)
        #expect(await center.delivered.isEmpty == false)
        #expect(await scheduler.clearForeignOwners(keeping: Self.ownerA) == true)
        #expect(await center.delivered.isEmpty)
    }

    @Test("the sign-out marker stays set until the clean-up is confirmed")
    func cleanupMarker() async {
        let center = FakeNotificationCenter()
        await center.seedPending(["\(LocalReminderPlanner.identifierPrefix(ownerKey: Self.ownerA))meal.x.1"])
        await center.setIgnoresRemoval(true)
        let marker = InMemoryLocalReminderCleanupMarker()
        let scheduler = LocalReminderScheduler(center: center, cleanupMarker: marker)

        await LocalReminderSessionClearer(scheduler: scheduler).clearSensitiveState()
        #expect(marker.isSet)

        await center.setIgnoresRemoval(false)
        #expect(await scheduler.clearAll() == true)
        #expect(!marker.isSet)
    }

    @Test("the trigger fires at the planned instant")
    func triggerNextDate() {
        let date = Date().addingTimeInterval(86_400).rounded(toMinute: ())
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: SystemLocalNotificationCenter.triggerComponents(for: date),
            repeats: false
        )
        #expect(trigger.nextTriggerDate() == date)
    }

    @Test("the trigger is the absolute instant in UTC, whatever the device zone")
    func triggerComponents() {
        let date = Date(timeIntervalSince1970: 1_793_514_600) // 2026-11-01T06:30:00Z
        let components = SystemLocalNotificationCenter.triggerComponents(for: date)
        #expect(components.timeZone?.identifier == "UTC" || components.timeZone?.secondsFromGMT() == 0)
        #expect(components.calendar?.date(from: components) == date)
        #expect([components.year, components.month, components.day, components.hour, components.minute]
            == [2026, 11, 1, 6, 30])
    }
}
