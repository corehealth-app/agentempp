import Foundation
import UserNotifications

enum LocalNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// The parts of `UNUserNotificationCenter` the reminders use. Production
/// always talks to the real center; the protocol exists for tests only.
protocol LocalNotificationCentering: Sendable {
    func authorization() async -> LocalNotificationAuthorization
    /// Asks the system once; returns whether alerts are now allowed.
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func add(_ reminder: PlannedLocalReminder, ownerKey: String) async throws
    func removePending(_ identifiers: [String]) async
    func removeDelivered(_ identifiers: [String]) async
}

/// Keys of a reminder's `userInfo`: routing identifiers only.
enum LocalReminderUserInfo {
    static let owner = "pai.owner"
    static let kind = "pai.kind"
    static let item = "pai.item"
}

struct SystemLocalNotificationCenter: LocalNotificationCentering {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> LocalNotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            // Allowed but shown nowhere (no alert, lock screen or Notification
            // Center) is reported as off, never as "scheduled".
            let visible = [settings.alertSetting, settings.lockScreenSetting, settings.notificationCenterSetting]
                .contains(.enabled)
            return visible ? .authorized : .denied
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        // No provisional, time-sensitive or critical alerts.
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    func add(_ reminder: PlannedLocalReminder, ownerKey: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = Self.userInfo(for: reminder, ownerKey: ownerKey)
        try await center.add(UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: Self.triggerComponents(for: reminder.fireDate),
                repeats: false
            )
        ))
    }

    func removePending(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// The absolute instant as full UTC components: unaffected by a change of
    /// the device time zone and unambiguous when a local time repeats.
    static func triggerComponents(for date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        calendar.timeZone = utc
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = calendar
        components.timeZone = utc
        return components
    }

    static func userInfo(for reminder: PlannedLocalReminder, ownerKey: String) -> [String: String] {
        switch reminder.destination {
        case let .routineItem(kind, itemID):
            [
                LocalReminderUserInfo.owner: ownerKey,
                LocalReminderUserInfo.kind: kind.rawValue,
                LocalReminderUserInfo.item: itemID,
            ]
        case .today:
            [LocalReminderUserInfo.owner: ownerKey]
        }
    }
}
