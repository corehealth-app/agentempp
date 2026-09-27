import Foundation

/// `GET /reminders` and `GET /notification-preferences` over the mobile BFF.
/// Both are read-only here: local reminders only follow what the server holds.
struct MobileReminderRepository: ReminderProviding {
    let transport: any MobileAPIEnvelopeExecuting

    static let rulesPath = "/api/mobile/v1/reminders"
    static let preferencesPath = "/api/mobile/v1/notification-preferences"

    func reminderRules() async throws -> ReminderRulesResponse {
        try await transport.executeCapability {
            try MobileAPIRequest(method: .get, path: Self.rulesPath)
        }
    }

    func notificationPreferences() async throws -> NotificationPreferencesResponse {
        try await transport.executeCapability {
            try MobileAPIRequest(method: .get, path: Self.preferencesPath)
        }
    }
}
