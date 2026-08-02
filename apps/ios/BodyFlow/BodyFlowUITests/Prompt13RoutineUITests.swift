import XCTest

final class Prompt13RoutineUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSupplementTakenUsesExactOccurrence() {
        let app = launchRoutine()
        openSupplement(app)
        app.buttons["routine.action.taken"].tap()
        XCTAssertTrue(app.buttons["routine.action.submit"].waitForExistence(timeout: 3))
        app.buttons["routine.action.submit"].tap()
        XCTAssertTrue(app.staticTexts["taken"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMedicationSkippedUsesExactOccurrence() {
        let app = launchRoutine()
        openMedication(app)
        app.buttons["routine.action.skipped"].tap()
        XCTAssertTrue(app.buttons["routine.action.submit"].waitForExistence(timeout: 3))
        app.buttons["routine.action.submit"].tap()
        XCTAssertTrue(app.staticTexts["skipped"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSnoozeOffers15_30_60AndCustom() {
        let app = launchRoutine()
        openSupplement(app)
        app.buttons["routine.action.snoozed"].tap()
        XCTAssertTrue(app.buttons["routine.snooze.15"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["routine.snooze.30"].exists)
        XCTAssertTrue(app.buttons["routine.snooze.60"].exists)
        XCTAssertTrue(app.buttons["routine.snooze.custom"].exists)
    }

    @MainActor
    func testCrossingDateSnoozeIsUnavailable() {
        let app = BodyFlowUITestSupport(testCase: self).launch(
            scenario: .loaded,
            additionalArguments: ["--ui-testing-routine-crossing-date"]
        )
        openSupplement(app)
        app.buttons["routine.action.snoozed"].tap()
        XCTAssertFalse(app.buttons["routine.snooze.60"].isEnabled)
    }

    @MainActor
    func testRoutineHistoryLoadMoreAppendsNextPage() {
        let app = launchRoutine()
        openSupplement(app)
        app.buttons["routine.history"].tap()
        XCTAssertTrue(app.buttons["routine.history.load-more"].waitForExistence(timeout: 3))
        app.buttons["routine.history.load-more"].tap()
        XCTAssertFalse(app.buttons["routine.history.load-more"].exists)
    }

    @MainActor
    func testUnavailableRoutineActionShowsNoSuccess() {
        let app = BodyFlowUITestSupport(testCase: self).launch(
            scenario: .routineActionUnavailable
        )
        openSupplement(app)
        app.buttons["routine.action.taken"].tap()
        app.buttons["routine.action.submit"].tap()
        XCTAssertTrue(app.staticTexts["Indisponível nesta versão"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["taken"].exists)
    }

    @MainActor
    func testConflictSheetKeepsRetryUntilDismissAfterTerminalRefresh() {
        let app = BodyFlowUITestSupport(testCase: self).launch(
            scenario: .routineConflictOnce
        )
        openSupplement(app)
        app.buttons["routine.action.taken"].tap()
        XCTAssertTrue(app.buttons["routine.action.submit"].waitForExistence(timeout: 3))
        app.buttons["routine.action.submit"].tap()

        XCTAssertTrue(
            app.staticTexts["Não foi possível concluir. Tente novamente."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Tentar novamente"].waitForExistence(timeout: 3))

        app.buttons["Fechar"].tap()
        XCTAssertFalse(app.buttons["routine.action.taken"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRoutineConflictRetryHasMinimumTapTarget() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .routineConflictOnce)
        openSupplement(app)
        app.buttons["routine.action.taken"].tap()
        app.buttons["routine.action.submit"].tap()

        XCTAssertTrue(
            app.buttons["Tentar novamente"].waitForExistence(timeout: 5)
        )
        let retry = app.buttons["routine.mutation.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(retry)
    }

    @MainActor
    func testRoutineActionAndSubmitControlsHaveMinimumTapTargets() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = launchRoutine()
        openSupplement(app)

        for identifier in [
            "routine.action.taken",
            "routine.action.snoozed",
            "routine.action.skipped",
        ] {
            let action = app.buttons[identifier]
            XCTAssertTrue(action.waitForExistence(timeout: 3))
            support.assertMinimumTapTarget(action)
        }

        app.buttons["routine.action.taken"].tap()
        let submit = app.buttons["routine.action.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(submit)
    }

    @MainActor
    func testRoutineSnoozeControlsHaveMinimumTapTargets() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = launchRoutine()
        openSupplement(app)
        app.buttons["routine.action.snoozed"].tap()

        for identifier in [
            "routine.snooze.15",
            "routine.snooze.30",
            "routine.snooze.60",
            "routine.snooze.custom",
        ] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 3))
            support.assertMinimumTapTarget(control)
        }
        let customTime = app.datePickers["routine.snooze.custom-time"]
        XCTAssertTrue(customTime.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(customTime)
    }

    @MainActor
    func testSupplementAndMedicationListsAreReachable() {
        let app = launchRoutine()
        XCTAssertTrue(app.buttons["routine.supplement-1"].waitForExistence(timeout: 3))

        let supplements = app.buttons["routine.list.supplement"]
        XCTAssertTrue(supplements.waitForExistence(timeout: 3))
        supplements.tap()
        XCTAssertTrue(app.navigationBars["Suplementos"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["routine.supplement-1"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let medications = app.buttons["routine.list.medication"]
        XCTAssertTrue(medications.waitForExistence(timeout: 3))
        medications.tap()
        XCTAssertTrue(app.navigationBars["Medicamentos"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["routine.medication-1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testListDetailsExposeActionsForSupplementAndMedication() {
        let app = launchRoutine()
        XCTAssertTrue(app.buttons["routine.supplement-1"].waitForExistence(timeout: 3))

        app.buttons["routine.list.supplement"].tap()
        XCTAssertTrue(app.buttons["routine.supplement-1"].waitForExistence(timeout: 3))
        app.buttons["routine.supplement-1"].tap()
        assertRoutineActions(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["routine.list.medication"].waitForExistence(timeout: 3))
        app.buttons["routine.list.medication"].tap()
        XCTAssertTrue(app.buttons["routine.medication-1"].waitForExistence(timeout: 3))
        app.buttons["routine.medication-1"].tap()
        assertRoutineActions(app)
    }

    @MainActor
    private func launchRoutine() -> XCUIApplication {
        BodyFlowUITestSupport(testCase: self).launch(scenario: .loaded)
    }

    @MainActor
    private func openSupplement(_ app: XCUIApplication) {
        let button = app.buttons["routine.supplement-1"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    @MainActor
    private func openMedication(_ app: XCUIApplication) {
        let button = app.buttons["routine.medication-1"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    @MainActor
    private func assertRoutineActions(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["routine.action.taken"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["routine.action.snoozed"].exists)
        XCTAssertTrue(app.buttons["routine.action.skipped"].exists)
    }
}
