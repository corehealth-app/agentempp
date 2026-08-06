#if DEBUG
import Testing

@testable import BodyFlow

@Suite("Prompt 14 Preview Support")
struct Prompt14PreviewSupportTests {
    @Test("Preview catalog covers every approved Prompt 14 surface and state")
    func coversApprovedSurfacesAndStates() {
        #expect(Set(Prompt14PreviewSupport.definitions.map(\.surface)) == Set(
            Prompt14PreviewSurface.allCases
        ))

        assertScenarios(
            [.loaded, .empty, .offline, .error, .unavailable],
            for: .library
        )
        assertScenarios(
            [
                .loaded,
                .contentNotFound,
                .subscriptionRequired,
                .markdownInvalid,
            ],
            for: .detail
        )
        assertScenarios(
            [.loaded, .empty, .offline, .error, .unavailable],
            for: .recommendations
        )
        assertScenarios(
            [.mascotVariants, .unavailable],
            for: .mascot
        )
        assertScenarios(
            [
                .loaded,
                .progressEmpty,
                .progressMinimum,
                .streakZero,
                .unavailable,
            ],
            for: .progress
        )
    }

    @Test("Every preview launch carries exactly one unique Prompt 14 flag")
    func usesExactlyOnePrompt14FlagPerLaunch() {
        let definitions = Prompt14PreviewSupport.definitions
        #expect(Set(definitions.map(\.id)).count == definitions.count)

        for definition in definitions {
            let prompt14Arguments = definition.launchArguments.filter {
                $0.hasPrefix("--ui-testing-prompt14-")
            }
            #expect(prompt14Arguments.count == 1)

            let configuration = AppLaunchConfiguration.resolve(
                arguments: definition.launchArguments,
                buildFlavor: .debug
            )
            #expect(configuration.prompt14Scenario == definition.scenario)
            #expect(configuration.prompt13Scenario == nil)
        }
    }

    @MainActor
    @Test("Preview contexts are local deterministic sessions")
    func buildsDeterministicLocalContexts() async throws {
        let first = Prompt14PreviewSupport.context(for: .loaded)
        let second = Prompt14PreviewSupport.context(for: .loaded)
        let query = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )

        let firstResponse = try await first.sessionOwner.contentListing.content(
            query
        )
        let secondResponse = try await second.sessionOwner.contentListing.content(
            query
        )

        #expect(firstResponse == DemoPrompt14Fixtures.libraryFeed)
        #expect(secondResponse == firstResponse)
        #expect(first.sessionOwner !== second.sessionOwner)
    }

    @MainActor
    @Test("Unavailable preview stays fail closed")
    func unavailablePreviewStaysFailClosed() async throws {
        let context = Prompt14PreviewSupport.context(for: .unavailable)
        let query = try ContentFeedQuery(
            surface: .library,
            category: nil,
            limit: 20,
            cursor: nil
        )

        await #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
            try await context.sessionOwner.contentListing.content(query)
        }
    }

    private func assertScenarios(
        _ expected: [DemoPrompt14Scenario],
        for surface: Prompt14PreviewSurface
    ) {
        #expect(
            Prompt14PreviewSupport.definitions
                .filter { $0.surface == surface }
                .map(\.scenario) == expected
        )
    }
}
#endif
