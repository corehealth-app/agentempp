import XCTest

@MainActor
final class ConversationalNavigationUITests: XCTestCase {
    func testCandidateShowsFourApprovedVisibleTabsAndReadOnlyFlow() {
        let app = launch(candidate: true)
        defer { app.terminate() }
        let bar = tabBar(app)
        guard bar.waitForExistence(timeout: 15) else { XCTFail("Root bar missing: \(app.debugDescription)"); return }
        XCTAssertEqual(bar.buttons.count, 4)
        let ids = ["tab.hoje", "tab.plano", "tab.registrar", "tab.progresso"]
        XCTAssertEqual(ids.map { bar.buttons[$0].label }, ["Flow", "Alimentação", "Treino", "Jornada"])
        XCTAssertFalse(bar.buttons["tab.perfil"].exists)
        XCTAssertTrue(element("flow.read-only", app).waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["flow.send"].exists)
        XCTAssertFalse(app.textFields["flow.composer"].exists)
        let screens = ["screen.flow-chat", "screen.alimentacao", "screen.treino", "screen.jornada"]
        for (id, screen) in zip(ids, screens) {
            let button = tabBar(app).buttons[id]
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            button.tap()
            XCTAssertTrue(element(screen, app).waitForExistence(timeout: 8), "Missing \(screen)")
            XCTAssertTrue(tabBar(app).buttons[id].isSelected)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "candidate-four-tabs-journey"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testOriginalRegisterSummaryProfileAndLibraryRemainRealSecondaryDestinations() {
        let app = launch(candidate: true)
        defer { app.terminate() }
        XCTAssertTrue(tabBar(app).waitForExistence(timeout: 15))
        openMore("navigation.registrations", app)
        XCTAssertTrue(element("screen.registrar", app).waitForExistence(timeout: 8))
        XCTAssertTrue(tabBar(app).buttons["tab.hoje"].isSelected, "Meal/mixed Register must remain on Flow origin")
        for id in ["register.refeicao", "register.treino", "register.peso", "register.hidratacao"] {
            XCTAssertTrue(app.buttons[id].exists)
        }
        back(app)
        openMore("navigation.overview", app)
        XCTAssertTrue(element("screen.hoje", app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["today.library"].exists)
        back(app)
        openMore("navigation.library", app)
        XCTAssertTrue(element("screen.library", app).waitForExistence(timeout: 8))
        back(app)
        app.buttons["navigation.profile"].tap()
        XCTAssertTrue(element("screen.perfil", app).waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["profile.tutorial"].exists, "The five-tab spotlight is not offered on the preview")
    }

    func testTrainingPlanPushRetainsTrainingOriginAndTabPathsSurviveSwitch() {
        let app = launch(candidate: true)
        defer { app.terminate() }
        XCTAssertTrue(tabBar(app).waitForExistence(timeout: 15))
        tabBar(app).buttons["tab.registrar"].tap()
        XCTAssertTrue(element("screen.treino", app).waitForExistence(timeout: 8))
        openMore("navigation.plans", app)
        XCTAssertTrue(element("screen.plano", app).waitForExistence(timeout: 8))
        XCTAssertTrue(tabBar(app).buttons["tab.registrar"].isSelected)
        tabBar(app).buttons["tab.plano"].tap()
        XCTAssertTrue(element("screen.alimentacao", app).waitForExistence(timeout: 8))
        tabBar(app).buttons["tab.registrar"].tap()
        XCTAssertTrue(element("screen.plano", app).waitForExistence(timeout: 8))
        XCTAssertTrue(tabBar(app).buttons["tab.registrar"].isSelected)
    }

    func testDefaultLaunchKeepsFiveLegacyTabs() {
        let app = launch(candidate: false)
        defer { app.terminate() }
        let bar = tabBar(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 15))
        XCTAssertEqual(bar.buttons.count, 5)
        XCTAssertEqual(["tab.hoje", "tab.plano", "tab.registrar", "tab.progresso", "tab.perfil"].map { bar.buttons[$0].label },
            ["Hoje", "Plano", "Registrar", "Progresso", "Perfil"])
        XCTAssertTrue(element("screen.hoje", app).waitForExistence(timeout: 8))
        XCTAssertFalse(element("flow.read-only", app).exists)
    }

    private func launch(candidate: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-prompt14-loaded"]
        if candidate { app.launchArguments.append("--ui-testing-conversational-navigation") }
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        return app
    }
    private func tabBar(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["navigation.tab-bar"].firstMatch
    }
    private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
    private func openMore(_ identifier: String, _ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["navigation.secondary-menu"].waitForExistence(timeout: 8))
        app.buttons["navigation.secondary-menu"].tap()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 4))
        app.buttons[identifier].tap()
    }
    private func back(_ app: XCUIApplication) {
        let buttons = app.navigationBars.buttons.allElementsBoundByIndex
        guard let button = buttons.min(by: { $0.frame.minX < $1.frame.minX }) else { XCTFail("Missing native back action"); return }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
}
