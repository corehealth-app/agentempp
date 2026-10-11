import UIKit
import XCTest

/// Diagnostic utility for the synthetic OnboardingJourney sign-up only.
/// Called after the unchanged final wait returns false; it does not retry
/// entry, submit, alter that result or replace the caller's assertion.
@MainActor
enum OnboardingSecureEntryFailureObserver {
    static func observe(
        expected: String, field: XCUIElement, app: XCUIApplication, testCase: XCTestCase
    ) {
        var receipt = SecureEntryFailureReceipt()
        receipt.isPassword = field.identifier == "auth.password"
        receipt.isConfirmation = field.identifier == "auth.password-confirmation"
        // Restrict revealing to the same synthetic input used by reachWelcome.
        receipt.callbackAllowed = expected == "local-pass"
            && (receipt.isPassword || receipt.isConfirmation)
        guard receipt.callbackAllowed else {
            attach(receipt, to: testCase)
            return
        }
        receipt.expectedCount = expected.count
        // Observe the failure entry before interacting with the eye.
        if let masked = field.value as? String {
            receipt.entrySecureValueAvailable = true
            receipt.entrySecureCount = masked.count
            receipt.entrySecureCountMatchesExpected = masked.count == expected.count
        }
        receipt.entryKeyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
            .evaluate(with: field)
        let eye = app.buttons[field.identifier + ".visibility"]
        let shown = app.descendants(matching: .any)
            .matching(identifier: field.identifier + ".shown").firstMatch
        let cleanup = SecureEntryFailureCleanup(app: app, eye: eye, shown: shown)
        testCase.addTeardownBlock { await cleanup.tearDown() }

        receipt.shownExistedBeforeEye = shown.exists
        cleanup.wasRevealed = receipt.shownExistedBeforeEye
        receipt.eyeExists = eye.exists
        receipt.eyeHittable = receipt.eyeExists && eye.isHittable
        if receipt.eyeHittable {
            if !receipt.shownExistedBeforeEye {
                eye.tap()
                cleanup.wasRevealed = true
            }
            receipt.shownExists = shown.waitForExistence(timeout: 5)
            if receipt.shownExists, let binding = shown.value as? String {
                receipt.shownValueAvailable = true
                receipt.shownCount = binding.count
                receipt.shownEqualsExpected = binding == expected
            }
        }
        // Missing shown/value stays inconclusive; it is never evidence of
        // empty input. A count match alone does not establish identity.
        receipt.inconclusive = !receipt.eyeHittable || !receipt.shownExists
            || !receipt.shownValueAvailable
        receipt.hiddenBeforeAssertion = cleanup.hideAndVerify()
        receipt.appTerminatedForHideFailure = cleanup.terminatedForHideFailure
        attach(receipt, to: testCase)
        // The caller now performs its original XCTAssertTrue(matched,...).
    }

    private static func attach(_ receipt: SecureEntryFailureReceipt, to testCase: XCTestCase) {
        let attachment = XCTAttachment(string: receipt.countsAndBooleans)
        attachment.name = "journey-secure-entry-failure-counts-and-booleans"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}

private struct SecureEntryFailureReceipt {
    var isPassword = false
    var isConfirmation = false
    var callbackAllowed = false
    var expectedCount = -1
    var entrySecureValueAvailable = false
    var entrySecureCount = -1
    var entrySecureCountMatchesExpected = false
    var entryKeyboardFocus = false
    var eyeExists = false
    var eyeHittable = false
    var shownExistedBeforeEye = false
    var shownExists = false
    var shownValueAvailable = false
    var shownCount = -1
    var shownEqualsExpected = false
    var hiddenBeforeAssertion = false
    var appTerminatedForHideFailure = false
    var inconclusive = true

    /// Only integer/boolean interpolation is allowed in this receipt.
    var countsAndBooleans: String {
        """
        originalPredicateMatched=false
        isPassword=\(isPassword)
        isConfirmation=\(isConfirmation)
        callbackAllowed=\(callbackAllowed)
        expectedCount=\(expectedCount)
        entrySecureValueAvailable=\(entrySecureValueAvailable)
        entrySecureCount=\(entrySecureCount)
        entrySecureCountMatchesExpected=\(entrySecureCountMatchesExpected)
        entryKeyboardFocus=\(entryKeyboardFocus)
        eyeExists=\(eyeExists)
        eyeHittable=\(eyeHittable)
        shownExistedBeforeEye=\(shownExistedBeforeEye)
        shownExists=\(shownExists)
        shownValueAvailable=\(shownValueAvailable)
        shownCount=\(shownCount)
        shownEqualsExpected=\(shownEqualsExpected)
        hiddenBeforeAssertion=\(hiddenBeforeAssertion)
        appTerminatedForHideFailure=\(appTerminatedForHideFailure)
        inconclusive=\(inconclusive)
        """
    }
}

/// A global actor type is Sendable for the Swift 6 teardown capture.
@MainActor
private final class SecureEntryFailureCleanup {
    let app: XCUIApplication
    let eye: XCUIElement
    let shown: XCUIElement
    var wasRevealed = false
    private var hidden = false
    private(set) var terminatedForHideFailure = false
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
            app.terminate()
            terminated = true
            terminatedForHideFailure = true
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
