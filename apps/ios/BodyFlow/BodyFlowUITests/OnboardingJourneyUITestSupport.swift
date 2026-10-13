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
            guard prepareFirstAuthPasswordForTyping(in: field, app) else {
                XCTFail("First password popup preparation was inconclusive", file: file, line: line)
                return
            }
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


    // Only the app-root offer/title and public Close action established by G1.
    // No password value is read here; no other field or unidentified modal is dismissed.
    func prepareFirstAuthPasswordForTyping(in field: XCUIElement, _ app: XCUIApplication) -> Bool {
        guard field.identifier == "auth.password", field.exists else { return false }
        let initialFields = app.secureTextFields.matching(identifier: "auth.password")
        guard initialFields.count == 1 else { return false }
        let titlePredicate = NSPredicate(format: "label == %@", "Usar Senha Forte?")
        let closePredicate = NSPredicate(format: "label == %@ OR label == %@", "Fechar", "Close")
        func readCurrentDecision() -> OnboardingStrongPasswordOfferDecision {
            let currentPrompts = app.staticTexts.matching(titlePredicate)
            let currentCloses = app.buttons.matching(closePredicate)
            let currentPromptCount = Int(currentPrompts.count)
            let currentCloseCount = Int(currentCloses.count)
            let currentModals = app.alerts.allElementsBoundByIndex + app.sheets.allElementsBoundByIndex
            let currentOtherModalCount = currentModals.reduce(0) { count, modal in
                count + (modal.staticTexts.matching(titlePredicate).count == 1 ? 0 : 1)
            }
            let currentHittable = currentPromptCount == 1 && currentCloseCount == 1
                && currentCloses.element(boundBy: 0).isHittable
            var publicCloseEligible = false
            if currentPromptCount == 1 && currentCloseCount == 1 && currentOtherModalCount == 0
                && !currentHittable {
                let target = currentCloses.element(boundBy: 0)
                let frame = target.frame
                let finite = [frame.minX, frame.minY, frame.maxX, frame.maxY, frame.width, frame.height]
                    .allSatisfy { $0.isFinite }
                let positive = frame.width > 0 && frame.height > 0
                var insideWindow = false
                if app.windows.count > 0 {
                    let window = app.windows.element(boundBy: 0).frame
                    let windowFinitePositive = [window.minX, window.minY, window.maxX, window.maxY,
                        window.width, window.height].allSatisfy { $0.isFinite }
                        && window.width > 0 && window.height > 0
                    insideWindow = finite && positive && windowFinitePositive && window.contains(frame)
                }
                publicCloseEligible = OnboardingStrongPasswordOfferDecision.knownPublicCloseEligible(
                    knownXmark: target.identifier == "xmark", enabled: target.isEnabled,
                    frameFinite: finite, framePositive: positive, frameInsideWindow: insideWindow)
            }
            return OnboardingStrongPasswordOfferDecision.evaluate(
                promptCount: currentPromptCount, closeCount: currentCloseCount,
                closeHittable: currentHittable, otherModalCount: currentOtherModalCount,
                publicCloseEligible: publicCloseEligible)
        }
        let prompts = app.staticTexts.matching(titlePredicate)
        let promptCount = Int(prompts.count)
        let closes = app.buttons.matching(closePredicate)
        let closeCount = Int(closes.count)
        let modalContainers = app.alerts.allElementsBoundByIndex + app.sheets.allElementsBoundByIndex
        let otherModalCount = modalContainers.reduce(0) { count, modal in
            count + (modal.staticTexts.matching(titlePredicate).count == 1 ? 0 : 1)
        }
        var closeHittable = false
        if promptCount == 1 && closeCount == 1 && otherModalCount == 0 {
            let close = closes.element(boundBy: 0)
            let predicate = NSPredicate(format: "isHittable == true")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: close)
            let result = XCTWaiter.wait(for: [expectation], timeout: 5)
            let finalHittable = predicate.evaluate(with: close)
            closeHittable = OnboardingJourneyWaitRevalidation.matches(result: result) {
                finalHittable
            } && finalHittable
        }
        var decision = OnboardingStrongPasswordOfferDecision.evaluate(
            promptCount: promptCount, closeCount: closeCount,
            closeHittable: closeHittable, otherModalCount: otherModalCount
        )
        if decision == .blocked && promptCount == 1 && closeCount == 1 && otherModalCount == 0
            && !closeHittable {
            // Explicit alternative only for this known false-hit offer; no generic retry/dismiss.
            let currentDecision = readCurrentDecision()
            if currentDecision == .dismissRecognizedOffer { decision = currentDecision }
        }
        switch decision {
        case .blocked:
            return false
        case .noOffer:
            break
        case .dismissRecognizedOffer:
            // Read the whole shape again after the wait, immediately before the tap.
            guard OnboardingStrongPasswordOfferDecision.matchesCurrent(
                .dismissRecognizedOffer, read: readCurrentDecision
            ) else { return false }
            closes.element(boundBy: 0).tap()
            guard prompts.element(boundBy: 0).waitForNonExistence(timeout: 5), prompts.count == 0 else {
                return false
            }
        }
        // Refetch without tapping/refocusing and reopening the offer.
        let fields = app.secureTextFields.matching(identifier: "auth.password")
        guard fields.count == 1 else { return false }
        let current = fields.element(boundBy: 0)
        guard current.exists, waitForKeyboardFocus(current), fields.count == 1,
              NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: current) else {
            return false
        }
        // No offer/unknown modal may appear while focus is being awaited.
        return OnboardingStrongPasswordOfferDecision.matchesCurrent(.noOffer, read: readCurrentDecision)
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

/// Pure UITest-only selection from allowlisted query metadata; no UI actions.
enum OnboardingStrongPasswordOfferDecision: Equatable {
    case noOffer, dismissRecognizedOffer, blocked

    /// Invoke the reader at the action boundary; never reuse a pre-wait decision.
    static func matchesCurrent(_ expected: Self, read: () -> Self) -> Bool {
        read() == expected
    }

    static func knownPublicCloseEligible(
        knownXmark: Bool, enabled: Bool, frameFinite: Bool, framePositive: Bool, frameInsideWindow: Bool
    ) -> Bool {
        knownXmark && enabled && frameFinite && framePositive && frameInsideWindow
    }

    static func evaluate(
        promptCount: Int, closeCount: Int, closeHittable: Bool, otherModalCount: Int,
        publicCloseEligible: Bool = false
    ) -> Self {
        guard otherModalCount == 0 else { return .blocked }
        if promptCount == 0 && closeCount == 0 { return .noOffer }
        if promptCount == 1 && closeCount == 1 && (closeHittable || publicCloseEligible) {
            return .dismissRecognizedOffer
        }
        return .blocked
    }
}
