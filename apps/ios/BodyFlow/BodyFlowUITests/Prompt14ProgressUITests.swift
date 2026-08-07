import XCTest

final class Prompt14ProgressUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompleteProgressRendersLiteralValuesAndDuplicateMedals() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .progressCompleteDuplicateBadges)

        support.openProgress(in: app)
        XCTAssertTrue(
            support.element("progress.summary", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["2.450 XP"].exists)
        XCTAssertTrue(app.staticTexts["Nível 7"].exists)
        XCTAssertTrue(app.staticTexts["12 dias"].exists)
        XCTAssertTrue(support.element("progress.medal.0", in: app).exists)
        XCTAssertTrue(support.element("progress.medal.1", in: app).exists)
        XCTAssertEqual(
            support.element("progress.medal.0", in: app).label,
            support.element("progress.medal.1", in: app).label
        )
        XCTAssertFalse(app.staticTexts["Próximo nível"].exists)
        support.captureEvidence(.progressGamification, of: app)
    }

    @MainActor
    func testNullProgressIsEmptyRatherThanInventedZeroSnapshot() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .progressEmpty)

        support.openProgress(in: app)
        XCTAssertTrue(
            support.element("state.empty", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(support.element("progress.summary", in: app).exists)
        XCTAssertFalse(app.staticTexts["0 XP"].exists)
    }

    @MainActor
    func testMinimumOfficialProgressRemainsLoadedData() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .progressMinimum)

        support.openProgress(in: app)
        XCTAssertTrue(
            support.element("progress.summary", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["0 XP"].exists)
        XCTAssertTrue(app.staticTexts["Nível 1"].exists)
        XCTAssertTrue(app.staticTexts["0 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Nenhuma medalha conquistada."].exists)
        XCTAssertFalse(support.element("state.empty", in: app).exists)
    }

    @MainActor
    func testZeroStreakIsSupportiveAndReturnsOnlyToToday() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .streakZero)

        support.openProgress(in: app)
        let restart = support.element("progress.streak.restart", in: app)
        support.reveal(restart, in: app)
        XCTAssertTrue(restart.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts[
                "Sua sequência pode recomeçar hoje. O que você já construiu continua contando."
            ].exists
        )
        let resume = support.element("progress.streak.resume-today", in: app)
        XCTAssertTrue(resume.exists)
        support.assertMinimumTapTarget(resume)

        let missions = support.element("progress.missions.unavailable", in: app)
        support.reveal(missions, in: app)
        XCTAssertTrue(missions.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Missões diárias — Indisponível nesta versão."]
                .exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "ranking")
            ).firstMatch.exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", "cooperativ")
            ).firstMatch.exists
        )
        support.captureEvidence(.streakZeroMissions, of: app)

        support.reveal(resume, in: app)
        resume.tap()
        XCTAssertTrue(
            support.element("screen.hoje", in: app)
                .waitForExistence(timeout: 5)
        )
    }
}
