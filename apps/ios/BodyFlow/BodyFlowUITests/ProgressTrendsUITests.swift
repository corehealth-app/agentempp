import XCTest

/// The Progress charts draw only stored series: the loaded demo shows the
/// weight, calorie, block and days cards; an empty account shows the honest
/// empty card and no chart.
final class ProgressTrendsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoadedAccountShowsTheFourTrendCards() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded, additionalArguments: ["--ui-testing-block-currentRecomposition"])
        app.buttons["tab.progresso"].tap()
        XCTAssertTrue(element("progress.trends", in: app).waitForExistence(timeout: 8))
        for id in ["progress.trends.weight", "progress.trends.calories", "progress.trends.block", "progress.trends.days"] {
            let card = element(id, in: app)
            for _ in 0..<4 where !card.exists || !card.isHittable { app.swipeUp() }
            XCTAssertTrue(card.exists, id)
        }
        XCTAssertTrue(app.staticTexts["78,4 kg"].exists)
        XCTAssertFalse(element("progress.trends.empty", in: app).exists)
    }

    @MainActor
    func testEmptyAccountShowsTheEmptyCardAndNoChart() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .empty)
        app.buttons["tab.progresso"].tap()
        XCTAssertTrue(element("progress.trends.empty", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(element("progress.trends.calories", in: app).exists)
        XCTAssertFalse(app.staticTexts["0 kg"].exists)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
