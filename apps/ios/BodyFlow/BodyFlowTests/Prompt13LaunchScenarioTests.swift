#if DEBUG
import Foundation
import Testing

@testable import BodyFlow

@Suite("Prompt 13 Launch Scenarios")
struct Prompt13LaunchScenarioTests {
    private let scenarios: [(flag: String, scenario: DemoBodyFlowScenario)] = [
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
        ("--ui-testing-prompt13-reduce-motion", .reduceMotionVerification),
    ]

    @Test("Debug maps every exact Prompt 13 flag")
    func debugMapsEveryExactFlag() {
        for entry in scenarios {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", entry.flag],
                buildFlavor: .debug
            )

            #expect(configuration.prompt13Scenario == entry.scenario)
            #expect(configuration.shouldResetDemoState)
            #expect(configuration.startsWithCompletedFixture)
            #expect(configuration.preloadsSyntheticOnboardingValues)
        }
    }

    @Test("Every Debug Prompt 13 scenario installs deterministic execution context")
    func debugScenariosInstallDeterministicExecutionContext() throws {
        let expectedTime = try #require(
            ISO8601DateFormatter().date(from: "2026-07-20T23:15:00Z")
        )
        let localDateFormatter = DateFormatter()
        localDateFormatter.calendar = Calendar(identifier: .gregorian)
        localDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        localDateFormatter.dateFormat = "yyyy-MM-dd"

        for entry in scenarios {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", entry.flag],
                buildFlavor: .debug
            )
            let dependencies = AppDependencies.make(configuration: configuration)

            #expect(dependencies.timeProvider.now == expectedTime)
            #expect(try dependencies.idempotencyKeyProvider.nextKey().value == "prompt13-key-0001")
            #expect(
                dependencies.patientTimeZone.documentedIANAIdentifier
                    == "America/Sao_Paulo"
            )
            let patientTimeZone = try dependencies.patientTimeZone.requireTimeZone()
            #expect(patientTimeZone.identifier == "America/Sao_Paulo")
            localDateFormatter.timeZone = patientTimeZone
            #expect(localDateFormatter.string(from: dependencies.timeProvider.now) == "2026-07-20")
            #expect(
                localDateFormatter.string(from: dependencies.timeProvider.now)
                    == DemoBodyFlowFixtures.loadedToday.data.localDate
            )

            let snoozedOccurrence = try #require(
                DemoBodyFlowFixtures.loadedToday.data.supplements.items
                    .flatMap(\.occurrences)
                    .first { $0.status == "snoozed" }
            )
            let lastActionAt = try #require(snoozedOccurrence.lastActionAt?.value)
            let snoozedUntil = try #require(snoozedOccurrence.snoozedUntil?.value)
            #expect(lastActionAt <= dependencies.timeProvider.now)
            #expect(dependencies.timeProvider.now < snoozedUntil)
        }
    }

    @Test("A directly constructed release mode cannot retain a Debug scenario")
    func directReleaseConfigurationDiscardsScenario() {
        let configuration = AppLaunchConfiguration(
            mode: .releaseUnavailable,
            shouldResetDemoState: false,
            startsWithCompletedFixture: false,
            preloadsSyntheticOnboardingValues: false,
            authBehavior: .fail(.operationUnavailable, after: nil),
            prompt13Scenario: .reduceMotionVerification
        )

        #expect(configuration.prompt13Scenario == nil)
        #expect(configuration.accessibilityReduceMotionOverride == nil)
        #expect(configuration.patientTimeZoneForPrompt13 == nil)
    }

    @Test("Only the Reduce Motion scenario overrides the environment")
    func onlyReduceMotionScenarioOverridesEnvironment() {
        for entry in scenarios {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", entry.flag],
                buildFlavor: .debug
            )

            if entry.scenario == .reduceMotionVerification {
                #expect(configuration.accessibilityReduceMotionOverride == true)
            } else {
                #expect(configuration.accessibilityReduceMotionOverride == nil)
            }
        }
    }

    @Test("Nil Reduce Motion override preserves the supplied system value")
    func nilReduceMotionOverridePreservesSystemValue() {
        #expect(
            BodyFlowReduceMotionPolicy.effectiveValue(
                systemValue: true,
                override: nil
            )
        )
        #expect(
            !BodyFlowReduceMotionPolicy.effectiveValue(
                systemValue: false,
                override: nil
            )
        )
    }

    @Test("True Reduce Motion override forces the effective value")
    func trueReduceMotionOverrideForcesEffectiveValue() {
        #expect(
            BodyFlowReduceMotionPolicy.effectiveValue(
                systemValue: false,
                override: true
            )
        )
    }

    @Test("Release ignores every Prompt 13 flag and installs no scenario")
    func releaseIgnoresEveryScenario() {
        for entry in scenarios {
            let configuration = AppLaunchConfiguration.resolve(
                arguments: ["--ui-testing", entry.flag],
                buildFlavor: .release
            )

            #expect(configuration.mode == .releaseUnavailable)
            #expect(configuration.prompt13Scenario == nil)
            #expect(configuration.accessibilityReduceMotionOverride == nil)
            #expect(configuration.patientTimeZoneForPrompt13 == nil)
        }
    }
}
#endif
