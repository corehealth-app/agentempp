import Foundation

enum AppRuntimeMode: Equatable, Sendable {
    case demo
    case releaseUnavailable
}

enum AppBuildFlavor: Equatable, Sendable {
    case debug
    case release
}

enum DemoStorageBoundary: Equatable, Sendable {
    case memory
    case keychain
}

#if DEBUG
enum DemoBodyFlowScenario: Equatable, Sendable {
    case loaded
    case loadingDelay
    case empty
    case initialOffline
    case staleOffline
    case initialError
    case staleError
    case incompleteDay
    case unavailablePresentation
    case registrationFailureOnce
    case routineConflictOnce
    case routineActionUnavailable
    case reduceMotionVerification

    fileprivate static func resolve(arguments: [String]) -> DemoBodyFlowScenario? {
        let mappings: [(String, DemoBodyFlowScenario)] = [
            ("--ui-testing-prompt13-loaded", .loaded),
            ("--ui-testing-prompt13-loading", .loadingDelay),
            ("--ui-testing-prompt13-empty", .empty),
            ("--ui-testing-prompt13-offline", .initialOffline),
            ("--ui-testing-prompt13-stale-offline", .staleOffline),
            ("--ui-testing-prompt13-error", .initialError),
            ("--ui-testing-prompt13-stale-error", .staleError),
            ("--ui-testing-prompt13-incomplete", .incompleteDay),
            ("--ui-testing-prompt13-unavailable", .unavailablePresentation),
            ("--ui-testing-prompt13-registration-error-once", .registrationFailureOnce),
            ("--ui-testing-prompt13-routine-conflict-once", .routineConflictOnce),
            ("--ui-testing-prompt13-routine-action-unavailable", .routineActionUnavailable),
            ("--ui-testing-prompt13-reduce-motion", .reduceMotionVerification),
        ]

        return mappings.first { arguments.contains($0.0) }?.1
    }
}

enum DemoPrompt14Scenario: Equatable, Sendable {
    case loaded
    case loading
    case empty
    case offline
    case error
    case stale
    case unavailable
    case openedError
    case contentNotFound
    case subscriptionRequired
    case markdownInvalid
    case coverInvalid
    case mascotVariants
    case progressEmpty
    case progressMinimum
    case streakZero
    case conflict
    case reduceMotion
    case differentiateWithoutColor
}

enum DemoPrompt14ScenarioSelection: Equatable, Sendable {
    case loaded
    case loading
    case empty
    case offline
    case error
    case stale
    case unavailable
    case openedError
    case contentNotFound
    case subscriptionRequired
    case markdownInvalid
    case coverInvalid
    case mascotVariants
    case progressEmpty
    case progressMinimum
    case streakZero
    case conflict
    case reduceMotion
    case differentiateWithoutColor
    case todayRecommendationsStale
    case nextPageFailureOnce
    case invalidCursorRecovery
    case incompleteDetail
    case mutationFailureOnce
    case markdownExternalLink
    case coverExpired
    case coverTooLarge
    case coverMIMEMismatch
    case coverAbusiveDimensions
    case coverExternalPath
    case mascotFocusActive
    case mascotZenNeglected
    case progressCompleteDuplicateBadges

    fileprivate static func resolve(
        arguments: [String]
    ) -> DemoPrompt14ScenarioSelection? {
        let mappings: [(String, DemoPrompt14ScenarioSelection)] = [
            ("--ui-testing-prompt14-loaded", .loaded),
            ("--ui-testing-prompt14-loading", .loading),
            ("--ui-testing-prompt14-empty", .empty),
            ("--ui-testing-prompt14-offline", .offline),
            ("--ui-testing-prompt14-error", .error),
            ("--ui-testing-prompt14-stale", .stale),
            ("--ui-testing-prompt14-unavailable", .unavailable),
            ("--ui-testing-prompt14-opened-error", .openedError),
            ("--ui-testing-prompt14-content-not-found", .contentNotFound),
            ("--ui-testing-prompt14-subscription-required", .subscriptionRequired),
            ("--ui-testing-prompt14-markdown-invalid", .markdownInvalid),
            ("--ui-testing-prompt14-cover-invalid", .coverInvalid),
            ("--ui-testing-prompt14-mascot-variants", .mascotVariants),
            ("--ui-testing-prompt14-progress-empty", .progressEmpty),
            ("--ui-testing-prompt14-progress-minimum", .progressMinimum),
            ("--ui-testing-prompt14-streak-zero", .streakZero),
            ("--ui-testing-prompt14-conflict", .conflict),
            ("--ui-testing-prompt14-reduce-motion", .reduceMotion),
            (
                "--ui-testing-prompt14-differentiate-without-color",
                .differentiateWithoutColor
            ),
            (
                "--ui-testing-prompt14-today-recommendations-stale",
                .todayRecommendationsStale
            ),
            (
                "--ui-testing-prompt14-next-page-failure-once",
                .nextPageFailureOnce
            ),
            (
                "--ui-testing-prompt14-invalid-cursor-recovery",
                .invalidCursorRecovery
            ),
            ("--ui-testing-prompt14-incomplete-detail", .incompleteDetail),
            (
                "--ui-testing-prompt14-mutation-failure-once",
                .mutationFailureOnce
            ),
            (
                "--ui-testing-prompt14-markdown-external-link",
                .markdownExternalLink
            ),
            ("--ui-testing-prompt14-cover-expired", .coverExpired),
            ("--ui-testing-prompt14-cover-too-large", .coverTooLarge),
            (
                "--ui-testing-prompt14-cover-mime-mismatch",
                .coverMIMEMismatch
            ),
            (
                "--ui-testing-prompt14-cover-abusive-dimensions",
                .coverAbusiveDimensions
            ),
            (
                "--ui-testing-prompt14-cover-external-path",
                .coverExternalPath
            ),
            (
                "--ui-testing-prompt14-mascot-focus-active",
                .mascotFocusActive
            ),
            (
                "--ui-testing-prompt14-mascot-zen-neglected",
                .mascotZenNeglected
            ),
            (
                "--ui-testing-prompt14-progress-complete-duplicate-badges",
                .progressCompleteDuplicateBadges
            ),
        ]

        let matches = arguments.compactMap { argument in
            mappings.first { $0.0 == argument }?.1
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    init(legacyScenario: DemoPrompt14Scenario) {
        self = switch legacyScenario {
        case .loaded: .loaded
        case .loading: .loading
        case .empty: .empty
        case .offline: .offline
        case .error: .error
        case .stale: .stale
        case .unavailable: .unavailable
        case .openedError: .openedError
        case .contentNotFound: .contentNotFound
        case .subscriptionRequired: .subscriptionRequired
        case .markdownInvalid: .markdownInvalid
        case .coverInvalid: .coverInvalid
        case .mascotVariants: .mascotVariants
        case .progressEmpty: .progressEmpty
        case .progressMinimum: .progressMinimum
        case .streakZero: .streakZero
        case .conflict: .conflict
        case .reduceMotion: .reduceMotion
        case .differentiateWithoutColor: .differentiateWithoutColor
        }
    }

    var legacyScenario: DemoPrompt14Scenario? {
        switch self {
        case .loaded: .loaded
        case .loading: .loading
        case .empty: .empty
        case .offline: .offline
        case .error: .error
        case .stale: .stale
        case .unavailable: .unavailable
        case .openedError: .openedError
        case .contentNotFound: .contentNotFound
        case .subscriptionRequired: .subscriptionRequired
        case .markdownInvalid: .markdownInvalid
        case .coverInvalid: .coverInvalid
        case .mascotVariants: .mascotVariants
        case .progressEmpty: .progressEmpty
        case .progressMinimum: .progressMinimum
        case .streakZero: .streakZero
        case .conflict: .conflict
        case .reduceMotion: .reduceMotion
        case .differentiateWithoutColor: .differentiateWithoutColor
        case .todayRecommendationsStale,
             .nextPageFailureOnce,
             .invalidCursorRecovery,
             .incompleteDetail,
             .mutationFailureOnce,
             .markdownExternalLink,
             .coverExpired,
             .coverTooLarge,
             .coverMIMEMismatch,
             .coverAbusiveDimensions,
             .coverExternalPath,
             .mascotFocusActive,
             .mascotZenNeglected,
             .progressCompleteDuplicateBadges:
            nil
        }
    }
}
#endif

enum DemoStorageService {
    static let development = "com.bodyflow.app.development.demo-state.v1"
    static let uiTesting = "com.bodyflow.app.ui-testing.demo-state.v1"
}

struct AppLaunchConfiguration: Sendable {
    let mode: AppRuntimeMode
    let shouldResetDemoState: Bool
    let startsWithCompletedFixture: Bool
    let preloadsSyntheticOnboardingValues: Bool
    let authBehavior: DemoOperationBehavior<AuthenticationError>
    let demoStorageBoundary: DemoStorageBoundary
    let demoKeychainService: String
    #if DEBUG
    let prompt13Scenario: DemoBodyFlowScenario?
    let prompt14Scenario: DemoPrompt14Scenario?
    let prompt14ScenarioSelection: DemoPrompt14ScenarioSelection?
    #endif

    #if DEBUG
    init(
        mode: AppRuntimeMode,
        shouldResetDemoState: Bool,
        startsWithCompletedFixture: Bool,
        preloadsSyntheticOnboardingValues: Bool,
        authBehavior: DemoOperationBehavior<AuthenticationError>,
        demoStorageBoundary: DemoStorageBoundary = .memory,
        demoKeychainService: String = DemoStorageService.development,
        prompt13Scenario: DemoBodyFlowScenario? = nil,
        prompt14Scenario: DemoPrompt14Scenario? = nil,
        prompt14ScenarioSelection: DemoPrompt14ScenarioSelection? = nil
    ) {
        self.mode = mode
        self.shouldResetDemoState = shouldResetDemoState
        self.startsWithCompletedFixture = startsWithCompletedFixture
        self.preloadsSyntheticOnboardingValues = preloadsSyntheticOnboardingValues
        self.authBehavior = authBehavior
        self.demoStorageBoundary = demoStorageBoundary
        self.demoKeychainService = demoKeychainService
        self.prompt13Scenario = mode == .demo ? prompt13Scenario : nil
        self.prompt14Scenario = mode == .demo ? prompt14Scenario : nil
        self.prompt14ScenarioSelection = mode == .demo
            ? prompt14ScenarioSelection
                ?? prompt14Scenario.map {
                    DemoPrompt14ScenarioSelection(legacyScenario: $0)
                }
            : nil
    }

    var patientTimeZoneForPrompt13: PatientTimeZoneContext? {
        guard mode == .demo, prompt13Scenario != nil else { return nil }
        return PatientTimeZoneContext(
            documentedIANAIdentifier: "America/Sao_Paulo"
        )
    }

    /// UI-test-only clock used to exercise a same-local-date snooze boundary.
    /// It is unavailable outside a configured debug Prompt 13 demo launch.
    var routineCrossingDateTimeOverride: Date? {
        guard mode == .demo,
              prompt13Scenario != nil,
              ProcessInfo.processInfo.arguments.contains(
                "--ui-testing-routine-crossing-date"
              )
        else { return nil }
        return Date(timeIntervalSince1970: 1_784_602_200) // 2026-07-20 23:50 BRT
    }
    #else
    init(
        mode: AppRuntimeMode,
        shouldResetDemoState: Bool,
        startsWithCompletedFixture: Bool,
        preloadsSyntheticOnboardingValues: Bool,
        authBehavior: DemoOperationBehavior<AuthenticationError>,
        demoStorageBoundary: DemoStorageBoundary = .memory,
        demoKeychainService: String = DemoStorageService.development
    ) {
        self.mode = mode
        self.shouldResetDemoState = shouldResetDemoState
        self.startsWithCompletedFixture = startsWithCompletedFixture
        self.preloadsSyntheticOnboardingValues = preloadsSyntheticOnboardingValues
        self.authBehavior = authBehavior
        self.demoStorageBoundary = demoStorageBoundary
        self.demoKeychainService = demoKeychainService
    }
    #endif

    var accessibilityReduceMotionOverride: Bool? {
        #if DEBUG
        guard mode == .demo,
              prompt13Scenario == .reduceMotionVerification
                || prompt14Scenario == .reduceMotion else {
            return nil
        }
        return true
        #else
        nil
        #endif
    }

    var differentiateWithoutColorOverride: Bool? {
        #if DEBUG
        guard mode == .demo,
              prompt14Scenario == .differentiateWithoutColor else {
            return nil
        }
        return true
        #else
        nil
        #endif
    }

    var developmentConsentAvailability: DevelopmentConsentAvailability {
        switch mode {
        case .demo:
            .syntheticDevelopment
        case .releaseUnavailable:
            .unavailable
        }
    }

    static func current() -> AppLaunchConfiguration {
        #if DEBUG
        resolve(arguments: ProcessInfo.processInfo.arguments, buildFlavor: .debug)
        #else
        resolve(arguments: ProcessInfo.processInfo.arguments, buildFlavor: .release)
        #endif
    }

    static func resolve(
        arguments: [String],
        buildFlavor: AppBuildFlavor
    ) -> AppLaunchConfiguration {
        #if DEBUG
        guard buildFlavor == .debug else {
            return releaseConfiguration()
        }

        if let scenario = DemoBodyFlowScenario.resolve(arguments: arguments) {
            return uiTestingConfiguration(
                startsWithCompletedFixture: true,
                authBehavior: .succeed(after: nil),
                prompt13Scenario: scenario
            )
        }

        if let selection = DemoPrompt14ScenarioSelection.resolve(
            arguments: arguments
        ) {
            return uiTestingConfiguration(
                startsWithCompletedFixture: true,
                authBehavior: .succeed(after: nil),
                prompt14Scenario: selection.legacyScenario,
                prompt14ScenarioSelection: selection
            )
        }

        if arguments.contains("--ui-testing-preserve-state") {
            return AppLaunchConfiguration(
                mode: .demo,
                shouldResetDemoState: false,
                startsWithCompletedFixture: false,
                preloadsSyntheticOnboardingValues: false,
                authBehavior: .succeed(after: nil),
                demoStorageBoundary: .keychain,
                demoKeychainService: DemoStorageService.uiTesting
            )
        }

        if arguments.contains("--ui-testing") {
            return uiTestingConfiguration(
                startsWithCompletedFixture: true,
                authBehavior: .succeed(after: nil)
            )
        }

        if arguments.contains("--ui-testing-fresh-auth") {
            return uiTestingConfiguration(
                startsWithCompletedFixture: false,
                authBehavior: .succeed(after: nil)
            )
        }

        if arguments.contains("--ui-testing-auth-error") {
            return uiTestingConfiguration(
                startsWithCompletedFixture: false,
                authBehavior: .fail(.serviceUnavailable, after: nil)
            )
        }

        if arguments.contains("--ui-testing-recovery") {
            return uiTestingConfiguration(
                startsWithCompletedFixture: false,
                authBehavior: .succeed(after: nil)
            )
        }

        return AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: false,
            startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .succeed(after: nil),
            demoStorageBoundary: .keychain
        )
        #else
        _ = arguments
        _ = buildFlavor
        return releaseConfiguration()
        #endif
    }

    #if DEBUG
    private static func uiTestingConfiguration(
        startsWithCompletedFixture: Bool,
        authBehavior: DemoOperationBehavior<AuthenticationError>,
        prompt13Scenario: DemoBodyFlowScenario? = nil,
        prompt14Scenario: DemoPrompt14Scenario? = nil,
        prompt14ScenarioSelection: DemoPrompt14ScenarioSelection? = nil
    ) -> AppLaunchConfiguration {
        AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: true,
            startsWithCompletedFixture: startsWithCompletedFixture,
            preloadsSyntheticOnboardingValues: true,
            authBehavior: authBehavior,
            demoStorageBoundary: .keychain,
            demoKeychainService: DemoStorageService.uiTesting,
            prompt13Scenario: prompt13Scenario,
            prompt14Scenario: prompt14Scenario,
            prompt14ScenarioSelection: prompt14ScenarioSelection
        )
    }
    #endif

    private static func releaseConfiguration() -> AppLaunchConfiguration {
        AppLaunchConfiguration(
            mode: .releaseUnavailable,
            shouldResetDemoState: false,
            startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .fail(.operationUnavailable, after: nil)
        )
    }
}
