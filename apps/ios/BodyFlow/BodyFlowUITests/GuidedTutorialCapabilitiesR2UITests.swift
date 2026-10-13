// PRIVATE TEST CANDIDATE. Existing tutorial only; no product implementation.
import XCTest

final class GuidedTutorialCapabilitiesR2UITests: XCTestCase {
    @MainActor private var support: PremiumUIUXUITestSupport { .init(testCase: self) }
    private let eligible = ["--ui-testing", "--ui-testing-tutorial-eligible"]
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNoDraftPlanNeverPromisesReviewOrImportInEitherLanguage() {
        for language in ["pt-BR", "en-US"] {
            let app = support.launch(arguments: eligible, language: language, dark: false)
            arrive(at: "plan", app: app)
            let body = support.element("tour.body.plan", app: app)
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            let forbidden = language == "pt-BR" ? ["sugest", "Para revisar", "Importar plano", "PDF"]
                : ["suggest", "To review", "Import plan", "PDF"]
            for term in forbidden { XCTAssertFalse(body.label.localizedCaseInsensitiveContains(term), term) }
            let current = language == "pt-BR" ? "atuais" : "current"
            XCTAssertTrue(body.label.localizedCaseInsensitiveContains(current))
            assertNoActionWasOpened(app)
            app.buttons["tour.skip"].tap()
            XCTAssertTrue(support.element("screen.hoje", app: app).waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    // Independent traversal: a Plan failure cannot prevent the trail oracle.
    @MainActor
    func testNoDraftTrailNeverPromisesFlowPlanChangesInEitherLanguage() {
        for language in ["pt-BR", "en-US"] {
            let app = support.launch(arguments: eligible, language: language, dark: false)
            arrive(at: "trail", app: app)
            let callout = support.element("tour.callout", app: app)
            XCTAssertTrue(callout.waitForExistence(timeout: 5))
            let displayed = callout.descendants(matching: .staticText)
                .allElementsBoundByIndex.map(\.label).joined(separator: "\n")
            let forbidden = language == "pt-BR" ? ["O Flow pode sugerir", "Para revisar", "Importar plano"]
                : ["Flow can suggest", "To review", "Import plan"]
            for term in forbidden { XCTAssertFalse(displayed.localizedCaseInsensitiveContains(term), term) }
            let protocolWord = language == "pt-BR" ? "protocolo" : "protocol"
            XCTAssertTrue(displayed.localizedCaseInsensitiveContains(protocolWord))
            XCTAssertTrue(support.element("tour.trail.diagram", app: app).exists)
            XCTAssertTrue(app.buttons["tour.finish"].isHittable)
            assertNoActionWasOpened(app)
            app.buttons["tour.finish"].tap()
            XCTAssertTrue(support.element("screen.hoje", app: app).waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testDraftOnlyPlanExplainsReviewButNotImport() {
        for language in ["pt-BR", "en-US"] {
            let app = support.launch(arguments: eligible + ["--ui-testing-plan-drafts"], language: language, dark: false)
            arrive(at: "plan", app: app)
            let body = support.element("tour.body.plan", app: app)
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            let queue = language == "pt-BR" ? "Para revisar" : "To review"
            XCTAssertTrue(body.label.localizedCaseInsensitiveContains(queue))
            XCTAssertTrue(body.label.localizedCaseInsensitiveContains("confirm"))
            for term in ["Importar plano", "Import plan", "PDF"] {
                XCTAssertFalse(body.label.localizedCaseInsensitiveContains(term), term)
            }
            assertNoActionWasOpened(app)
            app.buttons["tour.skip"].tap()
            app.terminate()
        }
    }

    @MainActor
    private func arrive(at target: String, app: XCUIApplication) {
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 10))
        app.buttons["tour.start"].tap()
        for step in ["flow", "library", "register", "plan", "progress", "profile", "trail"] {
            XCTAssertTrue(support.element("tour.step.\(step)", app: app).waitForExistence(timeout: 5), step)
            if step == target { return }
            app.buttons["tour.next"].tap()
        }
        XCTFail("Unknown preserved tutorial target")
    }

    @MainActor
    private func assertNoActionWasOpened(_ app: XCUIApplication) {
        XCTAssertFalse(support.element("sheet.fechar", app: app).exists)
        XCTAssertFalse(support.element("screen.flow-chat", app: app).exists)
    }
}
