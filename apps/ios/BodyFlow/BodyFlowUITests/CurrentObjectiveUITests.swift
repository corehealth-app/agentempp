import XCTest

final class CurrentObjectiveUITests: XCTestCase {
    @MainActor private var support: PremiumUIUXUITestSupport { PremiumUIUXUITestSupport(testCase: self) }

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testProfileOpensCurrentObjectiveWithoutChangingIt() {
        let app = support.launch(arguments: ["--ui-testing", "--ui-testing-current-objective"], language: "pt-BR", dark: false)
        XCTAssertTrue(app.buttons["tab.perfil"].waitForExistence(timeout: 10))
        app.buttons["tab.perfil"].tap()
        let entry = support.element("profile.current-objective", app: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Explicit local scenario offers read-only objective in Profile")
        support.assertTarget(entry)
        entry.tap()
        XCTAssertTrue(support.element("screen.current-objective", app: app).waitForExistence(timeout: 5))
        support.assertTarget(app.buttons["current-objective.refresh"])
        XCTAssertEqual(support.element("current-objective.value", app: app).label, "Manutenção")
        XCTAssertEqual(support.element("current-objective.calories", app: app).label, "Calorias: 2.123,45 kcal")
        XCTAssertEqual(support.element("current-objective.protein", app: app).label, "Proteína: 123,45 g")
        XCTAssertFalse(app.buttons["current-objective.change"].exists)
        let message = app.buttons["current-objective.message"]
        support.assertTarget(message)
        message.tap()
        XCTAssertTrue(support.element("screen.current-objective.welcome", app: app).waitForExistence(timeout: 5))
        XCTAssertEqual(support.element("current-objective.welcome.paragraph.0", app: app).label, "Esta é a mensagem de entrada sintética do seu objetivo atual.")
        app.buttons["current-objective.welcome.close"].tap()
        XCTAssertTrue(support.element("screen.current-objective", app: app).waitForExistence(timeout: 5))
        XCTAssertEqual(support.element("current-objective.value", app: app).label, "Manutenção")
        support.capture("e6-profile-current-objective-pt-light", app: app)
    }

    @MainActor
    func testEnglishReadAndCloseKeepProfileAndDoNotOfferTutorialAgain() {
        let app = support.launch(arguments: ["--ui-testing", "--ui-testing-current-objective"], language: "en-US", dark: true)
        openObjective(app)
        XCTAssertEqual(support.element("current-objective.value", app: app).label, "Maintenance")
        XCTAssertEqual(support.element("current-objective.calories", app: app).label, "Calories: 2,123.45 kcal")
        XCTAssertEqual(support.element("current-objective.protein", app: app).label, "Protein: 123.45 g")
        app.buttons["current-objective.message"].tap()
        XCTAssertEqual(support.element("current-objective.welcome.paragraph.0", app: app).label,
            "This is the synthetic entry message for your current objective.")
        let close = app.buttons["current-objective.welcome.close"]
        XCTAssertEqual(close.label, "Close")
        support.assertTarget(close)
        XCTAssertFalse(app.buttons["onboarding.protocol-welcome.continue"].exists)
        support.capture("e6-current-objective-welcome-en-dark", app: app)
        close.tap()
        XCTAssertTrue(support.element("screen.current-objective", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(support.element("screen.tutorial", app: app).exists)
        XCTAssertFalse(support.element("tour.overlay", app: app).exists)
    }

    @MainActor
    func testEmptyAndOfflineRetryNeverInventAnObjectiveOrTargets() {
        var app = support.launch(arguments: ["--ui-testing", "--ui-testing-current-objective-empty"], language: "pt-BR", dark: false)
        openObjective(app)
        // The screen identifier belongs to the containing scroll view on iOS 27;
        // verify the user's actual empty-state text, not an inherited identifier.
        XCTAssertTrue(app.staticTexts["Nada por aqui"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ainda não há conteúdo para mostrar."].exists)
        XCTAssertFalse(support.element("current-objective.value", app: app).exists)
        XCTAssertFalse(app.buttons["current-objective.message"].exists)
        support.capture("e6-current-objective-empty-pt-light", app: app)
        app.terminate()
        app = support.launch(arguments: ["--ui-testing", "--ui-testing-current-objective-offline"], language: "pt-BR", dark: false)
        openObjective(app)
        XCTAssertTrue(app.staticTexts["Você está offline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Confira sua conexão e tente novamente."].exists)
        XCTAssertFalse(support.element("current-objective.value", app: app).exists)
        let retry = app.buttons["state.retry"]
        support.assertTarget(retry)
        retry.tap()
        XCTAssertTrue(support.element("current-objective.value", app: app).waitForExistence(timeout: 5))
        XCTAssertEqual(support.element("current-objective.value", app: app).label, "Manutenção")
        XCTAssertEqual(support.element("current-objective.protein", app: app).label, "Proteína: 123,45 g")
        support.capture("e6-current-objective-offline-recovered-pt-light", app: app)
    }

    @MainActor
    func testLargestTextKeepsLongMessageAndCloseReachable() {
        let app = support.launch(arguments: ["--ui-testing", "--ui-testing-current-objective-long"], language: "pt-BR", dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL")
        openObjective(app)
        let message = app.buttons["current-objective.message"]
        reach(message, app: app)
        support.assertTarget(message)
        message.tap()
        let first = support.element("current-objective.welcome.paragraph.0", app: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        let scroll = support.element("current-objective.welcome.scroll", app: app)
        let last = support.element("current-objective.welcome.paragraph.11", app: app)
        for _ in 0..<100 where !last.isHittable { scroll.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertEqual(last.label, "Fim da mensagem sintética do seu objetivo atual.")
        let close = app.buttons["current-objective.welcome.close"]
        for _ in 0..<8 where !close.isHittable { scroll.swipeUp() }
        support.assertTarget(close)
        XCTAssertTrue(close.isHittable)
        support.capture("e6-current-objective-long-pt-light-axxxl-bottom", app: app)
        close.tap()
        XCTAssertTrue(support.element("screen.current-objective", app: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func openObjective(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tab.perfil"].waitForExistence(timeout: 10))
        app.buttons["tab.perfil"].tap()
        let entry = support.element("profile.current-objective", app: app)
        // List creates offscreen rows lazily at Accessibility XXXL.
        reach(entry, app: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        support.assertTarget(entry)
        entry.tap()
        XCTAssertTrue(support.element("screen.current-objective", app: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func reach(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<30 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
