import XCTest
import UIKit

final class PremiumAuthOnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAuthBrandAndTitleDoNotOverlapAXXXL() {
        let app = support.launch(
            arguments: ["--ui-testing-fresh-auth"],
            language: "pt-BR",
            dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let brand = support.element("brand.product-name", app: app)
        let title = support.element("auth.screen-title", app: app)
        XCTAssertTrue(brand.waitForExistence(timeout: 5))
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(brand.frame.intersects(title.frame))
        XCTAssertLessThan(brand.frame.maxY, title.frame.minY)
        support.capture("s2-auth-pt-light-axxxl", app: app)
    }

    @MainActor
    func testEnglishValidationAndNeutralRecoveryCopy() {
        let app = support.launch(
            arguments: ["--ui-testing-recovery"],
            language: "en-US",
            dark: true
        )
        XCTAssertTrue(app.staticTexts["Sign in"].waitForExistence(timeout: 5))
        let submit = app.buttons["auth.sign-in.submit"]
        submit.tap()
        XCTAssertTrue(app.staticTexts["Enter your email."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Enter your password."].exists)

        let recovery = app.buttons["auth.open-recovery"]
        reach(recovery, in: app)
        recovery.tap()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        email.tap()
        email.typeText("person@example.invalid")
        let send = app.buttons["auth.recovery.submit"]
        reach(send, in: app)
        send.tap()
        XCTAssertTrue(
            app.staticTexts[
                "If an account exists for this email, we will send recovery instructions."
            ].waitForExistence(timeout: 3)
        )
        support.capture("s2-recovery-en-dark", app: app)
    }

    @MainActor
    func testServerOwnedConsentActionsRemainReachableAXXXL() {
        let app = support.launch(
            arguments: ["--ui-testing-fresh-auth"],
            language: "pt-BR",
            dark: false
        )
        reachOfficialConsent(in: app)

        app.terminate()
        app.launchArguments = [
            "--ui-testing-preserve-state",
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR",
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(
            support.element("screen.onboarding.consent", app: app)
                .waitForExistence(timeout: 5)
        )

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Documento sintético de QA")
            ).firstMatch.waitForExistence(timeout: 3)
        )
        for key in [
            "qa_onboarding_required",
            "qa_onboarding_notice",
            "qa_onboarding_consent",
        ] {
            let action = app.buttons["onboarding.legal-action.\(key)"]
            reach(action, in: app, attempts: 60)
            support.assertTarget(action)
            action.tap()
            XCTAssertTrue(action.isSelected)
        }

        let continueButton = app.buttons["onboarding.continue"]
        reach(continueButton, in: app, attempts: 30)
        continueButton.tap()
        XCTAssertTrue(
            support.element("screen.onboarding.completion", app: app)
                .waitForExistence(timeout: 5)
        )
        let finish = app.buttons["onboarding.go-to-today"]
        reach(finish, in: app, attempts: 20)
        support.assertTarget(finish)
        support.capture("s2-consent-pt-light-axxxl", app: app)
    }

    @MainActor
    private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    @MainActor
    private func reachOfficialConsent(in app: XCUIApplication) {
        reach(app.buttons["auth.open-sign-up"], in: app)
        app.buttons["auth.open-sign-up"].tap()
        enter("person@example.invalid", in: app.textFields["auth.email"])
        enterSecure("local-pass", in: app.secureTextFields["auth.password"])
        enterSecure("local-pass", in: app.secureTextFields["auth.password-confirmation"])
        let signUp = app.buttons["auth.sign-up.submit"]
        reach(signUp, in: app)
        signUp.tap()
        let confirm = app.buttons["auth.confirm-development"]
        reach(confirm, in: app)
        confirm.tap()

        let name = app.textFields["onboarding.display-name"]
        enter("Pessoa QA\n", in: name)
        advance(app)

        XCTAssertTrue(support.element("screen.onboarding.body-data", app: app).waitForExistence(timeout: 5))
        advance(app)
        let objective = app.buttons["onboarding.objective.recomposicao"]
        reach(objective, in: app)
        objective.tap()
        advance(app)
        XCTAssertTrue(support.element("screen.onboarding.routine", app: app).waitForExistence(timeout: 5))
        advance(app)
        let persona = app.buttons["persona.focus"]
        reach(persona, in: app)
        persona.tap()
        advance(app)
        XCTAssertTrue(support.element("screen.onboarding.consent", app: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func advance(_ app: XCUIApplication) {
        let button = app.buttons["onboarding.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    @MainActor
    private func enter(_ value: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(value)
    }

    @MainActor
    private func enterSecure(_ value: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(waitForKeyboardFocus(field))
        if field.identifier == "auth.password" {
            field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(waitForKeyboardFocus(field))
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
        XCTAssertTrue(waitForSecureEntry(field, characterCount: value.count))
    }

    @MainActor
    private func waitForKeyboardFocus(_ field: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    @MainActor
    private func waitForSecureEntry(
        _ field: XCUIElement,
        characterCount: Int,
        timeout: TimeInterval = 3
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard
                    let element = object as? XCUIElement,
                    let value = element.value as? String
                else {
                    return false
                }
                return value.count == characterCount
            },
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func reach(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 16
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<attempts where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element.identifier) deve permanecer alcançável")
    }
}
