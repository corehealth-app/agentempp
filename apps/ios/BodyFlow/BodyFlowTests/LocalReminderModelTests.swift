import Foundation
import Testing
@testable import BodyFlow

private actor FakeReminderSources: ReminderProviding, RoutineProviding, ProgressProviding {
    var preferences = NotificationPreferencesSnapshot(
        pushEnabled: true, quietHours: nil, dailyPushLimit: 8, routinePreviewMode: "private"
    )
    var failure: BodyFlowCapabilityError?
    private var holdsRules = false
    private var heldRules: [CheckedContinuation<Void, Never>] = []
    private(set) var suspendedRuleReads = 0

    static let meta = MobileResponseMetadata(apiVersion: "v1", requestID: "test")

    func setPushEnabled(_ enabled: Bool) {
        preferences = NotificationPreferencesSnapshot(
            pushEnabled: enabled, quietHours: nil, dailyPushLimit: 8, routinePreviewMode: "private"
        )
    }
    func setFailure(_ error: BodyFlowCapabilityError?) { failure = error }
    func holdRules() { holdsRules = true }
    func releaseRules() {
        holdsRules = false
        let held = heldRules
        heldRules = []
        held.forEach { $0.resume() }
    }

    func notificationPreferences() async throws -> NotificationPreferencesResponse {
        if let failure { throw failure }
        return MobileResponse(data: preferences, meta: Self.meta)
    }

    func reminderRules() async throws -> ReminderRulesResponse {
        if holdsRules {
            suspendedRuleReads += 1
            await withCheckedContinuation { heldRules.append($0) }
        }
        return MobileResponse(data: [], meta: Self.meta)
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse {
        let items = kind == .medication
            ? [LocalReminderPlannerTests.item(schedules: [LocalReminderPlannerTests.schedule("10:00")])]
            : []
        return MobileResponse(data: RoutineListSnapshot(localDate: "2026-09-28", items: items), meta: Self.meta)
    }

    func record(_ attempt: MutationAttempt<RoutineActionCommand>) async throws -> RoutineActionResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func history(kind: RoutineItemKind, itemID: String, cursor: String?, limit: Int) async throws -> RoutineHistoryPage {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func progress() async throws -> ProgressResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

@MainActor
@Suite("Local reminder session model", .serialized)
struct LocalReminderModelTests {
    let center: FakeNotificationCenter
    let scheduler: LocalReminderScheduler
    private let sources = FakeReminderSources()
    let optIn = InMemoryLocalReminderOptInStore()

    init() {
        center = FakeNotificationCenter(status: .notDetermined)
        scheduler = LocalReminderScheduler(center: center)
    }

    func model(
        userID: String = "user-a",
        zone: String? = "America/Sao_Paulo",
        zoneSettled: Bool = true,
        scheduler: LocalReminderScheduler? = nil
    ) -> LocalReminderModel {
        LocalReminderModel(
            userID: userID,
            sources: LocalReminderSources(reminders: sources, routine: sources, progress: sources),
            scheduler: scheduler ?? self.scheduler,
            optIn: optIn,
            timeZone: { PatientTimeZoneContext(documentedIANAIdentifier: zone) },
            timeZoneSettled: { zoneSettled },
            now: { LocalReminderPlannerTests.instant("2026-09-28T12:00:00Z") },
            language: .portugueseBrazil
        )
    }

    @Test("without activation nothing is asked or scheduled")
    func notEnabled() async {
        let reminders = model()
        await reminders.refresh()

        #expect(reminders.status == .notEnabled)
        #expect(await center.requestCount == 0)
        #expect(await center.pending.isEmpty)
    }

    @Test("activation asks for permission once, then schedules and reports the verified coverage")
    func activation() async {
        let reminders = model()
        await reminders.activate()

        #expect(await center.requestCount == 1)
        guard case let .scheduled(coverage) = reminders.status else {
            Issue.record("expected scheduled, got \(reminders.status)")
            return
        }
        #expect(coverage.scheduledCount == LocalReminderPlanner.windowDays)
        #expect(coverage.renewalScheduled)
        #expect(await center.pending.count == LocalReminderPlanner.windowDays + 1)
        #expect(coverage.timeZoneIdentifier == "America/Sao_Paulo")
        await reminders.refresh()
        #expect(await center.requestCount == 1)
    }

    @Test("denied permission schedules nothing and says so")
    func denied() async {
        await center.setStatus(.denied)
        let reminders = model()
        await reminders.activate()

        #expect(reminders.status == .permissionDenied)
        #expect(await center.requestCount == 0)
        #expect(await center.pending.isEmpty)
    }

    @Test("permission revoked later: the next sync removes this owner's reminders")
    func revoked() async {
        let reminders = model()
        await reminders.activate()
        #expect(await !center.pending.isEmpty)

        await center.setStatus(.denied)
        await reminders.refresh()

        #expect(reminders.status == .permissionDenied)
        #expect(await center.pending.isEmpty)
    }

    @Test("no documented time zone: nothing is derived or scheduled")
    func timeZoneMissing() async {
        let reminders = model(zone: nil)
        await reminders.activate()

        #expect(reminders.status == .timeZoneMissing)
        #expect(await center.pending.isEmpty)
    }

    @Test("offline launch: a zone `/me` has not answered yet keeps what is scheduled")
    func unsettledZoneKeepsReminders() async {
        let first = model()
        await first.activate()
        let scheduled = await center.pending

        let offline = model(zone: nil, zoneSettled: false)
        await offline.refresh()

        #expect(offline.status == .unavailable)
        #expect(await center.pending == scheduled)
    }

    @Test("session start removes another account's leftovers even with reminders off")
    func foreignLeftoversRemovedWithoutOptIn() async {
        await center.seedPending(["\(LocalReminderPlanner.identifierPrefix(ownerKey: "0badf00d"))meal.x.1"])
        await center.seedDelivered(["\(LocalReminderPlanner.identifierPrefix(ownerKey: "0badf00d"))meal.x.2"])
        let reminders = model()

        await reminders.refresh()

        #expect(reminders.status == .notEnabled)
        #expect(await center.pending.isEmpty)
        #expect(await center.delivered.isEmpty)
    }

    @Test("activating while a sync runs ends scheduled, not in the state the older pass saw")
    func activationCoalescesWithRunningSync() async {
        await center.setStatus(.authorized)
        await sources.holdRules()
        let reminders = model()
        optIn.setEnabled(true, ownerKey: reminders.ownerKey)
        let first = Task { await reminders.refresh() }
        await waitUntil { [sources] in await sources.suspendedRuleReads == 1 }
        let activation = Task { await reminders.activate() }
        await sources.releaseRules()
        await first.value
        await activation.value

        guard case .scheduled = reminders.status else {
            Issue.record("expected scheduled, got \(reminders.status)")
            return
        }
    }

    @Test("preferences turned off on the server: nothing is scheduled")
    func preferencesOff() async {
        await sources.setPushEnabled(false)
        let reminders = model()
        await reminders.activate()

        #expect(reminders.status == .preferencesOff)
        #expect(await center.pending.isEmpty)
    }

    @Test("a failed sync keeps what the last sync scheduled and says it could not update")
    func unavailableKeepsPrevious() async {
        let reminders = model()
        await reminders.activate()
        let scheduled = await center.pending

        await sources.setFailure(.offline)
        await reminders.refresh()

        #expect(reminders.status == .unavailable)
        #expect(await center.pending == scheduled)
    }

    @Test("sign-out during a sync: the late response schedules nothing")
    func signOutDuringSync() async {
        let reminders = model()
        optIn.setEnabled(true, ownerKey: reminders.ownerKey)
        await center.setStatus(.authorized)
        await sources.holdRules()
        let syncing = Task { await reminders.refresh() }
        await waitUntil { [sources] in await sources.suspendedRuleReads == 1 }

        await LocalReminderSessionClearer(scheduler: scheduler).clearSensitiveState()
        await sources.releaseRules()
        await syncing.value

        #expect(await center.pending.isEmpty)
        #expect(reminders.status == .unavailable)
    }

    @Test("the session's shell ends during a sync: nothing is scheduled and later syncs are ignored")
    func endSessionDuringSync() async {
        let reminders = model()
        optIn.setEnabled(true, ownerKey: reminders.ownerKey)
        await center.setStatus(.authorized)
        await sources.holdRules()
        let syncing = Task { await reminders.refresh() }
        await waitUntil { [sources] in await sources.suspendedRuleReads == 1 }

        reminders.endSession()
        await sources.releaseRules()
        await syncing.value
        await reminders.refresh()
        await waitUntil { [center] in await center.pending.isEmpty }

        #expect(await center.pending.isEmpty)
    }

    @Test("A/B on one iPhone: the next account never inherits the previous account's reminders")
    func accountsDoNotShareReminders() async {
        await center.setStatus(.authorized)
        let first = model(userID: "user-a")
        await first.activate()
        let prefixA = LocalReminderPlanner.identifierPrefix(ownerKey: first.ownerKey)
        #expect(await center.pending.contains { $0.hasPrefix(prefixA) })

        await LocalReminderSessionClearer(scheduler: scheduler).clearSensitiveState()
        let second = model(userID: "user-b")
        #expect(!second.isEnabled)
        await second.activate()

        let pending = await center.pending
        #expect(!pending.contains { $0.hasPrefix(prefixA) })
        #expect(pending.allSatisfy { $0.hasPrefix(LocalReminderPlanner.identifierPrefix(ownerKey: second.ownerKey)) })
    }

    @Test("turning reminders off removes this owner's reminders")
    func deactivate() async {
        let reminders = model()
        await reminders.activate()
        await reminders.deactivate()

        #expect(reminders.status == .notEnabled)
        #expect(!reminders.isEnabled)
        #expect(await center.pending.isEmpty)
    }

    @Test("the screen reports coverage only for what the system holds, in the patient's zone")
    func presentation() {
        let coverage = LocalReminderCoverage(
            scheduledCount: 3,
            coverageEnd: LocalReminderPlannerTests.instant("2026-10-02T13:00:00Z"),
            renewalScheduled: true,
            skipped: [.quietHours: 2, .beyondBudget: 5],
            notAccepted: 1,
            previewMode: .private,
            timeZoneIdentifier: "America/Sao_Paulo"
        )
        let text = LocalReminderPresentation.coverageText(coverage, language: .portugueseBrazil)
        #expect(text?.contains("10:00") == true)
        let rows = LocalReminderPresentation.skippedRows(coverage, language: .portugueseBrazil)
        #expect(rows.map(\.id) == ["beyond_budget", "quiet_hours", "not_accepted"])
        #expect(rows.map(\.value) == ["5", "2", "1"])
        let none = LocalReminderCoverage(
            scheduledCount: 0, coverageEnd: nil, renewalScheduled: false, skipped: [:],
            notAccepted: 0, previewMode: .private, timeZoneIdentifier: "America/Sao_Paulo"
        )
        #expect(LocalReminderPresentation.coverageText(none, language: .portugueseBrazil) == nil)
        for language in SupportedAppLanguage.allCases {
            for status: LocalReminderStatus in [.loading, .notEnabled, .permissionDenied, .preferencesOff,
                                                .timeZoneMissing, .unavailable, .scheduled(coverage), .scheduled(none)] {
                let message = LocalReminderPresentation.statusMessage(status, language: language)
                #expect(!message.isEmpty && !message.hasPrefix("reminders."))
                #expect(!LocalReminderPresentation.summary(status, language: language).hasPrefix("reminders."))
            }
        }
    }
}

@Suite("Local reminder tap routing")
struct LocalReminderRoutingTests {
    @Test("a tap carries the owner and, for a routine item, its kind and id — nothing else")
    func parsesTap() {
        let owner = LocalReminderPlanner.ownerKey(for: "user-a")
        #expect(LocalReminderTap(userInfo: ["pai.owner": owner, "pai.kind": "medication", "pai.item": "item-1"])
            == LocalReminderTap(ownerKey: owner, destination: .routineItem(kind: .medication, itemID: "item-1")))
        #expect(LocalReminderTap(userInfo: ["pai.owner": owner])?.destination == .today)
        #expect(LocalReminderTap(userInfo: ["pai.owner": owner, "pai.kind": "medication", "pai.item": "../x"])?.destination == .today)
        #expect(LocalReminderTap(userInfo: [:]) == nil)
        #expect(LocalReminderTap(userInfo: ["pai.owner": "a b"]) == nil)
    }

    @MainActor
    @Test("an old tap is not opened later")
    func inboxValidity() {
        let inbox = LocalReminderRouteInbox()
        let tap = LocalReminderTap(ownerKey: "aaaa0000", destination: .today)
        let received = Date(timeIntervalSince1970: 1_790_000_000)
        inbox.receive(tap, at: received)
        #expect(inbox.take(ownerKey: "aaaa0000", now: received.addingTimeInterval(LocalReminderRouteInbox.validity + 1)) == nil)
        inbox.receive(tap, at: received)
        #expect(inbox.take(ownerKey: "aaaa0000", now: received.addingTimeInterval(60)) == tap)
    }

    @MainActor
    @Test("the inbox opens a tap only for its owner; another account's tap is discarded unopened")
    func inboxOwnership() {
        let inbox = LocalReminderRouteInbox()
        let tap = LocalReminderTap(ownerKey: "aaaa0000", destination: .today)
        inbox.receive(tap)
        #expect(inbox.take(ownerKey: "bbbb1111") == nil)
        #expect(inbox.pending == nil)
        inbox.receive(tap)
        #expect(inbox.take(ownerKey: "aaaa0000") == tap)
    }
}

@Suite("Mobile reminder repository")
struct MobileReminderRepositoryTests {
    private actor Spy: MobileAPIEnvelopeExecuting {
        private(set) var paths: [String] = []
        private(set) var methods: [HTTPMethod] = []
        let json: Data
        init(json: String) { self.json = Data(json.utf8) }

        func executeEnvelope<Response: Codable & Sendable>(
            _ request: MobileAPIRequest<Response>
        ) async throws -> MobileResponse<Response> {
            paths.append(request.path)
            methods.append(request.method)
            return try JSONDecoder().decode(MobileResponse<Response>.self, from: json)
        }
    }

    @Test("reads the patient's rules with a GET and decodes the contract")
    func rules() async throws {
        let spy = Spy(json: """
        {"data":[{"id":"r1","category":"meal","meal_type":"almoco","routine_item_id":null,"local_time":"12:30",
        "weekdays":[1,3],"active":true,"created_at":"2026-09-01T12:00:00Z","updated_at":"2026-09-01T12:00:00Z"}],
        "meta":{"api_version":"v1","request_id":"r"}}
        """)
        let response = try await MobileReminderRepository(transport: spy).reminderRules()
        #expect(response.data == [ReminderRuleSnapshot(
            id: "r1", category: "meal", mealType: "almoco", localTime: "12:30", weekdays: [1, 3], active: true
        )])
        #expect(await spy.paths == ["/api/mobile/v1/reminders"])
        #expect(await spy.methods == [.get])
    }

    @Test("reads the preferences with a GET; quiet hours may be null; an unknown mode is private")
    func preferences() async throws {
        let spy = Spy(json: """
        {"data":{"push_enabled":true,"quiet_hours":{"start":"22:00","end":"07:00"},"daily_push_limit":8,
        "hydration_target_ml":null,"routine_preview_mode":"name_and_dose","created_at":null,"updated_at":null},
        "meta":{"api_version":"v1","request_id":"r"}}
        """)
        let preferences = try await MobileReminderRepository(transport: spy).notificationPreferences().data
        #expect(preferences.quietHours == QuietHoursSnapshot(start: "22:00", end: "07:00"))
        #expect(preferences.previewMode == .nameAndDose)
        #expect(await spy.paths == ["/api/mobile/v1/notification-preferences"])
        let unknown = NotificationPreferencesSnapshot(
            pushEnabled: true, quietHours: nil, dailyPushLimit: 8, routinePreviewMode: "everything"
        )
        #expect(unknown.previewMode == .private)
    }
}
