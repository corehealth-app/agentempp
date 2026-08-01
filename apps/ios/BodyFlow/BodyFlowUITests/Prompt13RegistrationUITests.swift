import XCTest

final class Prompt13RegistrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTextMealReachesProposalBeforeConfirmation() {
        let app = launchAndOpenMeal(scenario: .loaded)

        let textSource = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(textSource.waitForExistence(timeout: 3))
        textSource.tap()

        let draft = app.textFields["registration.meal.text"]
        XCTAssertTrue(draft.waitForExistence(timeout: 3))
        XCTAssertFalse(draft.value as? String == "")
        app.buttons["registration.meal.detect"].tap()

        XCTAssertTrue(element("registration.proposal", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["389 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Valores sintéticos; confirme antes de registrar."].exists)
        XCTAssertTrue(app.buttons["registration.proposal.confirm"].exists)
        XCTAssertFalse(element("registration.proposal.confirmed", in: app).exists)
        XCTAssertTrue(
            element("registration.operation.summary", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["Proposta criada. Revise antes de confirmar."]
                .exists
        )
    }

    @MainActor
    func testPhotoDemonstrationReachesProposalWithoutPermission() {
        let app = launchAndOpenMeal(scenario: .loaded)

        let photo = app.buttons["registration.meal.source.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3))
        photo.tap()

        XCTAssertTrue(element("registration.meal.photo", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["registration.meal.detect"].tap()

        XCTAssertTrue(element("registration.proposal", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.buttons["registration.proposal.confirm"].exists)
    }

    @MainActor
    func testAudioDemonstrationReachesProposalWithoutPermission() {
        let app = launchAndOpenMeal(scenario: .loaded)

        let audio = app.buttons["registration.meal.source.audio"]
        XCTAssertTrue(audio.waitForExistence(timeout: 3))
        audio.tap()

        XCTAssertTrue(element("registration.meal.audio", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["registration.meal.detect"].tap()

        XCTAssertTrue(element("registration.proposal", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.buttons["registration.proposal.confirm"].exists)
    }

    @MainActor
    func testPendingMealEditReplacesProposal() {
        let app = reachTextProposal(scenario: .loaded)

        let edit = app.buttons["registration.proposal.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()

        XCTAssertTrue(
            element("registration.proposal.editor", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.textFields["registration.proposal.edit.food-name"].exists)
        XCTAssertTrue(app.textFields["registration.proposal.edit.quantity"].exists)
        XCTAssertTrue(app.textFields["registration.proposal.edit.user-kcal"].exists)
        XCTAssertTrue(app.buttons["registration.proposal.edit.meal-type"].exists)
        XCTAssertTrue(element("registration.proposal.edit.consumed-at", in: app).exists)
        XCTAssertFalse(app.textFields["registration.proposal.edit.protein"].exists)
        XCTAssertFalse(app.textFields["registration.proposal.edit.total"].exists)

        app.buttons["registration.proposal.edit.save"].tap()

        XCTAssertTrue(app.staticTexts["Substituição completa predefinida"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["512 kcal"].exists)
        XCTAssertFalse(app.staticTexts["Refeição textual de demonstração"].exists)
    }

    @MainActor
    func testMealMutationFailurePreservesPendingAndRetries() {
        let app = launchAndOpenMeal(scenario: .registrationErrorOnce)
        app.buttons["registration.meal.source.text"].tap()

        let draft = app.textFields["registration.meal.text"]
        XCTAssertTrue(draft.waitForExistence(timeout: 3))
        let originalDraft = draft.value as? String
        app.buttons["registration.meal.detect"].tap()

        let retry = app.buttons["registration.mutation.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, originalDraft)
        retry.tap()

        XCTAssertTrue(element("registration.proposal", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["389 kcal"].exists)
    }

    @MainActor
    func testConfirmedMealIsReadOnly() {
        let app = reachTextProposal(scenario: .loaded)

        let confirm = app.buttons["registration.proposal.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertTrue(
            element("registration.proposal.confirmed", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Refeição confirmada"].exists)
        XCTAssertFalse(app.buttons["registration.proposal.edit"].exists)
        XCTAssertFalse(app.buttons["registration.proposal.confirm"].exists)
        XCTAssertFalse(app.buttons["registration.proposal.cancel"].exists)
    }

    @MainActor
    func testUnavailableMealShowsVersionMessageWithoutSuccess() {
        let app = launchAndOpenMeal(scenario: .unavailable)
        app.buttons["registration.meal.source.text"].tap()

        XCTAssertTrue(
            app.textFields["registration.meal.text"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["registration.meal.detect"].tap()

        XCTAssertTrue(
            app.staticTexts["Indisponível nesta versão"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(element("registration.proposal", in: app).exists)
        XCTAssertFalse(element("registration.proposal.confirmed", in: app).exists)
        XCTAssertFalse(app.buttons["registration.mutation.retry"].exists)
    }

    @MainActor
    private func reachTextProposal(
        scenario: Prompt13UITestScenario
    ) -> XCUIApplication {
        let app = launchAndOpenMeal(scenario: scenario)
        app.buttons["registration.meal.source.text"].tap()
        XCTAssertTrue(
            app.textFields["registration.meal.text"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["registration.meal.detect"].tap()
        XCTAssertTrue(
            element("registration.proposal", in: app)
                .waitForExistence(timeout: 5)
        )
        return app
    }

    @MainActor
    private func launchAndOpenMeal(
        scenario: Prompt13UITestScenario
    ) -> XCUIApplication {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: scenario)
        let registerTab = app.tabBars.buttons["tab.registrar"]
        XCTAssertTrue(registerTab.waitForExistence(timeout: 5))
        registerTab.tap()

        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 3))
        meal.tap()
        XCTAssertTrue(
            element("sheet.registrar.refeicao", in: app)
                .waitForExistence(timeout: 3)
        )
        return app
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
