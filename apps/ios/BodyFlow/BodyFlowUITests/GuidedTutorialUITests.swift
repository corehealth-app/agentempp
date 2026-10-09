import XCTest

/// The guided tour: offered once on the first eligible entry, explained step
/// by step, closable at any point, and replayable from Profile. It never
/// moves the user's tab or opens an action by itself.
final class GuidedTutorialUITests: XCTestCase {
    @MainActor private var support: PremiumUIUXUITestSupport { PremiumUIUXUITestSupport(testCase: self) }
    /// The text tour is the VoiceOver path; the spotlight tour is covered by
    /// GuidedTourUITests.
    private let eligible = ["--ui-testing", "--ui-testing-tutorial-eligible", "--ui-testing-tutorial-text"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAvailableCurrentObjectiveIsExplainedWithoutOpeningIt() {
        for (language, consultation, position) in [
            ("pt-BR", "Em “Seu objetivo” você consulta o objetivo e as metas disponíveis para esta conta.", "Etapa 8 de 8"),
            ("en-US", "In “Your objective” you can view the objective and targets available for this account.", "Step 8 of 8"),
        ] {
            // A provider exists with an empty snapshot: screen availability is
            // independent of loaded values, and comes from the real factory.
            let app = support.launch(arguments: eligible + ["--ui-testing-current-objective-empty"], language: language, dark: false)
            XCTAssertTrue(support.element("tutorial.step.welcome", app: app).waitForExistence(timeout: 10))
            app.buttons["tutorial.start"].tap()
            XCTAssertTrue(support.element("tutorial.step.today", app: app).waitForExistence(timeout: 5))
            for area in ["flow", "plan", "register", "progress", "routineLibrary", "profile"] {
                app.buttons["tutorial.next"].tap()
                XCTAssertTrue(support.element("tutorial.step.\(area)", app: app).waitForExistence(timeout: 5), area)
            }
            let line = support.element("tutorial.line.tutorial.profile.objective", app: app)
            XCTAssertTrue(line.waitForExistence(timeout: 5))
            XCTAssertEqual(line.label, consultation)
            XCTAssertTrue(app.staticTexts[position].exists)
            XCTAssertTrue(app.buttons["tutorial.finish"].isHittable)
            XCTAssertFalse(support.element("screen.current-objective", app: app).exists)
            support.capture("tutorial-current-objective-\(language)-empty-capability", app: app)
            app.buttons["tutorial.close"].tap()
            XCTAssertTrue(support.element(AppTabIdentifiers.todayScreen, app: app).waitForExistence(timeout: 5))
            XCTAssertFalse(support.element("sheet.fechar", app: app).exists)
            app.buttons["tab.perfil"].tap()
            let entry = support.element("profile.current-objective", app: app)
            for _ in 0..<12 where !entry.isHittable { app.swipeUp() }
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertTrue(entry.isHittable)
            support.assertTarget(entry)
            XCTAssertFalse(support.element("screen.current-objective", app: app).exists)
            app.terminate()
        }
    }

    @MainActor
    func testDefaultUITestLaunchNeverOffersTheTour() {
        let app = support.launch(arguments: ["--ui-testing"], language: "pt-BR", dark: false)
        XCTAssertTrue(app.buttons["tab.hoje"].waitForExistence(timeout: 10))
        XCTAssertFalse(support.element("screen.tutorial", app: app).waitForExistence(timeout: 2))
        XCTAssertFalse(support.element("tour.overlay", app: app).exists)
    }

    @MainActor
    func testFirstEntryOffersTheTourAndNotNowKeepsTheUserWhereTheyWere() {
        let app = support.launch(arguments: eligible, language: "pt-BR", dark: false)
        XCTAssertTrue(support.element("screen.tutorial", app: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Etapa 1 de 8"].exists)
        XCTAssertTrue(app.staticTexts["Boas-vindas ao Performe AI"].exists)
        let later = app.buttons["tutorial.later"]
        let start = app.buttons["tutorial.start"]
        support.assertTarget(later)
        support.assertTarget(start)
        XCTAssertEqual(later.label, "Agora não")
        support.capture("tutorial-pt-light-welcome", app: app)
        later.tap()
        XCTAssertFalse(support.element("screen.tutorial", app: app).waitForExistence(timeout: 2))
        XCTAssertTrue(support.element(AppTabIdentifiers.todayScreen, app: app).waitForExistence(timeout: 5))
        // Answered: not offered again in this session.
        app.buttons["tab.perfil"].tap()
        app.buttons["tab.hoje"].tap()
        XCTAssertFalse(support.element("screen.tutorial", app: app).waitForExistence(timeout: 2))
    }

    @MainActor
    func testWalkThroughBackAndFinishThenReplayFromProfile() {
        let app = support.launch(arguments: eligible, language: "en-US", dark: true)
        XCTAssertTrue(support.element("screen.tutorial", app: app).waitForExistence(timeout: 10))
        app.buttons["tutorial.start"].tap()
        XCTAssertTrue(support.element("tutorial.step.today", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Step 2 of 8"].exists)
        support.capture("tutorial-en-dark-today", app: app)
        app.buttons["tutorial.back"].tap()
        XCTAssertTrue(support.element("tutorial.step.welcome", app: app).waitForExistence(timeout: 5))
        app.buttons["tutorial.start"].tap()
        for area in ["flow", "plan", "register", "progress", "routineLibrary", "profile"] {
            let next = app.buttons["tutorial.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
            XCTAssertTrue(support.element("tutorial.step.\(area)", app: app).waitForExistence(timeout: 5), area)
        }
        XCTAssertFalse(app.buttons["tutorial.next"].exists)
        let finish = app.buttons["tutorial.finish"]
        XCTAssertEqual(finish.label, "Done")
        finish.tap()
        XCTAssertFalse(support.element("screen.tutorial", app: app).waitForExistence(timeout: 2))

        app.buttons["tab.perfil"].tap()
        let replay = support.element("profile.tutorial", app: app)
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        support.assertTarget(replay)
        replay.tap()
        XCTAssertTrue(support.element("tutorial.step.welcome", app: app).waitForExistence(timeout: 5))
        // A replay only closes; it offers each area directly.
        XCTAssertFalse(app.buttons["tutorial.later"].exists)
        let progressArea = support.element("tutorial.area.progress", app: app)
        XCTAssertTrue(progressArea.waitForExistence(timeout: 5))
        support.assertTarget(progressArea)
        progressArea.tap()
        XCTAssertTrue(support.element("tutorial.step.progress", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Step 6 of 8"].exists)
        app.buttons["tutorial.close"].tap()
        XCTAssertFalse(support.element("screen.tutorial", app: app).waitForExistence(timeout: 2))
        // Closing the replay returns to the same Profile screen.
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTheTourNeverOpensAnActionOrChangesTheTab() {
        let app = support.launch(arguments: eligible, language: "pt-BR", dark: false)
        XCTAssertTrue(support.element("screen.tutorial", app: app).waitForExistence(timeout: 10))
        app.buttons["tutorial.start"].tap()
        for _ in 0..<6 { app.buttons["tutorial.next"].tap() }
        XCTAssertTrue(support.element("tutorial.step.profile", app: app).waitForExistence(timeout: 5))
        app.buttons["tutorial.close"].tap()
        XCTAssertTrue(support.element(AppTabIdentifiers.todayScreen, app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(support.element("screen.flow-chat", app: app).exists)
        // No registration sheet was opened by the tour.
        XCTAssertFalse(support.element("sheet.fechar", app: app).exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testAccessibilityXXXLKeepsTextAndActionsReachable() {
        let app = support.launch(
            arguments: eligible, language: "pt-BR", dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(support.element("screen.tutorial", app: app).waitForExistence(timeout: 10))
        let start = app.buttons["tutorial.start"]
        XCTAssertTrue(start.isHittable)
        support.assertTarget(start)
        start.tap()
        let title = support.element("tutorial.step.today", app: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let next = app.buttons["tutorial.next"]
        XCTAssertTrue(next.isHittable)
        XCTAssertTrue(app.buttons["tutorial.back"].isHittable)
        // The end of the step's last line scrolls fully into view above the
        // actions, even when one line is taller than the screen at AXXXL.
        let lastLine = support.element("tutorial.line.tutorial.today.details", app: app)
        var swipes = 0
        while lastLine.frame.maxY > next.frame.minY + 1 && swipes < 12 {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(lastLine.isHittable)
        XCTAssertLessThanOrEqual(lastLine.frame.maxY, next.frame.minY + 1)
        XCTAssertTrue(next.isHittable)
        support.capture("tutorial-axxxl-today", app: app)
    }
}

private enum AppTabIdentifiers {
    static let todayScreen = "screen.hoje"
}
