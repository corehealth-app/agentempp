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
        XCTAssertTrue(support.element("screen.onboarding.objective", app: app).waitForExistence(timeout: 5))
        let objective = app.buttons["onboarding.objective.recomposicao"]
        reach(objective, in: app, attempts: 30)
        support.assertTarget(objective)
        objective.tap()
        XCTAssertTrue(objective.isSelected)
        advance(app)
        XCTAssertTrue(
            support.element("screen.onboarding.completion", app: app)
                .waitForExistence(timeout: 5)
        )
        let finish = app.buttons["onboarding.go-to-today"]
        reach(finish, in: app, attempts: 20)
        support.assertTarget(finish)
        support.capture("s2-consent-pt-light-axxxl", app: app)
    }

    // MARK: Second update (2026-10-10) — a refused sign-up says why
    //
    // Reported by the physician on build 1.0 (3): "Criar conta" with an
    // e-mail that already has an account showed "Não foi possível conectar
    // agora. Tente novamente.", kept the e-mail and (in his screenshot) both
    // password fields looked empty.

    /// LOCK, over the fixture that already existed: what the app does with
    /// the three fields after a sign-up that failed. No line of the app
    /// empties a password field (RC U1B-S3).
    @MainActor
    func testFailedSignUpKeepsTheEmailAndBothPasswords() {
        let app = support.launch(
            arguments: ["--ui-testing-auth-error"],
            language: "pt-BR",
            dark: false
        )
        fillSignUp(in: app)
        submitSignUp(in: app)

        XCTAssertTrue(
            app.staticTexts["Não foi possível conectar agora. Tente novamente."]
                .waitForExistence(timeout: 5)
        )
        assertSignUpFormIsKept(in: app, submitLabel: "Criar conta")
    }

    @MainActor
    func testSignUpWithAnEmailThatAlreadyHasAnAccountSaysSo() {
        let app = support.launch(
            arguments: ["--ui-testing-sign-up-email-taken"],
            language: "pt-BR",
            dark: false
        )
        fillSignUp(in: app)
        submitSignUp(in: app)

        // Asserted by the text itself, not by the container's label.
        let banner = app.staticTexts[
            "Este e-mail já tem uma conta. Use outro e-mail ou toque em “Já tenho uma conta”."
        ]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 5),
            "A sign-up refused because the e-mail already has an account must say so"
        )
        XCTAssertFalse(app.staticTexts["Não foi possível conectar agora. Tente novamente."].exists)
        XCTAssertTrue(support.element("screen.auth.sign-up", app: app).exists)
        assertSignUpFormIsKept(in: app, submitLabel: "Criar conta")

        // The way the banner points at: it leads to "Entrar", without the
        // banner.
        let existing = app.buttons["Já tenho uma conta"]
        reach(existing, in: app)
        support.assertTarget(existing)
        existing.tap()
        declineSystemPasswordSave(app)
        XCTAssertTrue(support.element("screen.auth.sign-in", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(support.element("auth.error", app: app).exists)
        XCTAssertFalse(banner.exists)
        XCTAssertFalse(app.staticTexts["Não foi possível conectar agora. Tente novamente."].exists)
    }

    @MainActor
    func testSignUpRefusalsReadPlainlyInEnglish() {
        let taken = support.launch(
            arguments: ["--ui-testing-sign-up-email-taken"],
            language: "en-US",
            dark: true
        )
        fillSignUp(in: taken)
        submitSignUp(in: taken)
        XCTAssertTrue(
            taken.staticTexts[
                "This email already has an account. Use a different email or tap “I already have an account”."
            ].waitForExistence(timeout: 5),
            "A sign-up refused because the e-mail already has an account must say so"
        )
        XCTAssertFalse(taken.staticTexts["Could not connect right now. Try again."].exists)
        assertSignUpFormIsKept(in: taken, submitLabel: "Create account")
        taken.terminate()

        let weak = support.launch(
            arguments: ["--ui-testing-sign-up-weak-password"],
            language: "en-US",
            dark: true
        )
        fillSignUp(in: weak)
        submitSignUp(in: weak)
        XCTAssertTrue(
            weak.staticTexts[
                "That password is too weak. Choose a longer one that is harder to guess."
            ].waitForExistence(timeout: 5),
            "A sign-up refused for a weak password must say so"
        )
        XCTAssertFalse(weak.staticTexts["Could not connect right now. Try again."].exists)
        assertSignUpFormIsKept(in: weak, submitLabel: "Create account")
    }

    // MARK: Second update (2026-10-10) — the "eye" of the password fields
    //
    // The physician, on build 1.0 (3): "Deveria ter aquele olho pra mostrar
    // as senhas pra conferir".

    @MainActor
    func testEyeShowsAndHidesBothSignUpPasswordsKeepingTextAndFocus() {
        let app = support.launch(
            arguments: ["--ui-testing-fresh-auth"],
            language: "pt-BR",
            dark: false
        )
        reach(app.buttons["auth.open-sign-up"], in: app)
        app.buttons["auth.open-sign-up"].tap()
        enterSecure(signUpPassword, in: app.secureTextFields["auth.password"])

        let eye = app.buttons["auth.password.visibility"]
        XCTAssertTrue(
            eye.waitForExistence(timeout: 5),
            "The password field needs a control that shows what was typed"
        )
        XCTAssertEqual(eye.label, "Mostrar senha")
        XCTAssertTrue(eye.isHittable)
        support.assertTarget(eye)
        let confirmationEye = app.buttons["auth.password-confirmation.visibility"]
        XCTAssertTrue(confirmationEye.exists, "The confirmation has its own control")
        XCTAssertEqual(confirmationEye.label, "Mostrar confirmação da senha")
        support.assertTarget(confirmationEye)
        let place = eye.frame

        // Show: the same text, readable, with the keyboard still on the
        // very same field.
        let field = app.secureTextFields["auth.password"]
        let shown = support.element("auth.password.shown", app: app)
        eye.tap()
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "A touch shows the password")
        XCTAssertEqual(shown.value as? String, signUpPassword)
        XCTAssertEqual(eye.label, "Ocultar senha")
        XCTAssertTrue(field.exists, "The field itself is never replaced")
        XCTAssertTrue(waitForKeyboardFocus(field), "The keyboard stays on the field")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        assertSamePlace(eye.frame, place, "The control moved under the finger when it was touched")
        // One more character WITHOUT touching the field.
        app.typeText("1")
        XCTAssertTrue(waitForValue(shown, signUpPassword + "1"), "Typing goes on while it is shown")
        XCTAssertTrue(waitForSecureEntry(field, characterCount: signUpPassword.count + 1))
        // The confirmation was never shown.
        XCTAssertTrue(app.secureTextFields["auth.password-confirmation"].exists)
        XCTAssertFalse(support.element("auth.password-confirmation.shown", app: app).exists)
        XCTAssertEqual(confirmationEye.label, "Mostrar confirmação da senha")

        // Hide again: the same text, masked, with the keyboard still on it.
        eye.tap()
        XCTAssertTrue(shown.waitForNonExistence(timeout: 5), "A second touch hides it again")
        XCTAssertTrue(waitForSecureEntry(field, characterCount: signUpPassword.count + 1))
        XCTAssertEqual(eye.label, "Mostrar senha")
        XCTAssertTrue(waitForKeyboardFocus(field), "The keyboard stays on the field")
        assertSamePlace(eye.frame, place, "The control moved under the finger when it was touched")

        // Leaving the screen and coming back: nothing is shown, nothing is
        // kept.
        eye.tap()
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        let existing = app.buttons["Já tenho uma conta"]
        reach(existing, in: app)
        existing.tap()
        declineSystemPasswordSave(app)
        XCTAssertTrue(support.element("screen.auth.sign-in", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(shown.exists)
        reach(app.buttons["auth.open-sign-up"], in: app)
        app.buttons["auth.open-sign-up"].tap()
        for identifier in ["auth.password", "auth.password-confirmation"] {
            let empty = app.secureTextFields[identifier]
            XCTAssertTrue(empty.waitForExistence(timeout: 5), "\(identifier) is hidden again")
            XCTAssertEqual(empty.value as? String, empty.placeholderValue, "\(identifier) is empty")
            XCTAssertFalse(support.element(identifier + ".shown", app: app).exists, identifier)
        }
    }

    /// A password that is shown is kept exactly as typed: quotes and dashes
    /// are never turned into other characters. Everything is typed while it
    /// is shown. On "Entrar": the field is the same component, and the
    /// simulator does not put its strong-password offer over it.
    ///
    /// This reads the accessibility VALUE, not the screen. In exactly these
    /// steps the review of 2026-10-11 saw the bullets of the secure field
    /// drawn over the readable password while this test passed. No picture
    /// taken by XCUITest can see that: its screenshot never contains what a
    /// secure field draws (run u1b-fix1-02-red-run — a picture test of these
    /// same steps passed over the defect; and the kept picture
    /// u1b-eye-after-failed-sign-in-pt-light shows an EMPTY field holding
    /// ten masked characters). What is drawn is locked by the hosted
    /// `testNothingTheSecureFieldDrawsReachesTheScreenWhileThePasswordIsShown`
    /// (RC U1B-E6).
    @MainActor
    func testShownPasswordIsNeverRewritten() {
        let typed = "a'b\"c--d"
        let app = support.launch(
            arguments: ["--ui-testing-fresh-auth"],
            language: "pt-BR",
            dark: false
        )
        XCTAssertTrue(support.element("screen.auth.sign-in", app: app).waitForExistence(timeout: 5))
        let secure = app.secureTextFields["auth.password"]
        XCTAssertTrue(secure.waitForExistence(timeout: 5))
        secure.tap()
        XCTAssertTrue(waitForKeyboardFocus(secure))

        let eye = app.buttons["auth.password.visibility"]
        XCTAssertTrue(
            eye.waitForExistence(timeout: 5),
            "The password field needs a control that shows what was typed"
        )
        eye.tap()
        XCTAssertEqual(eye.label, "Ocultar senha")
        XCTAssertTrue(waitForKeyboardFocus(secure), "The keyboard stays on the field")
        for character in typed {
            app.typeText(String(character))
        }
        let shown = support.element("auth.password.shown", app: app)
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "What is typed while shown is readable")
        XCTAssertTrue(waitForValue(shown, typed), "Shown: «\(shown.value as? String ?? "<nil>")»")
        XCTAssertEqual(Array((shown.value as? String ?? "").utf8), Array(typed.utf8))
        XCTAssertTrue(waitForSecureEntry(secure, characterCount: typed.count))

        eye.tap()
        XCTAssertTrue(shown.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForSecureEntry(secure, characterCount: typed.count))

        eye.tap()
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCTAssertEqual(
            Array((shown.value as? String ?? "").utf8), Array(typed.utf8),
            "Hiding and showing again gives back the same characters"
        )
    }

    // MARK: Review of 2026-10-11 — "Criar conta" hides its passwords again
    //
    // "Entrar" had this lock (below); "Criar conta", the screen the physician
    // asked the eye for, had none: its two lines could be deleted and no test
    // failed.

    /// LOCK: sending "Criar conta" hides BOTH passwords again; their text
    /// stays in the fields.
    @MainActor
    func testSignUpPasswordsAreHiddenAgainWhenTheFormIsSent() {
        let app = support.launch(
            arguments: ["--ui-testing-sign-up-email-taken"],
            language: "pt-BR",
            dark: false
        )
        fillSignUp(in: app)
        showBothSignUpPasswords(in: app)

        submitSignUp(in: app)
        XCTAssertTrue(
            app.staticTexts[
                "Este e-mail já tem uma conta. Use outro e-mail ou toque em “Já tenho uma conta”."
            ].waitForExistence(timeout: 5)
        )
        assertBothSignUpPasswordsAreHidden(in: app, "Sending hides the passwords")
        assertSignUpFormIsKept(in: app, submitLabel: "Criar conta")
    }

    /// LOCK: no password of "Criar conta" stays readable once the app
    /// leaves the foreground; their text stays in the fields.
    @MainActor
    func testSignUpPasswordsAreHiddenAgainWhenTheAppLeavesTheForeground() {
        let app = support.launch(
            arguments: ["--ui-testing-fresh-auth"],
            language: "pt-BR",
            dark: false
        )
        fillSignUp(in: app)
        showBothSignUpPasswords(in: app)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 5))
        assertBothSignUpPasswordsAreHidden(in: app, "Leaving the foreground hides the passwords")
        assertSignUpFormIsKept(in: app, submitLabel: "Criar conta")
    }

    private let signUpPasswordFields = [
        (identifier: "auth.password", show: "Mostrar senha", hide: "Ocultar senha"),
        (
            identifier: "auth.password-confirmation",
            show: "Mostrar confirmação da senha",
            hide: "Ocultar confirmação da senha"
        ),
    ]

    /// Touches the eye of each password of "Criar conta": both are readable.
    @MainActor
    private func showBothSignUpPasswords(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for field in signUpPasswordFields {
            let eye = app.buttons[field.identifier + ".visibility"]
            XCTAssertTrue(
                waitUntilHittable(eye), "\(field.identifier): its control is in reach",
                file: file, line: line
            )
            XCTAssertEqual(eye.label, field.show, file: file, line: line)
            eye.tap()
            let shown = support.element(field.identifier + ".shown", app: app)
            XCTAssertTrue(
                shown.waitForExistence(timeout: 5), "\(field.identifier): a touch shows it",
                file: file, line: line
            )
            XCTAssertEqual(shown.value as? String, signUpPassword, file: file, line: line)
            XCTAssertEqual(eye.label, field.hide, file: file, line: line)
        }
    }

    @MainActor
    private func assertBothSignUpPasswordsAreHidden(
        in app: XCUIApplication,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for field in signUpPasswordFields {
            XCTAssertTrue(
                support.element(field.identifier + ".shown", app: app).waitForNonExistence(timeout: 5),
                "\(message): \(field.identifier)", file: file, line: line
            )
            XCTAssertEqual(
                app.buttons[field.identifier + ".visibility"].label, field.show,
                "\(message): \(field.identifier)", file: file, line: line
            )
        }
    }

    @MainActor
    func testPasswordIsHiddenAgainOnSubmitAndWhenTheAppLeavesTheForeground() {
        let app = support.launch(
            arguments: ["--ui-testing-auth-error"],
            language: "pt-BR",
            dark: false
        )
        enter(signUpEmail, in: app.textFields["auth.email"])
        let secure = app.secureTextFields["auth.password"]
        XCTAssertTrue(secure.waitForExistence(timeout: 5))
        secure.tap()
        secure.typeText(signUpPassword)
        XCTAssertTrue(waitForSecureEntry(secure, characterCount: signUpPassword.count))

        let eye = app.buttons["auth.password.visibility"]
        XCTAssertTrue(
            eye.waitForExistence(timeout: 5),
            "The password field of Entrar needs a control that shows what was typed"
        )
        XCTAssertEqual(eye.label, "Mostrar senha")
        support.assertTarget(eye)
        eye.tap()
        let shown = support.element("auth.password.shown", app: app)
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCTAssertEqual(shown.value as? String, signUpPassword)

        // Sending hides it.
        let submit = app.buttons["auth.sign-in.submit"]
        reach(submit, in: app)
        submit.tap()
        XCTAssertTrue(
            app.staticTexts["Não foi possível conectar agora. Tente novamente."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(shown.waitForNonExistence(timeout: 5), "Sending hides the password")
        XCTAssertTrue(secure.exists)
        XCTAssertTrue(waitForSecureEntry(secure, characterCount: signUpPassword.count))
        XCTAssertEqual(eye.label, "Mostrar senha")
        // Synthetic values only; the password is hidden at this point.
        support.capture("u1b-eye-after-failed-sign-in-pt-light", app: app)

        // Leaving the foreground hides it.
        XCTAssertTrue(waitUntilHittable(eye), "The control is back in reach after the form settled")
        eye.tap()
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(secure.waitForExistence(timeout: 5))
        XCTAssertTrue(shown.waitForNonExistence(timeout: 5), "Leaving the foreground hides the password")
        XCTAssertTrue(waitForSecureEntry(secure, characterCount: signUpPassword.count))
        XCTAssertEqual(eye.label, "Mostrar senha")
    }

    /// Existence, label and size only: no password is typed at the largest
    /// text size (a touch on a password field loses its focus there — the
    /// trap of the first round).
    @MainActor
    func testEyeKeepsItsTargetInEnglishAtAXXXL() {
        let app = support.launch(
            arguments: ["--ui-testing-fresh-auth"],
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let signInEye = app.buttons["auth.password.visibility"]
        XCTAssertTrue(
            signInEye.waitForExistence(timeout: 5),
            "The password field of Sign in needs a control that shows what was typed"
        )
        reach(signInEye, in: app)
        XCTAssertEqual(signInEye.label, "Show password")
        support.assertTarget(signInEye)

        reach(app.buttons["auth.open-sign-up"], in: app)
        app.buttons["auth.open-sign-up"].tap()
        XCTAssertTrue(support.element("screen.auth.sign-up", app: app).waitForExistence(timeout: 5))
        for (identifier, label) in [
            ("auth.password.visibility", "Show password"),
            ("auth.password-confirmation.visibility", "Show password confirmation"),
        ] {
            let eye = app.buttons[identifier]
            XCTAssertTrue(eye.waitForExistence(timeout: 5), identifier)
            reach(eye, in: app)
            XCTAssertEqual(eye.label, label)
            support.assertTarget(eye)
        }
    }

    @MainActor
    private func waitUntilHittable(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func waitForValue(_ field: XCUIElement, _ value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func assertSamePlace(
        _ frame: CGRect,
        _ expected: CGRect,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (value, reference) in [
            (frame.minX, expected.minX), (frame.minY, expected.minY),
            (frame.width, expected.width), (frame.height, expected.height),
        ] {
            XCTAssertEqual(
                value, reference, accuracy: 0.5,
                "\(message): \(frame) / \(expected)", file: file, line: line
            )
        }
    }

    private let signUpEmail = "person@example.invalid"
    /// Ten characters, synthetic.
    private let signUpPassword = "local-pass"

    @MainActor
    private func fillSignUp(in app: XCUIApplication) {
        reach(app.buttons["auth.open-sign-up"], in: app)
        app.buttons["auth.open-sign-up"].tap()
        enter(signUpEmail, in: app.textFields["auth.email"])
        enterSecure(signUpPassword, in: app.secureTextFields["auth.password"])
        enterSecure(signUpPassword, in: app.secureTextFields["auth.password-confirmation"])
    }

    @MainActor
    private func submitSignUp(in app: XCUIApplication) {
        let submit = app.buttons["auth.sign-up.submit"]
        reach(submit, in: app)
        submit.tap()
    }

    /// After a refusal: the e-mail and both passwords are still in their
    /// fields (a secure field shows one bullet per character) and the form
    /// can be sent again.
    @MainActor
    private func assertSignUpFormIsKept(
        in app: XCUIApplication,
        submitLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            app.textFields["auth.email"].value as? String, signUpEmail,
            file: file, line: line
        )
        for identifier in ["auth.password", "auth.password-confirmation"] {
            let field = app.secureTextFields[identifier]
            XCTAssertTrue(field.exists, "\(identifier) is a secure field", file: file, line: line)
            XCTAssertEqual(
                (field.value as? String)?.count, signUpPassword.count,
                "\(identifier) keeps its \(signUpPassword.count) masked characters",
                file: file, line: line
            )
        }
        let submit = app.buttons["auth.sign-up.submit"]
        XCTAssertTrue(submit.isEnabled, file: file, line: line)
        XCTAssertEqual(submit.label, submitLabel, file: file, line: line)
    }

    /// Leaving a form with typed passwords can raise the simulator's own
    /// "Salvar Senha?" sheet. It is the system's, not the app's: it is
    /// declined, so nothing is saved. Nothing happens when it is not there.
    @MainActor
    private func declineSystemPasswordSave(_ app: XCUIApplication) {
        let decline = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Agora Não", "Not Now"])
        ).firstMatch
        guard decline.waitForExistence(timeout: 3) else { return }
        var lastFrame: CGRect?
        var unchangedSince: TimeInterval?
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard decline.exists, decline.isHittable else {
                lastFrame = nil
                unchangedSince = nil
                return false
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard decline.frame == lastFrame, let since = unchangedSince else {
                lastFrame = decline.frame
                unchangedSince = now
                return false
            }
            return now - since >= 0.5
        }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [settled], timeout: 8), .completed,
            "The system's password sheet never settled"
        )
        decline.tap()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: decline
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [gone], timeout: 5), .completed,
            "The system's password sheet stayed on screen"
        )
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
