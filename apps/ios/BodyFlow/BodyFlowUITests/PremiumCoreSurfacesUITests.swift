import XCTest

final class PremiumCoreSurfacesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootBrandOnceAndIndependentStacks() {
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: "en-US",
            dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts.matching(identifier: "brand.product-name").count, 1)

        let expectedLabels = ["Today", "Register", "Plan", "Progress", "Profile"]
        let tabIDs = ["tab.hoje", "tab.registrar", "tab.plano", "tab.progresso", "tab.perfil"]
        for (id, label) in zip(tabIDs, expectedLabels) {
            let tab = app.buttons[id]
            XCTAssertTrue(tab.waitForExistence(timeout: 3))
            XCTAssertEqual(tab.label, label)
        }
        XCTAssertTrue(app.staticTexts["Meal proposal"].exists)
        XCTAssertTrue(app.staticTexts["Workout proposal"].exists)
        XCTAssertTrue(app.staticTexts["Pending confirmation"].exists)
        XCTAssertEqual(
            element("today.energy.remaining-food", app: app).value as? String,
            "731 kilocalories; exercise excluded"
        )
        XCTAssertEqual(
            element("today.energy.net-balance", app: app).value as? String,
            "minus 83 kilocalories; exercise included"
        )

        let flow = app.buttons["today.flow-chat"]
        XCTAssertTrue(flow.waitForExistence(timeout: 5))
        flow.tap()
        XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 5))

        app.buttons["tab.registrar"].tap()
        XCTAssertTrue(element("screen.registrar", app: app).waitForExistence(timeout: 5))
        app.buttons["tab.hoje"].tap()
        XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 5))
        support.capture("s3-shell-en-light-axxxl", app: app)
    }

    @MainActor
    func testFlowEntrySurvivesUnavailableToday() {
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-unavailable"],
            language: "pt-BR",
            dark: true
        )
        XCTAssertTrue(element("state.unavailable", app: app).waitForExistence(timeout: 8))
        let flow = app.buttons["today.flow-chat"]
        XCTAssertTrue(flow.waitForExistence(timeout: 5))
        support.assertTarget(flow)
        flow.tap()
        XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 5))
        support.capture("s3-today-unavailable-flow-dark", app: app)
    }

    @MainActor
    func testTodayCoreMetricsPrecedePendingInformationAXXXL() {
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: "pt-BR",
            dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let energy = element("today.energy.remaining-food", app: app)
        let hydration = element("today.hydration", app: app)
        let attention = element("today.attention", app: app)
        XCTAssertTrue(energy.waitForExistence(timeout: 8))
        XCTAssertTrue(hydration.waitForExistence(timeout: 5))
        XCTAssertTrue(attention.waitForExistence(timeout: 5))
        XCTAssertLessThan(energy.frame.minY, attention.frame.minY)
        XCTAssertLessThan(hydration.frame.minY, attention.frame.minY)
        support.capture("s3-today-pt-light-axxxl", app: app)
    }

    @MainActor
    private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    @MainActor
    private func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        support.element(id, app: app)
    }
}
