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
    func testPhysicalOfficialWeightAppearsWithMeasuredDateWhenProgressWeightIsNull() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .progressOfficialWeight)

        support.openProgress(in: app)
        XCTAssertTrue(
            support.element("progress.profile-weight.value", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            support.element("progress.profile-weight.value", in: app).label,
            "80 kg"
        )
        let measuredDate = support.element("progress.profile-weight.date", in: app)
        XCTAssertTrue(measuredDate.exists)
        XCTAssertTrue(measuredDate.label.contains("Medido em "))
        XCTAssertTrue(measuredDate.label.contains("2026"))
        XCTAssertTrue(support.element("progress.summary", in: app).exists)
    }

    @MainActor
    func testOfficialWeightAndMeasuredDateRemainVisibleWhileProgressReadIsPending() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .progressProfileFirst)

        support.openProgress(in: app)
        let weight = support.element("progress.profile-weight.value", in: app)
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertEqual(weight.label, "80 kg")
        let measuredDate = support.element("progress.profile-weight.date", in: app)
        XCTAssertTrue(measuredDate.exists)
        XCTAssertTrue(measuredDate.label.contains("Medido em "))
        XCTAssertTrue(measuredDate.label.contains("2026"))
        XCTAssertTrue(
            support.element("state.loading", in: app).exists,
            "The progress read must still be pending when profile weight is visible"
        )
        XCTAssertFalse(support.element("progress.summary", in: app).exists)
    }

    /// Measurements and consistency share one card and the achievements
    /// (streak restart, medals, missions) share another, while the official
    /// summary keeps its own card. Every existing identifier keeps a real
    /// container inside the group it belongs to.
    @MainActor
    func testProgressGroupsMeasurementsAndAchievementsPreservingIdentifiers() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .streakZero)

        support.openProgress(in: app)
        XCTAssertTrue(app.staticTexts["Seu progresso"].waitForExistence(timeout: 5))

        let body = support.element("progress.body", in: app)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let measurements = support.element("progress.measurements", in: app)
        let consistency = support.element("progress.consistency", in: app)
        XCTAssertTrue(measurements.exists)
        XCTAssertTrue(consistency.exists)
        XCTAssertTrue(
            body.frame.contains(measurements.frame),
            "Measurements \(measurements.frame) must sit inside the body card \(body.frame)"
        )
        XCTAssertTrue(
            body.frame.contains(consistency.frame),
            "Consistency \(consistency.frame) must sit inside the body card \(body.frame)"
        )
        XCTAssertLessThanOrEqual(measurements.frame.maxY, consistency.frame.minY)

        let summary = support.element("progress.summary", in: app)
        XCTAssertTrue(summary.exists)
        XCTAssertTrue(
            body.frame.intersection(summary.frame).isNull,
            "The official summary keeps its own card"
        )

        let achievements = support.element("progress.achievements", in: app)
        XCTAssertTrue(achievements.exists)
        for identifier in [
            "progress.streak.restart",
            "progress.badges",
            "progress.missions.unavailable",
        ] {
            let child = support.element(identifier, in: app)
            XCTAssertTrue(child.exists, identifier)
            XCTAssertTrue(
                achievements.frame.contains(child.frame),
                "\(identifier) \(child.frame) must sit inside the achievements card "
                    + "\(achievements.frame)"
            )
        }
        XCTAssertTrue(support.element("progress.dates", in: app).exists)
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
