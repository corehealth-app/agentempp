import XCTest

@MainActor
final class PremiumPerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLocalLaunchBaseline() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-fresh-auth",
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR",
        ]
        measure(metrics: [XCTApplicationLaunchMetric()], options: fiveIterations) {
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)["screen.auth.sign-in"]
                    .waitForExistence(timeout: 5)
            )
            app.terminate()
        }
    }

    func testLibraryFeedScrollBaseline() {
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)
        support.openLibrary(in: app)
        XCTAssertTrue(
            support.element(
                "library.card.10000000-0000-4000-8000-000000000001",
                in: app
            ).waitForExistence(timeout: 5)
        )

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric()],
            options: fiveIterations
        ) {
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
        app.terminate()
    }

    func testFlowFiftyMessageHistoryRenderBaseline() {
        let app = launchFlow(scenario: "longHistory")
        appendFiveLocalExchanges(to: app)
        let history = app.scrollViews["flow.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric()],
            options: fiveIterations
        ) {
            history.swipeDown(velocity: .fast)
            history.swipeUp(velocity: .fast)
        }
        app.terminate()
    }

    func testFlowLongPlainResponseWrappingBaseline() {
        let app = launchFlow(scenario: "response")
        let history = app.scrollViews["flow.history"]
        let body = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "QA_END_OF_LONG_RESPONSE")
        ).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric()],
            options: fiveIterations
        ) {
            history.swipeDown(velocity: .fast)
            history.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(body.exists)
        app.terminate()
    }

    private var fiveIterations: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    private func launchFlow(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-flow-\(scenario)",
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR",
        ]
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.hoje"]
                .waitForExistence(timeout: 5)
        )
        let entry = app.buttons["today.flow-chat"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.flow-chat"]
                .waitForExistence(timeout: 5)
        )
        return app
    }

    private func appendFiveLocalExchanges(to app: XCUIApplication) {
        for index in 0..<5 {
            let composer = app.textFields["flow.composer"]
            XCTAssertTrue(composer.waitForExistence(timeout: 5))
            composer.tap()
            composer.typeText("QA local \(index)")
            let send = app.buttons["flow.send"]
            XCTAssertTrue(send.isEnabled)
            send.tap()
            let responding = app.descendants(matching: .any)["flow.responding"]
            XCTAssertTrue(responding.waitForExistence(timeout: 2))
            let completed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: responding
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [completed], timeout: 5),
                .completed
            )
            XCTAssertTrue(
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS %@", "QA_REPLY_VISIBLE")
                ).firstMatch.waitForExistence(timeout: 5)
            )
            XCTAssertFalse(send.isEnabled)
        }
    }
}
