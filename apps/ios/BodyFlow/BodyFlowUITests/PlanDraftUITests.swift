import XCTest

/// Plan drafts over a synthetic imported draft: the patient completes what
/// is missing, saves, and only then confirms — with the notices that a draft
/// is not a plan and that the confirmation is not a professional review.
final class PlanDraftUITests: XCTestCase {
    private let rest = "plan.draft.field/weekly_schedule/0/exercises/1/rest_seconds"
    private let draftItem = "plan.drafts.item.0d0d0d0d-1111-4222-8333-444455556666"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReviewLocalizesFullBodyPlanType() {
        let app = launch(language: "pt-BR")
        app.buttons["tab.plano"].tap()
        let item = app.buttons[draftItem]
        XCTAssertTrue(item.waitForExistence(timeout: 8))
        item.tap()

        XCTAssertTrue(element("screen.plan.draft", app: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Corpo inteiro"].exists)
        XCTAssertFalse(app.staticTexts["full_body"].exists)
    }

    @MainActor
    func testTwentyDraftsKeepLastDraftImportAndPlanReachableAtAXXXL() {
        assertManyDraftsRemainReachable(scenario: "--ui-testing-prompt13-loaded", terminalID: "plan.detail")
    }

    @MainActor
    func testTwentyDraftsKeepImportAndEmptyStateReachableAtAXXXL() {
        assertManyDraftsRemainReachable(scenario: "--ui-testing-prompt13-empty", terminalID: "state.empty")
    }

    @MainActor
    func testTwentyDraftsKeepImportAndOfflineRecoveryReachableAtAXXXL() {
        assertManyDraftsRemainReachable(scenario: "--ui-testing-prompt13-offline", terminalID: "state.retry")
    }

    @MainActor
    func testNumericRestFieldDoneRestoresNavigationWithoutSavingOrConfirming() {
        let app = launch(language: "pt-BR")
        app.buttons["tab.plano"].tap()
        let item = app.buttons[draftItem]
        XCTAssertTrue(item.waitForExistence(timeout: 8))
        item.tap()
        let field = app.textFields[rest]
        reveal(field, app: app)
        field.tap()
        field.typeText("60")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let done = app.buttons["keyboard.done"]
        guard done.waitForExistence(timeout: 5) else {
            XCTFail("The numeric rest field must offer an accessible Done action")
            return
        }
        support.assertTarget(done)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.plano"].isHittable)
        XCTAssertEqual(field.value as? String, "60")
        XCTAssertFalse(element("plan.draft.confirmed", app: app).exists)
        XCTAssertFalse(app.buttons["plan.draft.confirm"].exists)
        reveal(app.buttons["plan.draft.save"], app: app)
        XCTAssertTrue(app.buttons["plan.draft.save"].isEnabled)
        support.capture("plan-rest-keyboard-dismissed-unsaved", app: app)
    }

    @MainActor
    func testTwentyDraftsKeepUnsavedRestAndReadingPositionAcrossAllTabs() {
        let app = launch(language: "pt-BR", manyDrafts: true)
        app.performeTabBar.buttons["tab.plano"].tap()
        let firstDraft = app.buttons[draftItem]
        XCTAssertTrue(firstDraft.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["plan.drafts.item.0d0d0d0d-1111-4222-8333-000000000020"].exists)
        firstDraft.tap()

        let field = app.textFields[rest]
        revealInLongList(field, app: app)
        field.tap()
        field.typeText("60")
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        support.assertTarget(done)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.performeTabBar.waitForExistence(timeout: 5))
        revealInLongList(field, app: app)
        XCTAssertEqual(field.value as? String, "60")
        let anchorBefore = field.frame
        support.capture("plan-unsaved-rest-before-tab-roundtrip", app: app)

        for (tab, screen) in [
            ("tab.perfil", "screen.perfil"),
            ("tab.progresso", "screen.progresso"),
            ("tab.registrar", "screen.registrar"),
            ("tab.hoje", "screen.hoje"),
        ] {
            app.performeTabBar.buttons[tab].tap()
            XCTAssertTrue(element(screen, app: app).waitForExistence(timeout: 5))
        }
        app.performeTabBar.buttons["tab.plano"].tap()
        XCTAssertTrue(element("screen.plan.draft", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable, "The same reading anchor must return without another scroll")
        XCTAssertEqual(field.value as? String, "60")
        XCTAssertEqual(field.frame.minY, anchorBefore.minY, accuracy: 2,
                       "Tab changes must preserve the unsaved form's reading position")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["plan.draft.save"].isEnabled)
        XCTAssertFalse(app.buttons["plan.draft.confirm"].exists)
        XCTAssertFalse(element("plan.draft.confirmed", app: app).exists)
        support.capture("plan-unsaved-rest-after-tab-roundtrip", app: app)
    }

    @MainActor
    private func assertManyDraftsRemainReachable(scenario: String, terminalID: String) {
        let app = launch(
            language: "pt-BR", scenario: scenario, manyDrafts: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        app.buttons["tab.plano"].tap()
        let last = app.buttons["plan.drafts.item.0d0d0d0d-1111-4222-8333-000000000020"]
        XCTAssertTrue(last.waitForExistence(timeout: 8))
        revealInLongList(last, app: app)
        support.assertTarget(last)
        revealInLongList(app.buttons["plan.import"], app: app)
        support.assertTarget(app.buttons["plan.import"])
        let terminal = terminalID == "state.empty"
            ? app.staticTexts["Nada por aqui"] : element(terminalID, app: app)
        revealInLongList(terminal, app: app)
        support.capture("plan-twenty-drafts-\(terminalID)-axxxl", app: app)
    }

    @MainActor
    private func revealInLongList(_ target: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0..<50 where !isReachable(target, app: app) {
            let window = visibleWindow(app)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let targetFrame = target.frame
            let movesDown = targetFrame.minY < window.top
            let neededDistance = movesDown
                ? window.top - targetFrame.minY + 20
                : targetFrame.maxY - window.bottom + 20
            let distance = min(max(neededDistance, 40), (window.bottom - window.top) * 0.6)
            let startY = movesDown ? window.top + 25 : window.bottom - 25
            let start = CGPoint(x: app.frame.midX, y: startY)
            let end = CGPoint(x: start.x, y: startY + (movesDown ? distance : -distance))
            origin.withOffset(CGVector(dx: start.x, dy: start.y)).press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)),
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
        }
        XCTAssertTrue(isReachable(target, app: app), "\(target.identifier) must scroll fully into the visible content area")
    }

    @MainActor
    func testImportedDraftIsCompletedSavedAndOnlyThenConfirmed() {
        let app = launch(language: "pt-BR")
        app.buttons["tab.plano"].tap()

        let item = app.buttons[draftItem]
        XCTAssertTrue(item.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Para revisar"].exists)
        support.assertTarget(item)
        // No document can be sent in this scenario: the import is not offered.
        XCTAssertFalse(app.buttons["plan.import"].exists)
        item.tap()

        XCTAssertTrue(element("screen.plan.draft", app: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[
            "Isto é um rascunho. Ele só vira o seu plano depois que você confirmar."
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[
            "A confirmação é sua. Este plano não foi revisado por um profissional."
        ].exists)
        XCTAssertTrue(app.staticTexts[
            "Ao confirmar, este plano substitui o seu plano de treino atual."
        ].exists)
        support.capture("plans-review-pt-light", app: app)

        let confirm = app.buttons["plan.draft.confirm"]
        reveal(confirm, app: app)
        XCTAssertFalse(confirm.isEnabled, "a draft with missing values cannot be confirmed")
        XCTAssertTrue(app.staticTexts[
            "Preencha ou remova o que está faltando para poder confirmar."
        ].exists)
        XCTAssertTrue(app.staticTexts[
            "Medicamentos, suplementos e doses não são importados. Converse com o seu profissional."
        ].exists)
        XCTAssertTrue(app.staticTexts["Tomar creatina 5 g após o treino."].exists)

        let field = app.textFields[rest]
        reveal(field, app: app, direction: .down)
        XCTAssertTrue(element(
            "plan.draft.uncertain/weekly_schedule/0/exercises/1/rest_seconds", app: app
        ).exists)
        field.tap()
        field.typeText("60")
        dismissKeyboard(app)

        // Something typed and not saved: saving comes before confirming.
        let save = app.buttons["plan.draft.save"]
        reveal(save, app: app)
        XCTAssertFalse(app.buttons["plan.draft.confirm"].exists)
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        reveal(confirm, app: app)
        XCTAssertTrue(confirm.isEnabled)
        support.assertTarget(confirm)
        confirm.tap()

        // The system presents the action twice in its hierarchy (container
        // and button); both are the same control.
        let accept = app.buttons["plan.draft.confirm.accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        XCTAssertEqual(accept.label, "Substituir e confirmar")
        XCTAssertTrue(app.staticTexts["Substituir o plano atual?"].exists)
        // Nothing is confirmed before the patient answers.
        XCTAssertFalse(element("plan.draft.confirmed", app: app).exists)
        accept.tap()

        XCTAssertTrue(element("plan.draft.confirmed", app: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[
            "Você confirmou este plano. Ele não foi revisado por um profissional."
        ].exists)
        XCTAssertFalse(app.buttons["plan.draft.confirm"].exists)
        XCTAssertFalse(app.buttons["plan.draft.discard"].exists)
        support.capture("plans-confirmed-pt-light", app: app)

        app.buttons["plan.draft.close"].tap()
        XCTAssertTrue(element("screen.plano", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[draftItem].waitForExistence(timeout: 2))
    }

    @MainActor
    func testDiscardAsksFirstAndThenEndsTheDraft() {
        let app = launch(language: "en-US", dark: true)
        app.buttons["tab.plano"].tap()
        let item = app.buttons[draftItem]
        XCTAssertTrue(item.waitForExistence(timeout: 8))
        item.tap()
        XCTAssertTrue(app.staticTexts[
            "The confirmation is yours. This plan was not reviewed by a professional."
        ].waitForExistence(timeout: 8))

        let discard = app.buttons["plan.draft.discard"]
        reveal(discard, app: app)
        support.assertTarget(discard)
        discard.tap()
        let accept = app.buttons["plan.draft.discard.accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        XCTAssertEqual(accept.label, "Discard")
        XCTAssertTrue(app.staticTexts["Discard this imported plan?"].exists)
        // Asking is not discarding: nothing happened yet.
        XCTAssertFalse(element("plan.draft.discarded", app: app).exists)
        accept.tap()
        XCTAssertTrue(element("plan.draft.discarded", app: app).waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["plan.draft.confirm"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testFlowProposalOpensTheReviewAndConfirmsNothingByItself() {
        let app = launch(language: "pt-BR")
        let flow = app.buttons["today.flow-chat"]
        XCTAssertTrue(flow.waitForExistence(timeout: 8))
        flow.tap()
        XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["flow.proposal.review"].exists)

        let composer = element("flow.composer", app: app)
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Quero um treino")
        guard waitForStableComposerKeyboard(composer, action: app.buttons["flow.send"], app: app,
                                           expectedComposer: "Quero um treino",
                                           diagnosticName: "plan-flow-proposal-before-send") else { return }
        app.buttons["flow.send"].tap()

        let review = app.buttons["flow.proposal.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        support.assertTarget(review)
        XCTAssertTrue(review.label.contains("Revisar sugestão"))
        XCTAssertTrue(review.label.contains("só vale depois que você confirmar"))
        review.tap()

        XCTAssertTrue(element("screen.plan.draft", app: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[
            "Isto é um rascunho. Ele só vira o seu plano depois que você confirmar."
        ].waitForExistence(timeout: 5))
        XCTAssertFalse(element("plan.draft.confirmed", app: app).exists)
    }

    @MainActor
    private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    @MainActor
    private func launch(
        language: String, dark: Bool = false,
        scenario: String = "--ui-testing-prompt13-loaded",
        manyDrafts: Bool = false,
        category: String = "UICTContentSizeCategoryL"
    ) -> XCUIApplication {
        let app = support.launch(
            arguments: [
                "--ui-testing", scenario, "--ui-testing-plan-drafts",
            ] + (manyDrafts ? ["--ui-testing-plan-drafts-many"] : []),
            language: language,
            dark: dark,
            category: category
        )
        XCTAssertTrue(app.buttons["tab.plano"].waitForExistence(timeout: 8))
        return app
    }

    private enum Direction { case up, down }

    @MainActor
    private func reveal(
        _ target: XCUIElement,
        app: XCUIApplication,
        direction: Direction = .up
    ) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        func step(_ direction: Direction) {
            let window = visibleWindow(app)
            let middle = (window.top + window.bottom) / 2
            let distance = min((window.bottom - window.top) / 3, 160)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: scroll.frame.midX, dy: middle)).press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(
                    dx: scroll.frame.midX,
                    dy: direction == .up ? middle - distance : middle + distance
                )),
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
        }
        for _ in 0..<30 where !isReachable(target, app: app) { step(direction) }
        for _ in 0..<60 where !isReachable(target, app: app) {
            step(direction == .up ? .down : .up)
        }
        XCTAssertTrue(isReachable(target, app: app), "\(target) is not reachable")
    }

    @MainActor
    private func visibleWindow(_ app: XCUIApplication) -> (top: CGFloat, bottom: CGFloat) {
        let bars = app.navigationBars
        let header = bars.element(boundBy: max(bars.count - 1, 0))
        let top = header.exists ? header.frame.maxY : 0
        let keyboard = app.keyboards.firstMatch
        let tabBar = app.performeTabBar
        var bottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        if keyboard.exists, keyboard.frame.height > 0,
           keyboard.frame.minY > top, keyboard.frame.minY < bottom {
            bottom = keyboard.frame.minY
        }
        return (top, bottom)
    }

    @MainActor
    private func isReachable(_ target: XCUIElement, app: XCUIApplication) -> Bool {
        guard target.exists, target.isHittable else { return false }
        let window = visibleWindow(app)
        return target.frame.minY >= window.top && target.frame.maxY <= window.bottom
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let header = app.navigationBars.firstMatch
        if header.exists {
            header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    @MainActor
    private func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        support.element(id, app: app)
    }
}
