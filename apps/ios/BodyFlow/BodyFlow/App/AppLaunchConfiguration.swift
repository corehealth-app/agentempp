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
        prompt13Scenario: DemoBodyFlowScenario? = nil
    ) {
        self.mode = mode
        self.shouldResetDemoState = shouldResetDemoState
        self.startsWithCompletedFixture = startsWithCompletedFixture
        self.preloadsSyntheticOnboardingValues = preloadsSyntheticOnboardingValues
        self.authBehavior = authBehavior
        self.demoStorageBoundary = demoStorageBoundary
        self.demoKeychainService = demoKeychainService
        self.prompt13Scenario = mode == .demo ? prompt13Scenario : nil
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
              prompt13Scenario == .reduceMotionVerification else {
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
        prompt13Scenario: DemoBodyFlowScenario? = nil
    ) -> AppLaunchConfiguration {
        AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: true,
            startsWithCompletedFixture: startsWithCompletedFixture,
            preloadsSyntheticOnboardingValues: true,
            authBehavior: authBehavior,
            demoStorageBoundary: .keychain,
            demoKeychainService: DemoStorageService.uiTesting,
            prompt13Scenario: prompt13Scenario
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
