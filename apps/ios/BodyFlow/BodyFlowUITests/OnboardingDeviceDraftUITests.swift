import XCTest

/// Package A4 (decision D6 of the orchestrator, announced to the owner on
/// 2026-10-10/11, who can strike it). The sign-up of a real account kept
/// nothing while it was not finished: a person whose app was ended in the
/// middle came back to "Boas-vindas", blank.
///
/// The fixture runs the repository of a real account over a stand-in server
/// (Debug only): no network and no real account.
@MainActor
final class OnboardingDeviceDraftUITests: XCTestCase {
    private var journey: OnboardingJourneyUITestSupport { .init(testCase: self) }

    /// In the middle of "Dados corporais" — the weight still being typed —
    /// the person leaves the app and the app is ended. Opening it again
    /// lands on "Dados corporais" with what was filled, and the name of the
    /// step before is still there.
    func testLeavingTheAppInTheMiddleOfDadosCorporaisKeepsWhatWasTyped() {
        continueAfterFailure = false
        let app = journey.launch("--ui-testing-onboarding-device-draft")
        journey.reachBodyData(app, name: "Pessoa QA")

        // A real account starts with nothing filled.
        let female = app.buttons["Feminino"]
        let chooseDate = app.buttons["Selecionar data"]
        let height = app.textFields["onboarding.height"]
        let weight = app.textFields["onboarding.weight"]
        XCTAssertTrue(chooseDate.waitForExistence(timeout: 5), "The fixture must open with no birth date")
        XCTAssertFalse(female.isSelected, "The fixture must open with no sex chosen")
        XCTAssertFalse(spoken(height).contains("170"), "The fixture must open with no height")
        XCTAssertFalse(spoken(weight).contains("65"), "The fixture must open with no weight")

        journey.tap(female, app)
        XCTAssertTrue(female.isSelected)
        journey.tap(chooseDate, app)
        XCTAssertTrue(chooseDate.waitForNonExistence(timeout: 5))
        journey.enter("170", in: height, app)
        // The number pad has no return key: its own "Concluído" closes it,
        // and the next field is in reach again.
        let done = app.buttons["Concluído"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The number pad offers no way to close it")
        done.tap()
        // The weight is left being typed: its keyboard is still up when the
        // person leaves.
        journey.enter("65", in: weight, app)
        journey.capture("u2-draft-dados-corporais-before-leaving", app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            app.wait(for: .runningBackground, timeout: 10)
                || app.wait(for: .runningBackgroundSuspended, timeout: 10),
            "The app did not leave the foreground"
        )
        app.terminate()

        // Opened again: the same account, nothing reset.
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()

        XCTAssertTrue(
            journey.element("screen.onboarding.body-data", app).waitForExistence(timeout: 20),
            "The sign-up did not reopen on “Dados corporais”"
        )
        journey.waitUntilArrived(app)
        journey.capture("u2-draft-dados-corporais-reopened", app)
        XCTAssertTrue(app.buttons["Feminino"].isSelected, "The sex was not kept")
        XCTAssertFalse(app.buttons["Selecionar data"].exists, "The birth date was not kept")
        let keptHeight = spoken(app.textFields["onboarding.height"])
        let keptWeight = spoken(app.textFields["onboarding.weight"])
        XCTAssertTrue(keptHeight.contains("170"), "The height was not kept: «\(keptHeight)»")
        XCTAssertTrue(
            keptWeight.contains("65"),
            "What was still being typed when the person left was not kept: «\(keptWeight)»"
        )

        // The step before is still filled too.
        journey.tap(app.buttons["onboarding.back.top"], app)
        XCTAssertTrue(journey.element("screen.onboarding.welcome", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["onboarding.display-name"].value as? String, "Pessoa QA")
    }

    /// What a field shows or says of its content.
    private func spoken(_ field: XCUIElement) -> String {
        field.value as? String ?? ""
    }
}
