import XCTest

final class PremiumRegistrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureChoicesExposeLocalSampleProvenance() {
        beginPerformanceConditionEvidence()
        let app = launchRegistration(language: "en-US", dark: false)
        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        open("register.refeicao", sheet: "sheet.registrar.refeicao", app: app)
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)

        let text = app.buttons["registration.meal.source.text"]
        let photo = app.buttons["registration.meal.source.photo"]
        let audio = app.buttons["registration.meal.source.audio"]
        for control in [text, photo, audio] {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            support.assertTarget(control)
        }
        XCTAssertEqual(text.label, "Text")
        XCTAssertEqual(photo.label, "Photo — local sample")
        XCTAssertEqual(audio.label, "Audio — local sample")
        XCTAssertEqual(app.alerts.count, 0)
        support.capture("s4-capture-en-light", app: app)
    }

    @MainActor
    func testProposalPrimaryConfirmAndLongTotalsAX() {
        let app = launchRegistration(
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        open("register.refeicao", sheet: "sheet.registrar.refeicao", app: app)
        app.buttons["registration.meal.source.text"].tap()
        XCTAssertTrue(app.textFields["registration.meal.text"].waitForExistence(timeout: 5))
        app.buttons["registration.meal.detect"].tap()

        XCTAssertTrue(element("registration.proposal", app: app).waitForExistence(timeout: 8))
        let confirm = app.buttons["registration.proposal.confirm"]
        let edit = app.buttons["registration.proposal.edit"]
        let cancel = app.buttons["registration.proposal.cancel"]
        for control in [confirm, edit, cancel] {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            support.assertTarget(control)
        }
        XCTAssertEqual(confirm.label, "Confirm")
        XCTAssertEqual(edit.label, "Edit first item")
        XCTAssertEqual(cancel.label, "Cancel proposal")
        XCTAssertLessThan(confirm.frame.minY, edit.frame.minY)
        XCTAssertLessThan(edit.frame.minY, cancel.frame.minY)
        XCTAssertTrue(app.staticTexts["Values supplied by the service"].exists)
        XCTAssertTrue(app.staticTexts["389 kcal"].exists)
        XCTAssertFalse(app.staticTexts["kcal: 389 g"].exists)
        support.capture("s4-proposal-en-dark-axxxl", app: app)

        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit proposal"].waitForExistence(timeout: 5))
        let mealType = app.buttons["registration.proposal.edit.meal-type"]
        XCTAssertTrue(mealType.waitForExistence(timeout: 5))
        XCTAssertEqual(mealType.label, "Lunch")
    }

    @MainActor
    func testBridgedControlsExpandAtAXXXL() {
        let app = launchRegistration(
            language: "en-US",
            dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        open("register.treino", sheet: "sheet.registrar.treino", app: app)

        let type = app.textFields["registration.workout.type"]
        let date = element("registration.workout.performed-at", app: app)
        let propose = app.buttons["registration.workout.propose"]
        for control in [type, date, propose] {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            support.assertTarget(control)
            XCTAssertGreaterThan(control.frame.height, 48)
        }
        XCTAssertEqual(propose.label, "Propose workout")
        let intensity = app.segmentedControls["registration.workout.intensity"]
        XCTAssertTrue(intensity.waitForExistence(timeout: 5))
        XCTAssertTrue(intensity.buttons["Moderate"].exists)
        support.capture("s4-workout-en-light-axxxl", app: app)
    }

    @MainActor
    private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    @MainActor
    private func launchRegistration(
        language: String,
        dark: Bool,
        category: String = "UICTContentSizeCategoryL"
    ) -> XCUIApplication {
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: language,
            dark: dark,
            category: category
        )
        let tab = app.buttons["tab.registrar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        XCTAssertTrue(element("screen.registrar", app: app).waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func open(_ command: String, sheet: String, app: XCUIApplication) {
        let button = app.buttons[command]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(element(sheet, app: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        support.element(id, app: app)
    }
}
