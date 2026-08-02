import XCTest

final class Prompt13AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFiveTabsRetainIndependentNavigationAfterDeepUse() {
        XCUIDevice.shared.appearance = .light
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: [
                "-AppleInterfaceStyle", "Light",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryLarge",
            ]
        )

        for identifier in [
            "tab.hoje", "tab.registrar", "tab.plano", "tab.progresso",
            "tab.perfil",
        ] {
            let tab = app.tabBars.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(tab)
        }

        let history = element("today.history", in: app)
        reveal(history, in: app)
        XCTAssertTrue(history.isHittable)
        history.tap()
        let meal = element("history.meal.demo-history-meal-row-1", in: app)
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        XCTAssertTrue(
            app.navigationBars["Registro de alimento"]
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.plano"].tap()
        let planDetail = element("plan.detail", in: app)
        reveal(planDetail, in: app)
        XCTAssertTrue(planDetail.isHittable)
        planDetail.tap()
        XCTAssertTrue(
            element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.progresso"].tap()
        XCTAssertTrue(
            element("screen.progresso", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.registrar"].tap()
        XCTAssertTrue(
            element("screen.registrar", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.perfil"].tap()
        XCTAssertTrue(
            element("screen.perfil", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.hoje"].tap()
        XCTAssertTrue(
            app.navigationBars["Registro de alimento"]
                .waitForExistence(timeout: 5)
        )
        app.tabBars.buttons["tab.plano"].tap()
        XCTAssertTrue(
            element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.hoje"].tap()
        app.navigationBars["Registro de alimento"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            element("screen.history", in: app).waitForExistence(timeout: 5)
        )
        app.navigationBars["Histórico"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        support.captureEvidence(named: "13-final-simulator.png", of: app)
    }

    @MainActor
    func testDarkModeKeepsRepresentativeContentReachable() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }

        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: ["-AppleInterfaceStyle", "Dark"]
        )

        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            element("screen.hoje", in: app).value as? String,
            "dark",
            "The running app must resolve the effective SwiftUI color scheme as dark"
        )
        XCTAssertTrue(
            element("today.energy.remaining-food", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element("today.energy.net-balance", in: app)
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(named: "10-dark-mode.png", of: app)
    }

    @MainActor
    func testAccessibilityXXXLKeepsLabelsAndControlsReachable() {
        XCUIDevice.shared.appearance = .light
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )

        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        let navigationBar = app.navigationBars["Hoje"]
        let tabBar = app.tabBars.element(boundBy: 0)
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        let remaining = element("today.energy.remaining-food", in: app)
        revealFully(remaining, in: app, within: window)
        XCTAssertTrue(remaining.isHittable)
        XCTAssertFalse(remaining.label.isEmpty)
        XCTAssertTrue(window.frame.contains(remaining.frame))

        let history = element("today.history", in: app)
        revealFully(history, in: app, within: window, attempts: 16)
        XCTAssertTrue(history.isHittable)
        XCTAssertTrue(window.frame.contains(history.frame))
        support.assertMinimumTapTarget(history)

        let nextAction = element("today.next-action", in: app)
        revealFully(nextAction, in: app, within: window)
        XCTAssertTrue(nextAction.isHittable)
        XCTAssertFalse(nextAction.label.isEmpty)
        support.assertMinimumTapTarget(nextAction)
        XCTAssertGreaterThanOrEqual(
            nextAction.frame.minY,
            navigationBar.frame.maxY,
            "Representative card must stay below the navigation bar"
        )
        XCTAssertLessThanOrEqual(
            nextAction.frame.maxY,
            tabBar.frame.minY,
            "Representative card must stay above the tab bar"
        )
        support.captureEvidence(named: "11-accessibility-xxxl.png", of: app)
    }

    @MainActor
    func testDebugReduceMotionPolicyPathKeepsAppUsable() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .reduceMotion)

        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        let refresh = app.buttons["today.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(refresh)
        refresh.tap()
        XCTAssertTrue(
            element("today.header.updated-at", in: app)
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(named: "12-reduce-motion.png", of: app)
    }

    @MainActor
    func testRecoverableAndSuccessSummariesStayVisibleWithMinimumTargets() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .registrationErrorOnce)

        let register = app.tabBars.buttons["tab.registrar"]
        XCTAssertTrue(register.waitForExistence(timeout: 5))
        register.tap()
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(meal)
        meal.tap()

        let textSource = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(textSource.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(textSource)
        textSource.tap()
        let detect = app.buttons["registration.meal.detect"]
        XCTAssertTrue(detect.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(detect)
        detect.tap()

        let summary = element("registration.operation.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Não foi possível concluir. Tente novamente."]
                .exists
        )
        let retry = app.buttons["registration.mutation.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(retry)
        retry.tap()

        XCTAssertTrue(
            element("registration.proposal", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Proposta criada. Revise antes de confirmar."]
                .waitForExistence(timeout: 3)
        )
        for identifier in [
            "registration.proposal.edit",
            "registration.proposal.confirm",
            "registration.proposal.cancel",
        ] {
            support.assertMinimumTapTarget(app.buttons[identifier])
        }
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 6
    ) {
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp()
        }
    }

    @MainActor
    private func revealFully(
        _ element: XCUIElement,
        in app: XCUIApplication,
        within window: XCUIElement,
        attempts: Int = 8
    ) {
        for _ in 0..<attempts where !window.frame.contains(element.frame) {
            app.swipeUp()
        }
    }
}
