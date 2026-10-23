import XCTest

/// P-ACTIVITY. Reported by the physician on build 1.0 (3), 2026-10-10 18:56,
/// on "Sua rotina" with the menu "Nível de atividade" open — Sedentário,
/// Leve, Moderado, Alto, Atleta, names only: "Aqui ele não diz qual a
/// frequência semanal de atividade física de cada categoria".
@MainActor
final class OnboardingActivityLevelUITests: XCTestCase {
    private var journey: OnboardingJourneyUITestSupport { .init(testCase: self) }

    /// The exact scenario: on "Sua rotina", without opening any menu, what
    /// each level means is on the screen; touching "Leve" chooses it, and
    /// the choice is still there after going on and coming back.
    func testSuaRotinaSaysWhatEachLevelMeansWithoutOpeningAMenu() {
        continueAfterFailure = false
        let app = journey.launch()
        journey.reachRoutine(app)
        journey.waitUntilArrived(app)

        // Habitual water is no longer part of the initial questionnaire.
        XCTAssertFalse(app.staticTexts["Consumo de água"].exists)
        // Nothing was touched on this step.
        let meanings = [
            "Não faz exercício",
            "1 a 3 dias por semana",
            "4 a 5 dias por semana",
            "6 a 7 dias por semana",
            "2 vezes por dia",
        ]
        let missing = meanings.filter { meaning in
            !app.buttons.matching(NSPredicate(format: "label CONTAINS %@", meaning)).firstMatch.exists
        }
        journey.capture("u2-activity-sua-rotina-arrival-pt-light", app)
        XCTAssertEqual(
            missing, [],
            "“Sua rotina” does not say, without opening anything, what these levels mean"
        )
        XCTAssertTrue(
            app.staticTexts[
                "Conte os dias em que você faz exercício: musculação, corrida, esporte, aula, pedal ou natação."
            ].exists,
            "No line saying which exercise counts"
        )

        // The UI-test sign-up comes with "Moderado" already chosen.
        let moderate = app.buttons["onboarding.activity-level.moderado"]
        let light = app.buttons["onboarding.activity-level.leve"]
        XCTAssertTrue(moderate.waitForExistence(timeout: 5))
        XCTAssertTrue(moderate.isSelected)
        XCTAssertTrue(light.label.contains("Leve"), light.label)
        XCTAssertTrue(light.label.contains("1 a 3 dias por semana"), light.label)
        XCTAssertFalse(light.isSelected)

        journey.tap(light, app)
        XCTAssertTrue(light.isSelected, "Touching “Leve” chooses it")
        XCTAssertFalse(moderate.isSelected)
        XCTAssertGreaterThanOrEqual(light.frame.height, 44)
        journey.capture("u2-activity-leve-chosen-pt-light", app)

        // The choice goes on with the sign-up and is kept on the way back.
        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.persona", app).waitForExistence(timeout: 5))
        journey.tap(app.buttons["onboarding.back"], app)
        XCTAssertTrue(journey.element("screen.onboarding.routine", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.activity-level.leve"].isSelected)
        XCTAssertFalse(app.buttons["onboarding.activity-level.moderado"].isSelected)
    }

    /// English, dark, the largest text size: the five meanings are there and
    /// every row can still be reached and chosen.
    func testEveryLevelCanBeChosenInEnglishAtTheLargestTextSize() {
        continueAfterFailure = false
        let app = journey.launch(
            language: "en-US", dark: true, category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        journey.reachRoutine(app)
        journey.waitUntilArrived(app)
        let rows: [(identifier: String, meaning: String)] = [
            ("onboarding.activity-level.sedentario", "Does not exercise."),
            ("onboarding.activity-level.leve", "Exercise 1 to 3 days a week."),
            ("onboarding.activity-level.moderado", "Exercise 4 to 5 days a week."),
            ("onboarding.activity-level.alto", "Exercise 6 to 7 days a week."),
            ("onboarding.activity-level.atleta", "Trains 2 times a day."),
        ]
        let missing = rows.filter { !app.buttons[$0.identifier].exists }.map(\.identifier)
        XCTAssertEqual(missing, [], "“Your routine” has no row for these levels")
        let window = app.windows.firstMatch.frame
        for row in rows {
            let button = app.buttons[row.identifier]
            XCTAssertTrue(button.label.contains(row.meaning), "\(row.identifier): \(button.label)")
            journey.tap(button, app)
            XCTAssertTrue(button.isSelected, row.identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, row.identifier)
            XCTAssertGreaterThanOrEqual(button.frame.minX, window.minX, row.identifier)
            XCTAssertLessThanOrEqual(button.frame.maxX, window.maxX, row.identifier)
        }
        journey.capture("u2-activity-your-routine-en-dark-axxxl", app)
        // The step still goes on.
        journey.advance(app)
        XCTAssertTrue(journey.element("screen.onboarding.persona", app).waitForExistence(timeout: 5))
    }
}
