import XCTest

/// P-TIMEZONE. Reported by the physician on build 1.0 (3), 2026-10-10
/// 18:54–18:55: "Ele já colocou aqui o fuso dos eua" / "Não se se ele pegou
/// pela minha localização".
///
/// LOCK, added after the change: the failing-first proof of this package is
/// `OnboardingTimeZoneOriginRenderingTests`. This reads the same line on the
/// running app and confirms that the time zone still opens its list.
@MainActor
final class OnboardingTimeZoneOriginUITests: XCTestCase {
    private var journey: OnboardingJourneyUITestSupport { .init(testCase: self) }

    func testTheFirstStepSaysWhereTheTimeZoneComesFromAndItCanStillBeChanged() {
        continueAfterFailure = false
        let app = journey.launch()
        journey.reachWelcome(app)

        let zone = app.buttons["onboarding.timezone"]
        let origin = app.staticTexts["onboarding.timezone.origin"]
        XCTAssertTrue(zone.waitForExistence(timeout: 5))
        XCTAssertTrue(origin.waitForExistence(timeout: 5), "No line under the time zone")
        XCTAssertEqual(
            origin.label,
            "O app começa com o fuso do relógio do seu aparelho. Não usa a sua localização. Toque para trocar."
        )
        XCTAssertGreaterThanOrEqual(origin.frame.minY, zone.frame.maxY)
        XCTAssertLessThanOrEqual(origin.frame.maxX, app.windows.firstMatch.frame.maxX)
        journey.reach(origin, app)
        journey.capture("u2-timezone-origin-welcome-pt-light", app)

        // "Toque para trocar": the control still opens the list of zones.
        journey.tap(zone, app)
        let list = app.navigationBars["Selecionar fuso"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "The time zone did not open its list")
        list.buttons.firstMatch.tap()
        XCTAssertTrue(journey.element("screen.onboarding.welcome", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["onboarding.timezone.origin"].exists)
    }
}
