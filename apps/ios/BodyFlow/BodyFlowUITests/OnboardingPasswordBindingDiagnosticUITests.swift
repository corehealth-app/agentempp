import Foundation
import UIKit
import XCTest

/// Observation of the failing English/dark/AXXXL preparation only.
/// The existing journey, helper, assertions and product remain unchanged.
@MainActor
final class OnboardingPasswordBindingDiagnosticUITests: XCTestCase {
    func testEnglishDarkAXXXLPasswordRecipeObservesTheBindingBeforeSignup() throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        let app = journey.launch(
            language: "en-US", dark: true, category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let eye = app.buttons["auth.password.visibility"]
        let shown = journey.element("auth.password.shown", app)
        let cleanup = PasswordBindingDiagnosticCleanup(app: app, eye: eye, shown: shown)
        addTeardownBlock { await cleanup.tearDown() }

        // Same synthetic input as reachWelcome. No submit or provider action.
        let expected = "local-pass"
        var observation = observePreparation(
            app: app, journey: journey, cleanup: cleanup, expected: expected
        )
        // Hide using the same eye before an assertion can trigger a capture.
        observation.hiddenBeforeAssertions = cleanup.hideAndVerify()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let receipt = XCTAttachment(
            data: try encoder.encode(observation), uniformTypeIdentifier: "public.json"
        )
        receipt.name = "password-binding-counts-and-booleans"
        receipt.lifetime = .keepAlways
        add(receipt)

        // These assertions contain only booleans or counts. A missing shown
        // element/value is explicitly inconclusive and cannot silently pass.
        XCTAssertTrue(observation.hiddenBeforeAssertions)
        XCTAssertFalse(observation.inconclusive)
        XCTAssertTrue(observation.openSignUpReached)
        XCTAssertTrue(observation.emailReached)
        XCTAssertTrue(observation.passwordExists)
        XCTAssertTrue(observation.passwordReached)
        XCTAssertTrue(observation.focusBeforeEscape)
        XCTAssertTrue(observation.focusAfterEscape)
        XCTAssertTrue(observation.eyeReached)
        XCTAssertTrue(observation.shownExists)
        XCTAssertTrue(observation.shownValueAvailable)
        XCTAssertEqual(observation.shownCount, observation.expectedCount)
        XCTAssertTrue(observation.shownMatchesExpected)
        // finalSecureEntryMatched is evidence, not an early stopping oracle.
    }

    private func observePreparation(
        app: XCUIApplication,
        journey: OnboardingJourneyUITestSupport,
        cleanup: PasswordBindingDiagnosticCleanup,
        expected: String
    ) -> PasswordBindingDiagnosticObservation {
        var observation = PasswordBindingDiagnosticObservation(expectedCount: expected.count)
        let openSignUp = app.buttons["auth.open-sign-up"]
        observation.openSignUpReached = reachWithoutAssertions(openSignUp, app: app)
        guard observation.openSignUpReached else { return observation }
        openSignUp.tap()

        let email = app.textFields["auth.email"]
        observation.emailReached = reachWithoutAssertions(email, app: app)
        guard observation.emailReached else { return observation }
        email.tap()
        email.typeText("person@example.invalid")

        let field = app.secureTextFields["auth.password"]
        observation.passwordExists = field.waitForExistence(timeout: 5)
        guard observation.passwordExists else { return observation }
        observation.passwordReached = reachWithoutAssertions(field, app: app)
        guard observation.passwordReached else { return observation }
        field.tap()
        observation.focusBeforeEscape = journey.waitForKeyboardFocus(field)
        field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        observation.focusAfterEscape = journey.waitForKeyboardFocus(field)

        // Exact enterSecure recipe, including its branch and existing waits.
        // The helper's final assertion is replaced only in this new probe.
        UIPasteboard.general.string = expected
        defer { UIPasteboard.general.string = nil }
        field.typeKey("v", modifierFlags: .command)
        observation.pasteSecureEntryMatched = journey.waitForSecureEntry(
            field, characterCount: expected.count, timeout: 1
        )
        observation.maskedCountAfterPaste = (field.value as? String)?.count ?? -1
        if !observation.pasteSecureEntryMatched {
            observation.usedTypingFallback = true
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            for character in expected {
                field.typeText(String(character))
            }
        }
        observation.finalSecureEntryMatched = journey.waitForSecureEntry(
            field, characterCount: expected.count
        )
        observation.maskedCountAtEnd = (field.value as? String)?.count ?? -1

        observation.eyeReached = reachWithoutAssertions(cleanup.eye, app: app)
        guard observation.eyeReached else { return observation }
        cleanup.eye.tap()
        cleanup.wasRevealed = true
        observation.shownExists = cleanup.shown.waitForExistence(timeout: 5)
        if observation.shownExists, let bindingValue = cleanup.shown.value as? String {
            observation.shownValueAvailable = true
            observation.shownCount = bindingValue.count
            observation.shownMatchesExpected = bindingValue == expected
        }
        observation.inconclusive = !observation.focusBeforeEscape
            || !observation.focusAfterEscape
            || !observation.shownExists
            || !observation.shownValueAvailable
        observation.maskedCountMismatchWithBindingIntact = !observation.inconclusive
            && !observation.finalSecureEntryMatched && observation.shownMatchesExpected
        observation.bindingDiffersFromExpected = !observation.inconclusive
            && !observation.shownMatchesExpected
        return observation
    }

    /// Same 5-second existence wait and at most 60 swipes as journey.reach.
    /// No element description, value, screenshot or hierarchy is emitted.
    private func reachWithoutAssertions(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<60 where !element.isHittable { app.swipeUp() }
        return element.isHittable
    }
}

/// Receipt properties are deliberately restricted to counts and booleans.
private struct PasswordBindingDiagnosticObservation: Encodable {
    let expectedCount: Int
    var openSignUpReached = false
    var emailReached = false
    var passwordExists = false
    var passwordReached = false
    var focusBeforeEscape = false
    var focusAfterEscape = false
    var pasteSecureEntryMatched = false
    var maskedCountAfterPaste = -1
    var usedTypingFallback = false
    var finalSecureEntryMatched = false
    var maskedCountAtEnd = -1
    var eyeReached = false
    var shownExists = false
    var shownValueAvailable = false
    var shownCount = -1
    var shownMatchesExpected = false
    var maskedCountMismatchWithBindingIntact = false
    var bindingDiffersFromExpected = false
    var inconclusive = true
    var hiddenBeforeAssertions = false
}

/// Global actor isolation also makes this teardown capture Sendable in Swift 6.
@MainActor
private final class PasswordBindingDiagnosticCleanup {
    let app: XCUIApplication
    let eye: XCUIElement
    let shown: XCUIElement
    var wasRevealed = false
    private var hidden = false
    private var terminated = false

    init(app: XCUIApplication, eye: XCUIElement, shown: XCUIElement) {
        self.app = app
        self.eye = eye
        self.shown = shown
    }

    func hideAndVerify() -> Bool {
        guard !terminated else { return hidden }
        guard wasRevealed else { return true }
        if !hidden, eye.exists, eye.isHittable {
            eye.tap()
            hidden = shown.waitForNonExistence(timeout: 5)
        }
        if !hidden {
            // A hide failure remains a failed observation. Terminating first
            // prevents an assertion artifact from keeping readable input.
            app.terminate()
            terminated = true
        }
        return hidden
    }

    func tearDown() {
        _ = hideAndVerify()
        UIPasteboard.general.string = nil
        if !terminated {
            app.terminate()
            terminated = true
        }
    }
}
