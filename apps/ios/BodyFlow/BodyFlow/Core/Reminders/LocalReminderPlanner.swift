import CryptoKit
import Foundation

/// Where a reminder leads when tapped. Identifiers only — never a name, dose
/// or health value — and it is opened only for the session that owns it.
enum LocalReminderDestination: Equatable, Sendable {
    case routineItem(kind: RoutineItemKind, itemID: String)
    case today
}

/// Why an occurrence with an official or patient time is not scheduled.
enum LocalReminderSkipReason: String, CaseIterable, Sendable {
    /// Past the device budget: it is scheduled after the next sync.
    case beyondBudget = "beyond_budget"
    case quietHours = "quiet_hours"
    case dailyLimit = "daily_limit"
    /// The local time does not exist that day (daylight-saving gap).
    case nonexistentLocalTime = "nonexistent_local_time"
    /// A reevaluation rule without a next reevaluation date.
    case noReevaluationDate = "no_reevaluation_date"
}

struct PlannedLocalReminder: Equatable, Sendable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
    let destination: LocalReminderDestination
    let isRenewal: Bool
}

struct LocalReminderPlan: Equatable, Sendable {
    /// Individual, non-repeating notifications in time order; the renewal
    /// notice, when present, is last and inside the same budget.
    let reminders: [PlannedLocalReminder]
    /// The last reminder that fits the budget; nil when nothing is scheduled.
    let coverageEnd: Date?
    let skipped: [LocalReminderSkipReason: Int]

    static let empty = LocalReminderPlan(reminders: [], coverageEnd: nil, skipped: [:])
}

/// Localized copy resolved by the caller, so the planner stays pure.
struct LocalReminderCopy: Equatable, Sendable {
    let genericTitle: String
    let genericBody: String
    /// Body under a patient-typed name ("name" mode, or a missing dose).
    let routineNameBody: String
    let categoryTitles: [String: String]
    let renewalTitle: String
    let renewalBody: String

    static let titleLimit = 60
    static let bodyLimit = 180
}

struct LocalReminderPlannerInput: Sendable {
    /// Hash of the session's user id; never the id itself.
    let ownerKey: String
    let routineItems: [RoutineItemSnapshot]
    let rules: [ReminderRuleSnapshot]
    let preferences: NotificationPreferencesSnapshot
    /// `user_progress.next_reevaluation` ("yyyy-MM-dd"), if known.
    let nextReevaluationDate: String?
    /// The patient's documented time zone (never the device's).
    let timeZone: TimeZone
    let now: Date
    let copy: LocalReminderCopy
}

/// Turns official routine times and the patient's own rules into individual
/// local notifications. It invents no time, frequency, item or dose: every
/// instant comes from a server schedule or rule, derived in the patient's
/// documented time zone exactly as the server derives occurrences.
enum LocalReminderPlanner {
    /// App policy: 60 pending notifications (the system keeps 64), renewal included.
    static let budget = 60
    static let windowDays = 30
    static let identifierPrefix = "pai."

    static func ownerKey(for userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func identifierPrefix(ownerKey: String) -> String {
        "\(identifierPrefix)\(ownerKey)."
    }

    static func plan(_ input: LocalReminderPlannerInput) -> LocalReminderPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.timeZone
        // Each skip keeps its instant (a gap uses its local day), so the report
        // covers the same period as the schedule; nil = no date at all.
        var skips: [SkipEntry] = []
        var candidates: [Candidate] = []
        let days = localDays(from: input.now, calendar: calendar)
        let quiet = input.preferences.quietHours.flatMap(QuietWindow.init)

        func add(
            _ instant: Date,
            priority: Int,
            category: String,
            sourceID: String,
            title: String,
            body: String,
            destination: LocalReminderDestination
        ) {
            candidates.append(Candidate(
                fireDate: instant,
                localDay: localDayKey(instant, calendar: calendar),
                minuteOfDay: minuteOfDay(instant, calendar: calendar),
                priority: priority,
                identifier: identifier(
                    owner: input.ownerKey,
                    category: category,
                    sourceID: sourceID,
                    instant: instant
                ),
                title: title,
                body: body,
                destination: destination
            ))
        }

        for item in input.routineItems
        where item.active && item.archivedAt == nil && item.remindersEnabled {
            let priority = item.kind == .medication ? 0 : 1
            let content = routineContent(item, mode: input.preferences.previewMode, copy: input.copy)
            let destination = LocalReminderDestination.routineItem(kind: item.kind, itemID: item.id)
            for schedule in item.schedules {
                guard let time = ReminderLocalTime(schedule.localTime) else { continue }
                let occurrence = schedule.occurrence
                // A snoozed occurrence is reminded once, when the snooze ends.
                if let occurrence, occurrence.status == "snoozed",
                   let until = occurrence.snoozedUntil?.value, until > input.now {
                    add(until, priority: priority, category: item.kind.rawValue,
                        sourceID: schedule.id, title: content.title, body: content.body,
                        destination: destination)
                }
                for day in days where schedule.weekdays.contains(day.weekday) {
                    guard let instant = resolve(day: day, time: time, calendar: calendar) else {
                        skips.append(SkipEntry(reason: .nonexistentLocalTime, at: dayStart(day, calendar: calendar)))
                        continue
                    }
                    guard instant > input.now else { continue }
                    // The server's occurrence for this instant decides: only
                    // a pending one is reminded at its scheduled time.
                    if let occurrence,
                       abs(occurrence.scheduledFor.value.timeIntervalSince(instant)) < 60,
                       occurrence.status != "pending" {
                        continue
                    }
                    add(instant, priority: priority, category: item.kind.rawValue,
                        sourceID: schedule.id, title: content.title, body: content.body,
                        destination: destination)
                }
            }
        }

        for rule in input.rules where rule.active {
            // Supplement and medication times come from their items only.
            guard let category = rule.knownCategory,
                  category != .supplement, category != .medication,
                  let time = ReminderLocalTime(rule.localTime) else { continue }
            let content = ruleContent(category, mode: input.preferences.previewMode, copy: input.copy)
            let priority = rulePriority(category)
            if category == .reevaluation {
                guard let dateText = input.nextReevaluationDate,
                      let day = ReminderLocalDay(dateText),
                      let start = dayStart(day, calendar: calendar) else {
                    skips.append(SkipEntry(reason: .noReevaluationDate, at: nil))
                    continue
                }
                guard let instant = resolve(day: day, time: time, calendar: calendar) else {
                    skips.append(SkipEntry(reason: .nonexistentLocalTime, at: start))
                    continue
                }
                if instant > input.now, days.contains(where: { $0.key == day.key }) {
                    add(instant, priority: priority, category: category.rawValue,
                        sourceID: rule.id, title: content.title, body: content.body,
                        destination: .today)
                }
                continue
            }
            for day in days where rule.weekdays.contains(day.weekday) {
                guard let instant = resolve(day: day, time: time, calendar: calendar) else {
                    skips.append(SkipEntry(reason: .nonexistentLocalTime, at: dayStart(day, calendar: calendar)))
                    continue
                }
                guard instant > input.now else { continue }
                add(instant, priority: priority, category: category.rawValue,
                    sourceID: rule.id, title: content.title, body: content.body,
                    destination: .today)
            }
        }

        // One notification per identifier.
        var seen = Set<String>()
        candidates = candidates
            .sorted(by: Candidate.timeOrder)
            .filter { seen.insert($0.identifier).inserted }

        // Quiet hours of the patient's preferences.
        if let quiet {
            skips += candidates.filter { quiet.contains($0.minuteOfDay) }
                .map { SkipEntry(reason: .quietHours, at: $0.fireDate) }
            candidates.removeAll { quiet.contains($0.minuteOfDay) }
        }

        // Daily limit per local day, by priority then time.
        let limit = max(0, input.preferences.dailyPushLimit)
        var kept: [Candidate] = []
        for (_, dayCandidates) in Dictionary(grouping: candidates, by: \.localDay) {
            let ordered = dayCandidates.sorted(by: Candidate.priorityOrder)
            kept.append(contentsOf: ordered.prefix(limit))
            skips += ordered.dropFirst(limit).map { SkipEntry(reason: .dailyLimit, at: $0.fireDate) }
        }
        kept.sort(by: Candidate.timeOrder)

        // The device budget, renewal notice included.
        let fitting = Array(kept.prefix(budget - 1))
        // Reported for the covered period only (the whole window when nothing
        // is covered); what lies past the budget is its own reason.
        var skipped: [LocalReminderSkipReason: Int] = [:]
        let covered = fitting.last?.fireDate
        for skip in skips {
            if let at = skip.at, let covered, at > covered { continue }
            skipped[skip.reason, default: 0] += 1
        }
        if kept.count > fitting.count {
            skipped[.beyondBudget, default: 0] += kept.count - fitting.count
        }
        guard let last = fitting.last else {
            return LocalReminderPlan(reminders: [], coverageEnd: nil, skipped: skipped)
        }

        var reminders = fitting.map {
            PlannedLocalReminder(
                identifier: $0.identifier,
                fireDate: $0.fireDate,
                title: $0.title,
                body: $0.body,
                destination: $0.destination,
                isRenewal: false
            )
        }
        var renewalAt = last.fireDate.addingTimeInterval(60)
        if let quiet {
            var steps = 0
            while quiet.contains(minuteOfDay(renewalAt, calendar: calendar)), steps < 1_440 {
                renewalAt = renewalAt.addingTimeInterval(60)
                steps += 1
            }
        }
        reminders.append(PlannedLocalReminder(
            identifier: "\(identifierPrefix(ownerKey: input.ownerKey))renewal.\(epochMinute(renewalAt))",
            fireDate: renewalAt,
            title: truncated(input.copy.renewalTitle, LocalReminderCopy.titleLimit),
            body: truncated(input.copy.renewalBody, LocalReminderCopy.bodyLimit),
            destination: .today,
            isRenewal: true
        ))
        return LocalReminderPlan(reminders: reminders, coverageEnd: last.fireDate, skipped: skipped)
    }

    // MARK: - Local time, as the server derives it

    /// `(local date + local time) AT TIME ZONE tz`: a time missing in a
    /// daylight-saving gap does not exist (nil); a repeated time resolves to
    /// the offset in force after the transition, as PostgreSQL does.
    static func resolve(day: ReminderLocalDay, time: ReminderLocalTime, calendar: Calendar) -> Date? {
        let wanted = DateComponents(
            year: day.year, month: day.month, day: day.day,
            hour: time.hour, minute: time.minute
        )
        guard let first = calendar.date(from: wanted),
              matches(first, wanted, calendar) else { return nil }
        for shift in [7_200.0, 3_600.0, 1_800.0] {
            let later = first.addingTimeInterval(shift)
            if matches(later, wanted, calendar) { return later }
        }
        return first
    }

    private static func matches(_ date: Date, _ wanted: DateComponents, _ calendar: Calendar) -> Bool {
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return actual.year == wanted.year && actual.month == wanted.month
            && actual.day == wanted.day && actual.hour == wanted.hour
            && actual.minute == wanted.minute
    }

    /// Local midnight of a valid date; nil for an impossible one (2026-02-31).
    private static func dayStart(_ day: ReminderLocalDay, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard parts.year == day.year, parts.month == day.month, parts.day == day.day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func localDays(from now: Date, calendar: Calendar) -> [ReminderLocalDay] {
        let start = calendar.startOfDay(for: now)
        return (0..<windowDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            guard let year = parts.year, let month = parts.month,
                  let day = parts.day, let weekday = parts.weekday else { return nil }
            return ReminderLocalDay(year: year, month: month, day: day, weekday: weekday - 1)
        }
    }

    private static func localDayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func epochMinute(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }

    private static func identifier(owner: String, category: String, sourceID: String, instant: Date) -> String {
        let safeSource = String(sourceID.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" ? Character(scalar) : "_"
        }.prefix(64))
        return "\(identifierPrefix(ownerKey: owner))\(category).\(safeSource).\(epochMinute(instant))"
    }

    // MARK: - Content by the patient's preview mode

    private static func routineContent(
        _ item: RoutineItemSnapshot,
        mode: RoutinePreviewMode,
        copy: LocalReminderCopy
    ) -> (title: String, body: String) {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let dose = item.doseText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .private:
            return generic(copy)
        case .name:
            guard !name.isEmpty else { return generic(copy) }
            return (truncated(name, LocalReminderCopy.titleLimit),
                    truncated(copy.routineNameBody, LocalReminderCopy.bodyLimit))
        case .nameAndDose:
            guard !name.isEmpty else { return generic(copy) }
            return (truncated(name, LocalReminderCopy.titleLimit),
                    truncated(dose.isEmpty ? copy.routineNameBody : dose, LocalReminderCopy.bodyLimit))
        }
    }

    /// Rules carry no patient-typed text: named modes show the category only.
    private static func ruleContent(
        _ category: ReminderRuleCategory,
        mode: RoutinePreviewMode,
        copy: LocalReminderCopy
    ) -> (title: String, body: String) {
        guard mode != .private, let title = copy.categoryTitles[category.rawValue] else {
            return generic(copy)
        }
        return (truncated(title, LocalReminderCopy.titleLimit),
                truncated(copy.genericBody, LocalReminderCopy.bodyLimit))
    }

    private static func generic(_ copy: LocalReminderCopy) -> (title: String, body: String) {
        (truncated(copy.genericTitle, LocalReminderCopy.titleLimit),
         truncated(copy.genericBody, LocalReminderCopy.bodyLimit))
    }

    static func truncated(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }

    /// Medication > supplement > meal > hydration > workout > reevaluation.
    private static func rulePriority(_ category: ReminderRuleCategory) -> Int {
        switch category {
        case .medication: 0
        case .supplement: 1
        case .meal: 2
        case .hydration: 3
        case .workout: 4
        case .reevaluation: 5
        case .content: 6
        case .reengagement: 7
        }
    }
}

struct ReminderLocalTime: Equatable, Sendable {
    let hour: Int
    let minute: Int

    init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    var minuteOfDay: Int { hour * 60 + minute }
}

struct ReminderLocalDay: Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    /// 0 = Sunday … 6 = Saturday, as the contract.
    let weekday: Int

    init(year: Int, month: Int, day: Int, weekday: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.weekday = weekday
    }

    /// "yyyy-MM-dd"; the weekday is not needed to resolve a single date.
    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
              let day = Int(parts[2]), (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day, weekday: -1)
    }

    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

private struct QuietWindow {
    let start: Int
    let end: Int

    init?(_ snapshot: QuietHoursSnapshot) {
        guard let start = ReminderLocalTime(snapshot.start), let end = ReminderLocalTime(snapshot.end),
              start != end else { return nil }
        self.start = start.minuteOfDay
        self.end = end.minuteOfDay
    }

    /// Start inclusive, end exclusive; may cross midnight.
    func contains(_ minute: Int) -> Bool {
        start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }
}

private struct SkipEntry {
    let reason: LocalReminderSkipReason
    let at: Date?
}

private struct Candidate {
    let fireDate: Date
    let localDay: String
    let minuteOfDay: Int
    let priority: Int
    let identifier: String
    let title: String
    let body: String
    let destination: LocalReminderDestination

    static func timeOrder(_ left: Candidate, _ right: Candidate) -> Bool {
        if left.fireDate != right.fireDate { return left.fireDate < right.fireDate }
        if left.priority != right.priority { return left.priority < right.priority }
        return left.identifier < right.identifier
    }

    static func priorityOrder(_ left: Candidate, _ right: Candidate) -> Bool {
        if left.priority != right.priority { return left.priority < right.priority }
        return timeOrder(left, right)
    }
}
