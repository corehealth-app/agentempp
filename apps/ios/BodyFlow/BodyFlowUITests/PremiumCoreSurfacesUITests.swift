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
        XCTAssertEqual(app.staticTexts.matching(identifier: "brand.product-name").count, 0)
        XCTAssertEqual(app.buttons.matching(identifier: "tab.registrar").count, 1)

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
        XCTAssertTrue(element("today.energy.food-excess", app: app).label.contains("17 kcal"))
        let technicalDetails = element("today.energy.details", app: app)
        XCTAssertTrue(technicalDetails.waitForExistence(timeout: 5))
        for _ in 0..<4 where !technicalDetails.isHittable { app.swipeUp() }
        XCTAssertTrue(technicalDetails.isHittable)
        technicalDetails.tap()
        XCTAssertEqual(
            element("today.energy.net-balance", app: app).value as? String,
            "deficit of 83 kilocalories; exercise included"
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

    /// The routine "Ver lista" links belong to their collection heading row at
    /// regular sizes (title left, link right), above the first routine row,
    /// and keep a full 44 pt target.
    @MainActor
    func testTodayRoutineListLinksShareTheCollectionHeaderRow() {
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: "pt-BR",
            dark: false
        )
        XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 8))
        let link = app.buttons["routine.list.supplement"]
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<12 where !link.isHittable { scrollView.swipeUp() }
        XCTAssertTrue(link.isHittable)
        support.assertTarget(link)
        let header = element("today.routine.header.supplement", app: app)
        XCTAssertTrue(header.exists, "The collection heading must be a distinct header element")
        XCTAssertEqual(header.frame.midY, link.frame.midY, accuracy: 1,
                       "The list link shares the heading row at regular sizes")
        XCTAssertLessThan(header.frame.maxX, link.frame.minX)
        let firstRow = app.buttons["routine.supplement-1"]
        XCTAssertTrue(firstRow.exists)
        XCTAssertLessThan(link.frame.maxY, firstRow.frame.minY)
        support.capture("s3-today-routine-header-row-pt-light", app: app)
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
    func testProgressMissingValuesAreNotZeroAndNoRangeSelector() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }

        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt14-progress-minimum"],
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let progressTab = app.buttons["tab.progresso"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 8))
        progressTab.tap()

        let measurements = element("progress.measurements", app: app)
        XCTAssertTrue(measurements.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Not available")
        ).count, 2)
        XCTAssertFalse(app.staticTexts["0 kg"].exists)
        XCTAssertFalse(app.staticTexts["0%"].exists)
        for unsupported in ["7D", "4W", "3M", "6M", "YTD", "1Y"] {
            XCTAssertFalse(app.buttons[unsupported].exists)
            XCTAssertFalse(app.staticTexts[unsupported].exists)
        }
        support.capture("s6-progress-missing-en-dark-axxxl", app: app)
    }

    @MainActor
    func testProgressUsesOfficialValuesAndBlockPercentage() {
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: "en-US",
            dark: false
        )
        let progressTab = app.buttons["tab.progresso"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 8))
        progressTab.tap()

        XCTAssertTrue(app.staticTexts["Current weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["78.4 kg"].exists)
        XCTAssertTrue(app.staticTexts["12 days"].exists)
        let detail = element("progress.block.detail", app: app)
        for _ in 0..<8 where !detail.isHittable { app.swipeUp() }
        XCTAssertTrue(detail.exists)
        support.assertTarget(detail)
        detail.tap()

        XCTAssertTrue(element("screen.block7700.detail", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reported percentage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["32%"].exists)
        XCTAssertFalse(app.staticTexts["Performance Score"].exists)
        support.capture("s6-block-official-percentage-en-light", app: app)
    }

    @MainActor
    func testProgressThemeAndLocaleMatrix() {
        let cases = [
            (language: "pt-BR", dark: false, heading: "Seu progresso", name: "pt-light"),
            (language: "pt-BR", dark: true, heading: "Seu progresso", name: "pt-dark"),
            (language: "en-US", dark: false, heading: "Your progress", name: "en-light"),
            (language: "en-US", dark: true, heading: "Your progress", name: "en-dark"),
        ]
        defer { XCUIDevice.shared.appearance = .light }

        for testCase in cases {
            XCUIDevice.shared.appearance = testCase.dark ? .dark : .light
            let app = support.launch(
                arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
                language: testCase.language,
                dark: testCase.dark
            )
            let tab = app.buttons["tab.progresso"]
            XCTAssertTrue(tab.waitForExistence(timeout: 8))
            tab.tap()
            XCTAssertTrue(app.staticTexts[testCase.heading].waitForExistence(timeout: 5))
            support.capture("s6-progress-\(testCase.name)", app: app)
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
