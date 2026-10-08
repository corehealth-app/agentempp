#if DEBUG
import Testing
@testable import BodyFlow

@Suite("Explicit block UI fixtures")
struct Block7700DemoFixtureTests {
    @Test("fixtures require an explicit UI test marker and a configured demo surface", arguments: DemoBlock7700Scenario.allCases)
    func launchBoundary(_ scenario: DemoBlock7700Scenario) {
        let args = ["--ui-testing", "--ui-testing-prompt13-loaded", scenario.argument]
        #expect(AppLaunchConfiguration.resolve(arguments: args, buildFlavor: .debug).block7700Scenario == scenario)
        #expect(AppLaunchConfiguration.resolve(arguments: args, buildFlavor: .release).block7700Scenario == nil)
        #expect(AppLaunchConfiguration.resolve(arguments: ["--ui-testing-prompt13-loaded", scenario.argument], buildFlavor: .debug).block7700Scenario == nil)
        #expect(AppLaunchConfiguration.resolve(arguments: ["--ui-testing", scenario.argument], buildFlavor: .debug).block7700Scenario == nil)
        #expect(AppLaunchConfiguration.resolve(arguments: [scenario.argument], buildFlavor: .debug).block7700Scenario == nil)
        #expect(DemoBlock7700Scenario.resolve(arguments: args + [DemoBlock7700Scenario.legacy.argument]) == (scenario == .legacy ? .legacy : nil))
    }

    @Test("null progress deliberately retains nonempty old series")
    func nullProgressWithOldTrends() async throws {
        let config = AppLaunchConfiguration.resolve(arguments: ["--ui-testing", "--ui-testing-prompt13-loaded", DemoBlock7700Scenario.nullProgress.argument], buildFlavor: .debug)
        let dependencies = AppDependencies.demo(configuration: config)
        #expect(try await dependencies.progress.progress().data == nil)
        #expect(try await dependencies.progress.trends(days: 14) == DemoBodyFlowFixtures.loadedTrends)
    }

    @Test("current recomposition adds eligibility without changing existing fixtures")
    func preservesExistingValues() throws {
        let before = BodyFlowTestFixtures.todayResponseWithBlock
        var expected = before.data
        expected.currentProtocol = "recomposicao"
        #expect(try DemoBlock7700Scenario.currentRecomposition.today(before).data == expected)
        let original = BodyFlowTestFixtures.progressResponse
        var progress = original.data
        progress?.currentProtocol = "recomposicao"
        progress?.block7700Enabled = true
        #expect(DemoBlock7700Scenario.currentRecomposition.progress(original).data == progress)
    }
}
#endif
