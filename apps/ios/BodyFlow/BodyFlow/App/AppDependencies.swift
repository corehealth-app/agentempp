import SwiftUI

struct AppDependencies: Sendable {
    let apiClient: any APIClient
    let authentication: any AuthenticationService
    let onboarding: any OnboardingRepository
    let coachPersona: any CoachPersonaRepository
    let secureStore: any SecureStoring
    let telemetry: any TelemetryClient
    let today: any TodayProviding
    let history: any HistoryProviding
    let plan: any PlanProviding
    let progress: any ProgressProviding
    let mealDetection: any MealDetectionProviding
    let registration: any RegistrationProviding
    let hydration: any HydrationRecording
    let weight: any WeightRecording
    let routine: any RoutineProviding
    let timeProvider: any TimeProviding
    let idempotencyKeyProvider: any IdempotencyKeyProviding
    let patientTimeZone: PatientTimeZoneContext

    static func scaffold() -> AppDependencies {
        make(configuration: AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: true,
            startsWithCompletedFixture: true,
            preloadsSyntheticOnboardingValues: true,
            authBehavior: .succeed(after: nil)
        ))
    }

    static func demo(configuration: AppLaunchConfiguration) -> AppDependencies {
        make(configuration: configuration)
    }

    static func make(configuration: AppLaunchConfiguration) -> AppDependencies {
        let secureStore: any SecureStoring = switch configuration.demoStorageBoundary {
        case .memory:
            InMemorySecureStore()
        case .keychain:
            KeychainSecureStore(
                service: configuration.demoKeychainService
            )
        }
        let stateStore = DemoStateStore(secureStore: secureStore)
        let buildFlavor: AppBuildFlavor = configuration.mode == .demo ? .debug : .release
        let unavailable = UnavailableBodyFlowCapabilities()
        #if DEBUG
        let todayRequest = APIRequest<TodaySummary>(method: .get, path: "/today")
        let apiClient: any APIClient = switch configuration.mode {
        case .demo:
            MockAPIClient(
                payloads: [todayRequest.key: AppFixtures.todayPayload]
            )
        case .releaseUnavailable:
            UnavailableAPIClient()
        }
        #else
        let apiClient: any APIClient = UnavailableAPIClient()
        #endif

        return AppDependencies(
            apiClient: apiClient,
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
            telemetry: InMemoryTelemetryClient(),
            today: unavailable,
            history: unavailable,
            plan: unavailable,
            progress: unavailable,
            mealDetection: unavailable,
            registration: unavailable,
            hydration: unavailable,
            weight: unavailable,
            routine: unavailable,
            timeProvider: SystemTimeProvider(),
            idempotencyKeyProvider: UnavailableIdempotencyKeyProvider(),
            patientTimeZone: PatientTimeZoneContext(
                documentedIANAIdentifier: nil
            )
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
