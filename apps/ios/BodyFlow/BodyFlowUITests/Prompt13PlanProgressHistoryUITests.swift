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
