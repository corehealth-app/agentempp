import Foundation

/// Read-only access to the patient's reminder rules and notification
/// preferences (existing contracts; nothing is created or changed here).
protocol ReminderProviding: Sendable {
    func reminderRules() async throws -> ReminderRulesResponse
    func notificationPreferences() async throws -> NotificationPreferencesResponse
}

extension UnavailableBodyFlowCapabilities: ReminderProviding {
    func reminderRules() async throws -> ReminderRulesResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func notificationPreferences() async throws -> NotificationPreferencesResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}
