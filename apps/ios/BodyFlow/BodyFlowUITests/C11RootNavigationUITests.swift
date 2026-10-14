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

    func testRealRootHistoryGET401RefreshesOnceAndShowsOfficialRecord() throws {
        let app = try launchFixture("--ui-testing-c11-root-get-401-200", selection: "get-401-200")
        try openActualHistoryRow(in: app)
        let detail = element("screen.meal-record", in: app)
        let entered = detail.waitForExistence(timeout: 8)
        XCTAssertTrue(entered,
            "CHARACTERIZATION: real Root/History must publish the official record after HTTP 401 and one real refresh")
        guard entered else { capture(app, name: "c11-root-get401-destination"); return }
        let name = app.textFields["meal-record.field.name"]
        let nameReady = name.waitForExistence(timeout: 5)
        XCTAssertTrue(nameReady, "The official GET response must reach the actual Form's own name field")
        guard nameReady else { capture(app, name: "c11-root-get401-field"); return }
        XCTAssertEqual(name.value as? String, "Synthetic C11 confirmed food")
        XCTAssertEqual(app.textFields["meal-record.field.quantity"].value as? String, "50")
        // Official stored kcal is displayed above the manual override field.
        // That override intentionally starts blank; do not fill it from the server.
        XCTAssertTrue(app.staticTexts["100 kcal"].exists)
        for id in ["screen.history.meal-detail", "meal-record.read-failure", "meal-record.failure",
                   "meal-record.saved", "meal-record.recovery.notice"] {
            XCTAssertFalse(element(id, in: app).exists,
                "A refreshed read must show the editable official detail without a false mutation result: \(id)")
        }
        let status = element("c11.fixture.status", in: app)
        let expected = "C11 get-401-200: get=2 bind=1 refresh=1 blocked=0 sameLogical=1 bearerChanged=1"
        let reached = expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: status)
        wait(for: [reached], timeout: 5)
        XCTAssertEqual(status.label, expected,
            "Real HTTP attempts must retain method/path/body/key/request ID, change bearer once, and avoid extra binding or endpoint")
        capture(app, name: "c11-root-get401-real-refresh-official-record")
    }

    func testRealRootPATCH401RefreshesOncePublishesUpdatedReceiptAndReloadsTodayHistory() throws {
        let app = try launchFixture("--ui-testing-c11-root-patch-401-200", selection: "patch-401-200")
        try openActualHistoryRow(in: app)
        XCTAssertTrue(element("screen.meal-record", in: app).waitForExistence(timeout: 8))
        let name = app.textFields["meal-record.field.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Synthetic C11 confirmed food")
        XCTAssertTrue(app.staticTexts["100 kcal"].exists)
        let quantity = app.textFields["meal-record.field.quantity"]
        XCTAssertEqual(quantity.value as? String, "50")
        let status = element("c11.fixture.status", in: app)
        let before = "C11 patch-401-200: get=1 bind=1 refresh=0 blocked=0 patch=0 sameLogical=0 bearerChanged=0 keys=0 today=1 history=1 commits=0"
        wait(for: [expectation(for: NSPredicate(format: "label == %@", before), evaluatedWith: status)], timeout: 5)
        XCTAssertEqual(status.label, before)
        quantity.tap()
        quantity.typeKey("a", modifierFlags: .command)
        quantity.typeText("75")
        XCTAssertEqual(quantity.value as? String, "75")
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let form = app.collectionViews["screen.meal-record"]
        let save = app.buttons["meal-record.patch"]
        for _ in 0..<6 {
            // Form virtualizes offscreen rows. Do not query a missing Save's
            // frame/traits; mount it by the same bounded normal scrolling.
            if !save.exists { form.swipeUp(); continue }
            let viewport = form.frame.intersection(app.frame)
            let button = save.frame
            let diagnostic = status.frame
            if save.isEnabled && save.isHittable && !viewport.isNull
                && viewport.width > 0 && viewport.height > 0 && button.width > 0 && button.height > 0
                && diagnostic.width > 0 && diagnostic.height > 0
                && viewport.contains(button) && !button.intersects(diagnostic) { break }
            form.swipeUp()
        }
        XCTAssertTrue(save.exists, "SETUP_VISIBLE_CONTROL: the real Save row must mount before frame/trait inspection")
        guard save.exists else {
            capture(app, name: "c11-root-patch401-save-row-not-mounted")
            return
        }
        let viewport = form.frame.intersection(app.frame)
        let buttonFrame = save.frame
        let diagnosticFrame = status.frame
        let wholeButtonVisible = !viewport.isNull && viewport.width > 0 && viewport.height > 0
            && buttonFrame.width > 0 && buttonFrame.height > 0 && viewport.contains(buttonFrame)
        let clearOfDiagnostic = diagnosticFrame.width > 0 && diagnosticFrame.height > 0
            && !buttonFrame.intersects(diagnosticFrame)
        XCTAssertTrue(save.isEnabled && save.isHittable)
        XCTAssertTrue(wholeButtonVisible, "SETUP_VISIBLE_CONTROL: entire Save frame must fit the actual Form/application viewport")
        XCTAssertTrue(clearOfDiagnostic, "SETUP_VISIBLE_CONTROL: Save must not intersect the measured diagnostic overlay")
        print("C11_PATCH_PRETAP app=\(app.frame) form=\(form.frame) viewport=\(viewport) save=\(buttonFrame) diagnostic=\(diagnosticFrame) enabled=\(save.isEnabled) hittable=\(save.isHittable) status=\(status.label)")
        capture(app, name: "c11-root-patch401-save-fully-visible-before-tap")
        guard save.isEnabled && save.isHittable && wholeButtonVisible && clearOfDiagnostic else { return }
        // Normal accessibility tap only; no forced coordinate or provider invocation.
        save.tap()
        let sent = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".* patch=[1-9][0-9]* .*"), object: status)
        let observedPATCH = XCTWaiter.wait(for: [sent], timeout: 8) == .completed
        XCTAssertTrue(observedPATCH,
            "ACTION_OBSERVATION: require a real synthetic PATCH call before scrolling or interpreting receipt/backend behavior")
        guard observedPATCH else {
            capture(app, name: "c11-root-patch401-no-http-after-visible-normal-tap")
            return
        }
        let receipt = element("meal-record.saved", in: app)
        // Native AX groups the label and official value into this static text.
        let officialKcal = app.staticTexts.matching(identifier: "meal-record.saved").matching(
            NSPredicate(format: "label == %@", "Consumo do dia salvo, 123 kcal")
        ).element
        for _ in 0..<6 {
            if receipt.exists && officialKcal.isHittable { break }
            form.swipeDown()
        }
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        XCTAssertTrue(officialKcal.exists,
            "Official persisted daily total is the synthetic receipt's literal123, not local quantity arithmetic")
        XCTAssertTrue(officialKcal.isHittable,
            "The official persisted123kcal must be visibly reachable in the viewport, not only present offscreen in AX")
        XCTAssertFalse(element("meal-record.failure", in: app).exists)
        XCTAssertFalse(element("meal-record.read-failure", in: app).exists)
        XCTAssertFalse(element("meal-record.recovery.notice", in: app).exists)
        capture(app, name: "c11-root-patch401-official-updated-receipt")
        // Use native back navigation, never fixture setters/router/driver calls.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("screen.history", in: app).waitForExistence(timeout: 5))
        let updated = element("history.meal.22222222-2222-4222-8222-222222222222", in: app)
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        XCTAssertFalse(element("history.meal.\(rowID)", in: app).exists)
        XCTAssertTrue(app.staticTexts["Synthetic C11 updated food"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("screen.hoje", in: app).waitForExistence(timeout: 5))
        let consumed = element("today.energy.consumed", in: app)
        XCTAssertTrue(consumed.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "123"), evaluatedWith: consumed)], timeout: 5)
        XCTAssertTrue(consumed.label.contains("123"))
        let after = "C11 patch-401-200: get=1 bind=1 refresh=1 blocked=0 patch=2 sameLogical=1 bearerChanged=1 keys=1 today=2 history=2 commits=1"
        wait(for: [expectation(for: NSPredicate(format: "label == %@", after), evaluatedWith: status)], timeout: 5)
        XCTAssertEqual(status.label, after,
            "Two identical PATCH attempts, one real refresh/key/fixture commit and one additional real provider call per visible feature")
        capture(app, name: "c11-root-patch401-today-history-reloaded")
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
