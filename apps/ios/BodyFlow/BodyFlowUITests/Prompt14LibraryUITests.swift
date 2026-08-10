import XCTest

final class Prompt14LibraryUITests: XCTestCase {
    private let firstPublicationID =
        "10000000-0000-4000-8000-000000000001"
    private let sixthPublicationID =
        "10000000-0000-4000-8000-000000000006"
    private let incompletePublicationID =
        "10000000-0000-4000-8000-000000000007"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLibraryLoadsApprovedMarkdownDetail() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        support.openLibrary(in: app)
        support.openContentDetail(firstPublicationID, in: app)

        XCTAssertTrue(
            app.staticTexts["Nutrição Sintética Prompt 14"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["CONTEÚDO SINTÉTICO PROMPT 14"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Este texto é uma amostra inteiramente sintética, criada apenas para validar a leitura determinística no aplicativo BodyFlow."
            ].exists
        )
        XCTAssertFalse(app.staticTexts["## CONTEÚDO SINTÉTICO PROMPT 14"].exists)
        support.captureEvidence(.contentDetailMarkdown, of: app)
    }

    @MainActor
    func testLibraryAllCategoryAndOpaquePagination() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)

        support.openLibrary(in: app)
        XCTAssertTrue(
            support.element("library.card.\(firstPublicationID)", in: app)
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(.libraryAll, of: app)

        let category = support.element("library.category", in: app)
        XCTAssertTrue(category.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(category)
        category.tap()
        XCTAssertTrue(app.buttons["Nutrição"].waitForExistence(timeout: 3))
        app.buttons["Nutrição"].tap()
        XCTAssertTrue(
            app.staticTexts["2 conteúdos disponíveis"]
                .waitForExistence(timeout: 5)
        )

        category.tap()
        XCTAssertTrue(
            app.buttons["Todas as categorias"].waitForExistence(timeout: 3)
        )
        app.buttons["Todas as categorias"].tap()
        let loadMore = support.element("library.load-more", in: app)
        support.reveal(loadMore, in: app)
        XCTAssertTrue(loadMore.isHittable)
        support.assertMinimumTapTarget(loadMore)
        loadMore.tap()
        let lastCard = support.element(
            "library.card.\(sixthPublicationID)",
            in: app
        )
        support.reveal(lastCard, in: app)
        XCTAssertTrue(lastCard.waitForExistence(timeout: 5))
        XCTAssertFalse(support.element("library.load-more", in: app).exists)

        let navigationBar = app.navigationBars["Biblioteca"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        let titles = navigationBar.staticTexts.matching(
            NSPredicate(format: "label == %@", "Biblioteca")
        )
        XCTAssertEqual(titles.count, 1)
        let title = titles.element(boundBy: 0)
        XCTAssertFalse(title.label.isEmpty)
        XCTAssertFalse(title.frame.isEmpty)
        XCTAssertTrue(
            navigationBar.frame.contains(title.frame),
            "The Library title \(title.frame) must remain inside "
                + "the collapsed navigation bar \(navigationBar.frame)"
        )

        let backButton = navigationBar.buttons["BackButton"]
        XCTAssertTrue(backButton.exists)
        XCTAssertTrue(backButton.isEnabled)
        XCTAssertTrue(backButton.isHittable)
        support.assertMinimumTapTarget(backButton)
        XCTAssertTrue(navigationBar.frame.contains(backButton.frame))
        XCTAssertTrue(
            title.frame.intersection(backButton.frame).isNull,
            "The Library title \(title.frame) must not overlap "
                + "the back button \(backButton.frame)"
        )
        support.captureEvidence(.libraryCategoryPagination, of: app)
    }

    @MainActor
    func testLibraryNeutralEmptyStatesForAllSavedAndCategory() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .empty)

        support.openLibrary(in: app)
        XCTAssertTrue(
            app.staticTexts[
                "Nenhum conteúdo publicado está disponível para você agora."
            ].waitForExistence(timeout: 5)
        )

        let saved = support.element("library.selection.saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 3))
        saved.tap()
        XCTAssertTrue(
            app.staticTexts["Você ainda não tem conteúdos salvos disponíveis."]
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(.librarySavedEmpty, of: app)

        let category = support.element("library.category", in: app)
        category.tap()
        XCTAssertTrue(app.buttons["Sono"].waitForExistence(timeout: 3))
        app.buttons["Sono"].tap()
        XCTAssertTrue(
            app.staticTexts["Nenhum conteúdo disponível nesta categoria."]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testNextPageFailureRetriesTheSameOpaqueCursor() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .nextPageFailureOnce)

        support.openLibrary(in: app)
        let loadMore = support.element("library.load-more", in: app)
        support.reveal(loadMore, in: app)
        loadMore.tap()

        let retry = support.element("state.retry-next-page", in: app)
        support.reveal(retry, in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(retry)
        retry.tap()

        let recoveredCard = support.element(
            "library.card.\(sixthPublicationID)",
            in: app
        )
        support.reveal(recoveredCard, in: app)
        XCTAssertTrue(recoveredCard.waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        support.captureEvidence(.offlineErrorRetry, of: app)
    }

    @MainActor
    func testInvalidCursorRecoversFromCursorNilFirstPage() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .invalidCursorRecovery)

        support.openLibrary(in: app)
        let loadMore = support.element("library.load-more", in: app)
        support.reveal(loadMore, in: app)
        loadMore.tap()

        let reload = support.element("state.reload-first-page", in: app)
        support.reveal(reload, in: app)
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(reload)
        reload.tap()

        XCTAssertTrue(
            support.element("library.card.\(firstPublicationID)", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(reload.exists)
    }

    @MainActor
    func testIncompleteDetailSupportsSaveUnsaveAndCompletion() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .incompleteDetail)

        support.openLibrary(in: app)
        support.openContentDetail(incompletePublicationID, in: app)

        let save = support.element("content-detail.save", in: app)
        let complete = support.element("content-detail.complete", in: app)
        support.reveal(save, in: app)
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(complete.exists)
        support.assertMinimumTapTarget(save)
        support.assertMinimumTapTarget(complete)

        save.tap()
        XCTAssertTrue(
            app.staticTexts["Conteúdo salvo"].waitForExistence(timeout: 5)
        )
        XCTAssertEqual(save.label, "Remover dos salvos")

        save.tap()
        XCTAssertTrue(
            app.staticTexts["Conteúdo removido dos salvos"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(save.label, "Salvar")

        complete.tap()
        XCTAssertTrue(
            app.staticTexts["Conteúdo concluído"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(complete.exists)
        XCTAssertTrue(app.staticTexts["Concluído"].exists)
    }

    @MainActor
    func testRecoverableSaveFailureRetriesTheImmutableAttempt() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .mutationFailureOnce)

        support.openLibrary(in: app)
        support.openContentDetail(firstPublicationID, in: app)
        let save = support.element("content-detail.save", in: app)
        support.reveal(save, in: app)
        save.tap()

        let retry = support.element("content-detail.mutation.retry", in: app)
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Não foi possível atualizar. Tente novamente."]
                .exists
        )
        support.assertMinimumTapTarget(retry)
        retry.tap()

        XCTAssertTrue(
            app.staticTexts["Conteúdo removido dos salvos"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(retry.exists)
    }

    @MainActor
    func testConflictReloadReturnsToAuthorizedDetailStatus() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .conflict)

        support.openLibrary(in: app)
        support.openContentDetail(firstPublicationID, in: app)
        let save = support.element("content-detail.save", in: app)
        support.reveal(save, in: app)
        save.tap()

        XCTAssertTrue(
            app.staticTexts["Nutrição Sintética Prompt 14"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["Salvo"].waitForExistence(timeout: 8))
        XCTAssertTrue(save.isEnabled)
        support.captureEvidence(.conflictReload, of: app)
    }

    @MainActor
    func testMarkdownFailureNeverExposesRawBody() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .markdownInvalid)

        support.openLibrary(in: app)
        support.openContentDetail(firstPublicationID, in: app)
        XCTAssertTrue(
            support.element("state.error", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["# CONTEÚDO SINTÉTICO INVÁLIDO"].exists)
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "deliberadamente fora")
            ).firstMatch.exists
        )
    }

    @MainActor
    func testNotFoundAndSubscriptionStatesStayBounded() {
        let support = Prompt14UITestSupport(testCase: self)

        let notFound = support.launch(scenario: .contentNotFound)
        support.openLibrary(in: notFound)
        support.openContentDetail(firstPublicationID, in: notFound)
        XCTAssertTrue(
            notFound.staticTexts["Este conteúdo não está mais disponível"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(notFound.buttons["Voltar"].exists)
        XCTAssertTrue(notFound.buttons["Biblioteca"].exists)
        notFound.terminate()

        let subscription = support.launch(scenario: .subscriptionRequired)
        support.openLibrary(in: subscription)
        support.openContentDetail(firstPublicationID, in: subscription)
        XCTAssertTrue(
            subscription.staticTexts[
                "Conteúdo indisponível para sua assinatura atual"
            ].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(subscription.buttons["Voltar"].exists)
        XCTAssertFalse(subscription.buttons["Assinar"].exists)
        XCTAssertFalse(subscription.buttons["Comprar"].exists)
    }

    @MainActor
    func testCoverFailuresStayInsideTheArticleWithNeutralPlaceholder() {
        let support = Prompt14UITestSupport(testCase: self)
        let scenarios: [Prompt14UITestScenario] = [
            .coverInvalid,
            .coverExpired,
            .coverTooLarge,
            .coverMIMEMismatch,
            .coverAbusiveDimensions,
            .coverExternalPath,
        ]

        for (index, scenario) in scenarios.enumerated() {
            let app = support.launch(scenario: scenario)
            support.openLibrary(in: app)
            support.openContentDetail(firstPublicationID, in: app)
            XCTAssertTrue(
                app.staticTexts["Nutrição Sintética Prompt 14"]
                    .waitForExistence(timeout: 5),
                "Scenario \(scenario.rawValue) must keep the article usable"
            )
            XCTAssertFalse(app.alerts.firstMatch.exists)
            if index == scenarios.indices.last {
                support.captureEvidence(.coverFailurePlaceholder, of: app)
            }
            app.terminate()
        }
    }
}
