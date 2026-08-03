#if DEBUG
import SwiftUI
import Testing

@testable import BodyFlow

private let prompt14Arguments = [
    "--ui-testing-prompt14-loaded",
    "--ui-testing-prompt14-loading",
    "--ui-testing-prompt14-empty",
    "--ui-testing-prompt14-offline",
    "--ui-testing-prompt14-error",
    "--ui-testing-prompt14-stale",
    "--ui-testing-prompt14-unavailable",
    "--ui-testing-prompt14-opened-error",
    "--ui-testing-prompt14-content-not-found",
    "--ui-testing-prompt14-subscription-required",
    "--ui-testing-prompt14-markdown-invalid",
    "--ui-testing-prompt14-cover-invalid",
    "--ui-testing-prompt14-mascot-variants",
    "--ui-testing-prompt14-progress-empty",
    "--ui-testing-prompt14-progress-minimum",
    "--ui-testing-prompt14-streak-zero",
    "--ui-testing-prompt14-conflict",
    "--ui-testing-prompt14-reduce-motion",
    "--ui-testing-prompt14-differentiate-without-color",
]

@Suite("Prompt 14 Launch Configuration")
struct Prompt14LaunchConfigurationTests {
    private let scenarios: [DemoPrompt14Scenario] = [
        .loaded,
        .loading,
        .empty,
        .offline,
        .error,
        .stale,
        .unavailable,
        .openedError,
        .contentNotFound,
        .subscriptionRequired,
        .markdownInvalid,
        .coverInvalid,
        .mascotVariants,
        .progressEmpty,
        .progressMinimum,
        .streakZero,
        .conflict,
        .reduceMotion,
        .differentiateWithoutColor,
    ]

    @Test("Debug maps every exact Prompt 14 flag")
    func debugMapsEveryExactFlag() {
        #expect(prompt14Arguments.count == 19)
        #expect(scenarios.count == 19)

        for (argument, scenario) in zip(prompt14Arguments, scenarios) {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", argument],
                buildFlavor: .debug
            )

            #expect(configuration.mode == .demo)
            #expect(configuration.prompt14Scenario == scenario)
            #expect(configuration.prompt13Scenario == nil)
            #expect(configuration.shouldResetDemoState)
            #expect(configuration.startsWithCompletedFixture)
            #expect(configuration.preloadsSyntheticOnboardingValues)
        }
    }

    @Test("Prompt 13 keeps precedence when both generations of flags are present")
    func prompt13KeepsPrecedenceOverPrompt14() {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: [
                "--ui-testing",
                "--ui-testing-prompt13-loaded",
                "--ui-testing-prompt14-loaded",
            ],
            buildFlavor: .debug
        )

        #expect(configuration.prompt13Scenario == .loaded)
        #expect(configuration.prompt14Scenario == nil)
    }

    @Test("Only Prompt 14 accessibility flags install their overrides")
    func accessibilityFlagsInstallOnlyTheirOwnOverrides() {
        for (argument, scenario) in zip(prompt14Arguments, scenarios) {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", argument],
                buildFlavor: .debug
            )

            #expect(
                configuration.accessibilityReduceMotionOverride
                    == (scenario == .reduceMotion ? true : nil)
            )
            #expect(
                configuration.differentiateWithoutColorOverride
                    == (scenario == .differentiateWithoutColor ? true : nil)
            )
        }
    }

    @Test("Release ignores every Prompt 14 flag")
    func releaseIgnoresEveryPrompt14Flag() {
        for argument in prompt14Arguments {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", argument],
                buildFlavor: .release
            )

            #expect(configuration.mode == .releaseUnavailable)
            #expect(configuration.prompt14Scenario == nil)
            #expect(configuration.prompt13Scenario == nil)
            #expect(configuration.accessibilityReduceMotionOverride == nil)
            #expect(configuration.differentiateWithoutColorOverride == nil)
        }
    }

    @Test("A directly constructed release configuration discards Prompt 14 state")
    func directReleaseConfigurationDiscardsPrompt14State() {
        let configuration = AppLaunchConfiguration(
            mode: .releaseUnavailable,
            shouldResetDemoState: false,
            startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .fail(.operationUnavailable, after: nil),
            prompt14Scenario: .differentiateWithoutColor
        )

        #expect(configuration.prompt14Scenario == nil)
        #expect(configuration.differentiateWithoutColorOverride == nil)
    }

    @Test("Prompt 13 mapping and accessibility behavior remain unchanged")
    func prompt13BehaviorRemainsUnchanged() {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing", "--ui-testing-prompt13-reduce-motion"],
            buildFlavor: .debug
        )

        #expect(configuration.prompt13Scenario == .reduceMotionVerification)
        #expect(configuration.prompt14Scenario == nil)
        #expect(configuration.accessibilityReduceMotionOverride == true)
        #expect(configuration.differentiateWithoutColorOverride == nil)
    }

    @Test("BodyFlow differentiate-without-color environment value is writable")
    func bodyFlowDifferentiateWithoutColorEnvironmentIsWritable() {
        var values = EnvironmentValues()

        #expect(!values.bodyFlowDifferentiateWithoutColor)
        values.bodyFlowDifferentiateWithoutColor = true
        #expect(values.bodyFlowDifferentiateWithoutColor)
    }
}
#endif
