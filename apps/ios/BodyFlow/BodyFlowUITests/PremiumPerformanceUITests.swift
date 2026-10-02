import XCTest

@MainActor
final class PremiumPerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLocalLaunchBaseline() {
        beginPerformanceConditionEvidence()
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-fresh-auth",
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR",
        ]
        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        measure(metrics: [XCTApplicationLaunchMetric()], options: fiveIterations) {
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)["screen.auth.sign-in"]
                    .waitForExistence(timeout: 5)
            )
            app.terminate()
        }
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
    }

    /// Runner-observed launch -> loaded Today with an official value and a
    /// usable action. This includes launch/idle/AX polling overhead; it is not
    /// native TTID, first-frame time, network latency or an Instruments metric.
    func testLocalTodayUsableObservedBaseline() {
        beginPerformanceConditionEvidence()
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-prompt13-loaded",
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        let options = fiveIterations
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        measure(metrics: [XCTClockMetric()], options: options) {
            // Termination, query construction and the previous iteration's
            // cleanup stay outside the measured interval. No fixture mutation.
            app.terminate()
            let today = app.descendants(matching: .any)["screen.hoje"].firstMatch
            let remaining = app.descendants(matching: .any)["today.energy.remaining-food"].firstMatch
            let refresh = app.buttons["today.refresh"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard today.exists, remaining.exists,
                      remaining.value as? String == "731 quilocalorias; exercício excluído",
                      remaining.isHittable,
                      refresh.exists, refresh.isEnabled, refresh.isHittable else { return false }
                let navigationBar = app.navigationBars.firstMatch
                let tabBar = self.benchmarkTabBar(in: app)
                guard navigationBar.exists, tabBar.exists else { return false }
                let viewport = app.windows.firstMatch.frame
                let valueFrame = remaining.frame
                let actionFrame = refresh.frame
                return valueFrame.width > 0 && valueFrame.height > 0
                    && actionFrame.width > 0 && actionFrame.height > 0
                    && viewport.contains(valueFrame) && viewport.contains(actionFrame)
                    && valueFrame.minY >= navigationBar.frame.maxY
                    && valueFrame.maxY <= tabBar.frame.minY
            }, object: nil)

            startMeasuring()
            app.launch()
            let result = XCTWaiter.wait(for: [ready], timeout: 5)
            stopMeasuring()
            XCTAssertEqual(result, .completed,
                           "Today must expose the exact loaded fixture value and usable refresh without scrolling")
        }
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "today-usable-observed-benchmark-final-iteration"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
    }

    func testLibraryFeedScrollBaseline() {
        beginPerformanceConditionEvidence()
        let support = Prompt14UITestSupport(testCase: self)
        let app = support.launch(scenario: .loaded)
        openBenchmarkLibrary(in: app)
        XCTAssertTrue(
            support.element(
                "library.card.10000000-0000-4000-8000-000000000001",
                in: app
            ).waitForExistence(timeout: 5)
        )

        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
            options: fiveIterations
        ) {
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
        app.terminate()
    }

    func testFlowFiftyMessageHistoryRenderBaseline() {
        beginPerformanceConditionEvidence()
        let app = launchFlow(scenario: "longHistory")
        assertFlowMessageCount(40, in: app)
        appendFiveLocalExchanges(to: app)
        let history = app.scrollViews["flow.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))

        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
            options: fiveIterations
        ) {
            history.swipeDown(velocity: .fast)
            history.swipeUp(velocity: .fast)
        }
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
        app.terminate()
    }

    func testFlowLongPlainResponseWrappingBaseline() {
        beginPerformanceConditionEvidence()
        let app = launchFlow(scenario: "response")
        let history = app.scrollViews["flow.history"]
        let body = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "QA_END_OF_LONG_RESPONSE")
        ).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))

        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)],
            options: fiveIterations
        ) {
            history.swipeDown(velocity: .fast)
            history.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(body.exists)
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
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
