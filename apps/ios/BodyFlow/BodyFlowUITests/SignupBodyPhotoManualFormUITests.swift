import XCTest

/// Existing local demo journey only. No real account/network/camera/ACK.
@MainActor
final class SignupBodyPhotoManualFormUITests: XCTestCase {
    private var journey: OnboardingJourneyUITestSupport { .init(testCase: self) }

    func testUnavailablePhotosKeepManualDecimalThroughFocusContinueAndBackInBothLanguages() throws {
        continueAfterFailure = false
        for language in ["pt-BR", "en-US"] {
            let app = journey.launch(language: language)
            journey.reachBodyData(app)
            let photo = app.buttons["onboarding.body-fat.choice.photos"]
            let manual = app.buttons["onboarding.body-fat.choice.typed"]
            let skip = app.buttons["onboarding.body-fat.choice.skip"]
            XCTAssertTrue(photo.waitForExistence(timeout: 5))
            XCTAssertFalse(photo.isEnabled, "Demo has no live capture capability; never show a fake real provider")
            XCTAssertTrue(manual.waitForExistence(timeout: 5) && manual.isEnabled)
            XCTAssertTrue(skip.exists && skip.isEnabled)
            journey.tap(manual, app)
            XCTAssertTrue(manual.isSelected)
            let height = app.textFields["onboarding.height"].value as? String
            let weight = app.textFields["onboarding.weight"].value as? String
            let field = app.textFields["onboarding.body-fat"]
            journey.tap(field, app)
            XCTAssertTrue(journey.waitForKeyboardFocus(field))
            // Existing project XCTest key recipe, not a direct draft mutation.
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            field.typeText(language == "pt-BR" ? "24,5" : "24.5")
            let done = app.buttons[language == "pt-BR" ? "Concluído" : "Done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap() // exercises FocusState/keyboard toolbar before Continue
            XCTAssertEqual(try decimal(field, language: language), 24.5)
            XCTAssertEqual(app.buttons.matching(identifier: "onboarding.continue").count, 1)
            journey.advance(app)
            XCTAssertTrue(journey.element("screen.onboarding.routine", app).waitForExistence(timeout: 5))
            journey.tap(app.buttons["onboarding.back.top"], app)
            XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
            XCTAssertEqual(try decimal(app.textFields["onboarding.body-fat"], language: language), 24.5,
                "Typed decimal must reach the real draft before advance and survive returning")
            XCTAssertEqual(app.textFields["onboarding.height"].value as? String, height)
            XCTAssertEqual(app.textFields["onboarding.weight"].value as? String, weight)
            XCTAssertTrue(app.buttons["onboarding.body-fat.choice.typed"].isSelected)
            XCTAssertFalse(journey.element("screen.onboarding.photos.consent", app).exists)
            journey.tap(app.buttons["onboarding.body-fat.choice.skip"], app)
            XCTAssertTrue(app.buttons["onboarding.body-fat.choice.skip"].isSelected)
            journey.tap(app.buttons["onboarding.body-fat.choice.typed"], app)
            let cleared = app.textFields["onboarding.body-fat"]
            XCTAssertTrue(cleared.waitForExistence(timeout: 5))
            XCTAssertNil(number(cleared.value as? String, language: language),
                "Explicit skip clears BF; selecting typed must not restore an old photo/manual value")
            journey.capture("signup-photo-manual-decimal-fallback-" + language, app)
            app.terminate()
        }
    }

    private func number(_ text: String?, language: String) -> NSNumber? {
        guard let text else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.numberStyle = .decimal
        return formatter.number(from: text.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private func decimal(_ field: XCUIElement, language: String) throws -> Double {
        try XCTUnwrap(number(field.value as? String, language: language),
            "The field does not expose a decimal after focus ends: \(field.value ?? "nil")").doubleValue
    }
}
