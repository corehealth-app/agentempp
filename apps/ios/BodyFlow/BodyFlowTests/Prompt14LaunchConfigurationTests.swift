#if DEBUG
import SwiftUI
import Testing

@testable import BodyFlow

private let legacyPrompt14Cases: [(String, DemoPrompt14Scenario)] = [
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
]

private let addedPrompt14Cases: [(String, String)] = [
    (
        "--ui-testing-prompt14-today-recommendations-stale",
        "todayRecommendationsStale"
    ),
    ("--ui-testing-prompt14-next-page-failure-once", "nextPageFailureOnce"),
    ("--ui-testing-prompt14-invalid-cursor-recovery", "invalidCursorRecovery"),
    ("--ui-testing-prompt14-incomplete-detail", "incompleteDetail"),
    ("--ui-testing-prompt14-mutation-failure-once", "mutationFailureOnce"),
    ("--ui-testing-prompt14-markdown-external-link", "markdownExternalLink"),
    ("--ui-testing-prompt14-cover-expired", "coverExpired"),
    ("--ui-testing-prompt14-cover-too-large", "coverTooLarge"),
    ("--ui-testing-prompt14-cover-mime-mismatch", "coverMIMEMismatch"),
    ("--ui-testing-prompt14-cover-abusive-dimensions", "coverAbusiveDimensions"),
    ("--ui-testing-prompt14-cover-external-path", "coverExternalPath"),
    ("--ui-testing-prompt14-mascot-focus-active", "mascotFocusActive"),
    ("--ui-testing-prompt14-mascot-zen-neglected", "mascotZenNeglected"),
    (
        "--ui-testing-prompt14-progress-complete-duplicate-badges",
        "progressCompleteDuplicateBadges"
    ),
    ("--ui-testing-prompt14-persona-stateful", "personaStateful"),
]

private let prompt14Arguments = legacyPrompt14Cases.map(\.0)
    + addedPrompt14Cases.map(\.0)

@Suite("Prompt 14 Launch Configuration")
struct Prompt14LaunchConfigurationTests {
    @Test("Debug preserves every exact legacy Prompt 14 flag")
    func debugPreservesEveryLegacyExactFlag() {
        #expect(legacyPrompt14Cases.count == 19)

        for (argument, scenario) in legacyPrompt14Cases {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", argument],
                buildFlavor: .debug
            )

            #expect(configuration.mode == .demo)
            #expect(configuration.prompt14Scenario == scenario)
            #expect(
                configuration.prompt14ScenarioSelection
                    == DemoPrompt14ScenarioSelection(legacyScenario: scenario)
            )
            #expect(configuration.prompt13Scenario == nil)
            #expect(configuration.shouldResetDemoState)
            #expect(configuration.startsWithCompletedFixture)
            #expect(configuration.preloadsSyntheticOnboardingValues)
        }
    }

    @Test("Debug maps every exact added Prompt 14 flag to its isolated state")
    func debugMapsEveryAddedExactFlag() {
        #expect(addedPrompt14Cases.count == 15)
        #expect(prompt14Arguments.count == 34)
        #expect(Set(prompt14Arguments).count == prompt14Arguments.count)

        for (argument, expectedName) in addedPrompt14Cases {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", argument],
                buildFlavor: .debug
            )

            #expect(configuration.mode == .demo)
            #expect(
                configuration.prompt14ScenarioSelection.map(
                    String.init(describing:)
                ) == expectedName
            )
            #expect(configuration.prompt14Scenario == nil)
            #expect(configuration.prompt13Scenario == nil)
            #expect(configuration.shouldResetDemoState)
            #expect(configuration.startsWithCompletedFixture)
            #expect(configuration.preloadsSyntheticOnboardingValues)
        }
    }

    @Test("Each Prompt 14 scenario launch uses one Prompt 14 flag")
    func eachScenarioLaunchUsesOnePrompt14Flag() {
        for argument in prompt14Arguments {
            let launchArguments = ["--ui-testing", argument]

            #expect(
                launchArguments.filter {
                    $0.hasPrefix("--ui-testing-prompt14-")
                }.count == 1
            )
        }
    }

    @Test("Zero or multiple Prompt 14 flags select no Prompt 14 scenario")
    func prompt14SelectionRequiresExactlyOneFlag() {
        let zero = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing"],
            buildFlavor: .debug
        )
        let twoLegacy = AppLaunchConfiguration.resolve(
            arguments: [
                "--ui-testing",
                legacyPrompt14Cases[0].0,
                legacyPrompt14Cases[1].0,
            ],
            buildFlavor: .debug
        )
        let legacyAndAdded = AppLaunchConfiguration.resolve(
            arguments: [
                "--ui-testing",
                legacyPrompt14Cases[0].0,
                addedPrompt14Cases[0].0,
            ],
            buildFlavor: .debug
        )

        #expect(zero.prompt14Scenario == nil)
        #expect(zero.prompt14ScenarioSelection == nil)
        #expect(twoLegacy.prompt14Scenario == nil)
        #expect(twoLegacy.prompt14ScenarioSelection == nil)
        #expect(legacyAndAdded.prompt14Scenario == nil)
        #expect(legacyAndAdded.prompt14ScenarioSelection == nil)
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
        #expect(configuration.prompt14ScenarioSelection == nil)
    }

    @Test("Only Prompt 14 accessibility flags install their overrides")
    func accessibilityFlagsInstallOnlyTheirOwnOverrides() {
        for (argument, scenario) in legacyPrompt14Cases {
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

        for (argument, _) in addedPrompt14Cases {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", argument],
                buildFlavor: .debug
            )

            #expect(configuration.accessibilityReduceMotionOverride == nil)
            #expect(configuration.differentiateWithoutColorOverride == nil)
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
            #expect(configuration.prompt14ScenarioSelection == nil)
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
        #expect(configuration.prompt14ScenarioSelection == nil)
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
