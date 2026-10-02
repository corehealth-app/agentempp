import XCTest

/// Local reminders on the demo routine (synthetic data). The enabled case
/// schedules in the Simulator's real notification center and reads it back;
/// it proves what the runtime accepts, not delivery on a physical iPhone.
final class LocalRemindersUITests: XCTestCase {
    private static let enabled = "--ui-testing-local-reminders"
    private static let denied = "--ui-testing-local-reminders-denied"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testDeniedPermissionSchedulesNothingAndOffersSettings() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded, additionalArguments: [Self.denied])
        openReminders(in: app, support: support)

        let activate = app.buttons["reminders.activate"]
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(activate)
        activate.tap()

        let settings = app.buttons["reminders.open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(settings)
        XCTAssertFalse(element("reminders.coverage", in: app).exists)
        XCTAssertFalse(element("reminders.status", in: app).label.isEmpty)
        XCTAssertTrue(app.buttons["reminders.deactivate"].exists)
    }

    @MainActor
    func testActivationSchedulesInTheSimulatorNotificationCenterAndTurnsOff() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded, additionalArguments: [Self.enabled])
        openReminders(in: app, support: support)

        let activate = app.buttons["reminders.activate"]
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
        activate.tap()
        // The system asks only here; on a Simulator that already answered it,
        // no alert appears.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons
            .matching(NSPredicate(format: "label IN %@", ["Allow", "Permitir"]))
            .firstMatch
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }

        // Coverage is shown only for reminders the notification center holds
        // (read back): the demo routine fills the app's budget of 60 —
        // 59 reminders plus the renewal notice.
        let coverage = element("reminders.coverage", in: app)
        XCTAssertTrue(coverage.waitForExistence(timeout: 15))
        let status = element("reminders.status", in: app)
        XCTAssertTrue(status.label.contains("59"), "status: \(status.label)")
        let refresh = app.buttons["reminders.refresh"]
        XCTAssertTrue(refresh.exists)
        support.assertMinimumTapTarget(refresh)
        XCTAssertTrue(element("reminders.skipped.beyond_budget", in: app).exists)

        let deactivate = app.buttons["reminders.deactivate"]
        deactivate.tap()
        XCTAssertTrue(app.buttons["reminders.activate"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("reminders.coverage", in: app).exists)
    }

    @MainActor
    func testRemindersAtAccessibilityXXXLKeepActionsReachable() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: [
                Self.denied,
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        openReminders(in: app, support: support)

        let activate = app.buttons["reminders.activate"]
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
        XCTAssertTrue(activate.isHittable)
        support.assertMinimumTapTarget(activate)
        activate.tap()
        let settings = app.buttons["reminders.open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        for _ in 0..<6 where !settings.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(settings.isHittable)
        support.assertMinimumTapTarget(settings)
    }

    @MainActor
    func testPlainDemonstrationHasNoRemindersEntry() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)
        let profileTab = app.performeTabBar.buttons["tab.perfil"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(element("profile.coach-persona", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("profile.reminders", in: app).exists)
    }

    @MainActor
    private func openReminders(in app: XCUIApplication, support: BodyFlowUITestSupport) {
        let profileTab = app.performeTabBar.buttons["tab.perfil"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(element("screen.perfil", in: app).waitForExistence(timeout: 5))
        // At large text sizes the row starts below the fold of a lazy list.
        let row = element("profile.reminders", in: app)
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.exists && row.isHittable)
        support.assertMinimumTapTarget(row)
        row.tap()
        let status = element("reminders.status", in: app)
        // On failure the message carries the hierarchy (the result bundle may
        // be incomplete when the runner hangs at teardown).
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
