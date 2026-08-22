import Foundation
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
    let publishedContentSessions: any PublishedContentSessionCreating
    let coachExperienceSessions: any CoachExperienceSessionCreating
    let contentCoverSessions: any ContentCoverSessionCreating
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

    static func make(
        configuration: AppLaunchConfiguration,
        mobileAPIConfigurationProvider: (any MobileAPIConfigurationProviding)? = nil,
        sessionTokenProvider: (any SessionTokenProviding)? = nil,
        mobileAPISession: URLSession = .shared,
        apiClientOverride: (any APIClient)? = nil
    ) -> AppDependencies {
        let secureStore: any SecureStoring = switch configuration.demoStorageBoundary {
        case .memory:
            InMemorySecureStore()
        case .keychain:
            KeychainSecureStore(
                service: configuration.demoKeychainService
            )
        }
        let stateStore = DemoStateStore(secureStore: secureStore)
        var coachPersona: any CoachPersonaRepository =
            DemoCoachPersonaRepository(stateStore: stateStore)
        let buildFlavor: AppBuildFlavor = configuration.mode == .demo ? .debug : .release
        let unavailable = UnavailableBodyFlowCapabilities()
        var publishedContentSessions: any PublishedContentSessionCreating =
            UnavailablePublishedContentSessionFactory()
        var coachExperienceSessions: any CoachExperienceSessionCreating =
            UnavailableCoachExperienceSessionFactory()
        var contentCoverSessions: any ContentCoverSessionCreating =
            UnavailableContentCoverSessionFactory()
        #if DEBUG
        let todayRequest = APIRequest<TodaySummary>(method: .get, path: "/today")
        let apiClient: any APIClient
        if configuration.mode == .demo, let apiClientOverride {
            apiClient = apiClientOverride
        } else if let mobileAPIConfiguration = mobileAPIConfigurationProvider?
                    .currentConfiguration(),
                  let sessionTokenProvider {
            apiClient = MobileAPITransport(
                configuration: mobileAPIConfiguration,
                sessionTokenProvider: sessionTokenProvider,
                session: mobileAPISession
            )
        } else {
            apiClient = switch configuration.mode {
            case .demo:
                MockAPIClient(
                    payloads: [todayRequest.key: AppFixtures.todayPayload]
                )
            case .releaseUnavailable:
                UnavailableAPIClient()
            }
        }
        #else
        _ = apiClientOverride
        let apiClient: any APIClient
        if let mobileAPIConfiguration = mobileAPIConfigurationProvider?
                .currentConfiguration(),
           let sessionTokenProvider {
            apiClient = MobileAPITransport(
                configuration: mobileAPIConfiguration,
                sessionTokenProvider: sessionTokenProvider,
                session: mobileAPISession
            )
        } else {
            apiClient = UnavailableAPIClient()
        }
        #endif

        #if DEBUG
        let timeProvider: any TimeProviding
        let idempotencyKeyProvider: any IdempotencyKeyProviding
        let patientTimeZone: PatientTimeZoneContext
        let today: any TodayProviding
        let history: any HistoryProviding
        let plan: any PlanProviding
        let progress: any ProgressProviding
        let mealDetection: any MealDetectionProviding
        let registration: any RegistrationProviding
        let hydration: any HydrationRecording
        let weight: any WeightRecording
        let routine: any RoutineProviding
        if configuration.mode == .demo,
           let scenario = configuration.prompt13Scenario {
            let repository = DemoBodyFlowRepository(scenario: scenario)
            timeProvider = FixedTimeProvider(
                value: configuration.routineCrossingDateTimeOverride
                    ?? Date(timeIntervalSince1970: 1_784_589_300)
            )
            idempotencyKeyProvider = DeterministicIdempotencyKeyProvider(
                prefix: "prompt13-key"
            )
            patientTimeZone = configuration.patientTimeZoneForPrompt13
                ?? PatientTimeZoneContext(documentedIANAIdentifier: nil)
            today = repository
            history = repository
            plan = repository
            progress = repository
            mealDetection = repository
            registration = repository
            hydration = repository
            weight = repository
            routine = repository
        } else if configuration.mode == .demo,
                  let scenario = configuration.prompt14ScenarioSelection {
            let repository = DemoBodyFlowRepository(scenario: .loaded)
            let prompt14TimeProvider = FixedTimeProvider(
                value: DemoPrompt14Fixtures.fixedNow
            )
            timeProvider = prompt14TimeProvider
            idempotencyKeyProvider = DeterministicIdempotencyKeyProvider(
                prefix: "prompt14-key"
            )
            patientTimeZone = PatientTimeZoneContext(
                documentedIANAIdentifier: nil
            )
            today = repository
            history = repository
            plan = repository
            progress = switch scenario {
            case .progressEmpty:
                DemoPrompt14ProgressProvider(
                    response: DemoPrompt14Fixtures.emptyProgress
                )
            case .progressMinimum:
                DemoPrompt14ProgressProvider(
                    response: DemoPrompt14Fixtures.minimumProgress
                )
            case .streakZero:
                DemoPrompt14ProgressProvider(
                    response: DemoPrompt14Fixtures.streakZeroProgress
                )
            case .progressCompleteDuplicateBadges:
                DemoPrompt14ProgressProvider(
                    response: DemoPrompt14Fixtures.duplicateBadgeCompleteProgress
                )
            default:
                repository
            }
            mealDetection = repository
            registration = repository
            hydration = repository
            weight = repository
            routine = repository
            publishedContentSessions = DemoPrompt14PublishedContentSessionFactory(
                selection: scenario
            )
            if scenario == .personaStateful {
                let personaState = DemoPrompt14PersonaSessionState()
                coachPersona = personaState
                coachExperienceSessions = DemoPrompt14CoachExperienceSessionFactory(
                    selection: scenario,
                    personaState: personaState
                )
            } else {
                coachExperienceSessions = DemoPrompt14CoachExperienceSessionFactory(
                    selection: scenario
                )
            }
            contentCoverSessions = DemoPrompt14ContentCoverSessionFactory(
                selection: scenario,
                timeProvider: prompt14TimeProvider
            )
        } else {
            timeProvider = SystemTimeProvider()
            idempotencyKeyProvider = UnavailableIdempotencyKeyProvider()
            patientTimeZone = PatientTimeZoneContext(
                documentedIANAIdentifier: nil
            )
            today = unavailable
            history = unavailable
            plan = unavailable
            progress = unavailable
            mealDetection = unavailable
            registration = unavailable
            hydration = unavailable
            weight = unavailable
            routine = unavailable
        }
        #else
        let timeProvider: any TimeProviding = SystemTimeProvider()
        let idempotencyKeyProvider: any IdempotencyKeyProviding =
            UnavailableIdempotencyKeyProvider()
        let patientTimeZone = PatientTimeZoneContext(
            documentedIANAIdentifier: nil
        )
        let today: any TodayProviding = unavailable
        let history: any HistoryProviding = unavailable
        let plan: any PlanProviding = unavailable
        let progress: any ProgressProviding = unavailable
        let mealDetection: any MealDetectionProviding = unavailable
        let registration: any RegistrationProviding = unavailable
        let hydration: any HydrationRecording = unavailable
        let weight: any WeightRecording = unavailable
        let routine: any RoutineProviding = unavailable
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
            coachPersona: coachPersona,
            secureStore: secureStore,
            telemetry: InMemoryTelemetryClient(),
            today: today,
            history: history,
            plan: plan,
            progress: progress,
            mealDetection: mealDetection,
            registration: registration,
            hydration: hydration,
            weight: weight,
            routine: routine,
            publishedContentSessions: publishedContentSessions,
            coachExperienceSessions: coachExperienceSessions,
            contentCoverSessions: contentCoverSessions,
            timeProvider: timeProvider,
            idempotencyKeyProvider: idempotencyKeyProvider,
            patientTimeZone: patientTimeZone
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
