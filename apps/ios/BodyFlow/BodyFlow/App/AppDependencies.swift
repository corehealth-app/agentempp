import SwiftUI

struct AppDependencies: Sendable {
    let apiClient: any APIClient
    let authentication: any AuthenticationService
    let onboarding: any OnboardingRepository
    let coachPersona: any CoachPersonaRepository
    let secureStore: any SecureStoring
    let telemetry: any TelemetryClient

    static func scaffold() -> AppDependencies {
        demo(configuration: AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: true,
            startsWithCompletedFixture: true,
            preloadsSyntheticOnboardingValues: true,
            authBehavior: .succeed(after: nil)
        ))
    }

    static func demo(configuration: AppLaunchConfiguration) -> AppDependencies {
        let todayRequest = APIRequest<TodaySummary>(method: .get, path: "/today")
        let secureStore: any SecureStoring = switch configuration.demoStorageBoundary {
        case .memory:
            InMemorySecureStore()
        case .keychain:
            KeychainSecureStore(
                service: "com.bodyflow.app.ui-testing.demo-state.v1"
            )
        }
        let stateStore = DemoStateStore(secureStore: secureStore)
        let buildFlavor: AppBuildFlavor = configuration.mode == .demo ? .debug : .release

        return AppDependencies(
            apiClient: MockAPIClient(
                payloads: [todayRequest.key: AppFixtures.todayPayload]
            ),
            authentication: DemoAuthenticationService(
                stateStore: stateStore,
                configuration: configuration
            ),
            onboarding: DemoOnboardingRepository(
                stateStore: stateStore,
                buildFlavor: buildFlavor,
                preloadsSyntheticOnboardingValues: configuration.preloadsSyntheticOnboardingValues
            ),
            coachPersona: DemoCoachPersonaRepository(stateStore: stateStore),
            secureStore: secureStore,
            telemetry: InMemoryTelemetryClient()
        )
    }
}

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue: AppDependencies? = nil
}

private extension EnvironmentValues {
    var installedAppDependencies: AppDependencies? {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
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

extension View {
    func installAppDependencies(_ dependencies: AppDependencies) -> some View {
        environment(\.installedAppDependencies, dependencies)
    }
}
