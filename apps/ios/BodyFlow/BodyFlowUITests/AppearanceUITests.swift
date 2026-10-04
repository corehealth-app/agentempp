import XCTest

/// Eduardo, 03/10: "na tela inicial adicionar o botão de dark ou light".
/// The control sits on Today's navigation bar; choosing a mode changes the
/// app at once, whatever the system appearance is.
final class AppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayAppearanceControlSwitchesDarkAndLight() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-prompt13-loaded",
            "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR",
        ]
        app.launch()
        let today = app.descendants(matching: .any)["screen.hoje"]
        XCTAssertTrue(today.waitForExistence(timeout: 8))
        let control = app.buttons["today.appearance"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(control.frame.width, 44)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        // A demo run starts on the system's choice.
        XCTAssertEqual(control.value as? String, "Igual ao iPhone")

        control.tap()
        app.buttons["Escuro"].tap()
        XCTAssertEqual(today.value as? String, "dark")
        XCTAssertEqual(control.value as? String, "Escuro")

        control.tap()
        app.buttons["Claro"].tap()
        XCTAssertEqual(today.value as? String, "light")

        control.tap()
        XCTAssertTrue(app.buttons["Automático: claro de dia, escuro à noite"].exists)
        app.buttons["Igual ao iPhone"].tap()
        XCTAssertEqual(control.value as? String, "Igual ao iPhone")
    }
}
