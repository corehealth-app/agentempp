import XCTest

final class Prompt13TodayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayShowsSnapshotHeaderAndCoreMetricsBeforeAttention() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)
        let screen = element("screen.hoje", in: app)
        XCTAssertTrue(screen.waitForExistence(timeout: 5))

        let localDate = element("today.header.local-date", in: app)
        let protocolName = element("today.header.protocol", in: app)
        let updatedAt = element("today.header.updated-at", in: app)
        let attention = element("today.attention", in: app)
        let pending = element("today.pending", in: app)
        let energy = element("today.energy.remaining-food", in: app)

        for item in [localDate, attention, pending, energy] {
            XCTAssertTrue(item.waitForExistence(timeout: 3))
        }
        XCTAssertFalse(protocolName.exists)
        XCTAssertFalse(updatedAt.exists)
        element("today.header.details", in: app).tap()
        XCTAssertTrue(protocolName.waitForExistence(timeout: 3))
        XCTAssertTrue(updatedAt.exists)
        XCTAssertLessThanOrEqual(energy.frame.minY, attention.frame.minY)
        XCTAssertTrue(app.staticTexts["segunda-feira, 20 de julho"].exists)
        XCTAssertTrue(app.staticTexts["Protocolo: Recomposição corporal"].exists)
        support.captureEvidence(named: "01-today.png", of: app)
    }

    @MainActor
    func testTodaySeparatesFoodRemainingFromNetBalance() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        let remaining = element("today.energy.remaining-food", in: app)
        let excess = element("today.energy.food-excess", in: app)
        let netBalance = element("today.energy.net-balance", in: app)
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        XCTAssertTrue(excess.waitForExistence(timeout: 3))
        XCTAssertFalse(netBalance.exists)
        element("today.energy.details", in: app).tap()
        XCTAssertTrue(netBalance.waitForExistence(timeout: 3))
        XCTAssertNotEqual(remaining.frame, netBalance.frame)
        XCTAssertTrue(app.staticTexts["731 kcal"].exists)
        XCTAssertTrue(app.staticTexts["17 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Déficit de 83 kcal"].exists)
        XCTAssertFalse(app.staticTexts["-83 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Balanço do dia"].exists)
        XCTAssertFalse(app.staticTexts["Déficit líquido"].exists)
        XCTAssertEqual(
            netBalance.value as? String,
            "déficit de 83 quilocalorias; exercício incluído"
        )
        XCTAssertTrue(app.staticTexts["Exercício excluído"].exists)
        XCTAssertTrue(app.staticTexts["Exercício incluído"].exists)
    }

    @MainActor
    func testFoodBalanceLeadsWhileTechnicalBalanceOpensInDetails() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        let food = element("today.energy.remaining-food", in: app)
        let technical = element("today.energy.net-balance", in: app)
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        XCTAssertFalse(technical.exists, "Technical balance belongs in the disclosure")
        XCTAssertTrue(element("today.energy.consumed", in: app).exists)
        XCTAssertTrue(element("today.energy.target", in: app).exists)
        XCTAssertTrue(app.staticTexts["1.200 kcal"].exists)
        XCTAssertTrue(app.staticTexts["1.935 kcal"].exists)

        let details = element("today.energy.details", in: app)
        for _ in 0..<3 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.isHittable)
        details.tap()
        XCTAssertTrue(technical.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Déficit de 83 kcal"].exists)
    }

    @MainActor
    func testTodayShowsIncompleteDayAsContent() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .incomplete)

        XCTAssertTrue(
            element("today.completion.insufficient-data", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Dados insuficientes para fechar o dia"].exists
        )
        XCTAssertFalse(element("state.error", in: app).exists)
    }

    @MainActor
    func testTodayPreservesTwoIndividualMealRows() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        let first = element("today.meal.meal-z", in: app)
        let second = element("today.meal.meal-a", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        XCTAssertNotEqual(first.frame, second.frame)
        XCTAssertTrue(app.staticTexts["Item sintético Z"].exists)
        XCTAssertTrue(app.staticTexts["Item sintético A"].exists)
    }

    @MainActor
    func testTodayOfflineContentShowsStaleBannerAndRetry() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .staleOffline)
        let screen = element("screen.hoje", in: app)
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        XCTAssertTrue(
            element("today.header.local-date", in: app)
                .waitForExistence(timeout: 3)
        )

        let refresh = app.buttons["today.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        refresh.tap()

        XCTAssertTrue(
            element("state.stale-banner", in: app)
                .waitForExistence(timeout: 3)
        )
        let retry = element("state.retry", in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(retry)
        XCTAssertTrue(element("today.header.local-date", in: app).exists)
        retry.tap()
        XCTAssertTrue(
            element("state.stale-banner", in: app)
                .waitForExistence(timeout: 3),
            "Retry must publish the stale result after the new read completes"
        )
        let completedRetry = element("state.retry", in: app)
        XCTAssertTrue(
            completedRetry.waitForExistence(timeout: 3),
            "A new terminal stale state must be published after retry"
        )
        XCTAssertTrue(
            element("state.stale-banner", in: app)
                .waitForExistence(timeout: 3)
        )
        support.captureEvidence(named: "09-offline-error-retry.png", of: app)
    }

    @MainActor
    func testInitialOfflineAndErrorExposeReachableRetry() {
        let support = BodyFlowUITestSupport(testCase: self)

        for entry in [
            (Prompt13UITestScenario.offline, "Você está offline"),
            (Prompt13UITestScenario.error, "Não foi possível carregar"),
        ] {
            let app = support.launch(scenario: entry.0)
            XCTAssertTrue(
                app.staticTexts[entry.1].waitForExistence(timeout: 5)
            )
            let retry = element("state.retry", in: app)
            XCTAssertTrue(retry.waitForExistence(timeout: 3))
            support.assertMinimumTapTarget(retry)
            retry.tap()
            XCTAssertTrue(
                retry.waitForNonExistence(timeout: 3),
                "Retry must leave the terminal error while a new read runs"
            )
            XCTAssertTrue(
                app.staticTexts[entry.1].waitForExistence(timeout: 3)
            )
            app.terminate()
        }
    }

    @MainActor
    func testStaleErrorPreservesSnapshotAndReachableRetry() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .staleError)

        let refresh = app.buttons["today.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.tap()

        XCTAssertTrue(
            element("state.stale-banner", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(element("today.header.local-date", in: app).exists)
        let retry = element("state.retry", in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(retry)
        retry.tap()
        XCTAssertTrue(
            element("state.stale-banner", in: app)
                .waitForExistence(timeout: 3),
            "Retry must publish the stale result after the new read completes"
        )
        XCTAssertTrue(
            element("state.retry", in: app).waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            element("state.stale-banner", in: app)
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testTodayUnavailableHasNoRefreshOrRetry() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .unavailable)

        XCTAssertTrue(
            app.staticTexts["Indisponível nesta versão"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["today.refresh"].exists)
        XCTAssertFalse(element("state.retry", in: app).exists)
    }

    @MainActor
    func testTodayRefreshToolbarControlHasMinimumTapTarget() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)
        XCTAssertTrue(
            element("today.header.local-date", in: app)
                .waitForExistence(timeout: 10)
        )
        let refresh = app.buttons["today.refresh"]

        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(refresh)
    }

    @MainActor
    func testTodayStaleRetryControlHasMinimumTapTarget() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .staleError)
        let refresh = app.buttons["today.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        refresh.tap()

        let retry = element("state.retry", in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(retry)
    }

    @MainActor
    func testTodayInitialErrorRetryControlHasMinimumTapTarget() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .error)
        let retry = element("state.retry", in: app)

        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        support.assertMinimumTapTarget(retry)
    }

    @MainActor
    func testExpandedTodayDetailsRenderLocalizedStatusLabels() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)
        let details = element("today.energy.details", in: app)
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        for _ in 0..<3 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.isHittable)
        details.tap()

        let balance = app.staticTexts["Dia em andamento"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        let hydration = app.staticTexts["Registrado sem meta"]
        // The status line combines its accessibility children. Verify its
        // rendered copy rather than requiring its child text to accept a tap.
        XCTAssertTrue(hydration.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["provisional"].exists)
        XCTAssertFalse(app.staticTexts["tracked_without_target"].exists)
    }

    // Review 2026-10-04: the confirmed workouts showed the stored codes
    // "musculacao", "moderada" and "leve".
    @MainActor
    func testConfirmedWorkoutsShowNamesNotStoredCodes() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        let strength = element("today.workout.workout-z", in: app)
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        XCTAssertTrue(strength.label.contains("Musculação"), strength.label)
        XCTAssertTrue(strength.label.contains("40 min · Moderada"), strength.label)
        XCTAssertFalse(strength.label.contains("musculacao"), strength.label)
        XCTAssertFalse(strength.label.contains("moderada"), strength.label)

        let walk = element("today.workout.workout-a", in: app)
        XCTAssertTrue(walk.exists)
        XCTAssertTrue(walk.label.contains("Caminhada"), walk.label)
        XCTAssertTrue(walk.label.contains("25 min · Leve"), walk.label)
        XCTAssertFalse(walk.label.contains("caminhada"), walk.label)
        XCTAssertFalse(walk.label.contains("leve"), walk.label)
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
