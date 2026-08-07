import XCTest

final class Prompt14TodayMascotUITests: XCTestCase {
    private let firstPublicationID =
        "10000000-0000-4000-8000-000000000001"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayRecommendationsLoadedInServerOrder() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        XCTAssertTrue(
            support.element("today.header.updated-at", in: app)
                .waitForExistence(timeout: 5)
        )
        let section = support.element("today.recommendations", in: app)
        support.reveal(section, in: app, attempts: 16)
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        let first = support.element(
            "today.recommendations.card.\(firstPublicationID)",
            in: app
        )
        XCTAssertTrue(first.exists)
        XCTAssertTrue(
            support.element("today.recommendations.library", in: app).exists
        )
        support.captureEvidence(.todayRecommendations, of: app)
    }

    @MainActor
    func testTodayRecommendationsEmptyKeepsLibraryActionAndOfficialToday() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .empty)

        XCTAssertTrue(
            support.element("today.header.updated-at", in: app)
                .waitForExistence(timeout: 5)
        )
        let section = support.element("today.recommendations", in: app)
        support.reveal(section, in: app, attempts: 16)
        XCTAssertTrue(
            app.staticTexts["Nenhum conteúdo selecionado para hoje"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            support.element("today.recommendations.library", in: app).exists
        )
    }

    @MainActor
    func testTodayRecommendationsOfflineAndErrorKeepOfficialToday() {
        let support = Prompt14UITestSupport(testCase: self)

        for scenario in [Prompt14UITestScenario.offline, .error] {
            let app = support.launch(scenario: scenario)
            XCTAssertTrue(
                support.element("today.header.updated-at", in: app)
                    .waitForExistence(timeout: 5)
            )
            let retry = support.element("today.recommendations.retry", in: app)
            support.reveal(retry, in: app, attempts: 16)
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(retry)
            retry.tap()
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            XCTAssertTrue(support.element("screen.hoje", in: app).exists)
            app.terminate()
        }
    }

    @MainActor
    func testTodayRecommendationsStaleAfterContentInvalidation() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .todayRecommendationsStale)

        let card = support.element(
            "today.recommendations.card.\(firstPublicationID)",
            in: app
        )
        support.reveal(card, in: app, attempts: 16)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(
            support.element(
                "screen.content-detail.\(firstPublicationID)",
                in: app
            ).waitForExistence(timeout: 5)
        )
        let save = support.element("content-detail.save", in: app)
        support.reveal(save, in: app)
        save.tap()
        XCTAssertTrue(
            support.element("content-detail.mutation.summary", in: app)
                .waitForExistence(timeout: 5)
        )
        app.navigationBars["Conteúdo"].buttons.element(boundBy: 0).tap()

        let stale = support.element("state.stale-banner", in: app)
        support.reveal(stale, in: app, attempts: 16)
        XCTAssertTrue(stale.waitForExistence(timeout: 8))
        XCTAssertTrue(
            support.element("today.recommendations.retry", in: app).exists
        )
        XCTAssertTrue(support.element("screen.hoje", in: app).exists)
    }

    @MainActor
    func testTodayUnavailableIsSectionBounded() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .unavailable)

        XCTAssertTrue(
            support.element("today.header.updated-at", in: app)
                .waitForExistence(timeout: 5)
        )
        let unavailable = support.element(
            "today.recommendations.unavailable",
            in: app
        )
        support.reveal(unavailable, in: app, attempts: 16)
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(
            support.element("today.recommendations.library", in: app).exists
        )
        support.captureEvidence(.unavailable, of: app)
    }

    @MainActor
    func testOpenedFailureLeavesAuthorizedArticleUsable() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .openedError)

        support.openLibrary(in: app)
        support.openContentDetail(firstPublicationID, in: app)
        XCTAssertTrue(
            app.staticTexts["Nutrição Sintética Prompt 14"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Não foi possível atualizar. Tente novamente."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            support.element("content-detail.mutation.retry", in: app).exists
        )
        XCTAssertTrue(support.element("content-detail.save", in: app).isEnabled)
        support.captureEvidence(.openedErrorNonblocking, of: app)
    }

    @MainActor
    func testFocusActiveMascotUsesTypedDetailReload() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .mascotFocusActive)

        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertTrue(mascot.label.contains("personalidade Foco"))
        XCTAssertTrue(mascot.label.contains("estado Ativo"))
        support.captureEvidence(.mascotFocusActive, of: app)
        mascot.tap()
        XCTAssertTrue(
            support.element("screen.mascot.detail", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "personalidade Foco")
            ).firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testZenNeglectedMascotUsesNonShamingState() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .mascotZenNeglected)

        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertTrue(mascot.label.contains("personalidade Zen"))
        XCTAssertTrue(mascot.label.contains("estado Em pausa"))
        XCTAssertFalse(mascot.label.localizedCaseInsensitiveContains("negligente"))
        support.captureEvidence(.mascotZenNeglected, of: app)
    }

    @MainActor
    func testMascotVariantsCoverAllStatesAndNeutralFallbacks() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .mascotVariants)

        let mascot = support.element("today.mascot", in: app)
        support.reveal(mascot, in: app)
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertTrue(mascot.label.contains("personalidade Equilibrada"))
        XCTAssertTrue(mascot.label.contains("estado Em repouso"))
        mascot.tap()

        let screen = support.element("screen.mascot.detail", in: app)
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        XCTAssertTrue(
            support.waitForLabel(containing: "Retomando com você", in: app)
        )

        let refresh = support.element("mascot.refresh", in: app)
        support.assertMinimumTapTarget(refresh)
        refresh.tap()
        XCTAssertTrue(support.waitForLabel(containing: "estado Ativo", in: app))

        refresh.tap()
        XCTAssertTrue(
            support.waitForLabel(
                containing: "Estado do mascote em atualização",
                in: app
            )
        )
        support.captureEvidence(.mascotEvolvingNeutral, of: app)

        refresh.tap()
        XCTAssertTrue(support.waitForLabel(containing: "estado Em pausa", in: app))

        refresh.tap()
        XCTAssertTrue(
            support.waitForLabel(
                containing: "Estado do mascote em atualização",
                in: app
            )
        )
    }
}
