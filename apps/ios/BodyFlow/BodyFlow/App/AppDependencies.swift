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
    let me: any MeProviding
    let publishedContentSessions: any PublishedContentSessionCreating
    let coachExperienceSessions: any CoachExperienceSessionCreating
    let contentCoverSessions: any ContentCoverSessionCreating
    let timeProvider: any TimeProviding
    let idempotencyKeyProvider: any IdempotencyKeyProviding
    /// Seeded per launch; the authenticated session owner resolves it from
    /// `GET /me` on a real account and resets it when that session ends.
    let patientTimeZoneStore: PatientTimeZoneStore
    let flowChat: any FlowChatProviding
    /// Local reminders on this iPhone; nil where no reminder source exists
    /// (a plain demonstration shows no reminders entry).
    var localReminders: LocalReminderCapability? = nil
    /// Meal capture from free text, photo and audio; nil where no server
    /// reads them (the demonstration keeps its local samples).
    var mealCapture: MealCaptureCapability? = nil
    /// Plan drafts (Flow proposals and imported documents); nil where no
    /// server keeps them.
    var planDrafts: PlanDraftCapability? = nil

    var patientTimeZone: PatientTimeZoneContext {
        patientTimeZoneStore.current
    }

    /// The Register tab keeps its local demonstration while the app runs on
    /// the demo authentication; on a real account it shows its actions only
    /// while a registration capability exists, and otherwise renders the
    /// honest unavailable state instead of the demonstration copy.
    var isRegistrationAvailable: Bool {
        !presentsRealAccountIdentity
            || !(registration is UnavailableBodyFlowCapabilities)
    }

    /// A real Supabase session identifies the account on the Profile tab;
    /// the demo service keeps the fixture identity the tests lock.
    var presentsRealAccountIdentity: Bool {
        authentication is SupabaseAuthenticationService
    }

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
        apiClientOverride: (any APIClient)? = nil,
        supabaseAuthConfiguration: SupabaseAuthConfiguration? = nil,
        authenticationSessionStore: AuthenticationSessionStore? = nil,
        supabaseAuthFetch: SupabaseAuthRemoteClient.Fetch? = nil,
        sessionLifecycleOverride: (any SessionLifecycleProviding)? = nil,
        sessionRefreshPolicy: SessionRefreshPolicy = .production
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
        // The patient's documented time zone: the Prompt 13 demo seeds it from
        // the launch arguments; everything else starts undocumented and a real
        // account resolves it from `/me` per session. The store also clears on
        // sign-out through the lifecycle's sensitive-state hook.
        let patientTimeZoneSeed: PatientTimeZoneContext
        #if DEBUG
        if configuration.mode == .demo, configuration.prompt13Scenario != nil {
            patientTimeZoneSeed = configuration.patientTimeZoneForPrompt13
                ?? PatientTimeZoneContext(documentedIANAIdentifier: nil)
        } else {
            patientTimeZoneSeed = PatientTimeZoneContext(documentedIANAIdentifier: nil)
        }
        #else
        patientTimeZoneSeed = PatientTimeZoneContext(documentedIANAIdentifier: nil)
        #endif
        let patientTimeZoneStore = PatientTimeZoneStore(seed: patientTimeZoneSeed)
        let releaseSessionStore: AuthenticationSessionStore? =
            if configuration.mode == .releaseUnavailable,
               supabaseAuthConfiguration != nil {
                authenticationSessionStore ?? AuthenticationSessionStore(
                    secureStore: KeychainSecureStore(
                        service: AuthenticationSessionStore.keychainService
                    )
                )
            } else {
                nil
            }
        let releaseAuthRemote: SupabaseAuthRemoteClient? =
            if let supabaseAuthConfiguration, releaseSessionStore != nil {
                SupabaseAuthRemoteClient(
                    configuration: supabaseAuthConfiguration,
                    fetch: supabaseAuthFetch ?? SupabaseAuthFetch(
                        configuration: supabaseAuthConfiguration
                    ).callAsFunction
                )
            } else {
                nil
            }
        let releaseLifecycle: (any SessionLifecycleProviding)? =
            if let sessionLifecycleOverride {
                sessionLifecycleOverride
            } else if let releaseSessionStore, let releaseAuthRemote {
                SessionLifecycleCoordinator(
                    store: releaseSessionStore,
                    remote: releaseAuthRemote,
                    // Sign-out and user switch: the time zone goes back to the
                    // seed, and no local reminder of the ended session survives.
                    sensitiveStateClearer: CompositeSensitiveStateClearer(clearers: [
                        patientTimeZoneStore,
                        LocalReminderSessionClearer(scheduler: .system),
                        MediaStagingSessionClearer(staging: MediaStagingStore()),
                    ]),
                    refreshPolicy: sessionRefreshPolicy
                )
            } else {
                nil
            }
        let mobileSessionTokenProvider: (any SessionTokenProviding)? =
            releaseLifecycle ?? releaseSessionStore ?? sessionTokenProvider
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
                  let mobileSessionTokenProvider {
            if let releaseLifecycle {
                apiClient = MobileAPITransport(
                    configuration: mobileAPIConfiguration,
                    sessionLifecycle: releaseLifecycle,
                    session: mobileAPISession,
                    clock: ContinuousClock()
                )
            } else {
                apiClient = MobileAPITransport(
                    configuration: mobileAPIConfiguration,
                    sessionTokenProvider: mobileSessionTokenProvider,
                    session: mobileAPISession
                )
            }
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
           let mobileSessionTokenProvider {
            if let releaseLifecycle {
                apiClient = MobileAPITransport(
                    configuration: mobileAPIConfiguration,
                    sessionLifecycle: releaseLifecycle,
                    session: mobileAPISession,
                    clock: ContinuousClock()
                )
            } else {
                apiClient = MobileAPITransport(
                    configuration: mobileAPIConfiguration,
                    sessionTokenProvider: mobileSessionTokenProvider,
                    session: mobileAPISession
                )
            }
        } else {
            apiClient = UnavailableAPIClient()
        }
        #endif

        #if DEBUG
        let timeProvider: any TimeProviding
        let idempotencyKeyProvider: any IdempotencyKeyProviding
        let today: any TodayProviding
        let history: any HistoryProviding
        let plan: any PlanProviding
        let progress: any ProgressProviding
        let mealDetection: any MealDetectionProviding
        let registration: any RegistrationProviding
        let hydration: any HydrationRecording
        let weight: any WeightRecording
        let routine: any RoutineProviding
        let me: any MeProviding
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
            today = repository
            history = repository
            plan = repository
            progress = repository
            mealDetection = repository
            registration = repository
            hydration = repository
            weight = repository
            routine = repository
            me = unavailable
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
            me = unavailable
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
            idempotencyKeyProvider = configuration.mode == .demo || apiClient is MobileAPITransport
                ? RandomIdempotencyKeyProvider()
                : UnavailableIdempotencyKeyProvider()
            if let transport = apiClient as? MobileAPITransport {
                let reads = MobileBodyFlowRepository(transport: transport)
                let mutations = MobileRegistrationRepository(transport: transport)
                let clock = timeProvider
                today = reads
                history = reads
                plan = MobileBodyFlowRepository(transport: transport.withResponseBodyLimit(
                    MobileAPITransport.planResponseBodyLimit
                ))
                progress = reads
                me = reads
                mealDetection = TextMealDetector(now: { clock.now })
                registration = mutations
                hydration = mutations
                weight = mutations
                routine = MobileRoutineRepository(transport: transport)
                coachPersona = MobileCoachPersonaRepository(transport: transport)
                publishedContentSessions = MobilePublishedContentSessionFactory(
                    transport: transport
                )
                coachExperienceSessions = MobileCoachExperienceSessionFactory(
                    transport: transport
                )
                contentCoverSessions = MobileContentCoverSessionFactory(
                    transport: transport,
                    timeProvider: timeProvider
                )
            } else {
                today = unavailable
                history = unavailable
                plan = unavailable
                progress = unavailable
                me = unavailable
                mealDetection = unavailable
                registration = unavailable
                hydration = unavailable
                routine = unavailable
                weight = unavailable
            }
        }
        #else
        let timeProvider: any TimeProviding = SystemTimeProvider()
        let idempotencyKeyProvider: any IdempotencyKeyProviding =
            apiClient is MobileAPITransport
                ? RandomIdempotencyKeyProvider()
                : UnavailableIdempotencyKeyProvider()
        // Every surface the BFF serves rides the same transport as
        // onboarding and Flow; without a transport they stay unavailable.
        let transport = apiClient as? MobileAPITransport
        let reads = transport.map { MobileBodyFlowRepository(transport: $0) }
        let mutations = transport.map { MobileRegistrationRepository(transport: $0) }
        let clock = timeProvider
        let today: any TodayProviding = reads ?? unavailable
        let history: any HistoryProviding = reads ?? unavailable
        let plan: any PlanProviding = transport.map {
            MobileBodyFlowRepository(transport: $0.withResponseBodyLimit(
                MobileAPITransport.planResponseBodyLimit
            ))
        } ?? unavailable
        let progress: any ProgressProviding = reads ?? unavailable
        let me: any MeProviding = reads ?? unavailable
        let mealDetection: any MealDetectionProviding = transport == nil
            ? unavailable : TextMealDetector(now: { clock.now })
        let registration: any RegistrationProviding = mutations ?? unavailable
        let hydration: any HydrationRecording = mutations ?? unavailable
        let routine: any RoutineProviding = transport
            .map { MobileRoutineRepository(transport: $0) } ?? unavailable
        let weight: any WeightRecording = mutations ?? unavailable
        if let transport {
            coachPersona = MobileCoachPersonaRepository(transport: transport)
            publishedContentSessions = MobilePublishedContentSessionFactory(
                transport: transport
            )
            coachExperienceSessions = MobileCoachExperienceSessionFactory(
                transport: transport
            )
            contentCoverSessions = MobileContentCoverSessionFactory(
                transport: transport,
                timeProvider: timeProvider
            )
        }
        #endif

        let authentication: any AuthenticationService
        #if DEBUG
        if configuration.mode == .demo {
            authentication = DemoAuthenticationService(
                stateStore: stateStore,
                configuration: configuration
            )
        } else if let releaseAuthRemote,
                  let releaseLifecycle {
            authentication = SupabaseAuthenticationService(
                remote: releaseAuthRemote,
                lifecycle: releaseLifecycle
            )
        } else {
            authentication = UnavailableAuthenticationService()
        }
        #else
        if let releaseAuthRemote,
           let releaseLifecycle {
            authentication = SupabaseAuthenticationService(
                remote: releaseAuthRemote,
                lifecycle: releaseLifecycle
            )
        } else {
            authentication = UnavailableAuthenticationService()
        }
        #endif

        let flowChat: any FlowChatProviding
        #if DEBUG
        if configuration.mode == .demo {
            if let scenario = FlowPreviewScenario.resolve(arguments: ProcessInfo.processInfo.arguments) {
                flowChat = FlowPreviewRepository(scenario: scenario)
            } else {
                flowChat = DemoFlowChatRepository()
            }
        } else if let transport = apiClient as? MobileAPITransport {
            flowChat = MobileFlowChatRepository(transport: transport)
        } else {
            flowChat = UnavailableFlowChatRepository()
        }
        #else
        if let transport = apiClient as? MobileAPITransport {
            flowChat = MobileFlowChatRepository(transport: transport)
        } else {
            flowChat = UnavailableFlowChatRepository()
        }
        #endif

        let localReminders: LocalReminderCapability?
        #if DEBUG
        if configuration.mode == .demo {
            if configuration.prompt13Scenario != nil,
               let permitted = DemoLocalReminderScenario.resolve(
                   arguments: ProcessInfo.processInfo.arguments
               ) {
                localReminders = LocalReminderCapability(
                    sources: LocalReminderSources(
                        reminders: DemoReminderProvider(),
                        routine: routine,
                        progress: progress
                    ),
                    scheduler: permitted
                        ? .system
                        : LocalReminderScheduler(center: DeniedLocalNotificationCenter()),
                    optIn: InMemoryLocalReminderOptInStore()
                )
            } else {
                localReminders = nil
            }
        } else if let transport = apiClient as? MobileAPITransport {
            localReminders = LocalReminderCapability(
                sources: LocalReminderSources(
                    reminders: MobileReminderRepository(transport: transport),
                    routine: routine,
                    progress: progress
                ),
                scheduler: .system,
                optIn: UserDefaultsLocalReminderOptInStore()
            )
        } else {
            localReminders = nil
        }
        #else
        localReminders = (apiClient as? MobileAPITransport).map { transport in
            LocalReminderCapability(
                sources: LocalReminderSources(
                    reminders: MobileReminderRepository(transport: transport),
                    routine: routine,
                    progress: progress
                ),
                scheduler: .system,
                optIn: UserDefaultsLocalReminderOptInStore()
            )
        }
        #endif

        // A capture left behind by a previous run never survives a launch.
        var mealCapture: MealCaptureCapability? =
            (apiClient as? MobileAPITransport).map { transport in
                let staging = MediaStagingStore()
                staging.purge()
                return MealCaptureCapability(
                    media: MobileMediaRepository(transport: transport),
                    drafts: MobileMealDraftRepository(transport: transport),
                    uploader: supabaseAuthConfiguration.map {
                        StorageUploadTransport(storageOrigin: $0.origin)
                    },
                    staging: staging
                )
            }
        #if DEBUG
        if configuration.mode == .demo,
           DemoMealCaptureScenario.isEnabled(arguments: ProcessInfo.processInfo.arguments) {
            mealCapture = MealCaptureCapability(
                media: nil,
                drafts: DemoMealDraftProvider(),
                uploader: nil,
                staging: MediaStagingStore()
            )
        }
        #endif

        var planDrafts: PlanDraftCapability? =
            (apiClient as? MobileAPITransport).map { transport in
                PlanDraftCapability(
                    drafts: MobilePlanDraftRepository(
                        transport: transport.withResponseBodyLimit(
                            MobileAPITransport.planResponseBodyLimit
                        )
                    ),
                    media: mealCapture?.media,
                    uploader: mealCapture?.uploader,
                    staging: mealCapture?.staging ?? MediaStagingStore()
                )
            }

        #if DEBUG
        if configuration.mode == .demo,
           DemoPlanDraftScenario.isEnabled(arguments: ProcessInfo.processInfo.arguments) {
            planDrafts = PlanDraftCapability(
                drafts: DemoPlanDraftProvider(),
                media: nil,
                uploader: nil,
                staging: MediaStagingStore()
            )
        }
        #endif

        let onboarding: any OnboardingRepository
        #if DEBUG
        if configuration.mode == .demo {
            onboarding = OnboardingPreviewRepository(
                stateStore: stateStore,
                buildFlavor: buildFlavor,
                preloadsSyntheticOnboardingValues: configuration.preloadsSyntheticOnboardingValues,
                preloadsCompletedFixture: configuration.startsWithCompletedFixture,
                receiptNamespace: configuration.demoStorageBoundary == .keychain
                    ? configuration.demoKeychainService : UUID().uuidString,
                persistsReceipts: configuration.demoStorageBoundary == .keychain,
                resetsReceipts: configuration.shouldResetDemoState
            )
        } else if let transport = apiClient as? MobileAPITransport {
            onboarding = MobileOnboardingRepository(transport: transport)
        } else {
            onboarding = UnavailableOnboardingRepository()
        }
        #else
        if let transport = apiClient as? MobileAPITransport {
            onboarding = MobileOnboardingRepository(transport: transport)
        } else {
            onboarding = UnavailableOnboardingRepository()
        }
        #endif

        return AppDependencies(
            apiClient: apiClient,
            authentication: authentication,
            onboarding: onboarding,
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
            me: me,
            publishedContentSessions: publishedContentSessions,
            coachExperienceSessions: coachExperienceSessions,
            contentCoverSessions: contentCoverSessions,
            timeProvider: timeProvider,
            idempotencyKeyProvider: idempotencyKeyProvider,
            patientTimeZoneStore: patientTimeZoneStore,
            flowChat: flowChat,
            localReminders: localReminders,
            mealCapture: mealCapture,
            planDrafts: planDrafts
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
