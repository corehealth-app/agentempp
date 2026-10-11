import XCTest

/// P-BACK. Reported by the physician on build 1.0 (3), 2026-10-10 18:56:
/// "Passei pra frente e ele não deixa voltar", with the step "Sua rotina"
/// on screen and the TOP of it circled. The only "Voltar" was the last item
/// of the scrolling column — below "Continuar", out of the window on that
/// step — and the review had none.
@MainActor
final class OnboardingBackUITests: XCTestCase {
    private var journey: OnboardingJourneyUITestSupport { .init(testCase: self) }

    /// The exact scenario: Boas-vindas → Continuar → Dados corporais →
    /// Continuar → "Sua rotina". On arrival, without scrolling, a "Voltar"
    /// is entirely inside the window; touching it returns to Dados corporais
    /// with what was filled.
    func testSuaRotinaShowsAWayBackOnArrivalAndKeepsWhatWasFilled() throws {
        continueAfterFailure = false
        let app = journey.launch()
        journey.reachBodyData(app)
        let height = app.textFields["onboarding.height"]
        let weight = app.textFields["onboarding.weight"]
        XCTAssertTrue(height.waitForExistence(timeout: 5))
        let filledHeight = try XCTUnwrap(height.value as? String)
        let filledWeight = try XCTUnwrap(weight.value as? String)
        XCTAssertFalse(filledHeight.isEmpty, "The fixture fills the height")
        XCTAssertFalse(filledWeight.isEmpty, "The fixture fills the weight")

        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.routine", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sua rotina"].waitForExistence(timeout: 5))
        journey.capture("u2-back-sua-rotina-arrival-pt-light", app)
        let back = try XCTUnwrap(journey.assertBackInReachOnArrival(app, step: "Sua rotina"))
        XCTAssertGreaterThanOrEqual(back.frame.width, 44)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)

        back.tap()
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
        XCTAssertFalse(journey.element("screen.onboarding.routine", app).exists)
        XCTAssertEqual(app.textFields["onboarding.height"].value as? String, filledHeight)
        XCTAssertEqual(app.textFields["onboarding.weight"].value as? String, filledWeight)
    }

    /// The same check on every step after the first, the review included
    /// (it had no way back at all), and the absence on the first step.
    func testEveryStepAfterTheFirstShowsAWayBackOnArrival() {
        // Each step is checked even when an earlier one fails, so the record
        // names every step that has no way back in reach.
        continueAfterFailure = true
        let app = journey.launch()
        journey.reachWelcome(app)
        XCTAssertEqual(
            journey.backCommands(app).count, 0,
            "The first step has nowhere to go back to"
        )
        XCTAssertFalse(app.buttons["onboarding.back.top"].exists)

        journey.enter("Pessoa QA\n", in: app.textFields["onboarding.display-name"], app)
        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
        journey.assertBackInReachOnArrival(app, step: "Dados corporais")

        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.routine", app).waitForExistence(timeout: 5))
        journey.assertBackInReachOnArrival(app, step: "Sua rotina")

        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.persona", app).waitForExistence(timeout: 5))
        journey.assertBackInReachOnArrival(app, step: "Estilo do Flow")
        journey.tap(app.buttons["persona.focus"], app)

        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.consent", app).waitForExistence(timeout: 5))
        journey.assertBackInReachOnArrival(app, step: "Documentos")
        journey.acceptDocuments(app)

        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.objective", app).waitForExistence(timeout: 5))
        journey.assertBackInReachOnArrival(app, step: "Objetivo")
        journey.tap(app.buttons["onboarding.objective.manutencao"], app)

        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.completion", app).waitForExistence(timeout: 5))
        journey.capture("u2-back-review-arrival-pt-light", app)
        let back = journey.assertBackInReachOnArrival(app, step: "Revisão")

        // From the review the way back lands on the objective, still chosen.
        guard let back else { return }
        back.tap()
        XCTAssertTrue(journey.element("screen.onboarding.objective", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.objective.manutencao"].isSelected)
        // The command that was already below "Continuar" is still there.
        XCTAssertTrue(app.buttons["onboarding.back"].exists)
    }

    /// English, dark, the largest text size, on the reported step: the
    /// command is in reach on arrival, keeps the minimum target and sits
    /// above the brand without touching it.
    func testSuaRotinaKeepsTheWayBackInReachInEnglishAtTheLargestTextSize() throws {
        continueAfterFailure = false
        let app = journey.launch(
            language: "en-US", dark: true, category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        journey.reachRoutine(app)
        journey.capture("u2-back-your-routine-arrival-en-dark-axxxl", app)
        let back = try XCTUnwrap(
            journey.assertBackInReachOnArrival(app, step: "Your routine", word: "Back")
        )
        XCTAssertGreaterThanOrEqual(back.frame.width, 44)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
        let brand = app.staticTexts["brand.product-name"]
        XCTAssertTrue(brand.waitForExistence(timeout: 5))
        XCTAssertTrue(
            back.frame.intersection(brand.frame).isNull,
            "The way back and the brand overlap: \(back.frame) / \(brand.frame)"
        )
        XCTAssertLessThanOrEqual(back.frame.maxY, brand.frame.minY)
        let progress = journey.element("onboarding.progress", app)
        XCTAssertGreaterThanOrEqual(progress.frame.minY, brand.frame.maxY)

        back.tap()
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
    }
}
