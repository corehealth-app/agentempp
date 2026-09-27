import Foundation
import Testing
@testable import BodyFlow

@Suite("Local reminder planner")
struct LocalReminderPlannerTests {
    static let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let owner = LocalReminderPlanner.ownerKey(for: "00000000-0000-4000-8000-00000000000a")

    static let copy = LocalReminderCopy(
        genericTitle: "Lembrete da rotina",
        genericBody: "Toque para ver o que está programado.",
        routineNameBody: "Toque para ver na sua rotina.",
        categoryTitles: ["meal": "Lembrete de refeição", "hydration": "Lembrete de hidratação"],
        renewalTitle: "Lembretes do Performe AI",
        renewalBody: "Abra o app para continuar recebendo lembretes."
    )

    static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    static func item(
        id: String = "11111111-1111-4111-8111-111111111111",
        kind: RoutineItemKind = .medication,
        name: String = "Remédio sintético",
        dose: String = "1 comprimido",
        remindersEnabled: Bool = true,
        active: Bool = true,
        archived: Bool = false,
        schedules: [RoutineScheduleSnapshot]
    ) -> RoutineItemSnapshot {
        let stamp = APITimestamp(value: instant("2026-09-01T12:00:00Z"))
        return RoutineItemSnapshot(
            id: id, kind: kind, name: name, doseText: dose, origin: "patient",
            remindersEnabled: remindersEnabled, active: active,
            archivedAt: archived ? stamp : nil, version: 1, createdAt: stamp, updatedAt: stamp,
            frequencySummary: RoutineFrequencySummary(timesPerWeek: 7), schedules: schedules
        )
    }

    static func schedule(
        id: String = "22222222-2222-4222-8222-222222222222",
        _ time: String,
        weekdays: [Int] = [0, 1, 2, 3, 4, 5, 6],
        occurrence: RoutineOccurrenceSnapshot? = nil
    ) -> RoutineScheduleSnapshot {
        RoutineScheduleSnapshot(id: id, localTime: time, weekdays: weekdays, occurrence: occurrence)
    }

    static func rule(
        id: String = "33333333-3333-4333-8333-333333333333",
        _ category: ReminderRuleCategory,
        _ time: String,
        weekdays: [Int] = [0, 1, 2, 3, 4, 5, 6],
        active: Bool = true
    ) -> ReminderRuleSnapshot {
        ReminderRuleSnapshot(
            id: id, category: category.rawValue, mealType: category == .meal ? "almoco" : nil,
            localTime: time, weekdays: weekdays, active: active
        )
    }

    static func preferences(
        quiet: QuietHoursSnapshot? = nil,
        limit: Int = 20,
        mode: RoutinePreviewMode = .private,
        pushEnabled: Bool = true
    ) -> NotificationPreferencesSnapshot {
        NotificationPreferencesSnapshot(
            pushEnabled: pushEnabled, quietHours: quiet, dailyPushLimit: limit,
            routinePreviewMode: mode.rawValue
        )
    }

    static func plan(
        items: [RoutineItemSnapshot] = [],
        rules: [ReminderRuleSnapshot] = [],
        preferences: NotificationPreferencesSnapshot = preferences(),
        nextReevaluation: String? = nil,
        zone: TimeZone = saoPaulo,
        now: Date = instant("2026-09-28T12:00:00Z")
    ) -> LocalReminderPlan {
        LocalReminderPlanner.plan(LocalReminderPlannerInput(
            ownerKey: owner, routineItems: items, rules: rules, preferences: preferences,
            nextReevaluationDate: nextReevaluation, timeZone: zone, now: now, copy: copy
        ))
    }

    static func reminders(_ plan: LocalReminderPlan) -> [PlannedLocalReminder] {
        plan.reminders.filter { !$0.isRenewal }
    }

    @Test("an official time becomes individual reminders in the patient's zone; nothing is invented")
    func officialTimesOnly() {
        // 2026-09-28 is a Monday; 12:00Z = 09:00 in São Paulo (UTC-3).
        let result = Self.plan(items: [Self.item(schedules: [Self.schedule("10:00")])])
        let times = Self.reminders(result).map(\.fireDate)

        #expect(times.first == Self.instant("2026-09-28T13:00:00Z"))
        #expect(times.count == LocalReminderPlanner.windowDays)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 86_400 })
        #expect(Self.plan().reminders.isEmpty)
    }

    @Test("weekdays follow the contract: 0 is Sunday")
    func weekdays() {
        let result = Self.plan(items: [Self.item(schedules: [Self.schedule("10:00", weekdays: [0])])])
        let weekdays = Set(Self.reminders(result).map(\.fireDate).map { date -> Int in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Self.saoPaulo
            return calendar.component(.weekday, from: date)
        })
        #expect(weekdays == [1])
    }

    @Test("inactive, archived or reminder-disabled items and inactive rules schedule nothing")
    func filteredItems() {
        let schedules = [Self.schedule("10:00")]
        let result = Self.plan(
            items: [
                Self.item(remindersEnabled: false, schedules: schedules),
                Self.item(active: false, schedules: schedules),
                Self.item(archived: true, schedules: schedules),
            ],
            rules: [Self.rule(.meal, "12:00", active: false)]
        )
        #expect(result.reminders.isEmpty)
        #expect(result.coverageEnd == nil)
    }

    @Test("supplement and medication rules of /reminders are ignored; their items own the times")
    func routineRulesIgnored() {
        let result = Self.plan(rules: [Self.rule(.medication, "08:00"), Self.rule(.supplement, "09:00")])
        #expect(result.reminders.isEmpty)
    }

    @Test("a time missing in a daylight-saving gap is skipped and reported")
    func springForwardGap() {
        // New York jumps from 02:00 to 03:00 on 2026-03-08 (a Sunday).
        let result = Self.plan(
            items: [Self.item(schedules: [Self.schedule("02:30", weekdays: [0])])],
            zone: Self.newYork,
            now: Self.instant("2026-03-01T12:00:00Z")
        )
        #expect(result.skipped[.nonexistentLocalTime] == 1)
        #expect(!Self.reminders(result).map(\.fireDate).contains(Self.instant("2026-03-08T07:30:00Z")))
        #expect(Self.reminders(result).first?.fireDate == Self.instant("2026-03-15T06:30:00Z"))
    }

    @Test("a repeated local time resolves to the offset after the transition, as the server")
    func fallBackRepeat() {
        // 01:30 happens twice in New York on 2026-11-01; PostgreSQL takes EST.
        let result = Self.plan(
            items: [Self.item(schedules: [Self.schedule("01:30", weekdays: [0])])],
            zone: Self.newYork,
            now: Self.instant("2026-10-31T12:00:00Z")
        )
        #expect(Self.reminders(result).first?.fireDate == Self.instant("2026-11-01T06:30:00Z"))
    }

    @Test("quiet hours crossing midnight: start inclusive, end exclusive")
    func quietHours() {
        let result = Self.plan(
            items: [Self.item(schedules: [
                Self.schedule(id: "a", "22:00"), Self.schedule(id: "b", "06:59"), Self.schedule(id: "c", "07:00"),
            ])],
            preferences: Self.preferences(quiet: QuietHoursSnapshot(start: "22:00", end: "07:00")),
            // Local midnight, so every time of the first day is still ahead.
            now: Self.instant("2026-09-28T03:00:00Z")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.saoPaulo
        let hours = Set(Self.reminders(result).map { calendar.component(.hour, from: $0.fireDate) })
        #expect(hours == [7])
        // Reported for the covered period (up to the last 07:00): 06:59 of
        // all 30 days and 22:00 of the first 29.
        #expect(result.skipped[.quietHours] == 2 * LocalReminderPlanner.windowDays - 1)
    }

    @Test("the daily limit keeps the higher priority: medication before hydration")
    func dailyLimitPriority() {
        let result = Self.plan(
            items: [Self.item(schedules: [Self.schedule("18:00")])],
            rules: [Self.rule(.hydration, "10:00")],
            preferences: Self.preferences(limit: 1)
        )
        let categories = Set(Self.reminders(result).map { $0.identifier.split(separator: ".")[2] })
        #expect(categories == ["medication"])
        #expect(result.skipped[.dailyLimit] == LocalReminderPlanner.windowDays)
    }

    @Test("60 notifications at most, renewal included: it comes last, after the last reminder")
    func budgetAndRenewal() {
        let schedules = (0..<6).map { Self.schedule(id: "s\($0)", String(format: "%02d:15", 10 + $0)) }
        let result = Self.plan(items: [Self.item(schedules: schedules)])

        #expect(result.reminders.count == LocalReminderPlanner.budget)
        let renewal = result.reminders.last
        #expect(renewal?.isRenewal == true)
        #expect(result.reminders.dropLast().allSatisfy { !$0.isRenewal })
        #expect(result.coverageEnd == result.reminders.dropLast().last?.fireDate)
        #expect(renewal?.fireDate == result.coverageEnd?.addingTimeInterval(60))
        #expect(renewal?.destination == .today)
        #expect(result.skipped[.beyondBudget] == 6 * LocalReminderPlanner.windowDays - 59)
    }

    @Test("the renewal notice waits for the end of quiet hours")
    func renewalOutsideQuietHours() {
        let result = Self.plan(
            items: [Self.item(schedules: [Self.schedule("21:59")])],
            preferences: Self.preferences(quiet: QuietHoursSnapshot(start: "22:00", end: "07:00"))
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.saoPaulo
        let renewal = try? #require(result.reminders.last)
        #expect(renewal?.isRenewal == true)
        #expect(renewal.map { calendar.component(.hour, from: $0.fireDate) } == 7)
    }

    @Test("the server occurrence decides today: taken or skipped is not reminded, snoozed once at its end")
    func occurrenceStatuses() {
        let today = APITimestamp(value: Self.instant("2026-09-28T13:00:00Z"))
        func occurrence(_ status: String, until: String? = nil) -> RoutineOccurrenceSnapshot {
            RoutineOccurrenceSnapshot(
                scheduledFor: today, status: status, lastActionAt: nil,
                snoozedUntil: until.map { APITimestamp(value: Self.instant($0)) }
            )
        }
        for status in ["taken", "skipped"] {
            let result = Self.plan(items: [Self.item(schedules: [Self.schedule("10:00", occurrence: occurrence(status))])])
            #expect(Self.reminders(result).first?.fireDate == Self.instant("2026-09-29T13:00:00Z"))
        }
        let snoozed = Self.plan(items: [Self.item(schedules: [
            Self.schedule("10:00", occurrence: occurrence("snoozed", until: "2026-09-28T13:30:00Z")),
        ])])
        #expect(Array(Self.reminders(snoozed).map(\.fireDate).prefix(2)) == [
            Self.instant("2026-09-28T13:30:00Z"), Self.instant("2026-09-29T13:00:00Z"),
        ])
        let pending = Self.plan(items: [Self.item(schedules: [Self.schedule("10:00", occurrence: occurrence("pending"))])])
        #expect(Self.reminders(pending).first?.fireDate == Self.instant("2026-09-28T13:00:00Z"))
    }

    @Test("lock-screen content follows the patient's preview mode; rules never show names or numbers")
    func previewModes() {
        let items = [Self.item(schedules: [Self.schedule("10:00")])]
        let rules = [Self.rule(.meal, "12:00")]
        let privatePlan = Self.plan(items: items, rules: rules, preferences: Self.preferences(mode: .private))
        #expect(Self.reminders(privatePlan).allSatisfy {
            $0.title == Self.copy.genericTitle && $0.body == Self.copy.genericBody
        })
        let named = Self.reminders(Self.plan(items: items, preferences: Self.preferences(mode: .name)))
        #expect(named.first?.title == "Remédio sintético")
        #expect(named.first?.body == Self.copy.routineNameBody)
        let dosed = Self.reminders(Self.plan(items: items, preferences: Self.preferences(mode: .nameAndDose)))
        #expect(dosed.first?.body == "1 comprimido")
        let ruleNamed = Self.reminders(Self.plan(rules: rules, preferences: Self.preferences(mode: .nameAndDose)))
        #expect(ruleNamed.first?.title == "Lembrete de refeição")
        #expect(ruleNamed.first?.body == Self.copy.genericBody)
    }

    @Test("titles and bodies respect the push limits")
    func lengthLimits() {
        let long = String(repeating: "x", count: 300)
        let result = Self.plan(
            items: [Self.item(name: long, dose: long, schedules: [Self.schedule("10:00")])],
            preferences: Self.preferences(mode: .nameAndDose)
        )
        #expect(result.reminders.allSatisfy {
            $0.title.count <= LocalReminderCopy.titleLimit && $0.body.count <= LocalReminderCopy.bodyLimit
        })
    }

    @Test("identifiers carry the owner hash and server ids only; owners never collide")
    func identifiers() {
        let result = Self.plan(items: [Self.item(schedules: [Self.schedule("10:00")])])
        let prefix = LocalReminderPlanner.identifierPrefix(ownerKey: Self.owner)
        #expect(result.reminders.allSatisfy { $0.identifier.hasPrefix(prefix) })
        #expect(result.reminders.allSatisfy { !$0.identifier.contains("00000000-0000-4000-8000-00000000000a") })
        #expect(result.reminders.allSatisfy { !$0.identifier.contains("Remédio") })
        #expect(Set(result.reminders.map(\.identifier)).count == result.reminders.count)
        #expect(Self.owner.count == 8)
        #expect(LocalReminderPlanner.ownerKey(for: "00000000-0000-4000-8000-00000000000b") != Self.owner)
    }

    @Test("a reevaluation rule reminds on the next reevaluation date only; without a date it is reported")
    func reevaluation() {
        let rule = Self.rule(.reevaluation, "08:00", weekdays: [1])
        let dated = Self.reminders(Self.plan(rules: [rule], nextReevaluation: "2026-10-03"))
        #expect(dated.map(\.fireDate) == [Self.instant("2026-10-03T11:00:00Z")])
        let undated = Self.plan(rules: [rule])
        #expect(undated.reminders.isEmpty)
        #expect(undated.skipped[.noReevaluationDate] == 1)
        let impossible = Self.plan(rules: [rule], nextReevaluation: "2026-02-31")
        #expect(impossible.skipped[.noReevaluationDate] == 1)
        #expect(impossible.skipped[.nonexistentLocalTime] == nil)
    }

    @Test("a 30-minute daylight-saving shift (Lord Howe): the gap is skipped, the repeat takes the later offset")
    func lordHowe() {
        let zone = TimeZone(identifier: "Australia/Lord_Howe")!
        // 2026-04-05 02:00 LHDT (+11) goes back to 01:30 LHST (+10:30).
        let repeated = Self.plan(
            items: [Self.item(schedules: [Self.schedule("01:45", weekdays: [0])])],
            zone: zone, now: Self.instant("2026-04-01T00:00:00Z")
        )
        #expect(Self.reminders(repeated).first?.fireDate == Self.instant("2026-04-04T15:15:00Z"))
        // 2026-10-04 02:00 LHST jumps to 02:30 LHDT.
        let gap = Self.plan(
            items: [Self.item(schedules: [Self.schedule("02:15", weekdays: [0])])],
            zone: zone, now: Self.instant("2026-09-30T00:00:00Z")
        )
        #expect(gap.skipped[.nonexistentLocalTime] == 1)
        #expect(!Self.reminders(gap).contains { $0.fireDate < Self.instant("2026-10-05T00:00:00Z") })
    }

    @Test("a daylight-saving jump at midnight (Santiago): 00:30 that day does not exist")
    func midnightGap() {
        let zone = TimeZone(identifier: "America/Santiago")!
        let result = Self.plan(
            items: [Self.item(schedules: [
                Self.schedule(id: "night", "00:30", weekdays: [0]),
                Self.schedule(id: "morning", "08:00", weekdays: [0]),
            ])],
            zone: zone, now: Self.instant("2026-09-01T12:00:00Z")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let firstSunday = Self.reminders(result).filter {
            calendar.dateComponents([.year, .month, .day], from: $0.fireDate) == DateComponents(year: 2026, month: 9, day: 6)
        }
        #expect(result.skipped[.nonexistentLocalTime] == 1)
        #expect(firstSunday.map { calendar.component(.hour, from: $0.fireDate) } == [8])
    }

    @Test("the notification copy of both languages is present, within limits and free of unsafe words")
    func notificationCopy() {
        let unsafe = ["vergonha", "fracass", "preguiços", "preguicos", "culpa", "garantid", "sem desculpas",
                      "shame", "failed", "failure", "lazy", "guilt", "guaranteed", "no excuses"]
        for language in SupportedAppLanguage.allCases {
            let copy = LocalReminderCopy.make(language: language)
            let texts = [copy.genericTitle, copy.genericBody, copy.routineNameBody, copy.renewalTitle, copy.renewalBody]
                + copy.categoryTitles.values
            #expect(copy.categoryTitles.count == 6)
            for text in texts {
                #expect(!text.isEmpty && !text.hasPrefix("reminders."))
                #expect(!unsafe.contains { text.lowercased().contains($0) })
            }
            #expect([copy.genericTitle, copy.renewalTitle].allSatisfy { $0.count <= LocalReminderCopy.titleLimit })
            #expect([copy.genericBody, copy.routineNameBody, copy.renewalBody].allSatisfy { $0.count <= LocalReminderCopy.bodyLimit })
        }
    }
}
