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

    private func checkCaptureJourney(language: String) throws {
        continueAfterFailure = false
        do {
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
