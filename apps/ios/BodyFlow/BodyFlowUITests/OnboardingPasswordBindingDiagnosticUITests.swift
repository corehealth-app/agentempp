import Foundation
import UIKit
import XCTest

/// Actual Root password keyboard recipes with app-root offer setup before input.
/// Existing count/equality assertions and product behavior remain unchanged.
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

        var field = app.secureTextFields["auth.password"]
        observation.passwordExists = field.waitForExistence(timeout: 5)
        guard observation.passwordExists else { return observation }
        observation.passwordReached = reachWithoutAssertions(field, app: app)
        guard observation.passwordReached else { return observation }
        field.tap()
        observation.focusBeforeEscape = journey.waitForKeyboardFocus(field)
        field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        observation.focusAfterEscape = journey.waitForKeyboardFocus(field)
        // Prepare only the validated app-root offer; retain the keyboard recipe below.
        observation.firstPasswordTypingPrepared = journey.prepareFirstAuthPasswordForTyping(in: field, app)
        guard observation.firstPasswordTypingPrepared else { return observation }
        let refetchedFields = app.secureTextFields.matching(identifier: "auth.password")
        observation.refetchedPasswordMatchCount = Int(refetchedFields.count)
        guard observation.refetchedPasswordMatchCount == 1 else { return observation }
        field = refetchedFields.element(boundBy: 0)
        observation.focusAfterOfferPreparation = field.exists
            && NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field)
        guard observation.focusAfterOfferPreparation else { return observation }

        // Original paste/fallback keyboard recipe, including its branch and waits.
        // App-root offer setup above does not change its input or result oracles.
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
    var firstPasswordTypingPrepared = false
    var refetchedPasswordMatchCount = -1
    var focusAfterOfferPreparation = false
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


// PT/light/L retains its keyboard recipe and receipt assertions.
// App-root offer setup is separate; there is no signup submit.
extension OnboardingPasswordBindingDiagnosticUITests {
    func testPortugueseLightDefaultSizeFirstPasswordBindingBeforeSignup() throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        let app = journey.launch(
            language: "pt-BR", dark: false, category: "UICTContentSizeCategoryL"
        )
        let eye = app.buttons["auth.password.visibility"]
        let shown = journey.element("auth.password.shown", app)
        let cleanup = PasswordBindingDiagnosticCleanup(app: app, eye: eye, shown: shown)
        addTeardownBlock { await cleanup.tearDown() }

        // Same actual signup first SecureField and synthetic input as the
        // failed journey. ORIGINAL field-directed fallback is run first.
        let expected = "local-pass"
        var observation = observePortuguesePreparation(
            app: app, journey: journey, cleanup: cleanup, expected: expected
        )
        observation.hiddenBeforeAssertions = cleanup.hideAndVerify()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let receipt = XCTAttachment(
            data: try encoder.encode(observation), uniformTypeIdentifier: "public.json"
        )
        receipt.name = "password-binding-pt-light-L-counts-and-booleans"
        receipt.lifetime = .keepAlways
        add(receipt)

        // Only boolean/count failures; never print or capture the input.
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
        XCTAssertTrue(observation.shownMatchesExpected,
            "The actual first-password Binding must retain the exact synthetic input")
        XCTAssertEqual(observation.maskedCountAtEnd, observation.expectedCount)
        XCTAssertTrue(observation.finalSecureEntryMatched)
    }

    private func observePortuguesePreparation(
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

        var field = app.secureTextFields["auth.password"]
        observation.passwordExists = field.waitForExistence(timeout: 5)
        guard observation.passwordExists else { return observation }
        observation.passwordReached = reachWithoutAssertions(field, app: app)
        guard observation.passwordReached else { return observation }
        field.tap()
        observation.focusBeforeEscape = journey.waitForKeyboardFocus(field)
        field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        observation.focusAfterEscape = journey.waitForKeyboardFocus(field)
        // Prepare only the validated app-root offer; retain the keyboard recipe below.
        observation.firstPasswordTypingPrepared = journey.prepareFirstAuthPasswordForTyping(in: field, app)
        guard observation.firstPasswordTypingPrepared else { return observation }
        let refetchedFields = app.secureTextFields.matching(identifier: "auth.password")
        observation.refetchedPasswordMatchCount = Int(refetchedFields.count)
        guard observation.refetchedPasswordMatchCount == 1 else { return observation }
        field = refetchedFields.element(boundBy: 0)
        observation.focusAfterOfferPreparation = field.exists
            && NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field)
        guard observation.focusAfterOfferPreparation else { return observation }

        // Original paste/fallback keyboard recipe, including its branch and waits.
        // App-root offer setup above does not change its input or result oracles.
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

}


// Controlled typing-only diagnostic. This is NOT a claimed reproduction of
// clipboard failure: clipboard is empty and Cmd+V is deliberately not sent.
// Keyboard recipes and assertions stay intact; app-root offer setup occurs first.
extension OnboardingPasswordBindingDiagnosticUITests {
    func testEnglishLightDefaultSizeControlledPerCharacterTypingBeforeSignup() throws {
        try observeEnglishLightControlledTyping(singleFieldCall: false)
    }

    func testEnglishLightDefaultSizeControlledSingleFieldTypingBeforeSignup() throws {
        try observeEnglishLightControlledTyping(singleFieldCall: true)
    }

    private func observeEnglishLightControlledTyping(singleFieldCall: Bool) throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        let app = journey.launch("--ui-testing-signup-body-photos-capture",
            language: "en-US", dark: false, category: "UICTContentSizeCategoryL")
        let eye = app.buttons["auth.password.visibility"]
        let shown = journey.element("auth.password.shown", app)
        let cleanup = PasswordBindingDiagnosticCleanup(app: app, eye: eye, shown: shown)
        addTeardownBlock { await cleanup.tearDown() }
        let expected = "local-pass" // project allowlisted synthetic input only
        let result = observeControlledTypingPreparation(app: app, journey: journey,
            cleanup: cleanup, expected: expected, singleFieldCall: singleFieldCall)
        var observation = result.observation
        // Hide before encoding, assertions, or automatic failure attachments.
        observation.hiddenBeforeAssertions = cleanup.hideAndVerify()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(observation)
        // The old Encodable observation contains only ints/bools. Additional
        // controlled-fixture evidence also contains only ints/bools, flat JSON.
        var safe = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        safe["controlledTypingOnly"] = true
        safe["pasteAttempted"] = false
        safe["clipboardEmpty"] = result.clipboardEmpty
        safe["typingCallCount"] = result.typingCalls
        safe["focusAfterTyping"] = result.focusAfterTyping
        let receipt = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        receipt.name = singleFieldCall
            ? "first-password-en-light-L-controlled-single-counts-and-booleans"
            : "first-password-en-light-L-controlled-per-character-counts-and-booleans"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue(observation.hiddenBeforeAssertions)
        XCTAssertFalse(observation.inconclusive)
        XCTAssertTrue(observation.openSignUpReached)
        XCTAssertTrue(observation.emailReached)
        XCTAssertTrue(observation.passwordExists)
        XCTAssertTrue(observation.passwordReached)
        XCTAssertTrue(observation.focusBeforeEscape)
        XCTAssertTrue(observation.focusAfterEscape)
        XCTAssertTrue(result.clipboardEmpty)
        XCTAssertTrue(observation.usedTypingFallback)
        XCTAssertEqual(result.typingCalls, singleFieldCall ? 1 : observation.expectedCount,
            "The chosen typing section must actually execute; no paste-success bypass")
        XCTAssertTrue(result.focusAfterTyping)
        XCTAssertTrue(observation.eyeReached)
        XCTAssertTrue(observation.shownExists)
        XCTAssertTrue(observation.shownValueAvailable)
        XCTAssertEqual(observation.shownCount, observation.expectedCount)
        XCTAssertTrue(observation.shownMatchesExpected)
        XCTAssertEqual(observation.maskedCountAtEnd, observation.expectedCount)
        XCTAssertTrue(observation.finalSecureEntryMatched)
        XCTAssertFalse(journey.element("screen.onboarding.body-data", app).exists)
    }

    private func observeControlledTypingPreparation(
        app: XCUIApplication, journey: OnboardingJourneyUITestSupport,
        cleanup: PasswordBindingDiagnosticCleanup, expected: String,
        singleFieldCall: Bool
    ) -> (observation: PasswordBindingDiagnosticObservation, typingCalls: Int,
          clipboardEmpty: Bool, focusAfterTyping: Bool) {
        var observation = PasswordBindingDiagnosticObservation(expectedCount: expected.count)
        var typingCalls = 0
        var clipboardEmpty = false
        var focusAfterTyping = false
        let openSignUp = app.buttons["auth.open-sign-up"]
        observation.openSignUpReached = reachWithoutAssertions(openSignUp, app: app)
        guard observation.openSignUpReached else {
            return (observation, typingCalls, clipboardEmpty, focusAfterTyping)
        }
        openSignUp.tap()
        let email = app.textFields["auth.email"]
        observation.emailReached = reachWithoutAssertions(email, app: app)
        guard observation.emailReached else {
            return (observation, typingCalls, clipboardEmpty, focusAfterTyping)
        }
        email.tap()
        email.typeText("person@example.invalid")
        var field = app.secureTextFields["auth.password"]
        observation.passwordExists = field.waitForExistence(timeout: 5)
        guard observation.passwordExists else {
            return (observation, typingCalls, clipboardEmpty, focusAfterTyping)
        }
        observation.passwordReached = reachWithoutAssertions(field, app: app)
        guard observation.passwordReached else {
            return (observation, typingCalls, clipboardEmpty, focusAfterTyping)
        }
        field.tap()
        observation.focusBeforeEscape = journey.waitForKeyboardFocus(field)
        field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        observation.focusAfterEscape = journey.waitForKeyboardFocus(field)
        // Prepare only the validated app-root offer; retain the keyboard recipe below.
        observation.firstPasswordTypingPrepared = journey.prepareFirstAuthPasswordForTyping(in: field, app)
        guard observation.firstPasswordTypingPrepared else { return (observation, typingCalls, clipboardEmpty, focusAfterTyping) }
        let refetchedFields = app.secureTextFields.matching(identifier: "auth.password")
        observation.refetchedPasswordMatchCount = Int(refetchedFields.count)
        guard observation.refetchedPasswordMatchCount == 1 else { return (observation, typingCalls, clipboardEmpty, focusAfterTyping) }
        field = refetchedFields.element(boundBy: 0)
        observation.focusAfterOfferPreparation = field.exists
            && NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field)
        guard observation.focusAfterOfferPreparation else { return (observation, typingCalls, clipboardEmpty, focusAfterTyping) }
        // Explicit fixture for the existing typing section, NOT a failed paste.
        UIPasteboard.general.string = nil
        defer { UIPasteboard.general.string = nil }
        clipboardEmpty = UIPasteboard.general.string == nil
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        observation.usedTypingFallback = true
        if singleFieldCall {
            field.typeText(expected)
            typingCalls += 1
        } else {
            for character in expected {
                field.typeText(String(character))
                typingCalls += 1
            }
        }
        observation.finalSecureEntryMatched = journey.waitForSecureEntry(
            field, characterCount: expected.count)
        observation.maskedCountAtEnd = (field.value as? String)?.count ?? -1
        focusAfterTyping = NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field)
        observation.eyeReached = reachWithoutAssertions(cleanup.eye, app: app)
        guard observation.eyeReached else {
            return (observation, typingCalls, clipboardEmpty, focusAfterTyping)
        }
        cleanup.eye.tap()
        cleanup.wasRevealed = true
        observation.shownExists = cleanup.shown.waitForExistence(timeout: 5)
        if observation.shownExists, let bindingValue = cleanup.shown.value as? String {
            observation.shownValueAvailable = true
            observation.shownCount = bindingValue.count
            observation.shownMatchesExpected = bindingValue == expected
        }
        observation.inconclusive = !observation.focusBeforeEscape
            || !observation.focusAfterEscape || !focusAfterTyping
            || !observation.shownExists || !observation.shownValueAvailable
        observation.maskedCountMismatchWithBindingIntact = !observation.inconclusive
            && !observation.finalSecureEntryMatched && observation.shownMatchesExpected
        observation.bindingDiffersFromExpected = !observation.inconclusive
            && !observation.shownMatchesExpected
        return (observation, typingCalls, clipboardEmpty, focusAfterTyping)
    }
}


// G1 fresh-field diagnostic: the EN/light/L/signup fixture keeps no
// Escape/Cmd-A/Delete keyboard preparation. Validated app-root offer setup is
// separate; raw failure receipts remain retained and assertions are unchanged.
extension OnboardingPasswordBindingDiagnosticUITests {
    func testEnglishLightDefaultSizeFreshPasswordTypingWithoutPreparationBeforeSignup() throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        let app = journey.launch("--ui-testing-signup-body-photos-capture",
            language: "en-US", dark: false, category: "UICTContentSizeCategoryL")
        let eye = app.buttons["auth.password.visibility"]
        let shown = journey.element("auth.password.shown", app)
        let cleanup = PasswordBindingDiagnosticCleanup(app: app, eye: eye, shown: shown)
        addTeardownBlock { await cleanup.tearDown() }
        UIPasteboard.general.string = nil
        defer { UIPasteboard.general.string = nil }
        let expected = "local-pass" // allowlisted synthetic DEBUG input only
        var safe: [String: Any] = [
            "expectedCount": expected.count, "escapeAttempted": false,
            "selectAllAttempted": false, "deleteAttempted": false,
            "pasteAttempted": false, "clipboardEmpty": UIPasteboard.general.string == nil,
            "typingCallCount": 0, "freshAXCount": -1, "freshFieldEmpty": false,
            "maskedCountAtEnd": -1, "shownCount": -1,
            "openSignUpReached": false, "emailReached": false,
            "passwordReached": false, "focusBeforeTyping": false,
            "focusAfterTyping": false, "finalSecureEntryMatched": false,
            "shownValueAvailable": false, "shownMatchesExpected": false,
            "hiddenBeforeAssertions": false, "firstPasswordTypingPrepared": false,
            "refetchedPasswordMatchCount": -1, "focusAfterOfferPreparation": false,
        ]
        let openSignUp = app.buttons["auth.open-sign-up"]
        let openReached = reachWithoutAssertions(openSignUp, app: app)
        safe["openSignUpReached"] = openReached
        if openReached {
            openSignUp.tap()
            let email = app.textFields["auth.email"]
            let emailReached = reachWithoutAssertions(email, app: app)
            safe["emailReached"] = emailReached
            if emailReached {
                email.tap()
                email.typeText("person@example.invalid")
                var field = app.secureTextFields["auth.password"]
                let reached = reachWithoutAssertions(field, app: app)
                safe["passwordReached"] = reached
                if reached {
                    field.tap()
                    let focused = journey.waitForKeyboardFocus(field)
                    // OS offer setup is separate from the deliberately omitted keyboard recipe.
                    let prepared = focused && journey.prepareFirstAuthPasswordForTyping(in: field, app)
                    safe["firstPasswordTypingPrepared"] = prepared
                    let refetchedFields = app.secureTextFields.matching(identifier: "auth.password")
                    let refetchedCount = Int(refetchedFields.count)
                    safe["refetchedPasswordMatchCount"] = refetchedCount
                    let focusAfterOfferPreparation = prepared && refetchedCount == 1
                        && refetchedFields.element(boundBy: 0).exists
                        && NSPredicate(format: "hasKeyboardFocus == true")
                            .evaluate(with: refetchedFields.element(boundBy: 0))
                    safe["focusAfterOfferPreparation"] = focusAfterOfferPreparation
                    if focusAfterOfferPreparation { field = refetchedFields.element(boundBy: 0) }
                    let freshValue = focusAfterOfferPreparation ? field.value as? String : nil
                    let freshCount = freshValue?.count ?? -1
                    let freshEmpty = freshValue != nil && (freshValue!.isEmpty
                        || (field.placeholderValue != nil && freshValue == field.placeholderValue))
                    safe["focusBeforeTyping"] = focused && focusAfterOfferPreparation
                    safe["freshAXCount"] = freshCount
                    safe["freshFieldEmpty"] = freshEmpty
                    if focused && focusAfterOfferPreparation && freshEmpty {
                        field.typeText(expected)
                        safe["typingCallCount"] = 1
                        safe["finalSecureEntryMatched"] = journey.waitForSecureEntry(
                            field, characterCount: expected.count)
                        safe["maskedCountAtEnd"] = (field.value as? String)?.count ?? -1
                        safe["focusAfterTyping"] = NSPredicate(format: "hasKeyboardFocus == true")
                            .evaluate(with: field)
                        if reachWithoutAssertions(eye, app: app) {
                            eye.tap()
                            cleanup.wasRevealed = true
                            if shown.waitForExistence(timeout: 5), let value = shown.value as? String {
                                safe["shownValueAvailable"] = true
                                safe["shownCount"] = value.count
                                safe["shownMatchesExpected"] = value == expected
                            }
                        }
                    }
                }
            }
        }
        // All values and equality comparisons stay local. Hide BEFORE the
        // receipt/assertions/automatic failure capture; no password screenshots.
        safe["hiddenBeforeAssertions"] = cleanup.hideAndVerify()
        let receipt = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        receipt.name = "first-password-en-light-L-fresh-no-preparation-counts-and-booleans"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue(safe["hiddenBeforeAssertions"] as? Bool == true)
        for key in ["openSignUpReached", "emailReached", "passwordReached", "focusBeforeTyping",
                    "focusAfterTyping", "clipboardEmpty", "shownValueAvailable"] {
            XCTAssertTrue(safe[key] as? Bool == true, key)
        }
        XCTAssertTrue(safe["freshFieldEmpty"] as? Bool == true)
        XCTAssertEqual(safe["typingCallCount"] as? Int, 1)
        XCTAssertEqual(safe["maskedCountAtEnd"] as? Int, expected.count)
        XCTAssertEqual(safe["shownCount"] as? Int, expected.count)
        XCTAssertTrue(safe["shownMatchesExpected"] as? Bool == true)
        XCTAssertTrue(safe["finalSecureEntryMatched"] as? Bool == true)
        XCTAssertFalse(journey.element("screen.onboarding.body-data", app).exists)
    }
}


// Query-only ownership diagnostic: no password input, Cancel action, reveal or submit.
// Service IDs come from pinned local runtime metadata; neither is a confirmed owner.
extension OnboardingPasswordBindingDiagnosticUITests {
    func testEnglishLightDefaultSizeStrongPasswordPopoverQueriesBeforePasswordInput() throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        let app = journey.launch("--ui-testing-signup-body-photos-capture",
            language: "en-US", dark: false, category: "UICTContentSizeCategoryL")
        let cleanup = PasswordBindingDiagnosticCleanup(app: app,
            eye: app.buttons["auth.password.visibility"],
            shown: journey.element("auth.password.shown", app))
        addTeardownBlock { await cleanup.tearDown() }
        UIPasteboard.general.string = nil
        var safe: [String: Any] = [
            "passwordInputSent": false, "cancelActionSent": false,
            "visibilityActionSent": false, "signupSubmitSent": false,
            "openSignUpReached": false, "emailReached": false,
            "passwordMatchCount": -1, "passwordReached": false,
            "focusAfterPasswordTap": false, "queryPhaseReached": false,
            "ownerIsConfirmed": false,
        ]
        let open = app.buttons["auth.open-sign-up"]
        let opened = reachWithoutAssertions(open, app: app)
        safe["openSignUpReached"] = opened
        if opened {
            open.tap()
            let email = app.textFields["auth.email"]
            let emailReached = reachWithoutAssertions(email, app: app)
            safe["emailReached"] = emailReached
            if emailReached {
                email.tap()
                email.typeText("person@example.invalid")
                let fields = app.secureTextFields.matching(identifier: "auth.password")
                let fieldMatchCount = Int(fields.count)
                safe["passwordMatchCount"] = fieldMatchCount
                if fieldMatchCount == 1 {
                    let field = fields.element(boundBy: 0)
                    let reached = reachWithoutAssertions(field, app: app)
                    safe["passwordReached"] = reached
                    if reached {
                        field.tap()
                        safe["focusAfterPasswordTap"] = journey.waitForKeyboardFocus(field)
                        let targets: [(String, XCUIApplication, Bool)] = [
                            ("com.bodyflow.app", app, false),
                            ("com.apple.InputUI", XCUIApplication(bundleIdentifier: "com.apple.InputUI"), true),
                            ("com.apple.AuthenticationServicesUI",
                             XCUIApplication(bundleIdentifier: "com.apple.AuthenticationServicesUI"), true),
                        ]
                        let cancelLabels = ["Cancel", "Cancelar", "Close", "Fechar"]
                        // Exact allowlisted labels only: Root-observed PT title and local UIKit EN marker.
                        let promptLabels = ["Usar Senha Forte?", "Strong Password"]
                        var rows: [[String: Any]] = []
                        for (bundleID, owner, candidateOnly) in targets {
                            let state = owner.state
                            let queryAllowed = state == .runningForeground || state == .runningBackground
                            var row: [String: Any] = ["bundleIdentifier": bundleID,
                                "candidateOnly": candidateOnly, "state": Int(state.rawValue),
                                "queried": queryAllowed]
                            var cancelRows: [[String: Any]] = []
                            for label in cancelLabels {
                                var count = -1
                                var hittable = false
                                if queryAllowed {
                                    let matches = owner.buttons.matching(NSPredicate(format: "label == %@", label))
                                    count = Int(matches.count)
                                    if count == 1 { hittable = matches.element(boundBy: 0).isHittable }
                                }
                                cancelRows.append(["allowlistedLabel": label,
                                    "buttonCount": count, "singleButtonHittable": hittable])
                            }
                            var promptRows: [[String: Any]] = []
                            for label in promptLabels {
                                let count = queryAllowed ? Int(owner.staticTexts
                                    .matching(NSPredicate(format: "label == %@", label)).count) : -1
                                promptRows.append(["allowlistedLabel": label, "staticTextCount": count])
                            }
                            row["cancelQueries"] = cancelRows
                            row["promptQueries"] = promptRows
                            rows.append(row)
                        }
                        safe["owners"] = rows
                        safe["queryPhaseReached"] = true
                    }
                }
            }
        }
        // No shown/value/snapshot/debugDescription/password access. Terminate
        // the owned demo app before receipt/assertions can trigger an attachment.
        app.terminate()
        UIPasteboard.general.string = nil
        let receipt = XCTAttachment(data: try JSONSerialization.data(
            withJSONObject: safe, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        receipt.name = "first-password-popover-owner-allowlisted-query-counts"
        receipt.lifetime = .keepAlways
        add(receipt)
        for key in ["openSignUpReached", "emailReached", "passwordReached", "queryPhaseReached"] {
            XCTAssertTrue(safe[key] as? Bool == true, key)
        }
        XCTAssertEqual(safe["passwordMatchCount"] as? Int, 1)
        // Candidate absence/zero matches is evidence; it cannot assert an owner.
    }
}


// Explicit popup-dismissed comparison remains its own method.
// Fresh diagnostics now prepare the app-root offer; prior raw failure receipts are retained.
// App-root query cooccurrence is not OS ownership.
extension OnboardingPasswordBindingDiagnosticUITests {
    func testEnglishLightDefaultSizeFreshPasswordTypingAfterDismissingStrongPasswordPopup() throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        let app = journey.launch("--ui-testing-signup-body-photos-capture",
            language: "en-US", dark: false, category: "UICTContentSizeCategoryL")
        let eye = app.buttons["auth.password.visibility"]
        let shown = journey.element("auth.password.shown", app)
        let cleanup = PasswordBindingDiagnosticCleanup(app: app, eye: eye, shown: shown)
        addTeardownBlock { await cleanup.tearDown() }
        UIPasteboard.general.string = nil
        defer { UIPasteboard.general.string = nil }
        let expected = "local-pass" // allowlisted synthetic DEBUG input only
        var safe: [String: Any] = [
            "expectedCount": expected.count, "typingCallCount": 0,
            "clipboardEmpty": UIPasteboard.general.string == nil,
            "escapeAttempted": false, "selectAllAttempted": false,
            "deleteAttempted": false, "pasteAttempted": false, "signupSubmitSent": false,
            "openSignUpReached": false, "emailReached": false,
            "initialPasswordMatchCount": -1, "passwordReached": false,
            "promptAppeared": false, "promptMatchCountBeforeClose": -1,
            "closeMatchCount": -1, "closeHittable": false, "closeTapSent": false,
            "preTapPromptMatchCount": -1, "preTapCloseMatchCount": -1,
            "preTapAllKnownCloseMatchCount": -1, "preTapOtherModalCount": -1,
            "preTapCloseHasKnownXmarkIdentifier": false,
            "promptDisappearedBeforeTyping": false, "refetchedPasswordMatchCount": -1,
            "refetchedPasswordReached": false, "focusBeforeTyping": false,
            "freshAXCount": -1, "freshFieldEmpty": false,
            "maskedCountAtEnd": -1, "shownCount": -1,
            "focusAfterTyping": false, "finalSecureEntryMatched": false,
            "shownValueAvailable": false, "shownMatchesExpected": false,
            "hiddenBeforeAssertions": false,
        ]
        let observe = {
            let open = app.buttons["auth.open-sign-up"]
            let opened = self.reachWithoutAssertions(open, app: app)
            safe["openSignUpReached"] = opened
            guard opened else { return }
            open.tap()
            let email = app.textFields["auth.email"]
            let emailReached = self.reachWithoutAssertions(email, app: app)
            safe["emailReached"] = emailReached
            guard emailReached else { return }
            email.tap()
            email.typeText("person@example.invalid")
            let initialFields = app.secureTextFields.matching(identifier: "auth.password")
            let initialCount = Int(initialFields.count)
            safe["initialPasswordMatchCount"] = initialCount
            guard initialCount == 1 else { return }
            let initial = initialFields.element(boundBy: 0)
            let reached = self.reachWithoutAssertions(initial, app: app)
            safe["passwordReached"] = reached
            guard reached else { return }
            initial.tap()
            let prompts = app.staticTexts.matching(NSPredicate(format: "label == %@", "Usar Senha Forte?"))
            let prompt = prompts.element(boundBy: 0)
            let appeared = prompt.waitForExistence(timeout: 5)
            let promptCount = Int(prompts.count)
            safe["promptAppeared"] = appeared
            safe["promptMatchCountBeforeClose"] = promptCount
            guard appeared && promptCount == 1 else { return }
            let closes = app.buttons.matching(NSPredicate(format: "label == %@", "Fechar"))
            let closeCount = Int(closes.count)
            safe["closeMatchCount"] = closeCount
            guard closeCount == 1 else { return }
            var close = closes.element(boundBy: 0)
            let hittable = close.isHittable
            safe["closeHittable"] = hittable // Metadata, not a necessary public-tap condition (2C68AE3F).
            let titlePredicate = NSPredicate(format: "label == %@", "Usar Senha Forte?")
            let currentPrompts = app.staticTexts.matching(titlePredicate)
            let currentCloses = app.buttons.matching(NSPredicate(format: "label == %@", "Fechar"))
            let currentTitleCount = Int(currentPrompts.count)
            let currentCloseCount = Int(currentCloses.count)
            let allKnownCloseCount = Int(app.buttons.matching(NSPredicate(
                format: "label == %@ OR label == %@", "Fechar", "Close")).count)
            let currentModals = app.alerts.allElementsBoundByIndex + app.sheets.allElementsBoundByIndex
            let otherModalCount = currentModals.reduce(0) { count, modal in
                count + (modal.staticTexts.matching(titlePredicate).count == 1 ? 0 : 1)
            }
            safe["preTapPromptMatchCount"] = currentTitleCount
            safe["preTapCloseMatchCount"] = currentCloseCount
            safe["preTapAllKnownCloseMatchCount"] = allKnownCloseCount
            safe["preTapOtherModalCount"] = otherModalCount
            guard currentTitleCount == 1 && currentCloseCount == 1
                && allKnownCloseCount == 1 && otherModalCount == 0 else { return }
            close = currentCloses.element(boundBy: 0)
            let knownIdentifier = close.identifier == "xmark"
            safe["preTapCloseHasKnownXmarkIdentifier"] = knownIdentifier
            guard knownIdentifier else { return }
            close.tap()
            safe["closeTapSent"] = true
            let disappeared = prompt.waitForNonExistence(timeout: 5)
            safe["promptDisappearedBeforeTyping"] = disappeared
            guard disappeared else { return }
            // Refetch after dismissing. Do not tap/refocus and reopen the popup.
            let fields = app.secureTextFields.matching(identifier: "auth.password")
            let fieldCount = Int(fields.count)
            safe["refetchedPasswordMatchCount"] = fieldCount
            guard fieldCount == 1 else { return }
            let field = fields.element(boundBy: 0)
            let fieldReached = self.reachWithoutAssertions(field, app: app)
            safe["refetchedPasswordReached"] = fieldReached
            guard fieldReached else { return }
            let focused = journey.waitForKeyboardFocus(field)
            safe["focusBeforeTyping"] = focused
            guard focused else { return }
            let freshValue = field.value as? String
            let freshEmpty = freshValue != nil && (freshValue!.isEmpty
                || (field.placeholderValue != nil && freshValue == field.placeholderValue))
            safe["freshAXCount"] = freshValue?.count ?? -1
            safe["freshFieldEmpty"] = freshEmpty
            guard freshEmpty else { return }
            field.typeText(expected)
            safe["typingCallCount"] = 1
            safe["finalSecureEntryMatched"] = journey.waitForSecureEntry(field, characterCount: expected.count)
            safe["maskedCountAtEnd"] = (field.value as? String)?.count ?? -1
            safe["focusAfterTyping"] = NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field)
            guard self.reachWithoutAssertions(eye, app: app) else { return }
            eye.tap()
            cleanup.wasRevealed = true
            if shown.waitForExistence(timeout: 5), let value = shown.value as? String {
                safe["shownValueAvailable"] = true
                safe["shownCount"] = value.count
                safe["shownMatchesExpected"] = value == expected
            }
        }
        observe()
        // Hide using the existing cleanup before receipt/assertions/automatic capture.
        safe["hiddenBeforeAssertions"] = cleanup.hideAndVerify()
        let receipt = XCTAttachment(data: try JSONSerialization.data(
            withJSONObject: safe, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        receipt.name = "first-password-en-light-L-popup-dismissed-counts-and-booleans"
        receipt.lifetime = .keepAlways
        add(receipt)
        for key in ["openSignUpReached", "emailReached", "passwordReached", "promptAppeared",
                    "preTapCloseHasKnownXmarkIdentifier", "closeTapSent", "promptDisappearedBeforeTyping",
                    "refetchedPasswordReached", "focusBeforeTyping", "freshFieldEmpty", "clipboardEmpty",
                    "focusAfterTyping", "shownValueAvailable", "shownMatchesExpected",
                    "finalSecureEntryMatched", "hiddenBeforeAssertions"] {
            XCTAssertTrue(safe[key] as? Bool == true, key)
        }
        for key in ["initialPasswordMatchCount", "promptMatchCountBeforeClose", "closeMatchCount",
                    "refetchedPasswordMatchCount", "typingCallCount"] {
            XCTAssertEqual(safe[key] as? Int, 1, key)
        }
        for key in ["preTapPromptMatchCount", "preTapCloseMatchCount", "preTapAllKnownCloseMatchCount"] {
            XCTAssertEqual(safe[key] as? Int, 1, key)
        }
        XCTAssertEqual(safe["preTapOtherModalCount"] as? Int, 0)
        XCTAssertEqual(safe["maskedCountAtEnd"] as? Int, expected.count)
        XCTAssertEqual(safe["shownCount"] as? Int, expected.count)
        XCTAssertFalse(journey.element("screen.onboarding.body-data", app).exists)
    }
}


// TDD of the actual public preparer. App languages differ; the observed system
// popup is PT on this owned runtime. No unverified English popup copy is used.
extension OnboardingPasswordBindingDiagnosticUITests {
    func testPortugueseLightDefaultSizeActualStrongPasswordPreparerBeforeTyping() throws {
        try observeActualStrongPasswordPreparer(
            language: "pt-BR", dark: false, category: "UICTContentSizeCategoryL")
    }

    func testEnglishDarkAXXXLActualStrongPasswordPreparerBeforeTyping() throws {
        try observeActualStrongPasswordPreparer(
            language: "en-US", dark: true, category: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func observeActualStrongPasswordPreparer(
        language: String, dark: Bool, category: String
    ) throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        let app = journey.launch("--ui-testing-signup-body-photos-capture",
            language: language, dark: dark, category: category)
        let eye = app.buttons["auth.password.visibility"]
        let shown = journey.element("auth.password.shown", app)
        let cleanup = PasswordBindingDiagnosticCleanup(app: app, eye: eye, shown: shown)
        addTeardownBlock { await cleanup.tearDown() }
        UIPasteboard.general.string = nil
        defer { UIPasteboard.general.string = nil }
        let expected = "local-pass" // allowlisted synthetic DEBUG input only
        var safe: [String: Any] = [
            "expectedCount": expected.count, "typingCallCount": 0,
            "clipboardEmpty": UIPasteboard.general.string == nil,
            "escapeAttempted": false, "selectAllAttempted": false,
            "deleteAttempted": false, "pasteAttempted": false, "signupSubmitSent": false,
            "openSignUpReached": false, "emailReached": false,
            "initialPasswordMatchCount": -1, "passwordReached": false,
            "promptAppeared": false, "promptMatchCountBeforeClose": -1,
            "closeMatchCount": -1, "closeHittable": false,
            "promptDisappearedBeforeTyping": false, "refetchedPasswordMatchCount": -1,
            "refetchedPasswordReached": false, "focusBeforeTyping": false,
            "freshAXCount": -1, "freshFieldEmpty": false,
            "maskedCountAtEnd": -1, "shownCount": -1,
            "focusAfterTyping": false, "finalSecureEntryMatched": false,
            "shownValueAvailable": false, "shownMatchesExpected": false,
            "hiddenBeforeAssertions": false, "preparerReturnedTrue": false,
        ]
        let observe = {
            let open = app.buttons["auth.open-sign-up"]
            let opened = self.reachWithoutAssertions(open, app: app)
            safe["openSignUpReached"] = opened
            guard opened else { return }
            open.tap()
            let email = app.textFields["auth.email"]
            let emailReached = self.reachWithoutAssertions(email, app: app)
            safe["emailReached"] = emailReached
            guard emailReached else { return }
            email.tap()
            email.typeText("person@example.invalid")
            let initialFields = app.secureTextFields.matching(identifier: "auth.password")
            let initialCount = Int(initialFields.count)
            safe["initialPasswordMatchCount"] = initialCount
            guard initialCount == 1 else { return }
            let initial = initialFields.element(boundBy: 0)
            let reached = self.reachWithoutAssertions(initial, app: app)
            safe["passwordReached"] = reached
            guard reached else { return }
            initial.tap()
            let prompts = app.staticTexts.matching(NSPredicate(format: "label == %@", "Usar Senha Forte?"))
            let prompt = prompts.element(boundBy: 0)
            let appeared = prompt.waitForExistence(timeout: 5)
            let promptCount = Int(prompts.count)
            safe["promptAppeared"] = appeared
            safe["promptMatchCountBeforeClose"] = promptCount
            guard appeared && promptCount == 1 else { return }
            let closes = app.buttons.matching(NSPredicate(format: "label == %@", "Fechar"))
            let closeCount = Int(closes.count)
            safe["closeMatchCount"] = closeCount
            guard closeCount == 1 else { return }
            let close = closes.element(boundBy: 0)
            // Readiness of this observed Close only; do not swipe behind the modal.
            let hitPredicate = NSPredicate(format: "isHittable == true")
            let hitExpectation = XCTNSPredicateExpectation(predicate: hitPredicate, object: close)
            let hitResult = XCTWaiter.wait(for: [hitExpectation], timeout: 5)
            let finalHittable = hitPredicate.evaluate(with: close)
            let hittable = OnboardingJourneyWaitRevalidation.matches(result: hitResult) {
                finalHittable
            } && finalHittable
            safe["closeHittabilityWaitResult"] = Int(hitResult.rawValue)
            safe["closeHittableRevalidated"] = finalHittable
            safe["closeHittable"] = hittable
            let closeFrame = close.frame
            let closeFramePositive = closeFrame.width > 0 && closeFrame.height > 0
            safe["closeFramePositive"] = closeFramePositive
            let windowCount = Int(app.windows.count)
            safe["windowMatchCount"] = windowCount
            var windowFramePositive = false
            var frameInsideWindow = false
            if windowCount > 0 {
                let windowFrame = app.windows.element(boundBy: 0).frame
                windowFramePositive = windowFrame.width > 0 && windowFrame.height > 0
                frameInsideWindow = closeFramePositive && windowFramePositive && windowFrame.contains(closeFrame)
            }
            safe["windowFramePositive"] = windowFramePositive
            safe["closeFrameInsideWindow"] = frameInsideWindow
            let prepared = journey.prepareFirstAuthPasswordForTyping(in: initial, app)
            safe["preparerReturnedTrue"] = prepared
            guard prepared else { return }
            let disappeared = prompt.waitForNonExistence(timeout: 5)
            safe["promptDisappearedBeforeTyping"] = disappeared
            guard disappeared else { return }
            // Refetch after dismissing. Do not tap/refocus and reopen the popup.
            let fields = app.secureTextFields.matching(identifier: "auth.password")
            let fieldCount = Int(fields.count)
            safe["refetchedPasswordMatchCount"] = fieldCount
            guard fieldCount == 1 else { return }
            let field = fields.element(boundBy: 0)
            let fieldReached = self.reachWithoutAssertions(field, app: app)
            safe["refetchedPasswordReached"] = fieldReached
            guard fieldReached else { return }
            let focused = journey.waitForKeyboardFocus(field)
            safe["focusBeforeTyping"] = focused
            guard focused else { return }
            let freshValue = field.value as? String
            let freshEmpty = freshValue != nil && (freshValue!.isEmpty
                || (field.placeholderValue != nil && freshValue == field.placeholderValue))
            safe["freshAXCount"] = freshValue?.count ?? -1
            safe["freshFieldEmpty"] = freshEmpty
            guard freshEmpty else { return }
            field.typeText(expected)
            safe["typingCallCount"] = 1
            safe["finalSecureEntryMatched"] = journey.waitForSecureEntry(field, characterCount: expected.count)
            safe["maskedCountAtEnd"] = (field.value as? String)?.count ?? -1
            safe["focusAfterTyping"] = NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field)
            guard self.reachWithoutAssertions(eye, app: app) else { return }
            eye.tap()
            cleanup.wasRevealed = true
            if shown.waitForExistence(timeout: 5), let value = shown.value as? String {
                safe["shownValueAvailable"] = true
                safe["shownCount"] = value.count
                safe["shownMatchesExpected"] = value == expected
            }
        }
        observe()
        // Hide using the existing cleanup before receipt/assertions/automatic capture.
        safe["hiddenBeforeAssertions"] = cleanup.hideAndVerify()
        app.terminate()
        let receipt = XCTAttachment(data: try JSONSerialization.data(
            withJSONObject: safe, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        receipt.name = "first-password-actual-preparer-counts-and-booleans"
        receipt.lifetime = .keepAlways
        add(receipt)
        for key in ["openSignUpReached", "emailReached", "passwordReached", "promptAppeared",
                    "preparerReturnedTrue", "promptDisappearedBeforeTyping",
                    "refetchedPasswordReached", "focusBeforeTyping", "freshFieldEmpty", "clipboardEmpty",
                    "focusAfterTyping", "shownValueAvailable", "shownMatchesExpected",
                    "finalSecureEntryMatched", "hiddenBeforeAssertions"] {
            XCTAssertTrue(safe[key] as? Bool == true, key)
        }
        for key in ["initialPasswordMatchCount", "promptMatchCountBeforeClose", "closeMatchCount",
                    "refetchedPasswordMatchCount", "typingCallCount"] {
            XCTAssertEqual(safe[key] as? Int, 1, key)
        }
        XCTAssertEqual(safe["maskedCountAtEnd"] as? Int, expected.count)
        XCTAssertEqual(safe["shownCount"] as? Int, expected.count)
    }
}


// No-password public Close diagnostic; this does not change the shared preparer.
extension OnboardingPasswordBindingDiagnosticUITests {
    func testPortugueseLightDefaultSizeKnownStrongPasswordClosePublicTapWithoutHittabilityGate() throws {
        continueAfterFailure = false
        let journey = OnboardingJourneyUITestSupport(testCase: self)
        // Same first PT iteration of SignupBodyPhotoManualFormUITests.
        let app = journey.launch(language: "pt-BR")
        let cleanup = PasswordBindingDiagnosticCleanup(app: app,
            eye: app.buttons["auth.password.visibility"],
            shown: journey.element("auth.password.shown", app))
        addTeardownBlock { await cleanup.tearDown() }
        UIPasteboard.general.string = nil
        var safe: [String: Any] = [
            "passwordInputSent": false, "visibilityActionSent": false, "signupSubmitSent": false,
            "escapeAttempted": false, "pasteAttempted": false,
            "openSignUpReached": false, "emailReached": false,
            "passwordMatchCount": -1, "passwordReached": false, "focusAfterPasswordTap": false,
            "promptAppeared": false, "promptMatchCount": -1,
            "fecharButtonMatchCount": -1, "allKnownCloseMatchCount": -1, "xmarkButtonMatchCount": -1,
            "closeHasKnownXmarkIdentifier": false, "closeEnabled": false, "closeHittable": false,
            "closeFrameFinite": false, "closeFramePositive": false, "windowMatchCount": -1,
            "windowFrameFinitePositive": false, "closeFrameInsideWindow": false,
            "otherModalCount": -1, "preTapPromptMatchCount": -1, "preTapCloseMatchCount": -1,
            "preTapAllKnownCloseMatchCount": -1, "preTapOtherModalCount": -1,
            "preTapCloseHasKnownXmarkIdentifier": false,
            "publicCloseTapAttempted": false, "publicCloseTapReturned": false,
            "promptGoneAfterTap": false, "promptMatchCountAfterTap": -1,
            "terminatedBeforeAssertions": false, "clipboardEmptyAtEnd": false,
        ]
        let observe = {
            let open = app.buttons["auth.open-sign-up"]
            let opened = self.reachWithoutAssertions(open, app: app)
            safe["openSignUpReached"] = opened
            guard opened else { return }
            open.tap()
            let email = app.textFields["auth.email"]
            let emailReached = self.reachWithoutAssertions(email, app: app)
            safe["emailReached"] = emailReached
            guard emailReached else { return }
            email.tap()
            email.typeText("person@example.invalid")
            let fields = app.secureTextFields.matching(identifier: "auth.password")
            let fieldCount = Int(fields.count)
            safe["passwordMatchCount"] = fieldCount
            guard fieldCount == 1 else { return }
            let field = fields.element(boundBy: 0)
            let reached = self.reachWithoutAssertions(field, app: app)
            safe["passwordReached"] = reached
            guard reached else { return }
            field.tap()
            let focused = journey.waitForKeyboardFocus(field)
            safe["focusAfterPasswordTap"] = focused
            guard focused else { return }
            // No swipe, password input, Escape, or preparer call after this focus.
            let titlePredicate = NSPredicate(format: "label == %@", "Usar Senha Forte?")
            let prompts = app.staticTexts.matching(titlePredicate)
            let appeared = prompts.element(boundBy: 0).waitForExistence(timeout: 5)
            let titleCount = Int(prompts.count)
            safe["promptAppeared"] = appeared
            safe["promptMatchCount"] = titleCount
            guard appeared && titleCount == 1 else { return }
            let closePredicate = NSPredicate(format: "label == %@", "Fechar")
            let allClosePredicate = NSPredicate(format: "label == %@ OR label == %@", "Fechar", "Close")
            let closes = app.buttons.matching(closePredicate)
            let closeCount = Int(closes.count)
            let allCloseCount = Int(app.buttons.matching(allClosePredicate).count)
            safe["fecharButtonMatchCount"] = closeCount
            safe["allKnownCloseMatchCount"] = allCloseCount
            safe["xmarkButtonMatchCount"] = Int(app.buttons.matching(identifier: "xmark").count)
            guard closeCount == 1 && allCloseCount == 1 else { return }
            let close = closes.element(boundBy: 0)
            let knownIdentifier = close.identifier == "xmark"
            safe["closeHasKnownXmarkIdentifier"] = knownIdentifier
            safe["closeEnabled"] = close.isEnabled
            safe["closeHittable"] = close.isHittable // Diagnostic only; not an action guard.
            let frame = close.frame
            let finite = [frame.minX, frame.minY, frame.maxX, frame.maxY, frame.width, frame.height]
                .allSatisfy { $0.isFinite }
            let positive = frame.width > 0 && frame.height > 0
            safe["closeFrameFinite"] = finite
            safe["closeFramePositive"] = positive
            let windowCount = Int(app.windows.count)
            safe["windowMatchCount"] = windowCount
            var windowFinitePositive = false
            var insideWindow = false
            if windowCount > 0 {
                let window = app.windows.element(boundBy: 0).frame
                windowFinitePositive = [window.minX, window.minY, window.maxX, window.maxY,
                    window.width, window.height].allSatisfy { $0.isFinite }
                    && window.width > 0 && window.height > 0
                insideWindow = finite && positive && windowFinitePositive && window.contains(frame)
            }
            safe["windowFrameFinitePositive"] = windowFinitePositive
            safe["closeFrameInsideWindow"] = insideWindow
            let modals = app.alerts.allElementsBoundByIndex + app.sheets.allElementsBoundByIndex
            let otherModalCount = modals.reduce(0) { count, modal in
                count + (modal.staticTexts.matching(titlePredicate).count == 1 ? 0 : 1)
            }
            safe["otherModalCount"] = otherModalCount
            guard knownIdentifier && otherModalCount == 0 else { return }
            // Requery the exact target/modal shape; still no isHittable/geometry gate.
            let currentPrompts = app.staticTexts.matching(titlePredicate)
            let currentCloses = app.buttons.matching(closePredicate)
            let currentTitleCount = Int(currentPrompts.count)
            let currentCloseCount = Int(currentCloses.count)
            let currentAllCloseCount = Int(app.buttons.matching(allClosePredicate).count)
            let currentModals = app.alerts.allElementsBoundByIndex + app.sheets.allElementsBoundByIndex
            let currentOtherModalCount = currentModals.reduce(0) { count, modal in
                count + (modal.staticTexts.matching(titlePredicate).count == 1 ? 0 : 1)
            }
            safe["preTapPromptMatchCount"] = currentTitleCount
            safe["preTapCloseMatchCount"] = currentCloseCount
            safe["preTapAllKnownCloseMatchCount"] = currentAllCloseCount
            safe["preTapOtherModalCount"] = currentOtherModalCount
            guard currentTitleCount == 1 && currentCloseCount == 1
                && currentAllCloseCount == 1 && currentOtherModalCount == 0 else { return }
            let target = currentCloses.element(boundBy: 0)
            let targetKnown = target.identifier == "xmark"
            safe["preTapCloseHasKnownXmarkIdentifier"] = targetKnown
            guard targetKnown else { return }
            safe["publicCloseTapAttempted"] = true
            target.tap() // Exactly one public tap; no guarantee from a nonhittable observation.
            safe["publicCloseTapReturned"] = true
            let gone = currentPrompts.element(boundBy: 0).waitForNonExistence(timeout: 5)
            safe["promptGoneAfterTap"] = gone
            safe["promptMatchCountAfterTap"] = Int(app.staticTexts.matching(titlePredicate).count)
        }
        observe()
        // No password/value/reveal access occurred. Terminate before receipt/assertions.
        app.terminate()
        UIPasteboard.general.string = nil
        safe["terminatedBeforeAssertions"] = app.state == .notRunning
        safe["clipboardEmptyAtEnd"] = UIPasteboard.general.string == nil
        let receipt = XCTAttachment(data: try JSONSerialization.data(
            withJSONObject: safe, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        receipt.name = "pt-fresh-auth-known-close-public-tap-no-password-counts-and-booleans"
        receipt.lifetime = .keepAlways
        add(receipt)
        for key in ["openSignUpReached", "emailReached", "passwordReached", "focusAfterPasswordTap",
                    "promptAppeared", "closeHasKnownXmarkIdentifier", "preTapCloseHasKnownXmarkIdentifier",
                    "publicCloseTapAttempted", "publicCloseTapReturned", "promptGoneAfterTap",
                    "terminatedBeforeAssertions", "clipboardEmptyAtEnd"] {
            XCTAssertTrue(safe[key] as? Bool == true, key)
        }
        for key in ["passwordMatchCount", "promptMatchCount", "fecharButtonMatchCount",
                    "allKnownCloseMatchCount", "preTapPromptMatchCount", "preTapCloseMatchCount",
                    "preTapAllKnownCloseMatchCount"] {
            XCTAssertEqual(safe[key] as? Int, 1, key)
        }
        XCTAssertEqual(safe["otherModalCount"] as? Int, 0)
        XCTAssertEqual(safe["preTapOtherModalCount"] as? Int, 0)
        XCTAssertEqual(safe["promptMatchCountAfterTap"] as? Int, 0)
        // enabled/hittable/frame metadata are observations, never success gates.
    }
}
