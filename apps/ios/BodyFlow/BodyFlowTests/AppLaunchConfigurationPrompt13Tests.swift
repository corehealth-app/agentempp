#if DEBUG
import Testing

@testable import BodyFlow

@Suite("Prompt 13 App Launch Configuration")
struct AppLaunchConfigurationPrompt13Tests {
    @Test(
        "Release ignores every Prompt 13 UI-testing argument",
        arguments: [
            "loaded",
            "loading",
            "empty",
            "offline",
            "stale-offline",
            "error",
            "stale-error",
            "incomplete",
            "unavailable",
            "registration-error-once",
            "routine-conflict-once",
            "reduce-motion",
        ]
    )
    func releaseIgnoresPrompt13Argument(suffix: String) {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing-prompt13-\(suffix)"],
            buildFlavor: .release
        )

        #expect(configuration.mode == .releaseUnavailable)
        #expect(!configuration.shouldResetDemoState)
        #expect(!configuration.startsWithCompletedFixture)
        #expect(!configuration.preloadsSyntheticOnboardingValues)
        #expect(configuration.demoStorageBoundary == .memory)
        #expect(configuration.demoKeychainService == DemoStorageService.development)

        switch configuration.authBehavior {
        case .succeed:
            Issue.record("Release must not enable synthetic authentication success")
        case let .fail(error, delay):
            #expect(error == .operationUnavailable)
            #expect(delay == nil)
        }
    }
}
#endif
