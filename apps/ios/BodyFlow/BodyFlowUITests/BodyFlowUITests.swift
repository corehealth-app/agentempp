import XCTest

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

            let screen = element(screenID, in: app)
            XCTAssertTrue(screen.waitForExistence(timeout: 3), "A tela \(screenID) deve existir")

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
        capture("06-hoje-detalhe-restaurado", app: app)
    }

    @MainActor
    func testRegistrationSheetExplainsNothingWasSaved() {
        let app = launchApp()
        app.tabBars.buttons["tab.registrar"].tap()

        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 3))
        meal.tap()

        XCTAssertTrue(
            element("sheet.registrar.refeicao", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["Demonstração local. Nenhum registro foi salvo."]
                .waitForExistence(timeout: 3)
        )

        capture("07-registro-refeicao", app: app)
        app.buttons["sheet.fechar"].tap()
        XCTAssertFalse(
            element("sheet.registrar.refeicao", in: app)
                .waitForExistence(timeout: 1)
        )
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
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
