import Foundation

#if DEBUG
/// UI-test scenario arguments for local reminders (Debug builds only).
enum DemoLocalReminderScenario {
    /// Demo routine + synthetic rules, scheduled in the real notification center.
    static let enabledArgument = "--ui-testing-local-reminders"
    /// The same data, with a notification center that denies permission.
    static let deniedArgument = "--ui-testing-local-reminders-denied"

    static func resolve(arguments: [String]) -> Bool? {
        if arguments.contains(deniedArgument) { return false }
        if arguments.contains(enabledArgument) { return true }
        return nil
    }
}

/// Synthetic rules and preferences; no real account data.
struct DemoReminderProvider: ReminderProviding {
    private static let meta = MobileResponseMetadata(
        apiVersion: "v1",
        requestID: "demo-local-reminders"
    )

    func reminderRules() async throws -> ReminderRulesResponse {
        MobileResponse(
            data: [
                ReminderRuleSnapshot(
                    id: "demo-rule-lunch",
                    category: ReminderRuleCategory.meal.rawValue,
                    mealType: "almoco",
                    localTime: "12:30",
                    weekdays: [0, 1, 2, 3, 4, 5, 6],
                    active: true
                ),
                ReminderRuleSnapshot(
                    id: "demo-rule-water",
                    category: ReminderRuleCategory.hydration.rawValue,
                    mealType: nil,
                    localTime: "15:00",
                    weekdays: [1, 2, 3, 4, 5],
                    active: true
                ),
            ],
            meta: Self.meta
        )
    }

    func notificationPreferences() async throws -> NotificationPreferencesResponse {
        MobileResponse(
            data: NotificationPreferencesSnapshot(
                pushEnabled: true,
                quietHours: QuietHoursSnapshot(start: "22:00", end: "07:00"),
                dailyPushLimit: 8,
                routinePreviewMode: RoutinePreviewMode.private.rawValue
            ),
            meta: Self.meta
        )
    }
}

/// A notification center whose permission is denied (the real center cannot
/// be put in that state from a UI test). Holds nothing.
struct DeniedLocalNotificationCenter: LocalNotificationCentering {
    func authorization() async -> LocalNotificationAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pendingIdentifiers() async -> [String] { [] }
    func deliveredIdentifiers() async -> [String] { [] }
    func add(_ reminder: PlannedLocalReminder, ownerKey: String) async throws {
        throw BodyFlowCapabilityError.operationUnavailable
    }
    func removePending(_ identifiers: [String]) async {}
    func removeDelivered(_ identifiers: [String]) async {}
}
#endif
