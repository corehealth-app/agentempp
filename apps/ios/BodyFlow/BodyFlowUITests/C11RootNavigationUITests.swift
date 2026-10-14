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

    func testRealRootDELETE401RefreshesOnceAfterConfirmationAndReloadsEmptyTodayHistory() throws {
        let app = try launchFixture("--ui-testing-c11-root-delete-401-200", selection: "delete-401-200")
        try openActualHistoryRow(in: app)
        XCTAssertTrue(element("screen.meal-record", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["meal-record.field.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["meal-record.field.name"].value as? String, "Synthetic C11 confirmed food")
        XCTAssertEqual(app.textFields["meal-record.field.quantity"].value as? String, "50")
        XCTAssertTrue(app.staticTexts["100 kcal"].exists)
        let status = element("c11.fixture.status", in: app)
        let before = "C11 delete-401-200: get=1 bind=1 refresh=0 blocked=0 delete=0 sameLogical=0 bearerChanged=0 keys=0 today=1 history=1 commits=0"
        wait(for: [expectation(for: NSPredicate(format: "label == %@", before), evaluatedWith: status)], timeout: 5)
        XCTAssertEqual(status.label, before)
        let form = app.collectionViews["screen.meal-record"]
        let selection = app.switches["meal-record.delete-selection.\(rowID)"]
        // The observed native AX exposes a full-row Switch wrapper and one
        // actual child Switch. A normal tap on the wrapper hits its label.
        let nativeSwitches = selection.descendants(matching: .switch)
        let nativeSwitch = nativeSwitches.element
        let delete = app.buttons["meal-record.delete"]
        func controlsFullyVisible() -> Bool {
            guard selection.exists, delete.exists, status.exists,
                  nativeSwitches.count == 1, nativeSwitch.exists else { return false }
            let viewport = form.frame.intersection(app.frame)
            let selectedFrame = selection.frame
            let nativeFrame = nativeSwitch.frame
            let actionFrame = delete.frame
            let diagnostic = status.frame
            return !viewport.isNull && viewport.width > 0 && viewport.height > 0
                && selectedFrame.width > 0 && selectedFrame.height > 0
                && nativeFrame.width > 0 && nativeFrame.height > 0
                && actionFrame.width > 0 && actionFrame.height > 0
                && diagnostic.width > 0 && diagnostic.height > 0
                && viewport.contains(selectedFrame) && viewport.contains(nativeFrame) && viewport.contains(actionFrame)
                && selectedFrame.contains(nativeFrame)
                && !selectedFrame.intersects(diagnostic) && !nativeFrame.intersects(diagnostic) && !actionFrame.intersects(diagnostic)
                && selection.isHittable && nativeSwitch.isEnabled && nativeSwitch.isHittable
                && delete.isEnabled && delete.isHittable
        }
        func reachDeletionControls() {
            for _ in 0..<6 {
                if !selection.exists || !delete.exists { form.swipeUp(); continue }
                if controlsFullyVisible() { break }
                form.swipeUp()
            }
        }
        reachDeletionControls()
        XCTAssertTrue(selection.exists && delete.exists,
            "SETUP_VISIBLE_CONTROL: actual Toggle and Delete row must mount before frame or trait inspection")
        guard selection.exists && delete.exists else {
            capture(app, name: "c11-root-delete401-controls-not-mounted")
            return
        }
        XCTAssertEqual(nativeSwitches.count, 1,
            "SETUP_NATIVE_SWITCH: require exactly the one observed child Switch, never an ambiguous descendant")
        guard nativeSwitches.count == 1, nativeSwitch.exists else {
            capture(app, name: "c11-root-delete401-native-switch-not-unique-or-mounted")
            return
        }
        let initialControlsReady = controlsFullyVisible()
        XCTAssertTrue(initialControlsReady,
            "SETUP_VISIBLE_CONTROL: whole Toggle/Delete frames must fit actual Form/app viewport clear of diagnostics")
        capture(app, name: "c11-root-delete401-selection-controls-fully-visible")
        guard initialControlsReady else { return }
        XCTAssertTrue(selection.isHittable)
        XCTAssertEqual(selection.value as? String, "1", "The actual GET preselects the single official record")
        XCTAssertEqual(nativeSwitch.value as? String, "1")
        XCTAssertTrue(nativeSwitch.isEnabled && nativeSwitch.isHittable)
        nativeSwitch.tap()
        XCTAssertEqual(selection.value as? String, "0")
        XCTAssertEqual(nativeSwitch.value as? String, "0")
        XCTAssertFalse(delete.isEnabled)
        guard selection.value as? String == "0", nativeSwitch.value as? String == "0", !delete.isEnabled else {
            capture(app, name: "c11-root-delete401-native-switch-did-not-disable-delete")
            return
        }
        XCTAssertTrue(nativeSwitch.exists && nativeSwitch.isEnabled && nativeSwitch.isHittable)
        guard nativeSwitch.exists, nativeSwitch.isEnabled, nativeSwitch.isHittable else { return }
        nativeSwitch.tap()
        XCTAssertEqual(selection.value as? String, "1")
        XCTAssertEqual(nativeSwitch.value as? String, "1")
        XCTAssertTrue(delete.isEnabled && delete.isHittable)
        XCTAssertEqual(status.label, before, "Selection alone must not issue a mutation, key or refresh")
        let beforeDialogReady = controlsFullyVisible()
        XCTAssertTrue(beforeDialogReady, "SETUP_VISIBLE_CONTROL: recheck full Toggle/Delete viewport before normal Delete tap")
        print("C11_DELETE_PRETAP app=\(app.frame) form=\(form.frame) toggle=\(selection.frame) delete=\(delete.frame) diagnostic=\(status.frame) status=\(status.label)")
        capture(app, name: "c11-root-delete401-action-fully-visible-before-dialog")
        guard beforeDialogReady else { return }
        delete.tap()
        let confirm = app.buttons["Apagar"]
        let dialogOpened = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(dialogOpened)
        guard dialogOpened else {
            capture(app, name: "c11-root-delete401-dialog-not-presented")
            return
        }
        XCTAssertTrue(confirm.isHittable)
        if status.exists {
            XCTAssertEqual(status.label, before,
                "Opening the real confirmation dialog must still leave DELETE0; only explicit confirmation sends")
        }
        // Observe the real native dismiss control, without inferring style from
        // SDK/size class. A popover can omit Cancelar and expose its AX region.
        // Either genuine dismissal must leave the command/key/refresh at zero.
        let cancel = app.buttons["Cancelar"]
        if cancel.exists {
            XCTAssertTrue(cancel.isHittable, "SETUP_MODAL_OBSERVER: the actual Cancel button must be hittable")
            guard cancel.isHittable else { return }
            cancel.tap()
        } else {
            let sheets = app.sheets.matching(NSPredicate(format: "label == %@", "Apagar este alimento?"))
            let sheet = sheets.element
            let dismissRegions = app.otherElements.matching(identifier: "PopoverDismissRegion")
            let dismissRegion = dismissRegions.element
            XCTAssertEqual(sheets.count, 1, "SETUP_MODAL_OBSERVER: exactly the observed confirmation Sheet is required")
            XCTAssertEqual(dismissRegions.count, 1, "SETUP_MODAL_OBSERVER: require the actual native dismiss region")
            guard sheets.count == 1, sheet.exists,
                  dismissRegions.count == 1, dismissRegion.exists else {
                capture(app, name: "c11-root-delete401-no-observed-native-dismiss-control")
                return
            }
            XCTAssertTrue(dismissRegion.isHittable)
            let regionFrame = dismissRegion.frame
            let sheetFrame = sheet.frame
            let normalTapCenter = CGPoint(x: regionFrame.midX, y: regionFrame.midY)
            let safeDismiss = regionFrame.width > 0 && regionFrame.height > 0
                && sheetFrame.width > 0 && sheetFrame.height > 0
                && app.frame.contains(normalTapCenter) && !sheetFrame.contains(normalTapCenter)
                && dismissRegion.isHittable
            XCTAssertTrue(safeDismiss,
                "SETUP_MODAL_OBSERVER: the normal dismiss-element tap center must be outside the observed Sheet")
            print("C11_DELETE_MODAL_DISMISS_AX region=\(regionFrame) sheet=\(sheetFrame) normalCenter=\(normalTapCenter) hittable=\(dismissRegion.isHittable)")
            capture(app, name: "c11-root-delete401-actual-popover-dismiss-surface")
            guard safeDismiss else { return }
            // Normal AX tap only: no coordinate override or router/model setter.
            dismissRegion.tap()
        }
        let modalGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirm)
        let dismissed = XCTWaiter.wait(for: [modalGone], timeout: 5) == .completed
        XCTAssertTrue(dismissed, "A genuine non-confirming dismissal must remove the native confirmation action")
        guard dismissed else {
            capture(app, name: "c11-root-delete401-native-dismiss-did-not-close-dialog")
            return
        }
        XCTAssertFalse(confirm.exists)
        let stillZero = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", before), object: status)
        let zeroObserved = XCTWaiter.wait(for: [stillZero], timeout: 5) == .completed
        XCTAssertTrue(zeroObserved, "Dialog open/cancel must return to foreground DELETE0/key0/refresh0")
        guard zeroObserved else {
            capture(app, name: "c11-root-delete401-dialog-cancel-issued-unexpected-command")
            return
        }
        XCTAssertEqual(status.label, before)
        reachDeletionControls()
        let confirmationReady = controlsFullyVisible()
        XCTAssertTrue(confirmationReady, "SETUP_VISIBLE_CONTROL: full Toggle/Delete frames required again after cancelling dialog")
        guard confirmationReady else { return }
        delete.tap()
        let reopened = confirm.waitForExistence(timeout: 5)
        XCTAssertTrue(reopened)
        guard reopened else { return }
        XCTAssertTrue(confirm.isHittable)
        if status.exists { XCTAssertEqual(status.label, before) }
        guard confirm.isHittable else { return }
        confirm.tap()
        let sent = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".* delete=[1-9][0-9]* .*"), object: status)
        let observedDELETE = XCTWaiter.wait(for: [sent], timeout: 8) == .completed
        XCTAssertTrue(observedDELETE, "ACTION_OBSERVATION: real DELETE must occur after confirmation before receipt scrolling")
        guard observedDELETE else {
            capture(app, name: "c11-root-delete401-no-http-after-confirmation")
            return
        }
        let receipt = element("meal-record.saved", in: app)
        // The actual saved row is a grouped StaticText with this inherited
        // identifier and full caption/value label (observed in PATCH R5/R6).
        let officialKcal = app.staticTexts.matching(identifier: "meal-record.saved").matching(
            NSPredicate(format: "label == %@", "Consumo do dia salvo, 0 kcal")
        ).element
        for _ in 0..<6 {
            if receipt.exists && officialKcal.isHittable { break }
            form.swipeDown()
        }
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        let savedRows = app.staticTexts.matching(identifier: "meal-record.saved").allElementsBoundByIndex
        for row in savedRows {
            print("C11_DELETE_RECEIPT_AX type=\(row.elementType.rawValue) id=\(row.identifier) label=\(row.label) hittable=\(row.isHittable) frame=\(row.frame)")
        }
        XCTAssertTrue(officialKcal.exists)
        XCTAssertTrue(officialKcal.isHittable,
            "The deleted receipt's official zero must be visible, not only in the offscreen AX tree")
        for id in ["meal-record.failure", "meal-record.read-failure", "meal-record.recovery.notice", "meal-record.refresh"] {
            XCTAssertFalse(element(id, in: app).exists)
        }
        capture(app, name: "c11-root-delete401-confirmed-official-zero")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("screen.history", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("history.empty", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("history.meal.\(rowID)", in: app).exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("screen.hoje", in: app).waitForExistence(timeout: 5))
        let consumed = element("today.energy.consumed", in: app)
        XCTAssertTrue(consumed.waitForExistence(timeout: 5))
        // Today calories are integers. This boundary excludes the old100,
        // unlike contains("0"), which would accept an unchanged100kcal.
        let zeroPattern = ".*(?<![0-9])0 kcal.*"
        wait(for: [expectation(for: NSPredicate(format: "label MATCHES %@", zeroPattern), evaluatedWith: consumed)], timeout: 5)
        XCTAssertNotNil(consumed.label.range(of: "(?<![0-9])0 kcal", options: .regularExpression))
        let after = "C11 delete-401-200: get=1 bind=1 refresh=1 blocked=0 delete=2 sameLogical=1 bearerChanged=1 keys=1 today=2 history=2 commits=1"
        wait(for: [expectation(for: NSPredicate(format: "label == %@", after), evaluatedWith: status)], timeout: 5)
        XCTAssertEqual(status.label, after,
            "Exactly two DELETE attempts share one command/key and one real refresh; official confirmation reloads both real Models")
        capture(app, name: "c11-root-delete401-empty-history-today-zero")
    }

    func testRealRootSecondGET401EndsWithoutThirdRequestAndKeepsVisibleReadOnlyHistoryData() throws {
        let app = try launchFixture("--ui-testing-c11-root-get-401-401", selection: "get-401-401")
        try openActualHistoryRow(in: app)
        let detail = element("screen.meal-record", in: app)
        let entered = detail.waitForExistence(timeout: 8)
        XCTAssertTrue(entered, "CHARACTERIZATION: terminal second HTTP401 remains on the real admitted C11 destination")
        guard entered else { capture(app, name: "c11-root-second401-destination"); return }
        let warning = element("meal-record.read-failure", in: app)
        let failedRead = warning.waitForExistence(timeout: 8)
        XCTAssertTrue(failedRead, "The actual repository/Model must publish its completed read failure after two real HTTP401 responses")
        guard failedRead else { capture(app, name: "c11-root-second401-read-not-terminal"); return }
        let status = element("c11.fixture.status", in: app)
        let expected = "C11 get-401-401: get=2 bind=1 refresh=1 blocked=0 sameLogical=1 bearerChanged=1"
        wait(for: [expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: status)], timeout: 5)
        XCTAssertEqual(status.label, expected,
            "Two actual GETs and one real refresh retain the logical request, change bearer and stop without a third automatic attempt")
        let localRows = app.staticTexts.matching(identifier: "meal-record.local-row")
        let food = localRows.matching(NSPredicate(format: "label == %@", "Synthetic C11 confirmed food")).element
        let quantity = localRows.matching(NSPredicate(format: "label == %@", "Quantidade: 50 g")).element
        let energy = localRows.matching(NSPredicate(format: "label == %@", "Energia: 100 kcal")).element
        XCTAssertTrue(element("meal-record.local-row", in: app).exists)
        for row in localRows.allElementsBoundByIndex {
            print("C11_SECOND401_LOCAL_AX type=\(row.elementType.rawValue) id=\(row.identifier) label=\(row.label) hittable=\(row.isHittable) frame=\(row.frame)")
        }
        for value in [food, quantity, energy] {
            let valueExists = value.exists
            XCTAssertTrue(valueExists, "History's own local food/quantity/energy must remain in the real read-only rows")
            guard valueExists else {
                capture(app, name: "c11-root-second401-local-value-not-mounted")
                return
            }
            XCTAssertTrue(value.isHittable, "The preserved local values must be visibly reachable, not only in offscreen AX")
        }
        let form = app.collectionViews["screen.meal-record"]
        let retry = app.buttons["meal-record.retry-read"]
        func failureControlsFullyVisible() -> Bool {
            guard warning.exists, retry.exists, status.exists else { return false }
            let viewport = form.frame.intersection(app.frame)
            let notice = warning.frame
            let button = retry.frame
            let diagnostic = status.frame
            return !viewport.isNull && viewport.width > 0 && viewport.height > 0
                && notice.width > 0 && notice.height > 0 && button.width > 0 && button.height >= 44
                && diagnostic.width > 0 && diagnostic.height > 0
                && viewport.contains(notice) && viewport.contains(button)
                && !notice.intersects(diagnostic) && !button.intersects(diagnostic)
                && warning.isHittable && retry.isEnabled && retry.isHittable
        }
        for _ in 0..<6 {
            if !warning.exists || !retry.exists { form.swipeUp(); continue }
            if failureControlsFullyVisible() { break }
            form.swipeUp()
        }
        XCTAssertTrue(warning.exists && retry.exists,
            "SETUP_VISIBLE_CONTROL: actual warning/retry rows must mount before frame or trait inspection")
        guard warning.exists && retry.exists else {
            capture(app, name: "c11-root-second401-controls-not-mounted")
            return
        }
        let controlsReady = failureControlsFullyVisible()
        XCTAssertTrue(controlsReady,
            "The whole warning and accessible retry button must fit the actual Form/app viewport clear of diagnostics")
        XCTAssertEqual(warning.label,
            "Não foi possível abrir este registro para alteração agora. Estes são os dados que já estavam no app.")
        XCTAssertEqual(retry.label, "Tentar abrir novamente")
        XCTAssertTrue(retry.isEnabled && retry.isHittable)
        print("C11_SECOND401_TERMINAL_AX app=\(app.frame) form=\(form.frame) warning=\(warning.frame) retry=\(retry.frame) diagnostic=\(status.frame) label=\(warning.label) status=\(status.label)")
        capture(app, name: "c11-root-second401-visible-local-data-warning-and-retry")
        guard controlsReady else { return }
        for id in ["meal-record.field.name", "meal-record.field.quantity", "meal-record.field.kcal",
                   "meal-record.patch", "meal-record.delete", "meal-record.saved", "meal-record.failure",
                   "meal-record.recovery.notice", "meal-record.recovery.action", "meal-record.progress",
                   "screen.history.meal-detail", "screen.auth.sign-in", "screen.auth.sign-up"] {
            XCTAssertFalse(element(id, in: app).exists,
                "A terminal failed read preserves protected local data without exposing editing, a mutation result or recovery authority: \(id)")
        }
        // Do not tap retry: this case characterizes the automatic terminal load,
        // not a subsequent explicit read. Terminal visible controls end the wait.
        XCTAssertEqual(status.label, expected)
        XCTAssertTrue(detail.exists)
        capture(app, name: "c11-root-second401-no-third-http-no-false-recovery")
    }

    func testRealRootManualReadRetryAfterSecond401UsesNewReadIDAndCurrentBearerForOfficialGET() throws {
        let app = try launchFixture("--ui-testing-c11-root-get-401-401-retry-200", selection: "get-401-401-retry-200")
        try openActualHistoryRow(in: app)
        let detail = element("screen.meal-record", in: app)
        let entered = detail.waitForExistence(timeout: 8)
        XCTAssertTrue(entered, "CHARACTERIZATION: manual retry must use the actual admitted Root/History/C11 destination")
        guard entered else { capture(app, name: "c11-root-manual-read-retry-destination"); return }
        let warning = element("meal-record.read-failure", in: app)
        let terminalRead = warning.waitForExistence(timeout: 8)
        XCTAssertTrue(terminalRead, "The first read must terminate after two actual HTTP401 responses before an explicit retry")
        guard terminalRead else { capture(app, name: "c11-root-manual-read-retry-not-terminal"); return }
        let status = element("c11.fixture.status", in: app)
        let before = "C11 get-401-401-retry-200: get=2 bind=1 refresh=1 blocked=0 sameLogical=1 bearerChanged=1 newReadID=0 currentBearerSame=0 bodyAbsent=0 keyAbsent=0"
        wait(for: [expectation(for: NSPredicate(format: "label == %@", before), evaluatedWith: status)], timeout: 5)
        XCTAssertEqual(status.label, before)
        guard status.label == before else { capture(app, name: "c11-root-manual-read-retry-before-counts"); return }
        let localRows = app.staticTexts.matching(identifier: "meal-record.local-row")
        for label in ["Synthetic C11 confirmed food", "Quantidade: 50 g", "Energia: 100 kcal"] {
            let value = localRows.matching(NSPredicate(format: "label == %@", label)).element
            let present = value.exists
            XCTAssertTrue(present, "The terminal read preserves History's own local food/quantity/energy")
            guard present else { capture(app, name: "c11-root-manual-read-retry-local-row-not-mounted"); return }
            XCTAssertTrue(value.isHittable)
        }
        for id in ["meal-record.field.name", "meal-record.field.quantity", "meal-record.field.kcal",
                   "meal-record.patch", "meal-record.delete", "meal-record.saved", "meal-record.failure",
                   "meal-record.recovery.notice", "meal-record.recovery.action", "meal-record.progress",
                   "screen.history.meal-detail", "screen.auth.sign-in", "screen.auth.sign-up"] {
            XCTAssertFalse(element(id, in: app).exists,
                "A terminal read must not invent official editing, a mutation result or recovery authority: \(id)")
        }
        let form = app.collectionViews["screen.meal-record"]
        let retry = app.buttons["meal-record.retry-read"]
        func terminalControlsFullyVisible() -> Bool {
            guard warning.exists, retry.exists, status.exists else { return false }
            let viewport = form.frame.intersection(app.frame)
            let notice = warning.frame, button = retry.frame, diagnostic = status.frame
            return !viewport.isNull && viewport.width > 0 && viewport.height > 0
                && notice.width > 0 && notice.height > 0 && button.width >= 44 && button.height >= 44
                && diagnostic.width > 0 && diagnostic.height > 0
                && viewport.contains(notice) && viewport.contains(button)
                && !notice.intersects(diagnostic) && !button.intersects(diagnostic)
                && warning.isHittable && retry.isEnabled && retry.isHittable
        }
        for _ in 0..<6 {
            if !warning.exists || !retry.exists { form.swipeUp(); continue }
            if terminalControlsFullyVisible() { break }
            form.swipeUp()
        }
        XCTAssertTrue(warning.exists && retry.exists, "SETUP_VISIBLE_CONTROL: mount the actual warning/retry before querying frames")
        guard warning.exists && retry.exists else { capture(app, name: "c11-root-manual-read-retry-controls-not-mounted"); return }
        let retryReady = terminalControlsFullyVisible()
        XCTAssertTrue(retryReady, "The entire enabled retry action must fit Form/app clear of diagnostics before a normal tap")
        XCTAssertEqual(warning.label, "Não foi possível abrir este registro para alteração agora. Estes são os dados que já estavam no app.")
        XCTAssertEqual(retry.label, "Tentar abrir novamente")
        XCTAssertEqual(status.label, before, "Re-read GET2 immediately before the single explicit retry")
        capture(app, name: "c11-root-manual-read-retry-terminal-full-button-before-tap")
        guard retryReady, status.label == before else { return }
        // Exactly one real user action. No driver/model setter, forced coordinate,
        // lease/grant diagnostic or replay of a mutation command.
        retry.tap()
        let admitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@",
            "C11 get-401-401-retry-200: get=3 "), object: status)
        let observedGET3 = XCTWaiter.wait(for: [admitted], timeout: 8) == .completed
        XCTAssertTrue(observedGET3, "ACTION_OBSERVATION: the explicit retry must issue the third actual GET")
        guard observedGET3 else { capture(app, name: "c11-root-manual-read-retry-no-third-get"); return }
        let name = app.textFields["meal-record.field.name"]
        let quantity = app.textFields["meal-record.field.quantity"]
        for _ in 0..<6 {
            if name.exists && quantity.exists && name.isHittable && quantity.isHittable { break }
            form.swipeDown()
        }
        XCTAssertTrue(name.exists && quantity.exists, "The official third GET must reach the actual Form's own field identifiers")
        guard name.exists && quantity.exists else { capture(app, name: "c11-root-manual-read-retry-official-fields-not-mounted"); return }
        XCTAssertTrue(name.isHittable && quantity.isHittable)
        XCTAssertEqual(name.value as? String, "Synthetic C11 confirmed food")
        XCTAssertEqual(quantity.value as? String, "50")
        let kcalOverride = app.textFields["meal-record.field.kcal"]
        for _ in 0..<6 {
            if kcalOverride.exists { break }
            form.swipeUp()
        }
        XCTAssertTrue(kcalOverride.exists, "SETUP: mount the existing manual override row before reading its value")
        guard kcalOverride.exists else { capture(app, name: "c11-root-manual-read-retry-override-row-not-mounted"); return }
        let placeholder = kcalOverride.placeholderValue
        XCTAssertNotNil(placeholder)
        XCTAssertEqual(placeholder, "Novo total de calorias (opcional)")
        guard let placeholder, placeholder == "Novo total de calorias (opcional)" else {
            capture(app, name: "c11-root-manual-read-retry-override-placeholder-unexpected")
            return
        }
        let currentValue = kcalOverride.value as? String
        XCTAssertNotNil(currentValue, "The mounted field must expose a string AX value before interpreting empty state")
        XCTAssertTrue(currentValue == "" || currentValue == placeholder,
            "The official response preserves the existing blank manual calorie override")
        for id in ["meal-record.read-failure", "meal-record.retry-read", "meal-record.progress", "meal-record.saved",
                   "meal-record.failure", "meal-record.recovery.notice", "meal-record.recovery.action",
                   "screen.history.meal-detail", "screen.auth.sign-in", "screen.auth.sign-up"] {
            XCTAssertFalse(element(id, in: app).exists,
                "Completed official read must remove the retry warning without inventing mutation or auth recovery: \(id)")
        }
        let after = "C11 get-401-401-retry-200: get=3 bind=1 refresh=1 blocked=0 sameLogical=1 bearerChanged=1 newReadID=1 currentBearerSame=1 bodyAbsent=1 keyAbsent=1"
        wait(for: [expectation(for: NSPredicate(format: "label == %@", after), evaluatedWith: status)], timeout: 5)
        XCTAssertEqual(status.label, after,
            "A new read ID uses the current refreshed bearer with no body/key and no extra refresh/source binding")
        XCTAssertTrue(detail.exists)
        capture(app, name: "c11-root-manual-read-retry-official-third-get")
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
