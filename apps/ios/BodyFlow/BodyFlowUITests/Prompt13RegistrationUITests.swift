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
        let support = BodyFlowUITestSupport(testCase: self)
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
        support.captureEvidence(named: "02-meal-proposal-edit.png", of: app)

        app.buttons["registration.proposal.edit.save"].tap()

        XCTAssertTrue(app.staticTexts["Substituição completa predefinida"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["512 kcal"].exists)
        XCTAssertFalse(app.staticTexts["Refeição textual de demonstração"].exists)
    }

    @MainActor
    func testMealProposalActionsHaveMinimumTapTargets() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = reachTextProposal(scenario: .loaded)

        for identifier in [
            "registration.proposal.edit",
            "registration.proposal.confirm",
            "registration.proposal.cancel",
        ] {
            let action = app.buttons[identifier]
            XCTAssertTrue(action.waitForExistence(timeout: 3))
            support.assertMinimumTapTarget(action)
        }
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
    func testMealMutationRetryHasMinimumTapTarget() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = launchAndOpenMeal(scenario: .registrationErrorOnce)
        app.buttons["registration.meal.source.text"].tap()
        app.buttons["registration.meal.detect"].tap()

        let retry = app.buttons["registration.mutation.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(retry)
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
    func testWorkoutReachesProposalBeforeConfirmation() {
        let app = launchAndOpenWorkout(scenario: .loaded)
        let support = BodyFlowUITestSupport(testCase: self)

        XCTAssertTrue(
            app.textFields["registration.workout.type"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.textFields["registration.workout.duration"].exists)
        XCTAssertTrue(element("registration.workout.intensity", in: app).exists)
        XCTAssertTrue(element("registration.workout.performed-at", in: app).exists)
        support.assertMinimumTapTarget(app.textFields["registration.workout.type"])
        support.assertMinimumTapTarget(app.textFields["registration.workout.duration"])
        support.assertMinimumTapTarget(element("registration.workout.intensity", in: app))
        support.assertMinimumTapTarget(element("registration.workout.performed-at", in: app))
        let propose = app.buttons["registration.workout.propose"]
        support.assertMinimumTapTarget(propose)
        propose.tap()

        XCTAssertTrue(
            element("registration.proposal", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["registration.proposal.confirm"].exists)
        XCTAssertFalse(element("registration.proposal.confirmed", in: app).exists)
        support.assertMinimumTapTarget(app.buttons["registration.proposal.edit"])
        support.assertMinimumTapTarget(app.buttons["registration.proposal.confirm"])
        support.assertMinimumTapTarget(app.buttons["registration.proposal.cancel"])
        support.captureEvidence(named: "04-workout-proposal.png", of: app)
    }

    @MainActor
    func testWorkoutDisplaysProviderCalories() {
        let app = reachWorkoutProposal(scenario: .loaded)

        XCTAssertTrue(app.staticTexts["333 kcal"].exists)
        XCTAssertFalse(app.staticTexts["334 kcal"].exists)
    }

    @MainActor
    func testConfirmedWorkoutIsReadOnly() {
        let app = reachWorkoutProposal(scenario: .loaded)
        app.buttons["registration.proposal.confirm"].tap()

        XCTAssertTrue(
            element("registration.proposal.confirmed", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Treino confirmado"].exists)
        XCTAssertFalse(app.buttons["registration.proposal.edit"].exists)
        XCTAssertFalse(app.buttons["registration.proposal.confirm"].exists)
        XCTAssertFalse(app.buttons["registration.proposal.cancel"].exists)
    }

    @MainActor
    func testUnavailableWorkoutShowsNoSuccess() {
        let app = launchAndOpenWorkout(scenario: .unavailable)
        XCTAssertTrue(
            app.buttons["registration.workout.propose"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["registration.workout.propose"].tap()

        XCTAssertTrue(
            app.staticTexts["Indisponível nesta versão"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(element("registration.proposal", in: app).exists)
        XCTAssertFalse(element("registration.proposal.confirmed", in: app).exists)
        XCTAssertFalse(app.buttons["registration.mutation.retry"].exists)
    }

    @MainActor
    func testWorkoutControlsHavePersistentVisibleAndAccessibleLabels() {
        let app = launchAndOpenWorkout(scenario: .loaded)

        XCTAssertTrue(app.staticTexts["Tipo"].exists)
        XCTAssertTrue(app.staticTexts["Duração (min)"].exists)
        XCTAssertTrue(app.staticTexts["Intensidade"].exists)
        XCTAssertTrue(app.staticTexts["Data e hora realizada"].exists)
        XCTAssertEqual(app.textFields["registration.workout.type"].label, "Tipo")
        XCTAssertEqual(
            app.textFields["registration.workout.duration"].label,
            "Duração (min)"
        )
        XCTAssertEqual(
            element("registration.workout.intensity", in: app).label,
            "Intensidade"
        )
        XCTAssertEqual(
            element("registration.workout.performed-at", in: app).label,
            "Data e hora realizada"
        )
    }

    @MainActor
    func testHydrationQuickAndCustomFlowsUseCompleteRefresh() {
        let app = launchAndOpenHydration(scenario: .loaded)
        let support = BodyFlowUITestSupport(testCase: self)

        let quick = app.buttons["registration.hydration.quick.250"]
        XCTAssertTrue(quick.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["registration.hydration.quick.500"].exists)
        XCTAssertTrue(app.buttons["registration.hydration.quick.750"].exists)
        XCTAssertTrue(app.textFields["registration.hydration.custom"].exists)
        XCTAssertTrue(element("registration.hydration.occurred-at", in: app).exists)
        support.assertMinimumTapTarget(quick)
        support.assertMinimumTapTarget(app.buttons["registration.hydration.submit"])

        quick.tap()
        app.buttons["registration.hydration.submit"].tap()
        XCTAssertTrue(app.staticTexts["Hidratação registrada."].waitForExistence(timeout: 5))

        app.buttons["sheet.fechar"].tap()
        app.tabBars.buttons["tab.hoje"].tap()
        XCTAssertTrue(element("today.hydration", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("today.hydration", in: app).value as? String == "2.111 ml; meta Indisponível")

        app.tabBars.buttons["tab.registrar"].tap()
        app.buttons["register.hidratacao"].tap()
        let custom = app.textFields["registration.hydration.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        custom.tap()
        custom.typeText("500")
        app.buttons["registration.hydration.submit"].tap()
        XCTAssertTrue(app.staticTexts["Hidratação registrada."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHydrationMutationRetryHasMinimumTapTarget() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = launchAndOpenHydration(scenario: .registrationErrorOnce)
        app.buttons["registration.hydration.quick.250"].tap()
        app.buttons["registration.hydration.submit"].tap()

        let retry = app.buttons["registration.mutation.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(retry)
        retry.tap()
        XCTAssertTrue(
            app.staticTexts["Hidratação registrada."]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testHydrationAndWeightShowExactBoundaryValidation() {
        let hydration = launchAndOpenHydration(scenario: .loaded)
        let custom = hydration.textFields["registration.hydration.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        custom.tap()
        custom.typeText("0")
        hydration.buttons["registration.hydration.submit"].tap()
        XCTAssertTrue(
            hydration.staticTexts["Informe um valor inteiro entre 1 e 5.000 ml."]
                .waitForExistence(timeout: 5)
        )

        let weight = launchAndOpenWeight(scenario: .loaded)
        let value = weight.textFields["registration.weight.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        value.tap()
        value.typeText("29.99")
        weight.buttons["registration.weight.submit"].tap()
        XCTAssertTrue(
            weight.staticTexts["Informe um valor entre 30 e 300 kg."]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testWeightReceiptIsClearlyLocal() {
        let app = launchAndOpenWeight(scenario: .loaded)
        let support = BodyFlowUITestSupport(testCase: self)
        let value = app.textFields["registration.weight.value"]

        XCTAssertTrue(value.waitForExistence(timeout: 3))
        XCTAssertTrue(element("registration.weight.recorded-at", in: app).exists)
        support.assertMinimumTapTarget(value)
        support.assertMinimumTapTarget(app.buttons["registration.weight.submit"])
        value.tap()
        value.typeText("78.4")
        app.buttons["registration.weight.submit"].tap()

        let receipt = element("registration.weight.demo-receipt", in: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demonstração local; não sincronizado"].exists)
    }

    @MainActor
    func testHydrationSuccessRefreshesTodayBeforeRoutineDetail() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = launchAndOpenHydration(scenario: .loaded)

        let quick = app.buttons["registration.hydration.quick.250"]
        XCTAssertTrue(quick.waitForExistence(timeout: 3))
        quick.tap()
        let submit = app.buttons["registration.hydration.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        submit.tap()
        XCTAssertTrue(
            app.staticTexts["Hidratação registrada."]
                .waitForExistence(timeout: 5)
        )

        app.buttons["sheet.fechar"].tap()
        let today = app.tabBars.buttons["tab.hoje"]
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        today.tap()
        let hydration = element("today.hydration", in: app)
        XCTAssertTrue(hydration.waitForExistence(timeout: 5))
        XCTAssertEqual(
            hydration.value as? String,
            "2.111 ml; meta Indisponível"
        )

        let routine = app.buttons["routine.supplement-1"]
        XCTAssertTrue(routine.waitForExistence(timeout: 5))
        reveal(routine, in: app)
        XCTAssertTrue(routine.isHittable)
        routine.tap()
        XCTAssertTrue(
            app.buttons["routine.action.snoozed"]
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(named: "05-hydration-routine.png", of: app)
    }

    @MainActor
    func testWeightValidationClearsPreviousLocalReceipt() {
        let app = launchAndOpenWeight(scenario: .loaded)
        let value = app.textFields["registration.weight.value"]

        XCTAssertTrue(value.waitForExistence(timeout: 3))
        value.tap()
        value.typeText("78.4")
        app.buttons["registration.weight.submit"].tap()
        XCTAssertTrue(
            element("registration.weight.demo-receipt", in: app)
                .waitForExistence(timeout: 5)
        )

        value.tap()
        value.typeText("29.99")
        app.buttons["registration.weight.submit"].tap()

        XCTAssertTrue(
            app.staticTexts["Informe um valor entre 30 e 300 kg."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(element("registration.weight.demo-receipt", in: app).exists)
        XCTAssertFalse(app.staticTexts["Demonstração local; não sincronizado"].exists)
    }

    @MainActor
    func testUnavailableHydrationAndWeightNeverShowSuccess() {
        let hydration = launchAndOpenHydration(scenario: .unavailable)
        XCTAssertTrue(
            hydration.buttons["registration.hydration.submit"]
                .waitForExistence(timeout: 3)
        )
        hydration.buttons["registration.hydration.quick.250"].tap()
        hydration.buttons["registration.hydration.submit"].tap()
        XCTAssertTrue(
            hydration.staticTexts["Indisponível nesta versão"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(hydration.staticTexts["Hidratação registrada."].exists)

        let weight = launchAndOpenWeight(scenario: .unavailable)
        XCTAssertTrue(
            weight.buttons["registration.weight.submit"].waitForExistence(timeout: 3)
        )
        let weightValue = weight.textFields["registration.weight.value"]
        weightValue.tap()
        weightValue.typeText("78.4")
        weight.buttons["registration.weight.submit"].tap()
        XCTAssertTrue(
            weight.staticTexts["Indisponível nesta versão"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(element("registration.weight.demo-receipt", in: weight).exists)
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
    private func reachWorkoutProposal(
        scenario: Prompt13UITestScenario
    ) -> XCUIApplication {
        let app = launchAndOpenWorkout(scenario: scenario)
        let propose = app.buttons["registration.workout.propose"]
        XCTAssertTrue(propose.waitForExistence(timeout: 3))
        propose.tap()
        XCTAssertTrue(
            element("registration.proposal", in: app).waitForExistence(timeout: 5)
        )
        return app
    }

    @MainActor
    private func launchAndOpenWorkout(
        scenario: Prompt13UITestScenario
    ) -> XCUIApplication {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: scenario)
        let registerTab = app.tabBars.buttons["tab.registrar"]
        XCTAssertTrue(registerTab.waitForExistence(timeout: 5))
        registerTab.tap()

        let workout = app.buttons["register.treino"]
        XCTAssertTrue(workout.waitForExistence(timeout: 3))
        workout.tap()
        XCTAssertTrue(
            element("sheet.registrar.treino", in: app)
                .waitForExistence(timeout: 3)
        )
        return app
    }

    @MainActor
    private func launchAndOpenHydration(
        scenario: Prompt13UITestScenario
    ) -> XCUIApplication {
        let app = launchRegistration(scenario: scenario)
        let hydration = app.buttons["register.hidratacao"]
        XCTAssertTrue(hydration.waitForExistence(timeout: 3))
        hydration.tap()
        XCTAssertTrue(
            element("sheet.registrar.hidratacao", in: app)
                .waitForExistence(timeout: 3)
        )
        return app
    }

    @MainActor
    private func launchAndOpenWeight(
        scenario: Prompt13UITestScenario
    ) -> XCUIApplication {
        let app = launchRegistration(scenario: scenario)
        let weight = app.buttons["register.peso"]
        XCTAssertTrue(weight.waitForExistence(timeout: 3))
        weight.tap()
        XCTAssertTrue(
            element("sheet.registrar.peso", in: app)
                .waitForExistence(timeout: 3)
        )
        return app
    }

    @MainActor
    private func launchRegistration(
        scenario: Prompt13UITestScenario
    ) -> XCUIApplication {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: scenario)
        let registerTab = app.tabBars.buttons["tab.registrar"]
        XCTAssertTrue(registerTab.waitForExistence(timeout: 5))
        registerTab.tap()
        return app
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
}
