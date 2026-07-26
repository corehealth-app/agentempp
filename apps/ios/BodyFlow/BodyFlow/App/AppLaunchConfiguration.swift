import Foundation

enum AppRuntimeMode: Equatable, Sendable {
    case demo
    case releaseUnavailable
}

enum AppBuildFlavor: Equatable, Sendable {
    case debug
    case release
}

struct AppLaunchConfiguration: Sendable {
    let mode: AppRuntimeMode
    let shouldResetDemoState: Bool
    let startsWithCompletedFixture: Bool
    let preloadsSyntheticOnboardingValues: Bool
    let authBehavior: DemoOperationBehavior<AuthenticationError>

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
            authBehavior: .succeed(after: nil)
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
            authBehavior: authBehavior
        )
    }
}
