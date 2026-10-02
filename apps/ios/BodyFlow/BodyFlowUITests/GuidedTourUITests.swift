import XCTest

/// The spotlight tour over the real screen: offered once on the first entry,
/// one real control lit per step, skippable at any point, replayable from
/// Profile (which comes back to Profile), with one contextual tip on the
/// first visit to Register. Nothing is opened or changed by the tour.
final class GuidedTourUITests: XCTestCase {
    @MainActor private var support: PremiumUIUXUITestSupport { PremiumUIUXUITestSupport(testCase: self) }
    private let eligible = ["--ui-testing", "--ui-testing-tutorial-eligible"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func assertCalloutClearOf(_ target: XCUIElement, app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let callout = support.element("tour.callout", app: app)
        XCTAssertTrue(callout.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(target.exists, file: file, line: line)
        XCTAssertFalse(callout.frame.intersects(target.frame), "The callout must not cover its target", file: file, line: line)
        XCTAssertTrue(app.frame.contains(callout.frame), "The callout must stay on screen", file: file, line: line)
        // The lit control itself is on screen (scrolled into view) and, for a
        // Today control, above the tab bar rather than behind it.
        XCTAssertTrue(app.frame.contains(target.frame), "The spotlighted control must be on screen", file: file, line: line)
        let bar = app.otherElements["navigation.tab-bar"].firstMatch
        if bar.exists, !bar.frame.contains(target.frame) {
            XCTAssertLessThanOrEqual(target.frame.maxY, bar.frame.minY + 0.5, "Target hidden behind the bar", file: file, line: line)
        }
    }

    @MainActor
    func testFirstEntryLightsEachRealControlAndFinishes() {
        let app = support.launch(arguments: eligible, language: "pt-BR", dark: false)
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Etapa 1 de 8"].exists)
        support.capture("tour-pt-light-welcome", app: app)
        let start = app.buttons["tour.start"]
        support.assertTarget(start)
        start.tap()

        let expectations: [(step: String, target: String)] = [
            ("flow", "today.flow-chat"), ("library", "today.library"), ("register", "tab.registrar"),
            ("plan", "tab.plano"), ("progress", "tab.progresso"), ("profile", "tab.perfil"),
        ]
        for (index, pair) in expectations.enumerated() {
            XCTAssertTrue(support.element("tour.step.\(pair.step)", app: app).waitForExistence(timeout: 5), pair.step)
            XCTAssertTrue(app.staticTexts["Etapa \(index + 2) de 8"].exists)
            assertCalloutClearOf(app.buttons[pair.target].firstMatch, app: app)
            if pair.step == "flow" { support.capture("tour-pt-light-flow", app: app) }
            support.assertTarget(app.buttons["tour.next"])
            app.buttons["tour.next"].tap()
        }
        XCTAssertTrue(support.element("tour.step.trail", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(support.element("tour.trail.diagram", app: app).exists)
        support.capture("tour-pt-light-trail", app: app)
        XCTAssertFalse(app.buttons["tour.next"].exists)
        app.buttons["tour.finish"].tap()
        XCTAssertFalse(support.element("tour.overlay", app: app).waitForExistence(timeout: 2))
        // Still on Today, nothing opened.
        XCTAssertTrue(support.element("screen.hoje", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(support.element("screen.flow-chat", app: app).exists)
        XCTAssertFalse(support.element("sheet.fechar", app: app).exists)
    }

    @MainActor
    func testNotNowAndSkipNeverCountAsFinishing() {
        let app = support.launch(arguments: eligible, language: "en-US", dark: true)
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 10))
        app.buttons["tour.start"].tap()
        XCTAssertTrue(support.element("tour.step.flow", app: app).waitForExistence(timeout: 5))
        support.capture("tour-en-dark-flow", app: app)
        app.buttons["tour.back"].tap()
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 5))
        app.buttons["tour.start"].tap()
        let skip = app.buttons["tour.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        support.assertTarget(skip)
        skip.tap()
        XCTAssertFalse(support.element("tour.overlay", app: app).waitForExistence(timeout: 2))
        // Deferred: the tour is not offered again by itself this session.
        app.buttons["tab.plano"].tap()
        app.buttons["tab.hoje"].tap()
        XCTAssertFalse(support.element("tour.overlay", app: app).waitForExistence(timeout: 2))
    }

    @MainActor
    func testReplayFromProfileGoesToTodayAndComesBack() {
        let app = support.launch(arguments: eligible, language: "pt-BR", dark: false)
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 10))
        app.buttons["tour.later"].tap()
        app.buttons["tab.perfil"].tap()
        let replay = support.element("profile.tutorial", app: app)
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        // The replay starts on Today's root, with Fechar instead of Agora não.
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tour.later"].exists)
        app.buttons["tour.start"].tap()
        XCTAssertTrue(support.element("tour.step.flow", app: app).waitForExistence(timeout: 5))
        assertCalloutClearOf(app.buttons["today.flow-chat"].firstMatch, app: app)
        app.buttons["tour.skip"].tap()
        // Back where the replay was asked for.
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        XCTAssertTrue(support.element("screen.perfil", app: app).exists)
    }

    @MainActor
    func testFirstVisitToRegisterShowsOneTipOnTheMealAction() {
        let app = support.launch(arguments: eligible, language: "pt-BR", dark: false)
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 10))
        app.buttons["tour.later"].tap()
        app.buttons["tab.registrar"].tap()
        XCTAssertTrue(support.element("tour.step.tip.meal", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(support.element("tour.position", app: app).exists)
        assertCalloutClearOf(app.buttons["register.refeicao"].firstMatch, app: app)
        support.capture("tour-tip-meal", app: app)
        app.buttons["tour.got-it"].tap()
        XCTAssertFalse(support.element("tour.overlay", app: app).waitForExistence(timeout: 2))
        // Once only: leaving and coming back shows no tip.
        app.buttons["tab.hoje"].tap()
        app.buttons["tab.registrar"].tap()
        XCTAssertFalse(support.element("tour.overlay", app: app).waitForExistence(timeout: 2))
        // The meal action still works after the tip.
        XCTAssertTrue(app.buttons["register.refeicao"].isHittable)
    }

    @MainActor
    func testAccessibilityXXXLKeepsTheCalloutOnScreenAndClearOfTheTarget() {
        let app = support.launch(
            arguments: eligible, language: "pt-BR", dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(support.element("tour.step.welcome", app: app).waitForExistence(timeout: 10))
        app.buttons["tour.start"].tap()
        XCTAssertTrue(support.element("tour.step.flow", app: app).waitForExistence(timeout: 5))
        assertCalloutClearOf(app.buttons["today.flow-chat"].firstMatch, app: app)
        let next = app.buttons["tour.next"]
        XCTAssertTrue(next.isHittable)
        support.assertTarget(next)
        for _ in 0..<2 { next.tap() }
        XCTAssertTrue(support.element("tour.step.register", app: app).waitForExistence(timeout: 5))
        assertCalloutClearOf(app.buttons["tab.registrar"].firstMatch, app: app)
        support.capture("tour-axxxl-register", app: app)
        // The tallest step (trail) must still end with Concluir reachable.
        for _ in 0..<4 { app.buttons["tour.next"].tap() }
        XCTAssertTrue(support.element("tour.step.trail", app: app).waitForExistence(timeout: 5))
        let finish = app.buttons["tour.finish"]
        var swipes = 0
        while !finish.isHittable && swipes < 8 {
            support.element("tour.callout", app: app).swipeUp()
            swipes += 1
        }
        XCTAssertTrue(finish.isHittable, "Concluir must be reachable at AXXXL")
        support.assertTarget(finish)
        support.capture("tour-axxxl-trail", app: app)
        finish.tap()
        XCTAssertFalse(support.element("tour.overlay", app: app).waitForExistence(timeout: 2))
    }
}
