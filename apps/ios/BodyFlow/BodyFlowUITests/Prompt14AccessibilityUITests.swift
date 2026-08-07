import XCTest

final class Prompt14AccessibilityUITests: XCTestCase {
    private let firstPublicationID =
        "10000000-0000-4000-8000-000000000001"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFiveOriginalTabsRetainIndependentStacks() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        for identifier in [
            "tab.hoje",
            "tab.registrar",
            "tab.plano",
            "tab.progresso",
            "tab.perfil",
        ] {
            let tab = app.tabBars.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(tab)
        }

        support.openLibrary(in: app)
        XCTAssertTrue(
            support.element("screen.library", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.plano"].tap()
        let planDetail = support.element("plan.detail", in: app)
        support.reveal(planDetail, in: app)
        planDetail.tap()
        XCTAssertTrue(
            support.element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.registrar"].tap()
        XCTAssertTrue(
            support.element("screen.registrar", in: app)
                .waitForExistence(timeout: 5)
        )
        app.tabBars.buttons["tab.progresso"].tap()
        XCTAssertTrue(
            support.element("screen.progresso", in: app)
                .waitForExistence(timeout: 5)
        )
        app.tabBars.buttons["tab.perfil"].tap()
        XCTAssertTrue(
            support.element("screen.perfil", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.hoje"].tap()
        XCTAssertTrue(
            support.element("screen.library", in: app)
                .waitForExistence(timeout: 5)
        )
        app.tabBars.buttons["tab.plano"].tap()
        XCTAssertTrue(
            support.element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(.finalSimulator, of: app)
    }

    @MainActor
    func testVoiceOverSemanticsExternalLinkAndMinimumTargets() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .markdownExternalLink)

        support.openLibrary(in: app)
        let all = support.element("library.selection.all", in: app)
        let saved = support.element("library.selection.saved", in: app)
        let category = support.element("library.category", in: app)
        for control in [all, saved, category] {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(control)
        }

        support.openContentDetail(firstPublicationID, in: app)
        XCTAssertTrue(
            app.staticTexts["CONTEÚDO SINTÉTICO COM REFERÊNCIA"]
                .waitForExistence(timeout: 5)
        )
        let link = app.links["Referência externa"]
        support.reveal(link, in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.debugDescription.contains("Link externo"))
        XCTAssertFalse(app.staticTexts["[Referência externa]"].exists)

        let save = support.element("content-detail.save", in: app)
        support.reveal(save, in: app)
        support.assertMinimumTapTarget(save)
    }

    @MainActor
    func testDarkModeEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .mascotFocusActive)

        let today = support.element("screen.hoje", in: app)
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertEqual(today.value as? String, "dark")
        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.isHittable)
        support.captureEvidence(.darkMode, of: app)
    }

    @MainActor
    func testAccessibilityXXXLEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        support.openLibrary(in: app)
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let category = support.element("library.category", in: app)
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(category)
        XCTAssertTrue(window.frame.contains(category.frame))

        let firstCard = support.element(
            "library.card.\(firstPublicationID)",
            in: app
        )
        support.revealFully(firstCard, in: app, within: window, attempts: 12)
        XCTAssertTrue(firstCard.isHittable)
        XCTAssertTrue(window.frame.contains(firstCard.frame))
        support.captureEvidence(.accessibilityXXXL, of: app)
    }

    @MainActor
    func testIncreaseContrastEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .progressCompleteDuplicateBadges)

        support.openProgress(in: app)
        let summary = support.element("progress.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(summary.label.isEmpty)
        support.captureEvidence(.increaseContrast, of: app)
    }

    @MainActor
    func testDifferentiateWithoutColorEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .differentiateWithoutColor)

        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertTrue(mascot.label.contains("personalidade Equilibrada"))
        XCTAssertTrue(mascot.label.contains("estado Em repouso"))
        support.captureEvidence(.differentiateWithoutColor, of: app)
    }

    @MainActor
    func testReduceMotionEvidence() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .reduceMotion)

        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        mascot.tap()
        let refresh = support.element("mascot.refresh", in: app)
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(refresh)
        support.captureEvidence(.reduceMotion, of: app)
    }
}
