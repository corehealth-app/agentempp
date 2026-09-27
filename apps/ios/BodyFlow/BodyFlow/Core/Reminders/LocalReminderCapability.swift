import Foundation

/// Where local reminders read their times from: the routine items, the
/// patient's own rules and preferences, and the next reevaluation date.
struct LocalReminderSources: Sendable {
    let reminders: any ReminderProviding
    let routine: any RoutineProviding
    let progress: any ProgressProviding
}

/// Present only where reminder sources exist (a real account, or a UI-test
/// scenario); a plain demonstration has none and shows no reminders entry.
struct LocalReminderCapability: Sendable {
    let sources: LocalReminderSources
    let scheduler: LocalReminderScheduler
    let optIn: any LocalReminderOptInStoring
}

extension LocalReminderScheduler {
    /// The one scheduler of the real notification center for the process;
    /// the session lifecycle clears through this same instance.
    static let system = LocalReminderScheduler(
        center: SystemLocalNotificationCenter(),
        cleanupMarker: UserDefaultsLocalReminderCleanupMarker()
    )
}
