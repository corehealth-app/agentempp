import UIKit
import XCTest

/// The walk through the sign-up that the second update's UI tests share
/// (2026-10-11): launch, create the local account, and move step by step.
/// The typing recipes are the ones `OnboardingEligibilityUITests` settled on.
@MainActor
struct OnboardingJourneyUITestSupport {
    let testCase: XCTestCase

    private var support: PremiumUIUXUITestSupport { .init(testCase: testCase) }

    static let documentKeys = ["qa_onboarding_required", "qa_onboarding_notice", "qa_onboarding_consent"]

    func launch(
        _ scenario: String = "--ui-testing-fresh-auth",
        language: String = "pt-BR",
        dark: Bool = false,
        category: String = "UICTContentSizeCategoryL",
        extraArguments: [String] = []
    ) -> XCUIApplication {
        support.launch(
            arguments: [scenario] + extraArguments, language: language, dark: dark, category: category
        )
    }

    func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        support.element(identifier, app: app)
    }

    func capture(_ name: String, _ app: XCUIApplication) {
        support.capture(name, app: app)
    }

    /// Creates the local account and confirms it: the sign-up opens on its
    /// first step.
    func reachWelcome(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons["auth.open-sign-up"], app, file: file, line: line)
        enter("person@example.invalid", in: app.textFields["auth.email"], app, file: file, line: line)
        enterSecure("local-pass", in: app.secureTextFields["auth.password"], app, file: file, line: line)
        enterSecure(
            "local-pass", in: app.secureTextFields["auth.password-confirmation"], app, file: file, line: line
        )
        tap(app.buttons["auth.sign-up.submit"], app, file: file, line: line)
        tap(app.buttons["auth.confirm-development"], app, file: file, line: line)
        XCTAssertTrue(
            element("screen.onboarding.welcome", app).waitForExistence(timeout: 10),
            "The sign-up did not open on its first step", file: file, line: line
        )
    }

    /// From the first step: types the name and continues.
    func reachBodyData(
        _ app: XCUIApplication, name: String = "Pessoa QA",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        reachWelcome(app, file: file, line: line)
        enter(name + "\n", in: app.textFields["onboarding.display-name"], app, file: file, line: line)
        advance(app, file: file, line: line)
        XCTAssertTrue(
            element("screen.onboarding.body-data", app).waitForExistence(timeout: 5), file: file, line: line
        )
    }

    func reachRoutine(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        reachBodyData(app, file: file, line: line)
        advance(app, file: file, line: line)
        XCTAssertTrue(
            element("screen.onboarding.routine", app).waitForExistence(timeout: 5), file: file, line: line
        )
    }

    func advance(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons["onboarding.continue"], app, file: file, line: line)
    }

    func acceptDocuments(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for key in Self.documentKeys {
            let action = app.buttons["onboarding.legal-action.\(key)"]
            tap(action, app, file: file, line: line)
            XCTAssertTrue(action.isSelected, file: file, line: line)
        }
    }

    func reach(
        _ target: XCUIElement, _ app: XCUIApplication, attempts: Int = 60,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(target.waitForExistence(timeout: 5), "\(target) does not exist", file: file, line: line)
        for _ in 0..<attempts where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable, "\(target.identifier) must stay reachable", file: file, line: line)
    }

    func tap(
        _ target: XCUIElement, _ app: XCUIApplication, attempts: Int = 60,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        reach(target, app, attempts: attempts, file: file, line: line)
        target.tap()
    }

    func enter(
        _ value: String, in field: XCUIElement, _ app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        tap(field, app, file: file, line: line)
        field.typeText(value)
    }

    func enterSecure(
        _ value: String, in field: XCUIElement, _ app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        tap(field, app, file: file, line: line)
        XCTAssertTrue(waitForKeyboardFocus(field), file: file, line: line)
        if field.identifier == "auth.password" {
            field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(waitForKeyboardFocus(field), file: file, line: line)
        }
        UIPasteboard.general.string = value
        defer { UIPasteboard.general.string = nil }
        field.typeKey("v", modifierFlags: .command)
        if !waitForSecureEntry(field, characterCount: value.count, timeout: 1) {
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            for character in value {
                field.typeText(String(character))
            }
        }
        let matched = waitForSecureEntry(field, characterCount: value.count)
        if !matched {
            OnboardingSecureEntryFailureObserver.observe(
                expected: value, field: field, app: app, testCase: testCase
            )
        }
        XCTAssertTrue(matched, file: file, line: line)
    }

    func waitForKeyboardFocus(_ field: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "hasKeyboardFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: field)
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        return OnboardingJourneyWaitRevalidation.matches(result: result) {
            predicate.evaluate(with: field)
        }
    }

    func waitForSecureEntry(
        _ field: XCUIElement, characterCount: Int, timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  let value = element.value as? String else { return false }
            return value.count == characterCount
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: field)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return OnboardingJourneyWaitRevalidation.matches(result: result) {
            predicate.evaluate(with: field)
        }
    }

    /// A step has arrived when its progress line stopped moving: the step
    /// change fades and returns the column to its top.
    @discardableResult
    func waitUntilArrived(_ app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let progress = element("onboarding.progress", app)
        guard progress.waitForExistence(timeout: timeout) else { return false }
        var lastFrame: CGRect?
        var unchangedSince: TimeInterval?
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard progress.exists else {
                lastFrame = nil
                unchangedSince = nil
                return false
            }
            let now = ProcessInfo.processInfo.systemUptime
            let frame = progress.frame
            guard frame == lastFrame, let since = unchangedSince else {
                lastFrame = frame
                unchangedSince = now
                return false
            }
            return now - since >= 0.5
        }, object: nil)
        return XCTWaiter.wait(for: [settled], timeout: timeout) == .completed
    }

    /// Every button that says "Voltar" (or "Back"), with where it is.
    func backCommands(_ app: XCUIApplication, word: String = "Voltar") -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", word)).allElementsBoundByIndex
    }

    /// The scenario of the report: on arrival at a step, WITHOUT scrolling,
    /// some "Voltar" is entirely inside the window and can be touched.
    @discardableResult
    func assertBackInReachOnArrival(
        _ app: XCUIApplication, step: String, word: String = "Voltar",
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement? {
        waitUntilArrived(app)
        let window = app.windows.firstMatch.frame
        let candidates = backCommands(app, word: word)
        let described = candidates.map { "\($0.identifier) «\($0.label)» \($0.frame)" }
        let inReach = candidates.first { window.contains($0.frame) && $0.isHittable }
        XCTAssertNotNil(
            inReach,
            "\(step): no “\(word)” inside the window on arrival. Found: \(described); window: \(window)",
            file: file, line: line
        )
        return inReach
    }
}
