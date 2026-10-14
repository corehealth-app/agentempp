import XCTest

/// Opens BodyFlowApp -> its actual Root/Shell -> Today -> History -> Detail.
/// The opt-in synthetic fixture keeps Auth/store/coordinator/transport real.
@MainActor
final class C11RootNavigationUITests: XCTestCase {
    private var runningApp: XCUIApplication?
    private let rowID = "11111111-1111-4111-8111-111111111111"

    override func tearDown() {
        runningApp?.terminate()
        runningApp = nil
        super.tearDown()
    }

    func testExplicitSyntheticSourceUsesRealRootHistoryRouteAndOneOfficialGET() throws {
        let app = try launchFixture("--ui-testing-c11-root-source-on", selection: "on")
        try openActualHistoryRow(in: app)
        let detail = element("screen.meal-record", in: app)
        let entered = detail.waitForExistence(timeout: 8)
        XCTAssertTrue(entered,
            "FEATURE_NOT_IMPLEMENTED: admitted synthetic source must use the actual C11 History destination")
        guard entered else { capture(app, name: "c11-root-positive-destination"); return }
        let name = app.textFields["meal-record.field.name"]
        let nameReady = name.waitForExistence(timeout: 5)
        XCTAssertTrue(nameReady, "The actual official Form must expose the name field's own accessibility identifier")
        guard nameReady else { capture(app, name: "c11-root-field-identifier-failure"); return }
        XCTAssertEqual(name.value as? String, "Synthetic C11 confirmed food")
        XCTAssertTrue(app.textFields["meal-record.field.quantity"].exists)
        capture(app, name: "c11-root-fields-own-identifiers")
        // Form virtualizes its lower rows. Reach the actual controls by scrolling.
        let form = app.collectionViews["screen.meal-record"]
        for _ in 0..<6 {
            if app.buttons["meal-record.patch"].isHittable && app.buttons["meal-record.delete"].isHittable { break }
            form.swipeUp()
        }
        XCTAssertTrue(element("meal-record.delete-selection.\(rowID)", in: app).exists)
        XCTAssertTrue(app.buttons["meal-record.patch"].exists)
        XCTAssertTrue(app.buttons["meal-record.delete"].exists)
        XCTAssertTrue(app.buttons["meal-record.patch"].isHittable)
        XCTAssertTrue(app.buttons["meal-record.delete"].isHittable)
        XCTAssertFalse(element("screen.history.meal-detail", in: app).exists)
        XCTAssertFalse(element("meal-record.saved", in: app).exists)
        XCTAssertFalse(element("meal-record.failure", in: app).exists)
        let status = element("c11.fixture.status", in: app)
        let expected = "C11 on: get=1 bind=1 refresh=0 blocked=0"
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, expected,
            "The route must perform one real transport GET and one source bind; no refresh or unexpected endpoint")
        capture(app, name: "c11-root-positive-official-get")
    }

    func testSyntheticSourceOFFPreservesActualReadOnlyHistoryWithoutBindingOrGET() throws {
        let app = try launchFixture("--ui-testing-c11-root-source-off", selection: "off")
        try openActualHistoryRow(in: app)
        XCTAssertTrue(element("screen.history.meal-detail", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic C11 confirmed food"].exists)
        XCTAssertFalse(element("screen.meal-record", in: app).exists)
        for id in ["meal-record.field.name", "meal-record.field.quantity", "meal-record.field.kcal",
                   "meal-record.patch", "meal-record.delete"] {
            XCTAssertFalse(element(id, in: app).exists, "OFF keeps the original read-only destination: \(id)")
        }
        XCTAssertEqual(element("c11.fixture.status", in: app).label,
                       "C11 off: get=0 bind=0 refresh=0 blocked=0")
        capture(app, name: "c11-root-source-off-read-only")
    }

    private func launchFixture(_ argument: String, selection: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        runningApp = app
        app.launchArguments = ["--ui-testing", argument,
                               "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let status = element("c11.fixture.status", in: app)
        guard status.waitForExistence(timeout: 8), status.label.hasPrefix("C11 \(selection):") else {
            capture(app, name: "c11-root-fixture-setup-failure")
            XCTFail("SETUP_NOT_RED: explicit synthetic BodyFlowApp fixture was not selected")
            throw SetupFailure.fixtureNotSelected
        }
        guard element("screen.hoje", in: app).waitForExistence(timeout: 8),
              element("today.history", in: app).waitForExistence(timeout: 5) else {
            capture(app, name: "c11-root-today-setup-failure")
            XCTFail("SETUP_NOT_RED: real Root restore/Shell must reach Today before interpreting C11")
            throw SetupFailure.todayNotReady
        }
        return app
    }

    private func openActualHistoryRow(in app: XCUIApplication) throws {
        element("today.history", in: app).tap()
        guard element("screen.history", in: app).waitForExistence(timeout: 5) else {
            XCTFail("SETUP_NOT_RED: actual Today action did not navigate to History")
            throw SetupFailure.historyNotReady
        }
        let row = element("history.meal.\(rowID)", in: app)
        guard row.waitForExistence(timeout: 5) else {
            XCTFail("SETUP_NOT_RED: the real History list did not draw the synthetic official UUID row")
            throw SetupFailure.rowNotReady
        }
        row.tap()
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private enum SetupFailure: Error { case fixtureNotSelected, todayNotReady, historyNotReady, rowNotReady }
}
