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
        guard buildFlavor == .debug else {
            return AppLaunchConfiguration(
                mode: .releaseUnavailable,
                shouldResetDemoState: false,
                startsWithCompletedFixture: false,
                preloadsSyntheticOnboardingValues: false,
                authBehavior: .fail(.operationUnavailable, after: nil)
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
    }

    private static func uiTestingConfiguration(
        startsWithCompletedFixture: Bool,
        authBehavior: DemoOperationBehavior<AuthenticationError>
    ) -> AppLaunchConfiguration {
        AppLaunchConfiguration(
            mode: .demo,
            shouldResetDemoState: true,
            startsWithCompletedFixture: startsWithCompletedFixture,
            preloadsSyntheticOnboardingValues: true,
            authBehavior: authBehavior,
            demoStorageBoundary: .keychain,
            demoKeychainService: DemoStorageService.uiTesting
        )
    }
}
