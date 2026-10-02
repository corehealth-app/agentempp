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
        openBenchmarkLibrary(in: app)
        XCTAssertTrue(
            support.element(
                "library.card.10000000-0000-4000-8000-000000000001",
                in: app
            ).waitForExistence(timeout: 5)
        )

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
            options: fiveIterations
        ) {
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
        app.terminate()
    }

    func testFlowFiftyMessageHistoryRenderBaseline() {
        let app = launchFlow(scenario: "longHistory")
        assertFlowMessageCount(40, in: app)
        appendFiveLocalExchanges(to: app)
        let history = app.scrollViews["flow.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
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
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
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
        let entry = revealBenchmarkEntry("today.flow-chat", in: app)
        entry.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.flow-chat"]
                .waitForExistence(timeout: 5)
        )
        return app
    }

    // Benchmark setup supports both the frozen native-bar baseline and the
    // custom-bar candidate. This fallback is intentionally local to this suite.
    private func benchmarkTabBar(in app: XCUIApplication) -> XCUIElement {
        let custom = app.otherElements["navigation.tab-bar"].firstMatch
        return custom.exists ? custom : app.tabBars.firstMatch
    }

    private func revealBenchmarkEntry(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let entry = app.buttons[identifier]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let bar = benchmarkTabBar(in: app)
        XCTAssertTrue(bar.exists, "Benchmark requires its authenticated tab bar")
        func entryIsVisible() -> Bool {
            entry.isHittable && app.windows.firstMatch.frame.contains(entry.frame)
                && entry.frame.maxY <= bar.frame.minY
        }
        for _ in 0..<8 where !entryIsVisible() {
            if entry.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(entryIsVisible())
        XCTAssertGreaterThanOrEqual(entry.frame.width, 44)
        XCTAssertGreaterThanOrEqual(entry.frame.height, 44)
        return entry
    }

    private func openBenchmarkLibrary(in app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["screen.hoje"].waitForExistence(timeout: 5))
        revealBenchmarkEntry("today.library", in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.library"].waitForExistence(timeout: 5))
    }

    private func assertFlowMessageCount(_ expected: Int, in app: XCUIApplication) {
        let messages = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@",
            "flow.message.", "flow.message.processing", "flow.message.failed"
        ))
        let reachedCount = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Set(messages.allElementsBoundByIndex.map(\.identifier)).count == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reachedCount], timeout: 8), .completed)
        XCTAssertEqual(Set(messages.allElementsBoundByIndex.map(\.identifier)).count, expected)
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
            let cancelling = app.buttons["flow.cancel"]
            let reply = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "QA_REPLY_VISIBLE")
            ).firstMatch
            let pendingObserved = cancelling.waitForExistence(timeout: 2)
            if pendingObserved {
                let completed = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"),
                    object: cancelling
                )
                XCTAssertEqual(
                    XCTWaiter.wait(for: [completed], timeout: 5),
                    .completed
                )
            }
            XCTAssertTrue(
                pendingObserved || reply.waitForExistence(timeout: 5),
                "neither pending nor completed state materialized for exchange index \(index)"
            )
            XCTAssertFalse(send.isEnabled)
            assertFlowMessageCount(40 + 2 * (index + 1), in: app)
        }
    }
}
