import UIKit

enum FlowMealPushEnvironment: String, Codable, Sendable {
    case sandbox, production

    static let infoKey = "PERFORME_FLOW_PUSH_ENVIRONMENT"
}

/// Apple supplies a fresh token to the application delegate. Never log or
/// persist it, and never request one before permission and feature opt-in.
@MainActor
final class FlowMealPushRegistration {
    static let shared = FlowMealPushRegistration()

    private var request: (id: UUID, continuation: CheckedContinuation<Data, any Error>)?

    func token() async throws -> Data {
        guard request == nil else { throw BodyFlowCapabilityError.operationUnavailable }
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request = (id, continuation)
                UIApplication.shared.registerForRemoteNotifications()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    self?.fail(id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail(id) }
        }
    }

    func registered(_ token: Data) {
        guard (32...256).contains(token.count) else {
            failed()
            return
        }
        let continuation = request?.continuation
        request = nil
        continuation?.resume(returning: token)
    }

    func failed() {
        if let id = request?.id { fail(id) }
    }

    private func fail(_ id: UUID) {
        guard request?.id == id else { return }
        let continuation = request?.continuation
        request = nil
        continuation?.resume(throwing: BodyFlowCapabilityError.serviceUnavailable)
    }
}

@MainActor
final class FlowMealPushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FlowMealPushRegistration.shared.registered(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        FlowMealPushRegistration.shared.failed()
    }
}
