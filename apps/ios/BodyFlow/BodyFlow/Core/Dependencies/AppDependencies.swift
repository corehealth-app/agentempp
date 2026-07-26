import SwiftUI

struct AppDependencies: Sendable {
    let apiClient: any APIClient
    let authSession: any AuthSessionProviding
    let secureStore: any SecureStoring
    let telemetry: any TelemetryClient

    static func scaffold() -> AppDependencies {
        let todayRequest = APIRequest<TodaySummary>(method: .get, path: "/today")

        return AppDependencies(
            apiClient: MockAPIClient(
                payloads: [todayRequest.key: AppFixtures.todayPayload]
            ),
            authSession: MockAuthSessionProvider(
                state: .authenticated(userID: "fixture-user")
            ),
            secureStore: InMemorySecureStore(),
            telemetry: InMemoryTelemetryClient()
        )
    }
}

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue: AppDependencies? = nil
}

extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get {
            guard let value = self[AppDependenciesKey.self] else {
                preconditionFailure(
                    "AppDependencies must be installed at the app root"
                )
            }
            return value
        }
        set {
            self[AppDependenciesKey.self] = newValue
        }
    }
}
