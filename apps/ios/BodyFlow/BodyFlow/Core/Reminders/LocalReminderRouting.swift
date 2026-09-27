import Foundation
import Observation
import UserNotifications

/// A tapped reminder: which session owns it and where it points. Built from
/// identifiers only; nothing here performs an action or a mutation.
struct LocalReminderTap: Equatable, Sendable {
    let ownerKey: String
    let destination: LocalReminderDestination

    init(ownerKey: String, destination: LocalReminderDestination) {
        self.ownerKey = ownerKey
        self.destination = destination
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let owner = userInfo[LocalReminderUserInfo.owner] as? String,
              Self.isIdentifier(owner) else { return nil }
        ownerKey = owner
        if let rawKind = userInfo[LocalReminderUserInfo.kind] as? String,
           let kind = RoutineItemKind(rawValue: rawKind),
           let item = userInfo[LocalReminderUserInfo.item] as? String,
           Self.isIdentifier(item) {
            destination = .routineItem(kind: kind, itemID: item)
        } else {
            destination = .today
        }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        (1...128).contains(value.count)
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
    }
}

/// Holds the latest tap until the shell of the owning session takes it.
@MainActor
@Observable
final class LocalReminderRouteInbox {
    static let shared = LocalReminderRouteInbox()
    /// A tap older than this is not opened later (e.g. after a new sign-in).
    static let validity: TimeInterval = 10 * 60

    private(set) var pending: LocalReminderTap?
    @ObservationIgnored private var receivedAt: Date?

    func receive(_ tap: LocalReminderTap, at date: Date = Date()) {
        pending = tap
        receivedAt = date
    }

    /// The pending tap, only for the session that owns it and only while it
    /// is recent. A tap of another session (a previous account on this
    /// iPhone) or an old one is discarded unopened.
    func take(ownerKey: String, now: Date = Date()) -> LocalReminderTap? {
        guard let tap = pending else { return nil }
        let received = receivedAt ?? now
        pending = nil
        receivedAt = nil
        guard now.timeIntervalSince(received) <= Self.validity else { return nil }
        return tap.ownerKey == ownerKey ? tap : nil
    }
}

/// Installed at launch so a tap on a reminder reaches the app.
final class LocalReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = LocalReminderNotificationDelegate()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let tap = LocalReminderTap(userInfo: response.notification.request.content.userInfo) else {
            return
        }
        await MainActor.run {
            LocalReminderRouteInbox.shared.receive(tap)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// Whether this account turned reminders on for this iPhone. Keyed by the
/// owner hash, never by the account id.
protocol LocalReminderOptInStoring: Sendable {
    func isEnabled(ownerKey: String) -> Bool
    func setEnabled(_ enabled: Bool, ownerKey: String)
}

struct UserDefaultsLocalReminderOptInStore: LocalReminderOptInStoring {
    func isEnabled(ownerKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.key(ownerKey))
    }

    func setEnabled(_ enabled: Bool, ownerKey: String) {
        UserDefaults.standard.set(enabled, forKey: Self.key(ownerKey))
    }

    private static func key(_ ownerKey: String) -> String {
        "\(LocalReminderPlanner.identifierPrefix)reminders-enabled.\(ownerKey)"
    }
}

final class InMemoryLocalReminderOptInStore: LocalReminderOptInStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Set<String>

    init(enabled: Set<String> = []) {
        self.enabled = enabled
    }

    func isEnabled(ownerKey: String) -> Bool {
        lock.withLock { enabled.contains(ownerKey) }
    }

    func setEnabled(_ value: Bool, ownerKey: String) {
        lock.withLock {
            if value { enabled.insert(ownerKey) } else { enabled.remove(ownerKey) }
        }
    }
}
