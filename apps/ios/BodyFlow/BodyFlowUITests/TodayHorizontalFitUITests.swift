import XCTest

/// Eduardo, 03/10 on the iPhone: "aparentemente está com um scroll lateral
/// na tela inicial… quando eu arrasto pra baixo e acabo puxando um pouco pro
/// lado, ele mexe". Today scrolls vertically only: no element of the day may
/// reach past the window's sides, at any text size, and a diagonal drag must
/// never move the content sideways.
final class TodayHorizontalFitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(scenario: String, category: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", scenario,
            "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR",
            "-UIPreferredContentSizeCategoryName", category,
        ]
        app.launch()
        return app
    }

    @MainActor
    private func assertNothingOverflowsSideways(_ app: XCUIApplication, _ note: String) {
        let window = app.windows.firstMatch.frame
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        var offenders: [String] = []
        for element in scroll.descendants(matching: .any).allElementsBoundByIndex {
            let frame = element.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            if frame.minX < window.minX - 0.5 || frame.maxX > window.maxX + 0.5 {
                offenders.append("\(element.elementType.rawValue) id='\(element.identifier)' label='\(element.label.prefix(40))' frame=\(frame)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "\(note): content past the window sides:\n" + offenders.joined(separator: "\n"))
    }

    /// Drags down-and-sideways (and up-and-sideways), holds, and reads the
    /// first visible element's leading edge while the finger is still down.
    @MainActor
    private func assertDiagonalDragStaysVertical(_ app: XCUIApplication, _ note: String) {
        let scroll = app.scrollViews.firstMatch
        guard let probe = scroll.descendants(matching: .staticText).allElementsBoundByIndex.first(where: {
            $0.isHittable && $0.frame.width > 0
        }) else { return XCTFail("\(note): no visible text to probe") }
        let before = probe.frame.minX
        for vector in [CGVector(dx: -140, dy: 180), CGVector(dx: 140, dy: -180)] {
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(vector),
                        withVelocity: .slow, thenHoldForDuration: 0.6)
            XCTAssertEqual(probe.frame.minX, before, accuracy: 0.5,
                           "\(note): a diagonal drag \(vector) left the content at a sideways offset")
        }
    }

    @MainActor
    func testTodayNeverExceedsTheWindowSidewaysInAnyScenario() {
        // Loaded day, the day with the mascot and recommendations, and an
        // incomplete day: every Today composition the app can render.
        let scenarios = ["--ui-testing-prompt13-loaded", "--ui-testing-prompt14-loaded", "--ui-testing-prompt13-incomplete"]
        let categories = ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL", "UICTContentSizeCategoryAccessibilityXXXL"]
        for scenario in scenarios {
            for category in categories {
                let app = launch(scenario: scenario, category: category)
                XCTAssertTrue(app.descendants(matching: .any)["today.energy.remaining-food"].waitForExistence(timeout: 8),
                              "\(scenario) \(category)")
                assertNothingOverflowsSideways(app, "\(scenario) \(category) top")
                for step in 0..<7 {
                    app.swipeUp()
                    assertNothingOverflowsSideways(app, "\(scenario) \(category) after swipe \(step)")
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testDiagonalDragNeverMovesTodaySideways() {
        for scenario in ["--ui-testing-prompt13-loaded", "--ui-testing-prompt14-loaded"] {
            let app = launch(scenario: scenario, category: "UICTContentSizeCategoryL")
            XCTAssertTrue(app.descendants(matching: .any)["today.energy.remaining-food"].waitForExistence(timeout: 8))
            assertDiagonalDragStaysVertical(app, "\(scenario) top")
            app.swipeUp()
            assertDiagonalDragStaysVertical(app, "\(scenario) scrolled")
            app.terminate()
        }
    }
}
