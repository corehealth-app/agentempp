import XCTest

/// A common Instruments workload for the frozen native-bar baseline and the
/// candidate. It intentionally stays outside the four measured benchmarks.
@MainActor
final class PremiumInstrumentsWorkloadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFiveTabNavigationCommonWorkload() {
        beginPerformanceConditionEvidence()
        let support = PremiumUIUXUITestSupport(testCase: self)
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: "pt-BR",
            dark: false,
            category: "UICTContentSizeCategoryL"
        )
        defer { app.terminate() }
        XCTAssertTrue(support.element("screen.hoje", app: app).waitForExistence(timeout: 8))

        // These tab/screen identifiers exist in both frozen versions. Query
        // buttons directly so this workload accepts either native/custom bar.
        let destinations = [
            (tab: "tab.registrar", screen: "screen.registrar"),
            (tab: "tab.plano", screen: "screen.plano"),
            (tab: "tab.progresso", screen: "screen.progresso"),
            (tab: "tab.perfil", screen: "screen.perfil"),
            (tab: "tab.hoje", screen: "screen.hoje"),
        ]
        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        for iteration in 1...5 {
            XCTContext.runActivity(named: "navigation-cycle-\(iteration)") { _ in
                for destination in destinations {
                    XCTContext.runActivity(named: "navigate-\(destination.tab)") { _ in
                        let button = app.buttons[destination.tab]
                        XCTAssertTrue(button.waitForExistence(timeout: 5), destination.tab)
                        XCTAssertTrue(button.isHittable, destination.tab)
                        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), destination.tab)
                        button.tap()
                        XCTAssertTrue(
                            support.element(destination.screen, app: app)
                                .waitForExistence(timeout: 5),
                            destination.screen
                        )
                    }
                }
            }
        }
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
    }
}
