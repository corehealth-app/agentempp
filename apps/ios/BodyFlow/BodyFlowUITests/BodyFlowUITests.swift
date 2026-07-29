import XCTest
import UIKit

final class BodyFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFiveTabsAreReachableAndCaptured() {
        let app = launchApp()
        let tabs = [
            ("tab.hoje", "screen.hoje", "01-hoje"),
            ("tab.registrar", "screen.registrar", "02-registrar"),
            ("tab.plano", "screen.plano", "03-plano"),
            ("tab.progresso", "screen.progresso", "04-progresso"),
            ("tab.perfil", "screen.perfil", "05-perfil"),
        ]

        for (tabID, screenID, attachmentName) in tabs {
            let tab = app.tabBars.buttons[tabID]
            XCTAssertTrue(tab.waitForExistence(timeout: 3), "A aba \(tabID) deve existir")
            tab.tap()
            XCTAssertTrue(
                waitForSelected(tab),
                "A aba \(tabID) deve concluir a seleção"
            )

            let screen = element(screenID, in: app)
            XCTAssertTrue(screen.waitForExistence(timeout: 3), "A tela \(screenID) deve existir")
            XCTAssertTrue(
                waitForHorizontallySettled(screen, in: app),
                "A tela \(screenID) deve concluir a transição"
            )
            XCTAssertTrue(waitForVisualStability())

            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = attachmentName
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        attachHierarchy(of: app, name: "five-tabs")
    }

    @MainActor
    func testTodayNavigationPersistsAcrossTabSwitch() {
        let app = launchApp()
        let nextAction = app.buttons["today.next-action"]
        XCTAssertTrue(nextAction.waitForExistence(timeout: 3))
        nextAction.tap()

        let detail = element("route.hoje.detalhe", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 3))

        app.tabBars.buttons["tab.registrar"].tap()
        XCTAssertTrue(
            element("screen.registrar", in: app).waitForExistence(timeout: 3)
        )

        app.tabBars.buttons["tab.hoje"].tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForHorizontallySettled(detail, in: app))
        XCTAssertTrue(waitForVisualStability())
        capture("06-hoje-detalhe-restaurado", app: app)
    }

    @MainActor
    func testRegistrationSheetExplainsNothingWasSaved() {
        let app = launchApp()
        app.tabBars.buttons["tab.registrar"].tap()

        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 3))
        meal.tap()

        let sheet = element("sheet.registrar.refeicao", in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForHorizontallySettled(sheet, in: app))
        XCTAssertTrue(waitForVisualStability())
        XCTAssertTrue(
            app.staticTexts["Demonstração local. Nenhum registro foi salvo."]
                .waitForExistence(timeout: 3)
        )

        capture("07-registro-refeicao", app: app)
        let closeButton = app.buttons["sheet.fechar"]
        XCTAssertEqual(closeButton.label, "Fechar")
        XCTAssertGreaterThanOrEqual(
            closeButton.frame.height,
            44,
            "Fechar deve preservar um alvo de toque de pelo menos 44 pt"
        )
        closeButton.tap()
        XCTAssertFalse(
            element("sheet.registrar.refeicao", in: app)
                .waitForExistence(timeout: 1)
        )
    }

    @MainActor
    func testFreshSignUpReachesDevelopmentConfirmation() {
        let app = launchApp(arguments: ["--ui-testing-fresh-auth"])
        XCTAssertTrue(
            element("screen.auth.sign-in", in: app)
                .waitForExistence(timeout: 3)
        )

        let openSignUp = app.buttons["auth.open-sign-up"]
        assertMinimumTapTarget(openSignUp)
        openSignUp.tap()
        XCTAssertTrue(
            element("screen.auth.sign-up", in: app)
                .waitForExistence(timeout: 3)
        )
        completeSignUpForm(in: app)

        let submit = app.buttons["auth.sign-up.submit"]
        XCTAssertTrue(submit.isHittable, "Criar conta deve ficar acessível com o teclado")
        assertMinimumTapTarget(submit)
        submit.tap()

        XCTAssertTrue(
            element("screen.auth.email-confirmation", in: app)
                .waitForExistence(timeout: 3)
        )
        assertMinimumTapTarget(app.buttons["auth.confirm-development"])
        assertMinimumTapTarget(app.buttons["auth.back-to-sign-in"])
    }

    @MainActor
    func testSignUpLabelsFocusOrderAndSubmitVisibility() {
        let app = launchApp(arguments: ["--ui-testing-fresh-auth"])
        let openSignUp = app.buttons["auth.open-sign-up"]
        XCTAssertTrue(openSignUp.waitForExistence(timeout: 3))
        openSignUp.tap()

        let email = app.textFields["auth.email"]
        let password = app.secureTextFields["auth.password"]
        let confirmation = app.secureTextFields["auth.password-confirmation"]
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        XCTAssertEqual(email.label, "E-mail")
        XCTAssertEqual(password.label, "Senha")
        XCTAssertEqual(confirmation.label, "Confirmar senha")
        XCTAssertTrue(app.staticTexts["E-mail"].exists)
        XCTAssertTrue(app.staticTexts["Senha"].exists)
        XCTAssertTrue(app.staticTexts["Confirmar senha"].exists)

        email.tap()
        XCTAssertTrue(waitForKeyboardFocus(email))
        let submit = app.buttons["auth.sign-up.submit"]
        assertVisibleAndHittable(submit)

        email.typeText("\n")
        XCTAssertTrue(waitForKeyboardFocus(password))
        assertVisibleAndHittable(submit)

        enterSecure("local-pass", in: password, app: app)
        XCTAssertTrue(waitForKeyboardFocus(password))
        assertVisibleAndHittable(submit)

        enterSecure("local-pass", in: confirmation, app: app)
        XCTAssertTrue(waitForKeyboardFocus(confirmation))
        assertVisibleAndHittable(submit)
    }

    @MainActor
    func testSignUpValidationPresentation() {
        let app = launchApp(arguments: ["--ui-testing-fresh-auth"])
        let openSignUp = app.buttons["auth.open-sign-up"]
        XCTAssertTrue(openSignUp.waitForExistence(timeout: 3))
        openSignUp.tap()
        let submit = app.buttons["auth.sign-up.submit"]
        assertVisibleAndHittable(submit)
        submit.tap()

        XCTAssertTrue(
            app.staticTexts[
                "Erros no formulário: Informe seu e-mail. Informe sua senha. Confirme sua senha."
            ]
            .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Informe seu e-mail."].exists)
        XCTAssertTrue(app.staticTexts["Informe sua senha."].exists)
        XCTAssertTrue(app.staticTexts["Confirme sua senha."].exists)
    }

    @MainActor
    func testOnboardingWelcomeHasNoOverlapAtAccessibilityDynamicType() {
        let app = launchApp(arguments: [
            "--ui-testing-fresh-auth",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        reachOnboardingWelcome(in: app)

        let displayName = app.textFields["onboarding.display-name"]
        let country = app.buttons["onboarding.country"]
        let timeZone = app.buttons["onboarding.timezone"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 3))
        XCTAssertEqual(displayName.label, "Como você quer ser chamado?")
        XCTAssertTrue(country.waitForExistence(timeout: 3))
        XCTAssertTrue(timeZone.waitForExistence(timeout: 3))
        assertNoOverlap(displayName, country)
        assertNoOverlap(country, timeZone)
        assertMinimumTapTarget(country)
        assertMinimumTapTarget(timeZone)

        let continueButton = app.buttons["onboarding.continue"]
        for _ in 0..<4 where !continueButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(
            continueButton.isHittable,
            "Continuar deve ser alcançável no Dynamic Type de acessibilidade"
        )
        assertMinimumTapTarget(continueButton)
    }

    @MainActor
    func testFreshUserCompletesOnboardingAndReachesToday() {
        let app = launchApp(arguments: ["--ui-testing-fresh-auth"])
        XCTAssertTrue(
            element("screen.auth.sign-in", in: app)
                .waitForExistence(timeout: 3)
        )
        let openSignUp = app.buttons["auth.open-sign-up"]
        assertMinimumTapTarget(openSignUp)
        openSignUp.tap()
        completeSignUpForm(in: app)
        app.buttons["auth.sign-up.submit"].tap()
        XCTAssertTrue(
            element("screen.auth.email-confirmation", in: app)
                .waitForExistence(timeout: 3)
        )
        let confirmDevelopment = app.buttons["auth.confirm-development"]
        assertMinimumTapTarget(confirmDevelopment)
        confirmDevelopment.tap()

        XCTAssertTrue(
            element("screen.onboarding.welcome", in: app)
                .waitForExistence(timeout: 3)
        )
        enter(
            "Pessoa Teste",
            in: app.textFields["onboarding.display-name"]
        )
        let continueButton = app.buttons["onboarding.continue"]
        assertMinimumTapTarget(continueButton)
        continueButton.tap()

        XCTAssertTrue(
            element("screen.onboarding.body-data", in: app)
                .waitForExistence(timeout: 3)
        )
        assertMinimumTapTarget(app.buttons["onboarding.back"])
        continueButton.tap()

        XCTAssertTrue(
            element("screen.onboarding.objective", in: app)
                .waitForExistence(timeout: 3)
        )
        let objective = app.buttons["onboarding.objective.recomposicao"]
        assertMinimumTapTarget(objective)
        objective.tap()
        XCTAssertTrue(objective.isSelected)
        continueButton.tap()

        XCTAssertTrue(
            element("screen.onboarding.routine", in: app)
                .waitForExistence(timeout: 3)
        )
        continueButton.tap()

        XCTAssertTrue(
            element("screen.onboarding.persona", in: app)
                .waitForExistence(timeout: 3)
        )
        let focusPersona = app.buttons["persona.focus"]
        assertMinimumTapTarget(focusPersona)
        focusPersona.tap()
        XCTAssertTrue(focusPersona.isSelected)
        XCTAssertTrue(focusPersona.label.contains("Selecionado"))
        continueButton.tap()

        XCTAssertTrue(
            element("screen.onboarding.consent", in: app)
                .waitForExistence(timeout: 3)
        )
        let termsConsent = app.buttons["consent.terms"]
        termsConsent.tap()
        XCTAssertTrue(termsConsent.isSelected)
        XCTAssertTrue(termsConsent.label.contains("Selecionado"))
        let privacyConsent = app.buttons["consent.privacy"]
        privacyConsent.tap()
        XCTAssertTrue(privacyConsent.isSelected)
        XCTAssertTrue(privacyConsent.label.contains("Selecionado"))
        assertMinimumTapTarget(termsConsent)
        assertMinimumTapTarget(privacyConsent)
        continueButton.tap()

        XCTAssertTrue(
            element("screen.onboarding.completion", in: app)
                .waitForExistence(timeout: 3)
        )
        let goToToday = app.buttons["onboarding.go-to-today"]
        assertMinimumTapTarget(goToToday)
        goToToday.tap()
        XCTAssertTrue(
            element("screen.hoje", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testCompletedFixtureRestoresToTodayAfterRelaunch() {
        let app = launchApp(arguments: ["--ui-testing"])
        XCTAssertTrue(
            element("screen.hoje", in: app)
                .waitForExistence(timeout: 5)
        )

        app.terminate()
        app.launchArguments = ["--ui-testing-preserve-state"]
        app.launch()

        XCTAssertTrue(
            element("screen.hoje", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testProfilePersonaChangeIsReflected() {
        let app = launchApp(arguments: ["--ui-testing"])
        XCTAssertTrue(
            element("screen.hoje", in: app)
                .waitForExistence(timeout: 5)
        )

        let profileTab = app.tabBars.buttons["tab.perfil"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(waitForSelected(profileTab))

        let profileScreen = element("screen.perfil", in: app)
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForHorizontallySettled(profileScreen, in: app))
        let personaCommand = app.buttons["profile.coach-persona"]
        XCTAssertTrue(personaCommand.waitForExistence(timeout: 3))
        personaCommand.tap()

        XCTAssertTrue(
            element("screen.profile.coach-persona", in: app)
                .waitForExistence(timeout: 3)
        )
        let zen = app.buttons["persona.zen"]
        XCTAssertTrue(zen.waitForExistence(timeout: 3))
        assertMinimumTapTarget(zen)
        zen.tap()
        XCTAssertTrue(zen.isSelected)

        let save = app.buttons["persona.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertFalse(
            element("screen.profile.coach-persona", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Zen"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPasswordRecoveryUsesNeutralConfirmation() {
        let app = launchApp(arguments: ["--ui-testing-recovery"])
        XCTAssertTrue(
            element("screen.auth.sign-in", in: app)
                .waitForExistence(timeout: 3)
        )
        let openRecovery = app.buttons["auth.open-recovery"]
        assertMinimumTapTarget(openRecovery)
        openRecovery.tap()

        XCTAssertTrue(
            element("screen.auth.password-recovery", in: app)
                .waitForExistence(timeout: 3)
        )
        enter("person@example.invalid", in: app.textFields["auth.email"])
        let recoverySubmit = app.buttons["auth.recovery.submit"]
        assertMinimumTapTarget(recoverySubmit)
        recoverySubmit.tap()

        XCTAssertTrue(
            element("auth.recovery.confirmation", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Se houver uma conta para este e-mail, enviaremos as instruções de recuperação."
            ]
            .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testDeterministicSignInFailureKeepsRetryAvailable() {
        let app = launchApp(arguments: ["--ui-testing-auth-error"])
        XCTAssertTrue(
            element("screen.auth.sign-in", in: app)
                .waitForExistence(timeout: 3)
        )
        enter("person@example.invalid", in: app.textFields["auth.email"])
        enter("local-pass", in: app.secureTextFields["auth.password"])
        app.buttons["auth.sign-in.submit"].tap()

        XCTAssertTrue(
            element("auth.error", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts[
                "O serviço está temporariamente indisponível. Tente novamente."
            ]
            .waitForExistence(timeout: 3)
        )
        let retry = app.buttons["auth.sign-in.submit"]
        XCTAssertTrue(retry.isEnabled)
        XCTAssertEqual(retry.label, "Entrar")
        assertMinimumTapTarget(retry)
    }

    @MainActor
    private func launchApp(
        arguments: [String] = ["--ui-testing"]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func enter(_ text: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func completeSignUpForm(in app: XCUIApplication) {
        enter("person@example.invalid", in: app.textFields["auth.email"])
        enterSecure(
            "local-pass",
            in: app.secureTextFields["auth.password"],
            app: app
        )
        enterSecure(
            "local-pass",
            in: app.secureTextFields["auth.password-confirmation"],
            app: app
        )
    }

    @MainActor
    private func reachOnboardingWelcome(in app: XCUIApplication) {
        XCTAssertTrue(
            element("screen.auth.sign-in", in: app)
                .waitForExistence(timeout: 3)
        )
        app.buttons["auth.open-sign-up"].tap()
        completeSignUpForm(in: app)
        app.buttons["auth.sign-up.submit"].tap()
        XCTAssertTrue(
            element("screen.auth.email-confirmation", in: app)
                .waitForExistence(timeout: 3)
        )
        app.buttons["auth.confirm-development"].tap()
        XCTAssertTrue(
            element("screen.onboarding.welcome", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func enterSecure(
        _ text: String,
        in field: XCUIElement,
        app: XCUIApplication
    ) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        XCTAssertTrue(waitForKeyboardFocus(field))

        // iOS 26.5 retains only the final character when XCUI bulk-types
        // into the first new-password field. The edit menu preserves the
        // complete synthetic credential while exercising the real field.
        UIPasteboard.general.string = text
        defer { UIPasteboard.general.string = nil }
        field.press(forDuration: 1)

        let paste = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "label == %@ OR label == %@",
                    "Colar",
                    "Paste"
                )
            )
            .firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 3))
        paste.tap()
    }

    @MainActor
    private func waitForKeyboardFocus(
        _ field: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func assertNoOverlap(
        _ first: XCUIElement,
        _ second: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            first.frame.intersection(second.frame).isNull,
            "\(first.identifier) e \(second.identifier) não devem se sobrepor",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertVisibleAndHittable(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 3),
            "O controle deve existir",
            file: file,
            line: line
        )
        XCTAssertTrue(
            element.isHittable,
            "O controle deve permanecer visível e acionável",
            file: file,
            line: line
        )
        assertMinimumTapTarget(element, file: file, line: line)
    }

    @MainActor
    private func assertMinimumTapTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 3),
            "O controle deve existir",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            43.99,
            "O alvo deve ter pelo menos 44 pt de largura",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            43.99,
            "O alvo deve ter pelo menos 44 pt de altura",
            file: file,
            line: line
        )
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachHierarchy(of: app, name: name)
    }

    @MainActor
    private func waitForSelected(
        _ element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                (object as? XCUIElement)?.isSelected == true
            },
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForHorizontallySettled(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 3
    ) -> Bool {
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: timeout) else {
            return false
        }

        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement,
                      element.exists else {
                    return false
                }

                let elementFrame = element.frame
                let windowFrame = window.frame
                return abs(elementFrame.midX - windowFrame.midX) <= 1
                    && elementFrame.width > 0
                    && elementFrame.height > 0
            },
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForVisualStability(
        timeout: TimeInterval = 1.5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(0.4)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in Date() >= deadline },
            object: NSObject()
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func attachHierarchy(of app: XCUIApplication, name: String) {
        let description = app.debugDescription
        let hierarchy = XCTAttachment(string: description)
        hierarchy.name = "\(name)-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        print("BODYFLOW_UI_TREE_BEGIN \(name)")
        print(description)
        print("BODYFLOW_UI_TREE_END \(name)")
    }
}
