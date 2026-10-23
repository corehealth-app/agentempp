import XCTest

/// The meal capture of a real account, over synthetic candidates: text is
/// read, the patient reviews, and only then a proposal exists.
final class MealCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayBreakfastSlotKeepsItsSelectionWhenTheFoodsAreRead() {
        let app = support.launch(arguments: [
            "--ui-testing", "--ui-testing-prompt13-loaded", "--ui-testing-meal-capture",
            "--ui-testing-meal-capture-empty-breakfast",
        ], language: "pt-BR", dark: false, category: "UICTContentSizeCategoryL")
        let breakfast = app.buttons["today.meal-slot.cafe.register"]
        XCTAssertTrue(breakfast.waitForExistence(timeout: 5))
        // This is Today, before a sheet exists: the sheet-only reveal helper
        // correctly requires its close button and cannot be used here.
        for _ in 0..<8 {
            if breakfast.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(breakfast.isHittable)
        breakfast.tap()
        XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 ovos mexidos e granola")
        XCTAssertEqual(field.value as? String, "2 ovos mexidos e granola")
        tapDetectInVisibleSheet(app.buttons["registration.meal.detect"], app: app)
        let mealType = element("registration.review.meal-type", app: app)
        XCTAssertTrue(mealType.waitForExistence(timeout: 8))
        XCTAssertTrue((mealType.label + " " + (mealType.value as? String ?? "")).contains("Café da manhã"),
            "The Today selection must reach the review without selecting it again")
        XCTAssertFalse(element("registration.proposal", app: app).exists)
        support.capture("roberto-breakfast-slot-review", app: app)
    }

    @MainActor
    func testWrittenMealIsReviewedBeforeAnyProposal() {
        let app = launchCapture(language: "pt-BR")

        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        XCTAssertEqual(write.label, "Escrever")
        support.assertTarget(write)
        // No local sample is offered where the capture is the real one.
        XCTAssertFalse(app.buttons["registration.meal.source.photo"].exists)
        XCTAssertFalse(app.buttons["registration.meal.source.audio"].exists)
        XCTAssertFalse(app.staticTexts["Demonstração local; sem permissão de mídia ou upload."].exists)
        write.tap()

        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, field.placeholderValue)
        let read = app.buttons["registration.meal.detect"]
        XCTAssertFalse(read.isEnabled)
        field.tap()
        field.typeText("2 ovos mexidos e granola")
        XCTAssertEqual(field.value as? String, "2 ovos mexidos e granola")
        XCTAssertTrue(read.isEnabled)
        tapDetectWithVisibleKeyboard(read, app: app)

        let eggs = app.textFields["registration.review.item.c1-0a1b2c3d.name"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 8))
        XCTAssertEqual(eggs.value as? String, "ovos mexidos")
        XCTAssertFalse(element("registration.proposal", app: app).exists)
        XCTAssertTrue(app.staticTexts["Revise os alimentos"].exists)
        support.capture("c1-review-pt-light", app: app)

        let submit = app.buttons["registration.review.submit"]
        reveal(submit, app: app)
        XCTAssertFalse(submit.isEnabled)

        let confirmEggs = app.switches["registration.review.item.c1-0a1b2c3d.confirm"]
        reveal(confirmEggs, app: app, direction: .down)
        support.assertTarget(confirmEggs)
        turnOn(confirmEggs)
        reveal(submit, app: app)
        XCTAssertFalse(submit.isEnabled, "granola still has no quantity")

        let granola = app.textFields["registration.review.item.c2-1b2c3d4e.quantity"]
        reveal(granola, app: app, direction: .down)
        XCTAssertFalse(app.switches["registration.review.item.c2-1b2c3d4e.confirm"].exists)
        granola.tap()
        granola.typeText("30")
        finishNumericEntry(app, expectedLabel: "Concluído")
        XCTAssertEqual(granola.value as? String, "30")
        XCTAssertFalse(element("registration.proposal", app: app).exists)

        reveal(submit, app: app)
        XCTAssertTrue(submit.isEnabled)
        support.assertTarget(submit)
        submit.tap()

        XCTAssertTrue(element("registration.proposal", app: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["registration.proposal.confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("registration.proposal.confirmed", app: app).exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testUnrecognizedTextSaysSoAndStartsOver() {
        let app = launchCapture(language: "pt-BR")
        app.buttons["registration.meal.source.text"].tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("xyz")
        XCTAssertEqual(field.value as? String, "xyz")
        let read = app.buttons["registration.meal.detect"]
        XCTAssertTrue(read.isEnabled)
        tapDetectWithVisibleKeyboard(read, app: app)

        let failure = element("registration.meal.capture.failure", app: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[
            "Nenhum alimento foi identificado. Tente descrever de outra forma."
        ].exists)
        XCTAssertFalse(app.buttons["registration.meal.capture.retry"].exists)
        XCTAssertFalse(element("registration.proposal", app: app).exists)

        let startOver = app.buttons["registration.meal.capture.start-over"]
        XCTAssertTrue(startOver.exists)
        support.assertTarget(startOver)
        startOver.tap()
        XCTAssertTrue(app.buttons["registration.meal.source.text"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewAtAccessibilitySizeKeepsTargetsInEnglish() {
        let app = launchCapture(
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        XCTAssertEqual(write.label, "Write")
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 eggs")
        dismissKeyboard(app)
        let read = app.buttons["registration.meal.detect"]
        reveal(read, app: app)
        read.tap()

        let eggs = app.textFields["registration.review.item.c1-0a1b2c3d.name"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Review the foods"].exists)
        let confirm = app.switches["registration.review.item.c1-0a1b2c3d.confirm"]
        reveal(confirm, app: app)
        support.assertTarget(confirm)
        let remove = app.buttons["registration.review.item.c2-1b2c3d4e.remove"]
        reveal(remove, app: app)
        support.assertTarget(remove)
        support.capture("c1-review-en-dark-axxxl", app: app)
        remove.tap()
        XCTAssertFalse(app.textFields["registration.review.item.c2-1b2c3d4e.name"].exists)
    }

    @MainActor
    func testQuantityDonePreservesInputAndCreatesNoProposalInEnglishAtAXXXL() {
        let app = launchCapture(
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        app.buttons["registration.meal.source.text"].tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 eggs")
        dismissKeyboard(app)
        let read = app.buttons["registration.meal.detect"]
        reveal(read, app: app)
        read.tap()

        let granola = app.textFields["registration.review.item.c2-1b2c3d4e.quantity"]
        XCTAssertTrue(granola.waitForExistence(timeout: 8))
        reveal(granola, app: app)
        granola.tap()
        granola.typeText("30")
        XCTAssertTrue(app.buttons["keyboard.done"].waitForExistence(timeout: 3))
        support.capture("c1-quantity-keyboard-en-dark-axxxl", app: app)
        finishNumericEntry(app, expectedLabel: "Done")
        XCTAssertEqual(granola.value as? String, "30")
        XCTAssertFalse(element("registration.proposal", app: app).exists)
        let submit = app.buttons["registration.review.submit"]
        reveal(submit, app: app)
        XCTAssertFalse(submit.isEnabled, "Closing the keyboard does not confirm the eggs")
    }

    // MARK: Second update (2026-10-10) — a failed calculation shows its error
    //
    // Found in the review of the first update: when "Calcular refeição"
    // fails, the review comes back from the top and the error line with
    // "Tentar novamente" is below it, off the screen. The failure is the one
    // the demonstration already had (the first mutation fails once).

    @MainActor
    func testFailedCalculationShowsItsErrorAndRetryWithoutScrolling() {
        let app = launchCapture(
            language: "pt-BR",
            scenario: "--ui-testing-prompt13-registration-error-once"
        )
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 ovos mexidos e granola")
        XCTAssertEqual(field.value as? String, "2 ovos mexidos e granola")
        tapDetectWithVisibleKeyboard(app.buttons["registration.meal.detect"], app: app)
        XCTAssertTrue(app.textFields["registration.review.item.c1-0a1b2c3d.name"].waitForExistence(timeout: 8))
        let submit = app.buttons["registration.review.submit"]
        reveal(submit, app: app)
        let confirmEggs = app.switches["registration.review.item.c1-0a1b2c3d.confirm"]
        reveal(confirmEggs, app: app, direction: .down)
        turnOn(confirmEggs)
        let granola = app.textFields["registration.review.item.c2-1b2c3d4e.quantity"]
        reveal(granola, app: app, direction: .down)
        granola.tap()
        granola.typeText("30")
        finishNumericEntry(app, expectedLabel: "Concluído")
        reveal(submit, app: app)
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        assertFailedCalculationIsInReach(app, message: "Não foi possível concluir. Tente novamente.")
        support.capture("u1b-failed-calculation-pt-light", app: app)
        app.buttons["registration.mutation.retry"].tap()
        XCTAssertTrue(element("registration.proposal", app: app).waitForExistence(timeout: 8))
    }

    @MainActor
    func testFailedCalculationShowsItsErrorAndRetryWithoutScrollingInEnglishAtAXXXL() {
        let app = launchCapture(
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL",
            scenario: "--ui-testing-prompt13-registration-error-once"
        )
        app.buttons["registration.meal.source.text"].tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 eggs")
        dismissKeyboard(app)
        let read = app.buttons["registration.meal.detect"]
        reveal(read, app: app)
        read.tap()
        let confirmEggs = app.switches["registration.review.item.c1-0a1b2c3d.confirm"]
        XCTAssertTrue(confirmEggs.waitForExistence(timeout: 8))
        reveal(confirmEggs, app: app)
        turnOn(confirmEggs)
        let granola = app.textFields["registration.review.item.c2-1b2c3d4e.quantity"]
        reveal(granola, app: app)
        granola.tap()
        granola.typeText("30")
        finishNumericEntry(app, expectedLabel: "Done")
        let submit = app.buttons["registration.review.submit"]
        reveal(submit, app: app)
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        assertFailedCalculationIsInReach(app, message: "Could not complete. Try again.")
        support.capture("u1b-failed-calculation-en-dark-axxxl", app: app)
        app.buttons["registration.mutation.retry"].tap()
        XCTAssertTrue(element("registration.proposal", app: app).waitForExistence(timeout: 8))
    }

    /// After the touch on "Calcular refeição", WITHOUT a swipe: the error
    /// line and its "Tentar novamente" are on screen, below the sheet's bar,
    /// and can be touched; no proposal exists.
    @MainActor
    private func assertFailedCalculationIsInReach(
        _ app: XCUIApplication,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let retry = app.buttons["registration.mutation.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8), "The calculation must fail once", file: file, line: line)
        let inReach = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: retry
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [inReach], timeout: 5), .completed,
            "Tentar novamente must be in reach without scrolling: \(retry.frame)",
            file: file, line: line
        )
        let window = visibleWindow(app)
        XCTAssertGreaterThanOrEqual(retry.frame.minY, window.top, file: file, line: line)
        XCTAssertLessThanOrEqual(retry.frame.maxY, window.bottom, file: file, line: line)
        XCTAssertTrue(app.frame.contains(retry.frame), "\(retry.frame)", file: file, line: line)
        support.assertTarget(retry)
        // The status line shows its text as one element inside another.
        let text = app.staticTexts[message].firstMatch
        XCTAssertTrue(text.exists, file: file, line: line)
        XCTAssertTrue(text.isHittable, "The error line must be on screen: \(text.frame)", file: file, line: line)
        // The review came back with what it had; nothing was proposed.
        XCTAssertTrue(app.buttons["registration.review.submit"].exists, file: file, line: line)
        XCTAssertFalse(element("registration.proposal", app: app).exists, file: file, line: line)
    }

    // MARK: First update (2026-10-10) — the ways of the meal card open directly
    //
    // Asked for by the owner on build 1.0 (3), real account: choosing Foto,
    // Texto or Áudio opened a sheet that asked the same question again.

    @MainActor
    func testTextWayOpensTheFieldWithTheKeyboardAndReachesTheReview() {
        let app = launchRegister(language: "pt-BR")
        let way = app.buttons["register.refeicao.texto"]
        XCTAssertTrue(way.waitForExistence(timeout: 5), "Texto must be a real button on the meal card")
        XCTAssertEqual(way.label, "Texto")
        support.assertTarget(way)
        way.tap()
        XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))

        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForKeyboardFocus(field), "The field takes the keyboard without a touch")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Como deseja adicionar a refeição?"].exists)
        XCTAssertFalse(app.buttons["registration.meal.source.text"].exists)

        // Typed without touching the field.
        field.typeText("2 ovos mexidos e granola")
        XCTAssertEqual(field.value as? String, "2 ovos mexidos e granola")
        let read = app.buttons["registration.meal.detect"]
        XCTAssertTrue(read.isEnabled)
        tapDetectWithVisibleKeyboard(read, app: app)

        let eggs = app.textFields["registration.review.item.c1-0a1b2c3d.name"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Revise os alimentos"].exists)
        XCTAssertFalse(element("registration.proposal", app: app).exists)
        support.capture("u1-text-way-review-pt-light", app: app)
    }

    @MainActor
    func testPhotoAndAudioWaysOpenTheirOwnStepAtOnce() {
        let app = launchRegister(language: "pt-BR", extraArguments: ["--ui-testing-meal-capture-media"])

        let audio = app.buttons["register.refeicao.audio"]
        XCTAssertTrue(audio.waitForExistence(timeout: 5), "Áudio must be a real button on the meal card")
        XCTAssertEqual(audio.label, "Áudio")
        audio.tap()
        XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))
        let start = app.buttons["registration.meal.record.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(start.label, "Começar gravação")
        XCTAssertTrue(element("registration.meal.record.elapsed", app: app).exists)
        XCTAssertFalse(app.staticTexts["Como deseja adicionar a refeição?"].exists)
        XCTAssertFalse(app.buttons["registration.meal.source.record"].exists)
        // Nothing records and nothing is asked before "Começar gravação".
        XCTAssertEqual(app.alerts.count, 0)
        support.capture("u1-audio-way-recorder-pt-light", app: app)

        // "Voltar" leads to the full choice, where "Importar áudio" lives.
        let back = app.buttons["registration.meal.source.back"]
        reveal(back, app: app)
        back.tap()
        XCTAssertTrue(app.buttons["registration.meal.source.text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["registration.meal.source.audio-import"].exists)
        app.buttons["sheet.fechar"].tap()

        let photo = app.buttons["register.refeicao.foto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.label, "Foto")
        photo.tap()
        let step = element("registration.meal.photo-step", app: app)
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(step.label, "Foto da refeição")
        let choose = app.buttons["registration.meal.source.gallery"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertEqual(choose.label, "Escolher foto")
        XCTAssertTrue(choose.isHittable)
        support.assertTarget(choose)
        XCTAssertFalse(app.staticTexts["Como deseja adicionar a refeição?"].exists)
        for absent in ["text", "record", "audio-import"] {
            XCTAssertFalse(app.buttons["registration.meal.source.\(absent)"].exists, absent)
        }
        XCTAssertEqual(app.alerts.count, 0)
        support.capture("u1-photo-way-step-pt-light", app: app)
    }

    // MARK: Second update (2026-10-10) — Foto opens the camera by itself
    //
    // The owner, on build 1.0 (3): "ao inves dele abrir direto, ele abre uma
    // tela q pergunta novamente sobre isso" (RC U1-A1). The camera here is
    // the Debug stand-in: the system's camera and its permission prompt are
    // never raised by a test (RC U1B-F1).

    @MainActor
    func testPhotoWayOpensTheCameraByItselfAndCancelLeavesTheStep() {
        let app = launchRegister(language: "pt-BR", extraArguments: [
            "--ui-testing-meal-capture-media", "--ui-testing-meal-capture-camera",
        ])
        let photo = app.buttons["register.refeicao.foto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()

        // No second touch: the camera is there, and it is the first time.
        let camera = element("registration.meal.camera", app: app)
        XCTAssertTrue(
            camera.waitForExistence(timeout: 8),
            "Foto must open the camera by itself, without a second touch"
        )
        XCTAssertEqual(app.staticTexts["registration.meal.camera.presentation"].label, "1")
        XCTAssertEqual(app.alerts.count, 0)
        support.capture("u1b-photo-way-camera-pt-light", app: app)

        // Cancel: the step is underneath, and nothing opens again by itself.
        app.buttons["registration.meal.camera.cancel"].tap()
        let step = element("registration.meal.photo-step", app: app)
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(step.label, "Foto da refeição")
        let take = app.buttons["registration.meal.source.camera"]
        let choose = app.buttons["registration.meal.source.gallery"]
        XCTAssertTrue(take.waitForExistence(timeout: 5))
        XCTAssertEqual(take.label, "Tirar foto")
        XCTAssertEqual(choose.label, "Escolher foto")
        XCTAssertTrue(take.isHittable)
        XCTAssertTrue(choose.isHittable)
        support.assertTarget(take)
        support.assertTarget(choose)
        XCTAssertFalse(camera.waitForExistence(timeout: 2), "The camera never opens again by itself")
        XCTAssertFalse(app.staticTexts["Permissão negada. Autorize o acesso nos Ajustes do iPhone."].exists)

        // "Tirar foto" still opens it by touch: the second time.
        take.tap()
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["registration.meal.camera.presentation"].label, "2")

        // The photo taken reaches the upload: what is refused is the SEND
        // (the synthetic capture sends nothing), never the file.
        app.buttons["registration.meal.camera.take"].tap()
        let failure = element("registration.meal.capture.failure", app: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["Este tipo de captura não está disponível agora."].exists,
            "The photo must reach the upload: \(failure.label)"
        )
        XCTAssertFalse(app.staticTexts["Não foi possível abrir o arquivo."].exists)
        XCTAssertFalse(camera.exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    /// Along the whole sheet the camera does not come back by itself: not
    /// after cancelling it, not after "Voltar", not after a meal read from
    /// text, not after a proposal that is cancelled.
    ///
    /// This is NOT the proof of the sheet's "once" mark: with the mark
    /// switched off (`alreadyOpened: false`, review run
    /// u1b-rev1-06-mutation2-run) this test still passed — nothing along
    /// this path builds the capture view again on its photo step, so the
    /// decision is never taken a second time. The mark is locked by the
    /// hosted `testPhotoEntryAsksForTheCameraOnceAfterTheSheetSettles`,
    /// which builds a second view over the same sheet's record and failed
    /// under that mutation (RC U1B-F5).
    @MainActor
    func testCameraIsNeverReopenedAlongTheSheet() {
        let app = launchRegister(language: "pt-BR", extraArguments: [
            "--ui-testing-meal-capture-media", "--ui-testing-meal-capture-camera",
        ])
        let photo = app.buttons["register.refeicao.foto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.tap()
        let camera = element("registration.meal.camera", app: app)
        XCTAssertTrue(
            camera.waitForExistence(timeout: 8),
            "Foto must open the camera by itself, without a second touch"
        )
        XCTAssertEqual(app.staticTexts["registration.meal.camera.presentation"].label, "1")
        app.buttons["registration.meal.camera.cancel"].tap()
        XCTAssertTrue(element("registration.meal.photo-step", app: app).waitForExistence(timeout: 5))

        // "Voltar": the full choice.
        let back = app.buttons["registration.meal.source.back"]
        reveal(back, app: app)
        back.tap()
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        XCTAssertFalse(camera.exists, "After Voltar")
        // From here on, the same steps as the written meal of this file.
        reveal(write, app: app, direction: .down)
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 ovos mexidos e granola")
        XCTAssertEqual(field.value as? String, "2 ovos mexidos e granola")
        tapDetectWithVisibleKeyboard(app.buttons["registration.meal.detect"], app: app)
        XCTAssertTrue(app.textFields["registration.review.item.c1-0a1b2c3d.name"].waitForExistence(timeout: 8))
        XCTAssertFalse(camera.exists, "With the review on screen")
        let submit = app.buttons["registration.review.submit"]
        reveal(submit, app: app)
        let confirmEggs = app.switches["registration.review.item.c1-0a1b2c3d.confirm"]
        reveal(confirmEggs, app: app, direction: .down)
        turnOn(confirmEggs)
        let granola = app.textFields["registration.review.item.c2-1b2c3d4e.quantity"]
        reveal(granola, app: app, direction: .down)
        granola.tap()
        granola.typeText("30")
        finishNumericEntry(app, expectedLabel: "Concluído")
        reveal(submit, app: app)
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(element("registration.proposal", app: app).waitForExistence(timeout: 8))
        XCTAssertFalse(camera.exists, "With the proposal on screen")

        // The proposal is cancelled: whatever comes back, the camera does
        // not.
        let cancel = app.buttons["registration.proposal.cancel"]
        reveal(cancel, app: app)
        cancel.tap()
        XCTAssertTrue(element("registration.proposal", app: app).waitForNonExistence(timeout: 8))
        XCTAssertFalse(camera.waitForExistence(timeout: 2), "After a cancelled proposal")
        let cameBack = [
            "registration.review.submit", "registration.meal.photo-step",
            "registration.meal.source.text", "registration.meal.text",
        ].filter { element($0, app: app).exists }
        let record = XCTAttachment(string: "On screen after the cancelled proposal: \(cameBack)")
        record.name = "u1b-after-cancelled-proposal"
        record.lifetime = .keepAlways
        add(record)
        XCTAssertFalse(cameBack.contains("registration.meal.photo-step") && camera.exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testWaysWithoutMediaFallBackToTheChoiceThatSaysSo() {
        let app = launchRegister(language: "pt-BR")
        for way in ["foto", "audio"] {
            let button = app.buttons["register.refeicao.\(way)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(way) must be a real button on the meal card")
            button.tap()
            XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["registration.meal.source.text"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Foto e áudio ainda não estão disponíveis nesta versão."].exists)
            XCTAssertFalse(element("registration.meal.photo-step", app: app).exists)
            XCTAssertFalse(app.buttons["registration.meal.record.start"].exists)
            app.buttons["sheet.fechar"].tap()
        }
    }

    /// Lock: the card's own action — the path every other registration test
    /// takes — still opens the full choice.
    @MainActor
    func testMealCardTitleStillOpensTheFullChoice() {
        let app = launchRegister(language: "pt-BR")
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        XCTAssertEqual(meal.label, "Refeição")
        support.assertTarget(meal)
        meal.tap()
        XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["registration.meal.source.text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Como deseja adicionar a refeição?"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    /// The touch areas tile the card: a finger beside a way, or between two
    /// of them, still opens a capture.
    @MainActor
    func testTouchesBesideAndBetweenTheWaysStillOpenACapture() {
        let app = launchRegister(language: "pt-BR")
        let photo = app.buttons["register.refeicao.foto"]
        let text = app.buttons["register.refeicao.texto"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "Foto must be a real button on the meal card")
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        let sheet = element("sheet.registrar.refeicao", app: app)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let y = photo.frame.midY
        // Left of the first way, and on each side of the line between two.
        for x in [photo.frame.minX + 3, photo.frame.maxX - 2, text.frame.minX + 2] {
            origin.withOffset(CGVector(dx: x, dy: y)).tap()
            XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Dead point at x=\(x) y=\(y)")
            app.buttons["sheet.fechar"].tap()
            XCTAssertTrue(photo.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(photo.frame.maxX, text.frame.minX, accuracy: 0.5)
    }

    @MainActor
    func testWaysKeepTheirTargetsInEnglishAtAXXXL() {
        let app = launchRegister(
            language: "en-US", dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        for (way, label) in [("foto", "Photo"), ("texto", "Text"), ("audio", "Audio")] {
            let button = app.buttons["register.refeicao.\(way)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(label) must be a real button at the largest text size")
            XCTAssertEqual(button.label, label)
            for _ in 0..<12 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable, label)
            support.assertTarget(button)
        }
        support.capture("u1-meal-card-en-dark-axxxl", app: app)
        let text = app.buttons["register.refeicao.texto"]
        for _ in 0..<12 where !text.isHittable { app.swipeDown() }
        text.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForKeyboardFocus(field))
        XCTAssertFalse(app.buttons["registration.meal.source.text"].exists)
    }

    /// The same step reached through the full choice ("Escrever") raises the
    /// keyboard too: one touch less on the path every other entry takes.
    @MainActor
    func testWriteInsideTheChoiceRaisesTheKeyboardAtOnce() {
        let app = launchCapture(language: "pt-BR")
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForKeyboardFocus(field), "The field takes the keyboard without a touch")
        field.typeText("2 ovos mexidos e granola")
        XCTAssertEqual(field.value as? String, "2 ovos mexidos e granola")
        tapDetectWithVisibleKeyboard(app.buttons["registration.meal.detect"], app: app)
        XCTAssertTrue(app.textFields["registration.review.item.c1-0a1b2c3d.name"].waitForExistence(timeout: 8))
    }

    // MARK: First update (2026-10-10) — one structured loading for the analysis
    //
    // Asked for by the owner: "quando está processando, aparecem vários
    // loading, o ideal seria manter somente 1 e melhor estruturado".

    @MainActor
    func testAnalysisShowsOneStructuredLoadingAndCancelReturnsToTheChoice() {
        let app = launchCapture(language: "pt-BR", extraArguments: ["--ui-testing-meal-capture-hold"])
        reachHeldAnalysis(app, text: "2 ovos mexidos e granola")

        let progress = element("registration.meal.capture.progress", app: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        XCTAssertEqual(progress.label, "Analisando sua refeição")
        XCTAssertEqual(progress.value as? String, "Lendo os alimentos…")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "registration.meal.capture.progress").count, 1
        )
        let cancel = app.buttons["registration.meal.capture.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertEqual(cancel.label, "Cancelar")
        XCTAssertTrue(cancel.isHittable)
        support.assertTarget(cancel)
        // The brand mark still says the state; it only stops drawing a second
        // indicator.
        XCTAssertEqual(element("registration.brand", app: app).label, "Processando")
        support.capture("u1-analysis-loading-pt-light", app: app)

        cancel.tap()
        XCTAssertTrue(app.buttons["registration.meal.source.text"].waitForExistence(timeout: 5))
        XCTAssertFalse(progress.exists)
    }

    @MainActor
    func testAnalysisLoadingInEnglishAtAXXXLWithReduceMotion() {
        let app = support.launch(
            arguments: [
                "--ui-testing", "--ui-testing-prompt13-reduce-motion",
                "--ui-testing-meal-capture", "--ui-testing-meal-capture-hold",
            ],
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let tab = app.buttons["tab.registrar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 eggs")
        dismissKeyboard(app)
        let read = app.buttons["registration.meal.detect"]
        reveal(read, app: app)
        read.tap()

        let progress = element("registration.meal.capture.progress", app: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        XCTAssertEqual(progress.label, "Analyzing your meal")
        XCTAssertEqual(progress.value as? String, "Reading the foods…")
        let cancel = app.buttons["registration.meal.capture.cancel"]
        reveal(cancel, app: app)
        XCTAssertEqual(cancel.label, "Cancel")
        support.assertTarget(cancel)
        support.capture("u1-analysis-loading-en-dark-axxxl-reduce-motion", app: app)
        cancel.tap()
        XCTAssertTrue(app.buttons["registration.meal.source.text"].waitForExistence(timeout: 5))
        XCTAssertFalse(progress.exists)
    }

    /// Writes a meal and asks for it to be read; the synthetic reader holds.
    @MainActor
    private func reachHeldAnalysis(_ app: XCUIApplication, text: String) {
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        tapDetectWithVisibleKeyboard(app.buttons["registration.meal.detect"], app: app)
    }

    @MainActor
    private func waitForKeyboardFocus(_ field: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    /// The Register tab with the synthetic capture; nothing is opened yet.
    @MainActor
    private func launchRegister(
        language: String,
        dark: Bool = false,
        category: String = "UICTContentSizeCategoryL",
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = support.launch(
            arguments: [
                "--ui-testing", "--ui-testing-prompt13-loaded", "--ui-testing-meal-capture",
            ] + extraArguments,
            language: language,
            dark: dark,
            category: category
        )
        let tab = app.buttons["tab.registrar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        return app
    }

    @MainActor
    private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    @MainActor
    private func launchCapture(
        language: String,
        dark: Bool = false,
        category: String = "UICTContentSizeCategoryL",
        extraArguments: [String] = [],
        scenario: String = "--ui-testing-prompt13-loaded"
    ) -> XCUIApplication {
        let app = support.launch(
            arguments: [
                "--ui-testing", scenario, "--ui-testing-meal-capture",
            ] + extraArguments,
            language: language,
            dark: dark,
            category: category
        )
        let tab = app.buttons["tab.registrar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))
        return app
    }

    /// The Today selection scenario works with either keyboard mode. XCTest
    /// can expose an offscreen keyboard even when no software keyboard is
    /// shown. Still require a stable, unobscured target and exactly one tap.
    @MainActor
    private func tapDetectInVisibleSheet(
        _ button: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var lastGeometry: CaptureTapGeometry?
        var unchangedSince: TimeInterval?
        func readyGeometry() -> CaptureTapGeometry? {
            let window = app.windows.firstMatch
            guard button.exists, button.isEnabled, window.exists else { return nil }
            let bars = app.navigationBars.containing(.button, identifier: "sheet.fechar")
            guard bars.count == 1 else { return nil }
            let keyboard = app.keyboards.firstMatch
            let geometry = CaptureTapGeometry(
                button: button.frame, keyboard: keyboard.exists ? keyboard.frame : .zero,
                header: bars.firstMatch.frame, window: window.frame
            )
            guard geometry.header.width > 0, geometry.header.height > 0,
                  geometry.window.contains(geometry.header),
                  geometry.button.width >= 44, geometry.button.height >= 44,
                  geometry.window.contains(geometry.button),
                  geometry.button.minY >= geometry.header.maxY else { return nil }
            if geometry.keyboard.height > 0, geometry.window.intersects(geometry.keyboard) {
                guard geometry.keyboard.minY > geometry.header.maxY,
                      geometry.button.maxY <= geometry.keyboard.minY else { return nil }
            }
            // Invalid/offscreen frames can make this XCTest query fail rather
            // than return false. Validate the geometry before requesting it.
            return button.isHittable ? geometry : nil
        }
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let geometry = readyGeometry() else {
                lastGeometry = nil
                unchangedSince = nil
                return false
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard geometry == lastGeometry, let since = unchangedSince else {
                lastGeometry = geometry
                unchangedSince = now
                return false
            }
            return now - since >= 0.25
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 8)
        XCTAssertEqual(result, .completed, "Detect target must settle inside the visible sheet",
                       file: file, line: line)
        guard result == .completed, let geometry = readyGeometry() else { return }
        XCTAssertEqual(geometry, lastGeometry, file: file, line: line)
        guard geometry == lastGeometry else { return }
        let attachment = XCTAttachment(string: String(describing: geometry))
        attachment.name = "meal-detect-visible-sheet-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        button.tap()
    }

    /// iOS 27 can accept typeText before the medium sheet finishes moving
    /// above the software keyboard. The failing recordings tapped during
    /// that transition. Keep the keyboard open and wait for the actual
    /// target geometry, rather than changing the capture scenario or retrying.
    private struct CaptureTapGeometry: Equatable {
        let button: CGRect
        let keyboard: CGRect
        let header: CGRect
        let window: CGRect
    }

    @MainActor
    private func tapDetectWithVisibleKeyboard(
        _ button: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let keyboard = app.keyboards.firstMatch
        let window = app.windows.firstMatch
        var lastGeometry: CaptureTapGeometry?
        var unchangedSince: TimeInterval?

        func readyGeometry() -> CaptureTapGeometry? {
            guard keyboard.exists, button.exists, button.isEnabled,
                  button.isHittable, window.exists else { return nil }
            // A presented sheet and its underlying tab can both expose a
            // navigation bar; query order does not identify the visible one.
            let bars = app.navigationBars.containing(.button, identifier: "sheet.fechar")
            guard bars.count == 1 else { return nil }
            let header = bars.firstMatch
            let geometry = CaptureTapGeometry(
                button: button.frame, keyboard: keyboard.frame,
                header: header.frame, window: window.frame
            )
            guard geometry.header.width > 0, geometry.header.height > 0,
                  geometry.window.contains(geometry.header),
                  geometry.keyboard.height > 0,
                  geometry.window.intersects(geometry.keyboard),
                  geometry.keyboard.minY > geometry.header.maxY,
                  geometry.button.width >= 44, geometry.button.height >= 44,
                  geometry.window.contains(geometry.button),
                  geometry.button.minY >= geometry.header.maxY,
                  geometry.button.maxY <= geometry.keyboard.minY else { return nil }
            return geometry
        }

        let geometrySettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let geometry = readyGeometry() else {
                lastGeometry = nil
                unchangedSince = nil
                return false
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard geometry == lastGeometry, let since = unchangedSince else {
                lastGeometry = geometry
                unchangedSince = now
                return false
            }
            return now - since >= 0.25
        }, object: nil)
        let result = XCTWaiter.wait(for: [geometrySettled], timeout: 8)
        XCTAssertEqual(result, .completed,
                       "Keyboard and detect target must settle before a single tap. Last geometry: \(String(describing: lastGeometry))",
                       file: file, line: line)
        guard result == .completed else { return }
        let finalGeometry = readyGeometry()
        XCTAssertNotNil(finalGeometry, file: file, line: line)
        XCTAssertEqual(finalGeometry, lastGeometry,
                       "Geometry changed between readiness and tap", file: file, line: line)
        guard finalGeometry == lastGeometry, let finalGeometry else { return }
        let attachment = XCTAttachment(string: String(describing: finalGeometry))
        attachment.name = "meal-detect-with-visible-keyboard-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        button.tap()
    }

    private enum Direction { case up, down }

    /// Scrolls the sheet in short steps until the element can be tapped:
    /// visible, below the sheet's header and above the keyboard.
    @MainActor
    private func reveal(
        _ target: XCUIElement,
        app: XCUIApplication,
        direction: Direction = .up
    ) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.firstMatch
        func scroll(_ direction: Direction) {
            let window = visibleWindow(app)
            let x = sheet.frame.midX
            let middle = (window.top + window.bottom) / 2
            let step = min((window.bottom - window.top) / 3, 120)
            let from = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x, dy: middle))
            let to = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x, dy: direction == .up ? middle - step : middle + step))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow,
                       thenHoldForDuration: 0.1)
        }
        for _ in 0..<20 {
            if isReachable(target, app: app) { break }
            scroll(direction)
        }
        for _ in 0..<40 {
            if isReachable(target, app: app) { break }
            scroll(direction == .up ? .down : .up)
        }
        let window = visibleWindow(app)
        XCTAssertTrue(
            isReachable(target, app: app),
            "\(target) not reachable: frame \(target.frame), window \(window), "
                + "hittable \(target.isHittable)"
        )
    }

    /// The part of the sheet between its header and the keyboard.
    @MainActor
    private func visibleWindow(_ app: XCUIApplication) -> (top: CGFloat, bottom: CGFloat) {
        // The sheet and underlying tab both expose bars. Query order does
        // not identify the sheet's visible header, as in detect geometry.
        let bars = app.navigationBars.containing(.button, identifier: "sheet.fechar")
        XCTAssertEqual(bars.count, 1)
        let header = bars.firstMatch
        XCTAssertTrue(header.exists)
        let top = header.frame.maxY
        let keyboard = app.keyboards.firstMatch
        let keyboardIsUp = keyboard.exists && keyboard.frame.height > 0
            && keyboard.frame.minY > top && keyboard.frame.minY < app.frame.maxY
        return (top, keyboardIsUp ? keyboard.frame.minY : app.frame.maxY)
    }

    @MainActor
    private func isReachable(_ target: XCUIElement, app: XCUIApplication) -> Bool {
        guard target.exists, target.isHittable else { return false }
        let window = visibleWindow(app)
        return target.frame.minY >= window.top && target.frame.maxY <= window.bottom
    }

    @MainActor
    private func turnOn(_ toggle: XCUIElement) {
        toggle.tap()
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: toggle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [enabled], timeout: 5),
            .completed,
            "O item deve ficar confirmado após um único toque"
        )
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let header = app.navigationBars.firstMatch
        if header.exists {
            header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if app.keyboards.count > 0, app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
    }

    @MainActor
    private func finishNumericEntry(_ app: XCUIApplication, expectedLabel: String) {
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3),
                      "The meal quantity needs an accessible keyboard completion control")
        XCTAssertEqual(done.label, expectedLabel)
        support.assertTarget(done)
        done.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    @MainActor
    private func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        support.element(id, app: app)
    }
}
