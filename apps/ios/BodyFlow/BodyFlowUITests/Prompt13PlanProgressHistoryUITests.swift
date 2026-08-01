import XCTest

final class Prompt13PlanProgressHistoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPlanShowsOnlyStableContractFields() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        app.tabBars.buttons["Plano"].tap()
        XCTAssertTrue(element("screen.plano", in: app).waitForExistence(timeout: 5))

        for label in [
            "Tipo de treino", "Dias por semana", "Equipamentos", "Gerado em",
            "Válido até", "Versão", "Observações", "Tipo de prescrição",
        ] {
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 3))
        }
        XCTAssertFalse(app.staticTexts["Planejadas"].exists)
        XCTAssertFalse(app.staticTexts["Concluídas"].exists)
        XCTAssertFalse(app.staticTexts["opaque"].exists)

        let detail = element("plan.detail", in: app)
        reveal(detail, in: app)
        XCTAssertTrue(detail.exists)
        support.assertMinimumTapTarget(detail)
        detail.tap()
        XCTAssertTrue(
            element("screen.plan.detail", in: app).waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testPlanEmptyDiffersFromUnavailable() {
        let support = BodyFlowUITestSupport(testCase: self)
        let empty = support.launch(scenario: .empty)
        empty.tabBars.buttons["Plano"].tap()
        XCTAssertTrue(empty.staticTexts["Nada por aqui"].waitForExistence(timeout: 5))
        empty.terminate()

        let unavailable = support.launch(scenario: .unavailable)
        unavailable.tabBars.buttons["Plano"].tap()
        XCTAssertTrue(
            unavailable.staticTexts["Indisponível nesta versão"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(element("state.retry", in: unavailable).exists)
    }

    @MainActor
    func testProgressShowsReceivedValues() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        app.tabBars.buttons["Progresso"].tap()
        XCTAssertTrue(
            element("progress.received-values", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["7.420 XP"].exists)
        XCTAssertTrue(app.staticTexts["6.999 kcal"].exists)
        XCTAssertTrue(app.staticTexts["78,4 kg"].exists)
    }

    @MainActor
    func testBlockDetailUsesTodaySnapshot() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        app.tabBars.buttons["Progresso"].tap()
        let detail = element("progress.block.detail", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(detail)
        detail.tap()

        XCTAssertTrue(
            element("screen.block7700.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["2.500 kcal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["user_progress"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["6.999 kcal"].exists)
    }

    @MainActor
    func testUnavailableBlockDoesNotShowZero() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .incomplete)

        app.tabBars.buttons["Progresso"].tap()
        let detail = element("progress.block.detail", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.tap()

        XCTAssertTrue(
            element("screen.block7700.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Indisponível nesta versão"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)
        XCTAssertFalse(app.staticTexts["0%"].exists)
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.exists {
            app.swipeUp()
        }
    }
}
