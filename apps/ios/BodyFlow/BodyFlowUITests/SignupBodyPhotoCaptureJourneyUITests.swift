import Foundation
import XCTest

/// Local DEBUG demo only; no real account/password,
/// backend/network/system camera/legal publication. No draft mutation in this test.
@MainActor
final class SignupBodyPhotoCaptureJourneyUITests: XCTestCase {
    private var journey: OnboardingJourneyUITestSupport { .init(testCase: self) }

    func testPortugueseConsentCapturesExplicitConfirmAndDraftContinuity() throws {
        try checkCaptureJourney(language: "pt-BR")
    }

    func testEnglishConsentCapturesExplicitConfirmAndDraftContinuity() throws {
        try checkCaptureJourney(language: "en-US")
    }

    func testPortugueseRetakeAndDeleteAfterExplicitConfirm() throws {
        try checkRetakeAndDeleteJourney(language: "pt-BR")
    }

    func testEnglishRetakeAndDeleteAfterExplicitConfirm() throws {
        try checkRetakeAndDeleteJourney(language: "en-US")
    }

    private func checkCaptureJourney(language: String) throws {
        continueAfterFailure = false
        do {
            let app = try freshCaptureResult(language: language)
            assertFirstEstimateDisclaimer(app, language: language)
            for (pose, value) in [("front", "18%"), ("side", "24%"), ("back", "30%")] {
                let reading = journey.element("onboarding.photos.result.reading." + pose, app)
                XCTAssertTrue(reading.waitForExistence(timeout: 5))
                XCTAssertEqual(reading.label, value)
            }
            XCTAssertEqual(journey.element("onboarding.photos.result.mean", app).label, "24%")
            XCTAssertFalse(confirmedCard(app).exists)
            let confirm = app.buttons["onboarding.photos.result.confirm"]
            XCTAssertTrue(confirm.exists && confirm.isEnabled)
            journey.capture("signup-photo-three-captures-before-confirm-" + language, app)
            journey.tap(app.buttons["onboarding.photos.flow.close"], app)
            XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
            XCTAssertFalse(confirmedCard(app).exists,
                "Closing the result before explicit confirmation must not claim confirmed photo origin")
            journey.tap(app.buttons["onboarding.body-fat.choice.photos"], app)
            XCTAssertTrue(journey.element("onboarding.photos.result.mean", app).waitForExistence(timeout: 5))
            assertFirstEstimateDisclaimer(app, language: language)
            journey.tap(confirm, app)
            XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
            assertConfirmedCard(app, language: language)
            XCTAssertTrue(app.buttons["onboarding.body-fat.choice.photos"].isSelected)
            journey.advance(app)
            XCTAssertTrue(journey.element("screen.onboarding.routine", app).waitForExistence(timeout: 5))
            journey.tap(app.buttons["onboarding.back.top"], app)
            XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
            assertConfirmedCard(app, language: language)
            journey.tap(app.buttons["onboarding.body-fat.choice.typed"], app)
            XCTAssertFalse(confirmedCard(app).exists)
            XCTAssertTrue(app.textFields["onboarding.body-fat"].exists)
            XCTAssertEqual(number(app.textFields["onboarding.body-fat"], language: language)?.doubleValue, 24)
            journey.tap(app.buttons["onboarding.body-fat.choice.skip"], app)
            XCTAssertFalse(confirmedCard(app).exists)
            journey.tap(app.buttons["onboarding.body-fat.choice.typed"], app)
            XCTAssertNil(number(app.textFields["onboarding.body-fat"], language: language),
                "Explicit skip clears the actual field; typed mode does not resurrect the confirmed photo percentage")
            journey.capture("signup-photo-confirm-continue-back-proof-" + language, app)
            app.terminate()
        }
    }

    private func checkRetakeAndDeleteJourney(language: String) throws {
        continueAfterFailure = false
        let app = try freshCaptureResult(language: language)
        defer { app.terminate() }
        assertFirstEstimateDisclaimer(app, language: language)
        for (pose, value) in [("front", "18%"), ("side", "24%"), ("back", "30%")] {
            let reading = journey.element("onboarding.photos.result.reading." + pose, app)
            XCTAssertTrue(reading.waitForExistence(timeout: 5))
            XCTAssertEqual(reading.label, value)
        }
        XCTAssertEqual(journey.element("onboarding.photos.result.mean", app).label, "24%")
        XCTAssertFalse(confirmedCard(app).exists)
        let initialConfirm = app.buttons["onboarding.photos.result.confirm"]
        XCTAssertTrue(initialConfirm.exists && initialConfirm.isEnabled)
        journey.tap(initialConfirm, app)
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
        assertConfirmedCard(app, language: language)

        journey.tap(app.buttons["onboarding.body-fat.choice.photos"], app)
        XCTAssertTrue(journey.element("onboarding.photos.result.mean", app).waitForExistence(timeout: 5))
        assertFirstEstimateDisclaimer(app, language: language)
        let retake = app.buttons["onboarding.photos.result.retake"]
        XCTAssertTrue(retake.exists && retake.isEnabled)
        XCTAssertEqual(retake.label, language == "pt-BR" ? "Refazer fotos" : "Retake photos")
        journey.tap(retake, app)
        XCTAssertTrue(app.buttons["onboarding.photos.capture.camera.front"].waitForExistence(timeout: 5))
        for pose in ["front", "side", "back"] {
            XCTAssertTrue(journey.element("onboarding.photos.capture.status." + pose + ".read", app).exists)
        }
        XCTAssertFalse(app.buttons["onboarding.photos.result.confirm"].exists)
        XCTAssertFalse(journey.element("onboarding.photos.result.mean", app).exists)
        journey.tap(app.buttons["onboarding.photos.capture.camera.front"], app)
        XCTAssertTrue(app.buttons["registration.meal.camera.take"].waitForExistence(timeout: 5))
        journey.tap(app.buttons["registration.meal.camera.take"], app)
        XCTAssertTrue(journey.element("onboarding.photos.result.mean", app).waitForExistence(timeout: 5))
        assertFirstEstimateDisclaimer(app, language: language)
        for (pose, value) in [("front", "18%"), ("side", "24%"), ("back", "30%")] {
            XCTAssertEqual(journey.element("onboarding.photos.result.reading." + pose, app).label, value)
        }
        XCTAssertEqual(journey.element("onboarding.photos.result.mean", app).label, "24%")
        journey.tap(app.buttons["onboarding.photos.flow.close"], app)
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
        XCTAssertFalse(confirmedCard(app).exists,
            "A new capture invalidates the old photo proof even when the visible estimate remains 24%")
        journey.tap(app.buttons["onboarding.body-fat.choice.photos"], app)
        XCTAssertTrue(journey.element("onboarding.photos.result.mean", app).waitForExistence(timeout: 5))
        assertFirstEstimateDisclaimer(app, language: language)
        let newConfirm = app.buttons["onboarding.photos.result.confirm"]
        XCTAssertTrue(newConfirm.exists && newConfirm.isEnabled)
        journey.tap(newConfirm, app)
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
        assertConfirmedCard(app, language: language)
        journey.capture("signup-photo-retake-same-estimate-new-confirm-" + language, app)

        let delete = app.buttons["onboarding.photos.delete"]
        XCTAssertTrue(delete.exists && delete.isEnabled)
        XCTAssertEqual(delete.label, language == "pt-BR" ? "Apagar fotos" : "Delete photos")
        journey.tap(delete, app)
        let cancelledAlert = try assertDeleteConfirmation(app, language: language)
        journey.capture("signup-photo-delete-confirmation-B-" + language, app)
        journey.tap(try nativeDeleteAlertButton("onboarding.photos.delete.cancel", in: cancelledAlert), app)
        XCTAssertFalse(cancelledAlert.exists)
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).exists)
        assertConfirmedCard(app, language: language)
        XCTAssertTrue(delete.exists && delete.isEnabled)
        XCTAssertFalse(journey.element("onboarding.photos.delete.pending", app).exists)
        XCTAssertFalse(journey.element("onboarding.photos.delete.error", app).exists)

        journey.tap(delete, app)
        let confirmedAlert = try assertDeleteConfirmation(app, language: language)
        journey.tap(try nativeDeleteAlertButton("onboarding.photos.delete.confirm", in: confirmedAlert), app)
        XCTAssertFalse(confirmedAlert.exists)
        let cardGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: confirmedCard(app))
        XCTAssertEqual(XCTWaiter.wait(for: [cardGone], timeout: 5), .completed,
            "Explicit DELETE must clear the confirmed photo-origin card")
        let deletionFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: journey.element("onboarding.photos.delete.pending", app))
        XCTAssertEqual(XCTWaiter.wait(for: [deletionFinished], timeout: 5), .completed,
            "Wait for the visible deletion operation before reopening photos")
        XCTAssertFalse(journey.element("onboarding.photos.delete.error", app).exists)
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).exists)
        journey.tap(app.buttons["onboarding.body-fat.choice.photos"], app)
        for pose in ["front", "side", "back"] {
            XCTAssertTrue(journey.element("onboarding.photos.capture.status." + pose + ".empty", app)
                .waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.buttons["onboarding.photos.capture.camera.front"].exists)
        XCTAssertFalse(journey.element("onboarding.photos.result.mean", app).exists)
        XCTAssertFalse(app.buttons["onboarding.photos.result.confirm"].exists)
        XCTAssertFalse(journey.element("onboarding.photos.delete.pending", app).exists)
        XCTAssertFalse(journey.element("onboarding.photos.delete.error", app).exists)
        journey.capture("signup-photo-delete-returns-empty-capture-" + language, app)
        journey.tap(app.buttons["onboarding.photos.flow.close"], app)
        XCTAssertTrue(journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 5))
        XCTAssertFalse(confirmedCard(app).exists,
            "Returning from the empty capture must not restore the old photo confirmation")
    }

    private func freshCaptureResult(language: String) throws -> XCUIApplication {
        let app = journey.launch("--ui-testing-signup-body-photos-capture", language: language)
        journey.reachBodyData(app)
        let male = app.buttons[language == "pt-BR" ? "Masculino" : "Male"]
        let chooseDate = app.buttons[language == "pt-BR" ? "Selecionar data" : "Choose a date"]
        XCTAssertTrue(chooseDate.waitForExistence(timeout: 5), "Fresh signup has no seeded birth date")
        XCTAssertFalse(male.isSelected, "Fresh signup has no seeded sex")
        journey.tap(male, app)
        journey.tap(chooseDate, app) // existing user action selects the existing 2000-01-01 default
        try enterNumber("170", in: app.textFields["onboarding.height"], app, language: language)
        try enterNumber("65", in: app.textFields["onboarding.weight"], app, language: language)
        XCTAssertFalse(confirmedCard(app).exists)
        journey.tap(app.buttons["onboarding.body-fat.choice.photos"], app)
        XCTAssertTrue(journey.element("screen.onboarding.photos.consent", app).waitForExistence(timeout: 5))
        let body = journey.element("onboarding.photos.consent.body", app)
        XCTAssertTrue(body.exists && !body.label.isEmpty)
        XCTAssertTrue(body.label.hasPrefix(language == "pt-BR"
            ? "Fotos do corpo para estimar o percentual de gordura"
            : "Body photos to estimate body fat percentage"))
        XCTAssertFalse(app.buttons["registration.meal.camera.take"].exists)
        journey.tap(app.buttons["onboarding.photos.consent.accept"], app)

        for pose in ["front", "side", "back"] {
            XCTAssertTrue(journey.element("onboarding.photos.capture.status." + pose + ".empty", app)
                .waitForExistence(timeout: 5))
        }
        // Cancellation is a real stand-in button; it must not create a slot/result.
        journey.tap(app.buttons["onboarding.photos.capture.camera.front"], app)
        XCTAssertTrue(app.buttons["registration.meal.camera.cancel"].waitForExistence(timeout: 5))
        journey.tap(app.buttons["registration.meal.camera.cancel"], app)
        XCTAssertTrue(journey.element("onboarding.photos.capture.status.front.empty", app)
            .waitForExistence(timeout: 5))
        for (index, pose) in ["front", "side", "back"].enumerated() {
            journey.tap(app.buttons["onboarding.photos.capture.camera." + pose], app)
            XCTAssertTrue(app.buttons["registration.meal.camera.take"].waitForExistence(timeout: 5))
            journey.tap(app.buttons["registration.meal.camera.take"], app)
            if index < 2 {
                XCTAssertTrue(journey.element("onboarding.photos.capture.status." + pose + ".read", app)
                    .waitForExistence(timeout: 5))
                XCTAssertFalse(journey.element("onboarding.photos.result.mean", app).exists)
                XCTAssertFalse(app.buttons["onboarding.photos.result.confirm"].exists)
            }
        }
        return app
    }

    private func assertFirstEstimateDisclaimer(_ app: XCUIApplication, language: String) {
        let first = journey.element("onboarding.photos.result.disclaimer.estimate", app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        // No tap/swipe first: entering a result must already expose its first disclaimer.
        XCTAssertTrue(first.isHittable, "The first estimate disclaimer must be visible at result entry")
        let scroll = app.scrollViews["onboarding.photos.flow.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let firstFrame = first.frame
        let scrollFrame = scroll.frame
        XCTAssertGreaterThan(firstFrame.width, 0)
        XCTAssertGreaterThan(firstFrame.height, 0)
        XCTAssertGreaterThan(scrollFrame.width, 0)
        XCTAssertGreaterThan(scrollFrame.height, 0)
        XCTAssertGreaterThanOrEqual(firstFrame.minY, scrollFrame.minY - 1,
            "The first estimate disclaimer must not extend above the scroll viewport")
        XCTAssertLessThanOrEqual(firstFrame.maxY, scrollFrame.maxY + 1,
            "The first estimate disclaimer must not extend below the scroll viewport")
        XCTAssertEqual(first.label, language == "pt-BR"
            ? "Este número é a estimativa do seu percentual de gordura corporal."
            : "This number is the estimate of your body fat percentage.")
    }
    private func assertDeleteConfirmation(_ app: XCUIApplication, language: String) throws -> XCUIElement {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let title = language == "pt-BR" ? "Apagar fotos" : "Delete photos"
        XCTAssertTrue(alert.staticTexts[title].exists)
        let message = alert.staticTexts.matching(
            NSPredicate(format: "label == %@", deleteMessage(language: language))).firstMatch
        XCTAssertTrue(message.exists)
        XCTAssertEqual(message.label, deleteMessage(language: language))
        let confirm = try nativeDeleteAlertButton("onboarding.photos.delete.confirm", in: alert)
        let cancel = try nativeDeleteAlertButton("onboarding.photos.delete.cancel", in: alert)
        XCTAssertTrue(confirm.exists && confirm.isEnabled)
        XCTAssertTrue(cancel.exists && cancel.isEnabled)
        XCTAssertEqual(confirm.label, title)
        XCTAssertEqual(cancel.label, language == "pt-BR" ? "Cancelar" : "Cancel")
        return alert
    }

    private enum NativeDeleteAlertQueryError: Error {
        case invalidMatchCount
        case invalidNestedDuplicate
    }

    private func nativeDeleteAlertButton(_ identifier: String, in alert: XCUIElement) throws -> XCUIElement {
        let matches = alert.buttons.matching(identifier: identifier)
        let count = matches.count
        guard count == 1 || count == 2 else {
            XCTFail("Expected one native alert action or one nested wrapper/action pair for \(identifier)")
            throw NativeDeleteAlertQueryError.invalidMatchCount
        }
        let action = matches.firstMatch
        if count == 2 {
            guard action.buttons.matching(identifier: identifier).count == 1 else {
                XCTFail("Two sibling alert actions must not be accepted as a nested duplicate for \(identifier)")
                throw NativeDeleteAlertQueryError.invalidNestedDuplicate
            }
        }
        return action
    }

    private func deleteMessage(language: String) -> String {
        if language == "pt-BR" {
            return """
            Quando a exclusão é concluída no app, o resultado da leitura é apagado do catálogo; a linha que registra a foto continua guardada.

            A original escolhida da galeria, e a cópia na nuvem da galeria, continuam lá; o app não as apaga. Apagar fotos não revoga este aceite nem apaga seu registro. Também não apaga automaticamente uma estimativa ou um percentual já registrado no perfil.

            Um envio já autorizado pode chegar depois de uma tentativa de exclusão. Por isso, não há garantia de que as fotos fiquem permanentemente ausentes, nem de exclusão das cópias dos serviços externos.
            """
        }
        return """
        When deletion is completed in the app, the reading result is cleared from the catalogue; the record of the photo remains stored.

        The original selected from your photo library, and its library cloud copy, remain there; the app does not delete them. Deleting photos does not revoke this consent or delete its record. It also does not automatically erase an estimate or percentage already stored in your profile.

        An upload that was already authorised may arrive after a deletion attempt. There is therefore no guarantee that the photos remain permanently absent, or that copies held by external services are deleted.
        """
    }

    private func enterNumber(_ value: String, in field: XCUIElement, _ app: XCUIApplication,
                             language: String) throws {
        journey.enter(value, in: field, app)
        let done = app.buttons[language == "pt-BR" ? "Concluído" : "Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    }
    private func confirmedCard(_ app: XCUIApplication) -> XCUIElement {
        journey.element("onboarding.body-fat.photos.confirmed", app)
    }
    private func assertConfirmedCard(_ app: XCUIApplication, language: String) {
        let card = confirmedCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, language == "pt-BR"
            ? "Você confirmou a estimativa por fotos: 24%" : "You confirmed the photo estimate: 24%")
    }
    private func number(_ field: XCUIElement, language: String) -> NSNumber? {
        guard let text = field.value as? String else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.numberStyle = .decimal
        return formatter.number(from: text.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
