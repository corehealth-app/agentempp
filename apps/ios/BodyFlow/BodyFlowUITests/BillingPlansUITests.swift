import XCTest

@MainActor
final class BillingPlansUITests: XCTestCase {
    private var support: PremiumUIUXUITestSupport { PremiumUIUXUITestSupport(testCase: self) }
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOfficialAccessWithMissingCheckoutConfigurationInPortuguese() {
        let app = launch("--ui-testing-billing-config-off", language: "pt-BR", dark: false)
        XCTAssertEqual(support.element("screen.hoje", app: app).value as? String, "light")
        openPlans(app)
        let status = support.element("billing.access-status", app: app)
        XCTAssertTrue(app.staticTexts["Acesso ativo"].waitForExistence(timeout: 6))
        XCTAssertEqual(status.label, "Acesso ativo")
        XCTAssertTrue(support.element("billing.checkout-unavailable", app: app).exists)
        XCTAssertFalse(app.buttons["billing.purchase.qa-subscription-ui"].exists)
        let restore = app.buttons["billing.restore"]
        reach(restore, app: app)
        support.assertTarget(restore)
        XCTAssertFalse(restore.isEnabled)
        XCTAssertTrue(probe(app).label.contains("sdk=0 "))
        XCTAssertTrue(probe(app).label.hasSuffix("unexpected=0"))
        support.capture("billing-config-off-pt-light", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(support.element("screen.perfil", app: app).waitForExistence(timeout: 5))
        app.terminate()
    }

    func testPendingReconciliationDoesNotRepurchaseAndProfileSurvivesToday402AtLargestText() {
        let app = launch("--ui-testing-billing-sync", language: "en-US", dark: true,
                         category: "UICTContentSizeCategoryAccessibilityXXXL")
        let blockedToday = expectation(for: NSPredicate(format: "label MATCHES %@", ".*today402=[1-9][0-9]*.*"), evaluatedWith: probe(app))
        wait(for: [blockedToday], timeout: 8)
        XCTAssertTrue(app.staticTexts["Unable to load"].waitForExistence(timeout: 6), "The actual Today UI must receive its 402 before navigating away")
        XCTAssertEqual(support.element("screen.hoje", app: app).value as? String, "dark", "The app must actually render dark, not merely receive a dark launch argument")
        openPlans(app)
        XCTAssertTrue(app.staticTexts["No active access"].waitForExistence(timeout: 6))
        let price = support.element("billing.price.qa-subscription-ui", app: app)
        XCTAssertTrue(price.waitForExistence(timeout: 6))
        XCTAssertEqual(price.label, "QA price")
        let buy = app.buttons["billing.purchase.qa-subscription-ui"]
        reach(buy, app: app)
        support.assertTarget(buy)
        buy.tap()
        let message = support.element("billing.operation-message", app: app)
        XCTAssertTrue(message.waitForExistence(timeout: 6))
        let synchronized = expectation(for: NSPredicate(format: "label CONTAINS %@", "Waiting for confirmation"), evaluatedWith: message)
        wait(for: [synchronized], timeout: 6)
        XCTAssertTrue(message.label.contains("Waiting for confirmation"))
        XCTAssertTrue(probe(app).label.contains("purchase=1 "))
        XCTAssertFalse(app.buttons["billing.purchase.qa-subscription-ui"].exists)
        for _ in 0..<5 { app.swipeDown() }
        support.capture("billing-pending-en-dark-axxxl", app: app)
        let refresh = app.buttons["billing.refresh"]
        reach(refresh, app: app)
        support.assertTarget(refresh)
        refresh.tap()
        XCTAssertTrue(app.staticTexts["Active access"].waitForExistence(timeout: 6))
        XCTAssertTrue(probe(app).label.contains("purchase=1 "))
        XCTAssertTrue(probe(app).label.contains("offers=1 "))
        XCTAssertTrue(probe(app).label.hasSuffix("unexpected=0"))
        for _ in 0..<5 { app.swipeDown() }
        support.capture("billing-confirmed-en-dark-axxxl", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let signOut = app.buttons["profile.account.sign-out"]
        reach(signOut, app: app)
        support.assertTarget(signOut)
        signOut.tap()
        let dialog = app.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let confirm = dialog.buttons["Sign out"]
        support.assertTarget(confirm)
        confirm.tap()
        XCTAssertTrue(support.element("screen.auth.sign-in", app: app).waitForExistence(timeout: 8))
        app.terminate()
    }

    private func launch(_ flag: String, language: String, dark: Bool,
                        category: String = "UICTContentSizeCategoryL") -> XCUIApplication {
        let app = support.launch(arguments: ["--ui-testing", flag], language: language, dark: dark, category: category)
        let marker = probe(app)
        XCTAssertTrue(marker.waitForExistence(timeout: 8), "Explicit DEBUG fixture must use real Root/Auth/binding")
        XCTAssertTrue(app.buttons["tab.perfil"].waitForExistence(timeout: 8))
        return app
    }
    private func openPlans(_ app: XCUIApplication) {
        app.buttons["tab.perfil"].tap()
        let row = support.element("profile.billing", app: app)
        reach(row, app: app)
        support.assertTarget(row)
        row.tap()
        XCTAssertTrue(support.element("screen.billing-plans", app: app).waitForExistence(timeout: 6))
    }
    private func probe(_ app: XCUIApplication) -> XCUIElement { support.element("billing.fixture.status", app: app) }
    private func reach(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<20 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
    }
}
