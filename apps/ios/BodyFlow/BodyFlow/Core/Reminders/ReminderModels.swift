import Foundation

typealias ReminderRulesResponse = MobileResponse<[ReminderRuleSnapshot]>
typealias NotificationPreferencesResponse = MobileResponse<NotificationPreferencesSnapshot>

/// Categories of `GET /reminders`. Supplement and medication rules may still
/// be listed there, but their schedules are owned by the routine items.
enum ReminderRuleCategory: String, Sendable, CaseIterable {
    case meal
    case hydration
    case workout
    case reevaluation
    case content
    case reengagement
    case supplement
    case medication
}

/// One patient-created rule: a local time and weekdays in the patient's
/// documented time zone. The server never derives these from the profile.
struct ReminderRuleSnapshot: Codable, Equatable, Sendable {
    let id: String
    let category: String
    let mealType: String?
    let localTime: String
    let weekdays: [Int]
    let active: Bool

    var knownCategory: ReminderRuleCategory? {
        ReminderRuleCategory(rawValue: category)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case mealType = "meal_type"
        case localTime = "local_time"
        case weekdays
        case active
    }
}

struct QuietHoursSnapshot: Codable, Equatable, Sendable {
    /// "HH:MM", inclusive.
    let start: String
    /// "HH:MM", exclusive; may be earlier than `start` (crosses midnight).
    let end: String
}

/// What a reminder may show on the lock screen, chosen by the patient.
enum RoutinePreviewMode: String, Sendable {
    case `private`
    case name
    case nameAndDose = "name_and_dose"
}

struct NotificationPreferencesSnapshot: Codable, Equatable, Sendable {
    let pushEnabled: Bool
    let quietHours: QuietHoursSnapshot?
    let dailyPushLimit: Int
    let routinePreviewMode: String

    /// An unknown mode is shown as the most private one.
    var previewMode: RoutinePreviewMode {
        RoutinePreviewMode(rawValue: routinePreviewMode) ?? .private
    }

    private enum CodingKeys: String, CodingKey {
        case pushEnabled = "push_enabled"
        case quietHours = "quiet_hours"
        case dailyPushLimit = "daily_push_limit"
        case routinePreviewMode = "routine_preview_mode"
    }
}
