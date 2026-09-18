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
    func testPlanGroupsReceivedFieldsAndReloadsDetail() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }

        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let planTab = app.buttons["tab.plano"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 8))
        planTab.tap()

        XCTAssertTrue(element("plan.training", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Training plan"].exists)
        XCTAssertFalse(app.staticTexts["Active"].exists)

        let type = app.staticTexts["Training type"]
        for _ in 0..<4 where !type.exists { app.swipeUp() }
        XCTAssertTrue(type.exists)

        let nutrition = app.staticTexts["Nutrition prescription"]
        for _ in 0..<6 where !nutrition.exists { app.swipeUp() }
        XCTAssertTrue(nutrition.exists)

        let detail = element("plan.detail", app: app)
        for _ in 0..<6 where !detail.isHittable { app.swipeUp() }
        XCTAssertTrue(detail.exists)
        support.assertTarget(detail)
        detail.tap()
        XCTAssertTrue(element("screen.plan.detail", app: app).waitForExistence(timeout: 5))
        let generated = app.staticTexts["Generated on"]
        for _ in 0..<5 where !generated.exists { app.swipeUp() }
        XCTAssertTrue(generated.exists)
        support.capture("s5-plan-en-dark-axxxl", app: app)
    }

    @MainActor
    func testPlanThemeAndLocaleMatrix() {
        let cases = [
            (language: "pt-BR", dark: false, heading: "Plano de treino", name: "pt-light"),
            (language: "pt-BR", dark: true, heading: "Plano de treino", name: "pt-dark"),
            (language: "en-US", dark: false, heading: "Training plan", name: "en-light"),
            (language: "en-US", dark: true, heading: "Training plan", name: "en-dark"),
        ]
        defer { XCUIDevice.shared.appearance = .light }

        for testCase in cases {
            XCUIDevice.shared.appearance = testCase.dark ? .dark : .light
            let app = support.launch(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                language: testCase.language,
                dark: testCase.dark
            )
            let tab = app.buttons["tab.plano"]
            XCTAssertTrue(tab.waitForExistence(timeout: 8))
            tab.tap()
            XCTAssertTrue(app.staticTexts[testCase.heading].waitForExistence(timeout: 5))
            support.capture("s5-plan-\(testCase.name)", app: app)
            app.terminate()
        }
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
