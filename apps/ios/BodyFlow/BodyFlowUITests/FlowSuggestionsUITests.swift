import XCTest

/// A first conversation offers ready-made questions. Tapping one only fills
/// the composer; nothing is sent until the person presses Send, and a typed
/// draft is never replaced.
final class FlowSuggestionsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // The questions depend on the text size: pin the regular one.
        app.launchArguments = [
            "--ui-testing", "--ui-testing-prompt13-loaded",
            "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func openFlow(_ app: XCUIApplication) {
        let open = app.buttons["today.flow-chat"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        for _ in 0..<4 where !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.flow-chat"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSuggestionFillsTheComposerWithoutSending() {
        let app = launch()
        openFlow(app)
        let suggestion = app.buttons["flow.suggestion.0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(suggestion.frame.height, 44)
        XCTAssertEqual(suggestion.label, "Como está meu dia até agora?")
        XCTAssertFalse(app.buttons["flow.send"].isEnabled)
        suggestion.tap()
        let composer = app.textFields["flow.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, "Como está meu dia até agora?")
        // Still the empty conversation: nothing was sent, and Send is ready.
        XCTAssertTrue(app.descendants(matching: .any)["flow.empty"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["flow.outbox"].exists)
        XCTAssertTrue(app.buttons["flow.send"].isEnabled)
        // An untouched question can still be swapped for another one.
        let second = app.buttons["flow.suggestion.1"]
        XCTAssertTrue(second.exists)
        second.tap()
        XCTAssertEqual(composer.value as? String, "Sugira um jantar para fechar o dia")
    }

    /// The scenario from the 2026-10-04 review: a typed draft survives leaving
    /// and reopening the chat, and the questions must not be able to replace it.
    @MainActor
    func testTypedDraftHidesSuggestionsAndSurvivesReopening() {
        let app = launch()
        openFlow(app)
        XCTAssertTrue(app.buttons["flow.suggestion.0"].waitForExistence(timeout: 8))
        let composer = app.textFields["flow.composer"]
        composer.tap()
        composer.typeText("Rascunho meu")
        XCTAssertEqual(composer.value as? String, "Rascunho meu")
        XCTAssertFalse(app.buttons["flow.suggestion.0"].exists,
                       "A typed draft must not sit next to a control that replaces it")
        XCTAssertTrue(app.descendants(matching: .any)["flow.empty"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        openFlow(app)
        XCTAssertEqual(app.textFields["flow.composer"].value as? String, "Rascunho meu")
        XCTAssertFalse(app.buttons["flow.suggestion.0"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["flow.outbox"].exists)
    }
}
