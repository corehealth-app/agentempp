import XCTest
import UIKit

@MainActor
final class OnboardingEligibilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private var support: PremiumUIUXUITestSupport { .init(testCase: self) }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { support.element(id, app: app) }

    func testAssignedRecompositionShowsNoticeAndCollapsedGainDisclosure() {
        let app = start("--ui-testing-onboarding-assigned")
        reachObjective(app)
        XCTAssertTrue(app.staticTexts["Seu objetivo inicial"].exists)
        XCTAssertTrue(element("onboarding.objective.notice", app).label.contains("Nesta simulação local"))
        XCTAssertFalse(app.buttons["onboarding.objective.recomposicao"].exists)
        XCTAssertTrue(element("onboarding.objective.recomposicao", app).isSelected)
        XCTAssertFalse(element("onboarding.objective.reason.ganho-massa", app).exists)
        support.assertTarget(element("onboarding.objective.about-gain", app))
        tap(element("onboarding.objective.about-gain", app), app)
        XCTAssertTrue(element("onboarding.objective.reason.ganho-massa", app).exists, app.debugDescription)
        XCTAssertEqual(element("onboarding.objective.reason.ganho-massa", app).label,
            "O ganho de massa está indisponível nesta simulação local.")
        XCTAssertFalse(app.buttons["onboarding.objective.ganho-massa"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "onboarding.objective.reason.ganho-massa").count, 1)
        reach(element("onboarding.objective.reason.ganho-massa", app), app)
        support.capture("e3-assigned-pt-light-expanded-stable", app: app)
        advance(app)
        XCTAssertTrue(element("screen.onboarding.completion", app).waitForExistence(timeout: 5))
    }

    func testBlockedGainIsNotAButtonAndShowsServerReason() {
        let app = start("--ui-testing-onboarding-gain-blocked", dark: true)
        reachObjective(app)
        XCTAssertFalse(app.buttons["onboarding.objective.ganho-massa"].exists)
        XCTAssertTrue(element("onboarding.objective.ganho-massa", app).exists)
        reach(element("onboarding.objective.reason.ganho-massa", app), app)
        XCTAssertTrue(element("onboarding.objective.reason.ganho-massa", app).label.contains("O ganho de massa está indisponível nesta simulação local."))
        tap(app.buttons["onboarding.objective.manutencao"], app)
        XCTAssertTrue(app.buttons["onboarding.objective.manutencao"].isSelected)
        support.capture("e3-gain-blocked-pt-dark", app: app)
        advance(app)
        XCTAssertTrue(element("screen.onboarding.completion", app).waitForExistence(timeout: 5))
    }

    func testAllAvailableDefaultChoiceRequiresSelection() {
        let app = start()
        reachObjective(app)
        for id in ["recomposicao", "ganho-massa", "manutencao"] {
            XCTAssertTrue(app.buttons["onboarding.objective.\(id)"].exists)
            XCTAssertFalse(app.buttons["onboarding.objective.\(id)"].isSelected)
        }
        advance(app)
        XCTAssertTrue(element("screen.onboarding.objective", app).exists)
        XCTAssertTrue(app.staticTexts["Selecione um objetivo."].exists)
        tap(app.buttons["onboarding.objective.ganho-massa"], app)
        XCTAssertTrue(app.buttons["onboarding.objective.ganho-massa"].isSelected)
        support.capture("e3-default-choice-pt-light", app: app)
    }

    func testObjectiveOptionsRemainReachableAtAXXXL() {
        let app = start(category: "UICTContentSizeCategoryAccessibilityXXXL")
        reachObjective(app)
        for id in ["recomposicao", "ganho-massa", "manutencao"] {
            let option = app.buttons["onboarding.objective.\(id)"]
            tap(option, app)
            support.assertTarget(option)
            XCTAssertTrue(option.isSelected)
        }
        support.capture("e3-choice-pt-light-axxxl", app: app)
        advance(app)
        XCTAssertTrue(element("screen.onboarding.completion", app).waitForExistence(timeout: 5))
    }

    func testProtocolWelcomeDefersTodayAndGuidedTourUntilContinue() {
        let app = start("--ui-testing-onboarding-welcome", extraArguments: ["--ui-testing-tutorial-eligible", "--ui-testing-tutorial-text"])
        finishToWelcome(app)
        XCTAssertFalse(element("screen.hoje", app).exists)
        XCTAssertFalse(element("tour.overlay", app).exists)
        XCTAssertFalse(element("screen.tutorial", app).exists)
        let first = element("onboarding.protocol-welcome.paragraph.0", app)
        XCTAssertTrue(first.isHittable, "Welcome starts at the top after saving the same completion step")
        XCTAssertEqual(first.label, "Esta é uma mensagem sintética do Flow para testar a entrada no objetivo.")
        support.capture("e3-welcome-pt-light-top", app: app)
        tap(app.buttons["onboarding.protocol-welcome.continue"], app)
        XCTAssertTrue(element("screen.tutorial", app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("screen.onboarding.protocol-welcome", app).exists)
        support.capture("e3-welcome-followed-by-existing-tutorial", app: app)
        tap(app.buttons["tutorial.later"], app)
        XCTAssertTrue(element("screen.hoje", app).waitForExistence(timeout: 5))
    }

    func testLongestWelcomeAndContinueRemainReachableAtAXXXL() {
        let app = start("--ui-testing-onboarding-welcome", dark: true,
                        category: "UICTContentSizeCategoryAccessibilityXXXL")
        finishToWelcome(app)
        XCTAssertTrue(element("onboarding.protocol-welcome.paragraph.0", app).isHittable)
        support.capture("e3-welcome-pt-dark-axxxl-top", app: app)
        let last = element("onboarding.protocol-welcome.paragraph.11", app)
        reach(last, app, attempts: 100)
        XCTAssertEqual(last.label, "Fim da mensagem sintética. A próxima tela será Hoje.")
        let finish = app.buttons["onboarding.protocol-welcome.continue"]
        reach(finish, app)
        support.assertTarget(finish)
        support.capture("e3-welcome-pt-dark-axxxl-bottom", app: app)
        finish.tap()
        XCTAssertTrue(element("screen.hoje", app).waitForExistence(timeout: 5))
    }

    func testEnglishAssignedAndWelcomeFrameCopy() {
        var app = start("--ui-testing-onboarding-assigned", language: "en-US", dark: true)
        reachObjective(app)
        XCTAssertTrue(app.staticTexts["Your starting objective"].exists)
        XCTAssertTrue(element("onboarding.objective.notice", app).label.contains("In this local simulation"))
        support.capture("e3-assigned-en-dark", app: app)
        app.terminate()
        app = start("--ui-testing-onboarding-welcome", language: "en-US")
        finishToWelcome(app)
        XCTAssertTrue(app.staticTexts["Message from Flow"].exists)
        let last = element("onboarding.protocol-welcome.paragraph.11", app)
        reach(last, app)
        XCTAssertEqual(last.label, "End of the synthetic message. The next screen will be Today.")
        XCTAssertEqual(app.buttons["onboarding.protocol-welcome.continue"].label, "Go to Today")
        support.capture("e3-welcome-en-light-bottom", app: app)
    }

    func testEligibilityFailureKeepsDocumentsAndRetryPreservesInput() {
        let app = start("--ui-testing-onboarding-eligibility-failure")
        reachDocuments(app)
        acceptDocuments(app)
        advance(app)
        XCTAssertTrue(element("onboarding.error", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("screen.onboarding.consent", app).exists)
        XCTAssertFalse(element("screen.onboarding.objective", app).exists)
        for key in documentKeys { XCTAssertTrue(app.buttons["onboarding.legal-action.\(key)"].isSelected) }
        advance(app)
        XCTAssertTrue(element("screen.onboarding.consent", app).exists)
        XCTAssertTrue(element("onboarding.error", app).exists)
        XCTAssertFalse(element("screen.hoje", app).exists)
        support.capture("e3-check-failure-pt-light", app: app)
    }

    func testUncertainCompletionKeepsRetryAvailableAndEditingLocked() {
        let app = start("--ui-testing-onboarding-completion-uncertain")
        reachObjective(app)
        tap(app.buttons["onboarding.objective.recomposicao"], app)
        advance(app)
        tap(app.buttons["onboarding.go-to-today"], app)
        XCTAssertTrue(element("onboarding.completion.unresolved", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("onboarding.error", app).exists)
        XCTAssertFalse(app.buttons["onboarding.back"].exists)
        XCTAssertFalse(app.buttons["onboarding.continue"].exists)
        XCTAssertFalse(element("screen.hoje", app).exists)
        support.capture("e3-uncertain-completion-pt-light", app: app)
        tap(app.buttons["onboarding.go-to-today"], app)
        XCTAssertTrue(element("screen.hoje", app).waitForExistence(timeout: 5))
    }

    /// Reported on 2026-10-10 11:55: a person signs in with an account that
    /// administers the team's panel; the read of the sign-up is refused for
    /// that reason and the screen offered only "Tentar novamente", forever.
    func testTeamPanelAccountSeesWhyAndSignsOutToSignIn() {
        let app = start("--ui-testing-onboarding-admin-conflict")
        signIn(app)
        XCTAssertTrue(element("screen.onboarding.load-error", app).waitForExistence(timeout: 10))
        let signOut = app.buttons["onboarding.load-error.sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "A team-panel account needs a way out of the screen")
        let message = element("onboarding.load-error.message", app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label,
            "Este e-mail é do painel da equipe. O app precisa de um e-mail diferente. Saia desta conta e entre com outro e-mail.")
        XCTAssertTrue(app.staticTexts["Use outro e-mail no app"].exists)
        XCTAssertFalse(app.buttons["onboarding.load-error.retry"].exists)
        XCTAssertEqual(signOut.label, "Sair da conta")
        reach(signOut, app)
        support.assertTarget(signOut)
        support.capture("u1-load-error-team-panel-pt-light", app: app)
        signOut.tap()
        XCTAssertTrue(element("screen.auth.sign-in", app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("screen.onboarding.load-error", app).exists)
    }

    func testLoadFailureKeepsRetryAndGainsSignOutInEnglishAtAXXXL() {
        let app = start("--ui-testing-onboarding-load-failure", language: "en-US", dark: true,
                        category: "UICTContentSizeCategoryAccessibilityXXXL")
        signIn(app)
        XCTAssertTrue(element("screen.onboarding.load-error", app).waitForExistence(timeout: 10))
        let signOut = app.buttons["onboarding.load-error.sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "Every load failure needs a way out of the screen")
        let message = element("onboarding.load-error.message", app)
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "Try again to continue your setup.")
        XCTAssertTrue(app.staticTexts["Could not load"].exists)
        let retry = app.buttons["onboarding.load-error.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(retry.label, "Try again")
        reach(retry, app)
        support.assertTarget(retry)
        XCTAssertEqual(signOut.label, "Sign out")
        reach(signOut, app)
        support.assertTarget(signOut)
        support.capture("u1-load-error-temporary-en-dark-axxxl", app: app)
        signOut.tap()
        XCTAssertTrue(element("screen.auth.sign-in", app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("screen.onboarding.load-error", app).exists)
    }

    /// Signs in with the file's synthetic values (the local fixture accepts
    /// any well-formed pair). The keyboard carries the form: Return on the
    /// e-mail moves to the password and Return there submits (the sign-in
    /// screen's own `onSubmit`), so no field has to be scrolled under a
    /// finger at the largest text size.
    private func signIn(_ app: XCUIApplication) {
        XCTAssertTrue(element("screen.auth.sign-in", app).waitForExistence(timeout: 10))
        enter("person@example.invalid\n", in: app.textFields["auth.email"], app: app)
        let password = app.secureTextFields["auth.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForKeyboardFocus(password), "Return on the e-mail moves to the password")
        password.typeText("local-pass\n")
        declineSystemPasswordSave(app)
    }

    /// After a sign-in typed into a password field the simulator's own
    /// "Salvar Senha?" sheet covers the screen (seen in the first green
    /// attempt of these tests). It is the system's, not the app's: it is
    /// declined, so nothing is saved, and the screen under test is reached.
    /// The sheet is still sliding in when its button first exists, so the one
    /// tap waits for the button to stop moving.
    private func declineSystemPasswordSave(_ app: XCUIApplication) {
        let decline = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Agora Não", "Not Now"])
        ).firstMatch
        guard decline.waitForExistence(timeout: 5) else { return }
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

    private let documentKeys = ["qa_onboarding_required", "qa_onboarding_notice", "qa_onboarding_consent"]
    private func start(_ scenario: String = "--ui-testing-fresh-auth", language: String = "pt-BR",
                       dark: Bool = false, category: String = "UICTContentSizeCategoryL", extraArguments: [String] = []) -> XCUIApplication {
        support.launch(arguments: [scenario] + extraArguments, language: language, dark: dark, category: category)
    }
    private func reachDocuments(_ app: XCUIApplication) {
        tap(app.buttons["auth.open-sign-up"], app)
        enter("person@example.invalid", in: app.textFields["auth.email"], app: app)
        enterSecure("local-pass", in: app.secureTextFields["auth.password"], app: app)
        enterSecure("local-pass", in: app.secureTextFields["auth.password-confirmation"], app: app)
        tap(app.buttons["auth.sign-up.submit"], app)
        tap(app.buttons["auth.confirm-development"], app)
        enter("Pessoa QA\n", in: app.textFields["onboarding.display-name"], app: app)
        advance(app)
        XCTAssertTrue(element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
        advance(app)
        XCTAssertTrue(element("screen.onboarding.routine", app).waitForExistence(timeout: 5))
        advance(app)
        XCTAssertTrue(element("screen.onboarding.persona", app).waitForExistence(timeout: 5))
        tap(app.buttons["persona.focus"], app)
        advance(app)
        XCTAssertTrue(element("screen.onboarding.consent", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.continue"].isEnabled)
    }
    private func acceptDocuments(_ app: XCUIApplication) {
        for key in documentKeys {
            let action = app.buttons["onboarding.legal-action.\(key)"]
            tap(action, app, attempts: 60)
            XCTAssertTrue(action.isSelected)
        }
    }
    private func reachObjective(_ app: XCUIApplication) {
        reachDocuments(app)
        acceptDocuments(app)
        advance(app)
        XCTAssertTrue(element("screen.onboarding.objective", app).waitForExistence(timeout: 5))
    }
    private func finishToWelcome(_ app: XCUIApplication) {
        reachObjective(app)
        tap(app.buttons["onboarding.objective.recomposicao"], app)
        advance(app)
        XCTAssertTrue(element("screen.onboarding.completion", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.go-to-today"].label,
            app.launchArguments.contains("(en-US)") ? "Finish sign-up" : "Concluir cadastro")
        tap(app.buttons["onboarding.go-to-today"], app)
        XCTAssertTrue(element("screen.onboarding.protocol-welcome", app).waitForExistence(timeout: 5))
    }
    private func advance(_ app: XCUIApplication) { tap(app.buttons["onboarding.continue"], app, attempts: 60) }
    private func enter(_ value: String, in field: XCUIElement, app: XCUIApplication) {
        tap(field, app)
        field.typeText(value)
    }
    private func reach(_ target: XCUIElement, _ app: XCUIApplication, attempts: Int = 60) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0..<attempts where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable, "\(target.identifier) must stay reachable")
    }
    private func tap(_ target: XCUIElement, _ app: XCUIApplication, attempts: Int = 60) {
        reach(target, app, attempts: attempts)
        target.tap()
    }
    @MainActor
    private func enterSecure(_ value: String, in field: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field, app)
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

}
