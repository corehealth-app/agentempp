import XCTest

/// Real root/detail composition, including ScrollView's virtual AX rows.
/// The values are synthetic and the fixture is an explicit Debug opt-in.
final class Block7700EligibilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private var support: PremiumUIUXUITestSupport { PremiumUIUXUITestSupport(testCase: self) }

    @MainActor func testRecompositionShowsBlockAndKeepsOfficialValues() {
        verifyRoot(context: "recomposition", enabled: true, explanation: false)
    }
    @MainActor func testGainHidesBlockAndKeepsOfficialValues() {
        verifyRoot(context: "gain", enabled: false, explanation: true)
    }
    @MainActor func testMaintenanceHidesBlockAndKeepsOfficialValues() {
        verifyRoot(context: "maintenance", enabled: false, explanation: true)
    }
    @MainActor func testLegacyPayloadHidesBlockWithoutInferringTheObjective() {
        verifyRoot(context: "legacy", enabled: false, explanation: false)
    }

    @MainActor func testNullProgressKeepsOldTrendsWithoutBlock() {
        for language in ["pt-BR", "en-US"] {
            let app = launch("nullProgress", language: language)
            app.buttons["tab.progresso"].tap()
            XCTAssertTrue(element("progress.trends", app).waitForExistence(timeout: 8))
            for id in ["progress.trends.weight", "progress.trends.calories", "progress.trends.days"] {
                let card = element(id, app)
                reveal(card, app)
                XCTAssertTrue(card.exists, id)
            }
            XCTAssertTrue(app.staticTexts[language == "pt-BR" ? "78,4 kg" : "78.4 kg"].exists)
            XCTAssertFalse(element("progress.trends.block", app).exists)
            XCTAssertFalse(element("progress.block.detail", app).exists)
            XCTAssertFalse(element("progress.metric.reported-deficit", app).exists)
            XCTAssertFalse(app.staticTexts["Primeiro Bloco"].exists)
            support.capture("c3-null-old-trends-\(language)", app: app)
            app.terminate()
        }
    }

    @MainActor func testDirectDetailRejectsGainMaintenanceAndLegacyButKeepsRecompositionFigures() {
        for context in ["recomposition", "gain", "maintenance", "legacy"] {
            let app = launch(context, language: "pt-BR", extra: ["--ui-testing-block-direct-detail"])
            XCTAssertTrue(element("screen.block7700.detail", app).waitForExistence(timeout: 8))
            if context == "recomposition" {
                XCTAssertTrue(element("block7700.summary", app).waitForExistence(timeout: 8))
                XCTAssertTrue(app.staticTexts["3.850 kcal"].exists)
                XCTAssertTrue(app.staticTexts["50%"].exists)
                XCTAssertTrue(app.staticTexts["19.250 kcal"].exists)
                XCTAssertFalse(element("block7700.retry", app).exists)
            } else {
                XCTAssertTrue(element(context == "legacy" ? "block7700.context-unavailable" : "block7700.ineligible", app).waitForExistence(timeout: 8))
                XCTAssertTrue(app.buttons["block7700.retry"].exists)
                support.assertTarget(app.buttons["block7700.retry"])
                XCTAssertFalse(element("block7700.summary", app).exists)
                for figure in ["3.850 kcal", "50%", "19.250 kcal", "0 kcal"] {
                    XCTAssertFalse(app.staticTexts[figure].exists, figure)
                }
                app.buttons["block7700.retry"].tap()
                XCTAssertTrue(element(context == "legacy" ? "block7700.context-unavailable" : "block7700.ineligible", app).waitForExistence(timeout: 8))
            }
            support.capture("c3-direct-\(context)", app: app)
            app.terminate()
        }
    }

    @MainActor func testTextTourUsesCurrentTodayFactsAndKeepsAllEightAreas() {
        for context in ["recomposition", "gain", "legacy"] {
            let app = launch(context, language: "pt-BR", extra: ["--ui-testing-tutorial-text"])
            XCTAssertTrue(element("today.energy.food-excess", app).waitForExistence(timeout: 8))
            app.buttons["tab.perfil"].tap()
            let replay = element("profile.tutorial", app)
            XCTAssertTrue(replay.waitForExistence(timeout: 5))
            replay.tap()
            XCTAssertTrue(element("screen.tutorial", app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("tutorial.step.welcome", app).exists)
            XCTAssertTrue(app.staticTexts["Etapa 1 de 8"].exists)
            for area in ["today", "flow", "plan", "register", "progress", "routineLibrary", "profile"] {
                XCTAssertTrue(element("tutorial.area.\(area)", app).exists, area)
            }
            let progress = element("tutorial.area.progress", app)
            reveal(progress, app)
            progress.tap()
            XCTAssertTrue(element("tutorial.step.progress", app).waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Etapa 6 de 8"].exists)
            let expected = context == "recomposition" ? "tutorial.progress.body" : "tutorial.progress.body.without-block"
            XCTAssertTrue(element("tutorial.line.\(expected)", app).exists)
            let unexpected = context == "recomposition" ? "tutorial.progress.body.without-block" : "tutorial.progress.body"
            XCTAssertFalse(element("tutorial.line.\(unexpected)", app).exists)
            app.buttons["tutorial.close"].tap()
            XCTAssertTrue(replay.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor func testSpotlightTrailUsesCurrentObjectiveAndReturnsToProfile() {
        for context in ["recomposition", "gain"] {
            let app = launch(context, language: "en-US")
            XCTAssertTrue(element("today.energy.food-excess", app).waitForExistence(timeout: 8))
            app.buttons["tab.perfil"].tap()
            let replay = element("profile.tutorial", app)
            XCTAssertTrue(replay.waitForExistence(timeout: 5))
            replay.tap()
            XCTAssertTrue(element("tour.step.welcome", app).waitForExistence(timeout: 5))
            app.buttons["tour.start"].tap()
            for step in ["flow", "library", "register", "plan", "progress", "profile"] {
                XCTAssertTrue(element("tour.step.\(step)", app).waitForExistence(timeout: 5), step)
                app.buttons["tour.next"].tap()
            }
            XCTAssertTrue(element("tour.step.trail", app).waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Step 8 of 8"].exists)
            let diagram = element("tour.trail.diagram", app)
            XCTAssertTrue(diagram.exists)
            XCTAssertTrue(diagram.label.contains("Register") && diagram.label.contains("Today") && diagram.label.contains("Progress"), diagram.label)
            XCTAssertEqual(diagram.label.contains("7,700"), context == "recomposition", diagram.label)
            XCTAssertTrue(app.buttons["tour.finish"].isHittable)
            app.buttons["tour.finish"].tap()
            XCTAssertTrue(replay.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor private func verifyRoot(context: String, enabled: Bool, explanation: Bool) {
        for language in ["pt-BR", "en-US"] {
            let app = launch(context, language: language)
            XCTAssertTrue(element("today.energy.food-excess", app).waitForExistence(timeout: 8))
            XCTAssertTrue(element("today.energy.food-excess", app).label.contains("233 kcal"))
            let trail = element("today.trail", app)
            reveal(trail, app)
            XCTAssertTrue(trail.exists)
            for id in ["today.trail.register", "today.trail.today", "today.trail.progress"] {
                XCTAssertTrue(element(id, app).exists, id)
            }
            XCTAssertEqual(element("today.trail.block", app).exists, enabled)
            let history = element("today.history", app)
            reveal(history, app)
            XCTAssertTrue(history.exists)
            XCTAssertEqual(element("today.block", app).exists, enabled)
            XCTAssertEqual(element("today.block.explanation", app).exists, explanation)
            app.buttons["tab.progresso"].tap()
            XCTAssertTrue(element("progress.received-values", app).waitForExistence(timeout: 8))
            for id in ["progress.trends.weight", "progress.trends.calories", "progress.trends.days"] {
                let card = element(id, app)
                reveal(card, app)
                XCTAssertTrue(card.exists, id)
            }
            XCTAssertEqual(element("progress.trends.block", app).exists, enabled)
            let body = element("progress.body", app)
            reveal(body, app)
            XCTAssertTrue(body.exists)
            XCTAssertTrue(app.staticTexts["80 kg"].exists)
            let summary = element("progress.summary", app)
            reveal(summary, app)
            XCTAssertTrue(summary.exists)
            XCTAssertTrue(app.staticTexts[language == "pt-BR" ? "1.240 XP" : "1,240 XP"].exists)
            XCTAssertEqual(element("progress.metric.completed-blocks", app).exists, enabled)
            XCTAssertEqual(element("progress.metric.reported-deficit", app).exists, enabled)
            XCTAssertEqual(element("progress.block.explanation", app).exists, explanation)
            let achievements = element("progress.achievements", app)
            reveal(achievements, app)
            XCTAssertTrue(app.staticTexts["Primeira Semana"].firstMatch.exists)
            XCTAssertTrue(app.staticTexts["badge-z"].exists)
            XCTAssertEqual(app.staticTexts["Primeiro Bloco"].exists, enabled)
            XCTAssertEqual(element("progress.block.detail", app).exists, enabled)
            support.capture("c3-root-\(context)-\(language)", app: app)
            app.terminate()
        }
    }

    @MainActor private func launch(_ context: String, language: String, extra: [String] = []) -> XCUIApplication {
        support.launch(arguments: ["--ui-testing", "--ui-testing-prompt13-loaded", "--ui-testing-block-\(context)"] + extra,
                       language: language, dark: language == "en-US")
    }
    @MainActor private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }
    @MainActor private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<10 where !target.exists || !target.isHittable { app.swipeUp() }
    }
}
