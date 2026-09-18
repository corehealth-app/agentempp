import XCTest

final class PremiumContentProfileUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProfileFixtureProvenanceAndServerOptionGate() {
        let support = PremiumUIUXUITestSupport(testCase: self)
        let app = support.launch(
            arguments: [
                "--ui-testing",
                "--ui-testing-prompt14-persona-stateful",
            ],
            language: "pt-BR",
            dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        openProfile(in: app)
        XCTAssertTrue(app.staticTexts["Perfil de demonstração"].exists)
        XCTAssertTrue(app.staticTexts["Dados de demonstração"].exists)
        XCTAssertFalse(app.buttons["Excluir conta"].exists)
        XCTAssertFalse(app.buttons["Enviar notificações"].exists)

        let style = support.element("profile.coach-persona", app: app)
        XCTAssertTrue(style.waitForExistence(timeout: 5))
        support.assertTarget(style)
        style.tap()

        let editor = support.element(
            "screen.profile.coach-persona",
            app: app
        )
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Estilo do Flow"].exists)
        XCTAssertTrue(app.buttons["persona.focus"].exists)
        for identifier in ["persona.impulse", "persona.zen"] {
            let option = app.buttons[identifier]
            for _ in 0..<4 where !option.exists {
                app.swipeUp()
            }
            XCTAssertTrue(option.exists)
        }
        XCTAssertFalse(
            support.element("persona.options.unavailable", app: app).exists
        )

        let cancel = app.buttons["Cancelar"]
        let save = app.buttons["Salvar"]
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(save.exists)
        support.assertTarget(cancel)
        support.assertTarget(save)
        XCTAssertTrue(cancel.frame.intersection(save.frame).isNull)
        assertFullyVisible(cancel, in: app)
        assertFullyVisible(save, in: app)
        support.capture("s7-profile-pt-light-axxxl", app: app)
        app.terminate()

        let gated = support.launch(
            arguments: ["--ui-testing"],
            language: "en-US",
            dark: true
        )
        openProfile(in: gated)
        support.element("profile.coach-persona", app: gated).tap()
        XCTAssertTrue(
            support.element("persona.options.unavailable", app: gated)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(gated.navigationBars["Flow’s style"].exists)
        support.capture("s7-profile-en-dark-unavailable", app: gated)
    }

    @MainActor
    func testArticleActionsAndMetadataAtAXXXXL() {
        let support = PremiumUIUXUITestSupport(testCase: self)
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt14-loaded"],
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        let library = support.element("today.library", app: app)
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        for _ in 0..<6 where !library.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(library.isHittable)
        library.tap()
        XCTAssertTrue(
            support.element("screen.library", app: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.navigationBars["Library"].exists)
        let allFilter = app.buttons["All"]
        let savedFilter = app.buttons["Saved"]
        XCTAssertTrue(allFilter.exists)
        XCTAssertTrue(savedFilter.exists)
        assertFullyVisible(allFilter, in: app)
        assertFullyVisible(savedFilter, in: app)
        XCTAssertLessThanOrEqual(
            allFilter.frame.maxY,
            savedFilter.frame.minY,
            "Accessibility filters must stack rather than compress labels"
        )

        let card = app.buttons[
            "library.card.10000000-0000-4000-8000-000000000001"
        ]
        for _ in 0..<5 where !card.exists {
            app.swipeUp()
        }
        XCTAssertTrue(card.exists)
        XCTAssertTrue(
            card.label.contains("Open article"),
            "The AX action must identify article opening separately from metadata"
        )
        XCTAssertTrue(app.staticTexts["Nutrition"].exists)
        XCTAssertTrue(app.staticTexts["7 min read"].exists)
        support.assertTarget(card)
        support.capture("s7-library-en-dark-axxxl", app: app)

        card.tap()
        XCTAssertTrue(
            support.element(
                "screen.content-detail.10000000-0000-4000-8000-000000000001",
                app: app
            ).waitForExistence(timeout: 5)
        )
        let save = support.element("content-detail.save", app: app)
        for _ in 0..<6 where !save.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(save.exists)
        XCTAssertEqual(save.label, "Remove from saved")
        support.assertTarget(save)
        let category = support.element("content-detail.category", app: app)
        let readingTime = support.element("content-detail.reading-time", app: app)
        XCTAssertEqual(category.label, "Nutrition")
        XCTAssertEqual(readingTime.label, "4 min read")
        XCTAssertFalse(app.images["content.cover"].exists)
        support.capture("s7-article-en-dark-axxxl", app: app)
    }

    @MainActor
    func testRoutineActionSheetAndHistoryReadOnlyAX() {
        let support = PremiumUIUXUITestSupport(testCase: self)
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            language: "pt-BR",
            dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        let supplement = support.element("routine.supplement-1", app: app)
        XCTAssertTrue(supplement.waitForExistence(timeout: 8))
        supplement.tap()

        let taken = app.buttons["routine.action.taken"]
        XCTAssertTrue(taken.waitForExistence(timeout: 5))
        support.assertTarget(taken)
        taken.tap()
        XCTAssertTrue(app.navigationBars["Confirmar ação"].waitForExistence(timeout: 5))
        let submit = app.buttons["routine.action.submit"]
        XCTAssertTrue(submit.exists)
        support.assertTarget(submit)
        XCTAssertTrue(app.buttons["Fechar"].exists)
        support.capture("s7-routine-confirmation-pt-light-axxxl", app: app)
        app.buttons["Fechar"].tap()

        let routineHistory = app.buttons["routine.history"]
        XCTAssertTrue(routineHistory.waitForExistence(timeout: 5))
        support.assertTarget(routineHistory)
        routineHistory.tap()
        XCTAssertTrue(
            support.element(
                "routine.history.row.routine-history-rule-20",
                app: app
            ).waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["Editar"].exists)
        XCTAssertFalse(app.buttons["Excluir"].exists)
        XCTAssertFalse(app.buttons["Corrigir"].exists)
        support.capture("s7-routine-history-read-only-pt-light-axxxl", app: app)
    }

    @MainActor
    private func openProfile(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["tab.perfil"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.perfil"]
                .waitForExistence(timeout: 5)
        )
    }

    private func assertFullyVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        let appFrame = app.frame
        XCTAssertGreaterThanOrEqual(frame.minX, appFrame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, appFrame.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, appFrame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, appFrame.maxY, file: file, line: line)
    }
}
