import Foundation

typealias RoutineListResponse = MobileResponse<RoutineListSnapshot>
typealias RoutineActionResponse = MobileResponse<RoutineActionReceipt>
typealias RoutineHistoryPage = MobileResponse<RoutineHistorySnapshot>

enum RoutineItemKind: String, Codable, Hashable, Sendable {
    case supplement
    case medication
}

struct RoutineListSnapshot: Codable, Equatable, Sendable {
    let localDate: String
    let items: [RoutineItemSnapshot]

    private enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case items
    }
}

struct RoutineItemSnapshot: Codable, Equatable, Sendable {
    let id: String
    let kind: RoutineItemKind
    let name: String
    let doseText: String
    let origin: String
    let remindersEnabled: Bool
    let active: Bool
    let archivedAt: APITimestamp?
    let version: Int
    let createdAt: APITimestamp
    let updatedAt: APITimestamp
    let frequencySummary: RoutineFrequencySummary
    let schedules: [RoutineScheduleSnapshot]

    private enum CodingKeys: String, CodingKey {
        case id
        case kind = "item_type"
        case name
        case doseText = "dose_text"
        case origin
        case remindersEnabled = "reminders_enabled"
        case active
        case archivedAt = "archived_at"
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case frequencySummary = "frequency_summary"
        case schedules
    }
}

struct RoutineFrequencySummary: Codable, Equatable, Sendable {
    let timesPerWeek: Int

    private enum CodingKeys: String, CodingKey {
        case timesPerWeek = "times_per_week"
    }
}

struct RoutineScheduleSnapshot: Codable, Equatable, Sendable {
    let id: String
    let localTime: String
    let weekdays: [Int]
    let occurrence: RoutineOccurrenceSnapshot?

    private enum CodingKeys: String, CodingKey {
        case id
        case localTime = "local_time"
        case weekdays
        case occurrence
    }
}

struct RoutineOccurrenceSnapshot: Codable, Equatable, Sendable {
    let scheduledFor: APITimestamp
    let status: String
    let lastActionAt: APITimestamp?
    let snoozedUntil: APITimestamp?

    private enum CodingKeys: String, CodingKey {
        case scheduledFor = "scheduled_for"
        case status
        case lastActionAt = "last_action_at"
        case snoozedUntil = "snoozed_until"
    }
}

struct RoutineHistorySnapshot: Codable, Equatable, Sendable {
    let items: [RoutineHistoryItem]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

extension MobileResponse where Payload == RoutineHistorySnapshot {
    var items: [RoutineHistoryItem] {
        data.items
    }

    var nextCursor: String? {
        data.nextCursor
    }
}

struct RoutineHistoryItem: Codable, Equatable, Sendable {
    let id: String
    let routineItemID: String
    let kind: RoutineItemKind
    let status: String
    let reminderRuleID: String
    let scheduledFor: APITimestamp
    let occurredAt: APITimestamp
    let snoozedUntil: APITimestamp?
    let source: String
    let supersedesLogID: String?
    let createdAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case id
        case routineItemID = "routine_item_id"
        case kind = "item_type"
        case status
        case reminderRuleID = "reminder_rule_id"
        case scheduledFor = "scheduled_for"
        case occurredAt = "occurred_at"
        case snoozedUntil = "snoozed_until"
        case source
        case supersedesLogID = "supersedes_log_id"
        case createdAt = "created_at"
    }
}

enum RoutineActionStatus: String, Codable, Hashable, Sendable {
    case taken
    case snoozed
    case skipped
}

enum RoutineCommandValidationError: Error, Equatable, Sendable {
    case invalidSnoozeStructure
    case invalidHydrationAmount
    case invalidWeight
}

struct RoutineActionCommand: Encodable, Hashable, Sendable {
    let kind: RoutineItemKind
    let itemID: String
    let status: RoutineActionStatus
    let reminderRuleID: String
    let scheduledFor: APITimestamp
    let occurredAt: APITimestamp
    let snoozedUntil: APITimestamp?

    init(
        kind: RoutineItemKind,
        itemID: String,
        status: RoutineActionStatus,
        reminderRuleID: String,
        scheduledFor: APITimestamp,
        occurredAt: APITimestamp,
        snoozedUntil: APITimestamp?
    ) throws {
        try Self.validate(status: status, snoozedUntil: snoozedUntil)
        self.kind = kind
        self.itemID = itemID
        self.status = status
        self.reminderRuleID = reminderRuleID
        self.scheduledFor = scheduledFor
        self.occurredAt = occurredAt
        self.snoozedUntil = snoozedUntil
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case reminderRuleID = "reminder_rule_id"
        case scheduledFor = "scheduled_for"
        case occurredAt = "occurred_at"
        case snoozedUntil = "snoozed_until"
    }

    private static func validate(
        status: RoutineActionStatus,
        snoozedUntil: APITimestamp?
    ) throws {
        let hasValidStructure = switch status {
        case .snoozed:
            snoozedUntil != nil
        case .taken, .skipped:
            snoozedUntil == nil
        }

        guard hasValidStructure else {
            throw RoutineCommandValidationError.invalidSnoozeStructure
        }
    }
}

struct RoutineActionReceipt: Codable, Equatable, Sendable {
    let adherenceLogID: String
    let occurrenceKey: String
    let kind: RoutineItemKind
    let status: String

    private enum CodingKeys: String, CodingKey {
        case adherenceLogID = "adherence_log_id"
        case occurrenceKey = "occurrence_key"
        case kind = "item_type"
        case status
    }
}
