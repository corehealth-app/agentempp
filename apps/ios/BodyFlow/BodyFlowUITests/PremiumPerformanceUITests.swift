import XCTest
import UIKit

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

    /// Runner-observed cycle of the same five destinations in both versions.
    /// Includes tap/idle/AX polling overhead, not native animation or hitch time.
    func testFiveTabNavigationUsableObservedBaseline() {
        beginPerformanceConditionEvidence()
        let app = observedTransitionBenchmarkApp()
        let options = fiveIterations
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        measure(metrics: [XCTClockMetric()], options: options) {
            app.terminate()
            app.launch()
            defer { app.terminate() }
            let destinations: [(tab: String, screen: String, content: XCUIElement)] = [
                ("tab.registrar", "screen.registrar", app.buttons["register.refeicao"]),
                ("tab.plano", "screen.plano", app.staticTexts["Training plan"]),
                // Direction v2: Progress leads with the trend charts, so the
                // first official value on screen is the weight card's header
                // ("Weight, 78.4 kg"); the measurements row sits below the fold.
                ("tab.progresso", "screen.progresso", app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH 'Weight' AND label CONTAINS '78.4 kg'")
                ).firstMatch),
                ("tab.perfil", "screen.perfil", app.buttons["profile.coach-persona"]),
                ("tab.hoje", "screen.hoje", app.buttons["today.refresh"]),
            ]
            let initialToday = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.observedRootIsUsable(
                    tab: "tab.hoje", screen: "screen.hoje",
                    content: app.buttons["today.refresh"], in: app
                )
            }, object: nil)
            let initialResult = XCTWaiter.wait(for: [initialToday], timeout: 8)
            if initialResult != .completed {
                let header = app.navigationBars.firstMatch
                let refresh = app.buttons["today.refresh"]
                let remaining = app.descendants(matching: .any)["today.energy.remaining-food"].firstMatch
                let details = "scale=\(UIScreen.main.scale) window=\(app.windows.firstMatch.frame) header=\(header.frame) "
                    + "refresh=\(refresh.frame) remaining=\(remaining.frame) "
                    + "bar=\(benchmarkTabBar(in: app).frame)\n\(app.debugDescription)"
                let attachment = XCTAttachment(string: details)
                attachment.name = "navigation-initial-today-failure-geometry"
                attachment.lifetime = .keepAlways
                add(attachment)
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "navigation-initial-today-failure-screen"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                print("NAVIGATION_INITIAL_TODAY_GEOMETRY:\(details)")
            }
            XCTAssertEqual(initialResult, .completed)
            // Construct every query and expectation before starting the clock.
            let transitions = destinations.map { destination in
                (button: app.buttons[destination.tab], ready: XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        self.observedRootIsUsable(
                            tab: destination.tab, screen: destination.screen,
                            content: destination.content, in: app
                        )
                    }, object: nil
                ))
            }
            var outcomes: [XCTWaiter.Result] = []
            startMeasuring()
            for transition in transitions {
                transition.button.tap()
                let result = XCTWaiter.wait(for: [transition.ready], timeout: 5)
                outcomes.append(result)
                if result != .completed { break }
            }
            stopMeasuring()
            XCTAssertEqual(outcomes.count, destinations.count,
                           "The entire five-tab cycle must execute")
            for (destination, result) in zip(destinations, outcomes) {
                XCTAssertEqual(result, .completed,
                               "Destination must be selected, loaded and usable: \(destination.tab)")
            }
        }
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
    }

    /// Runner-observed presentation of one representative registration sheet.
    /// Launch/navigation/dismissal/reset are outside the measured interval.
    func testMealSheetPresentationUsableObservedBaseline() {
        beginPerformanceConditionEvidence()
        let app = observedTransitionBenchmarkApp()
        let options = fiveIterations
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        capturePerformanceConditionEvidence(phase: "workload-start", app: app)
        measure(metrics: [XCTClockMetric()], options: options) {
            app.terminate()
            app.launch()
            defer { app.terminate() }
            let register = app.buttons["tab.registrar"]
            XCTAssertTrue(register.waitForExistence(timeout: 8))
            XCTAssertTrue(observedControlIsUsable(register, in: app))
            register.tap()
            let open = app.buttons["register.refeicao"]
            let registrationReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.observedRootIsUsable(
                    tab: "tab.registrar", screen: "screen.registrar", content: open, in: app
                )
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [registrationReady], timeout: 5), .completed)
            let sheet = app.descendants(matching: .any)["sheet.registrar.refeicao"].firstMatch
            let close = app.buttons["sheet.fechar"]
            let headers = app.navigationBars.containing(.button, identifier: "sheet.fechar")
            let choices = [
                app.buttons["registration.meal.source.text"],
                app.buttons["registration.meal.source.photo"],
                app.buttons["registration.meal.source.audio"],
            ]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard sheet.exists, headers.count == 1,
                      self.observedControlIsUsable(close, in: app) else { return false }
                let header = headers.firstMatch
                return choices.allSatisfy {
                    self.observedControlIsUsable($0, in: app)
                        && $0.frame.minY >= header.frame.maxY
                }
            }, object: nil)
            startMeasuring()
            open.tap()
            let result = XCTWaiter.wait(for: [ready], timeout: 5)
            stopMeasuring()
            XCTAssertEqual(result, .completed,
                           "Meal sheet must expose all three usable choices and its close button")
            XCTAssertEqual(choices.map(\.label), ["Text", "Photo — local sample", "Audio — local sample"])
            XCTAssertEqual(app.alerts.count, 0)
            close.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !sheet.exists && self.observedRootIsUsable(
                    tab: "tab.registrar", screen: "screen.registrar", content: open, in: app
                )
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        }
        capturePerformanceConditionEvidence(phase: "workload-end", app: app)
    }

    private func observedTransitionBenchmarkApp() -> XCUIApplication {
        XCTAssertEqual(XCUIDevice.shared.appearance, .light,
                       "The paired benchmark requires the recorded Light configuration")
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-testing-prompt13-loaded",
            "-AppleLanguages", "(en-US)", "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ]
        return app
    }

    private func observedControlIsUsable(_ control: XCUIElement, in app: XCUIApplication) -> Bool {
        control.exists && control.isEnabled && control.isHittable
            && control.frame.width >= 44 && control.frame.height >= 44
            && app.windows.firstMatch.frame.contains(control.frame)
    }

    private func observedRootIsUsable(
        tab: String, screen: String, content: XCUIElement, in app: XCUIApplication
    ) -> Bool {
        let selected = app.buttons[tab]
        let root = app.descendants(matching: .any)[screen].firstMatch
        let bar = benchmarkTabBar(in: app)
        let header = app.navigationBars.firstMatch
        guard root.exists, selected.isSelected,
              observedControlIsUsable(selected, in: app),
              content.exists, content.isHittable,
              content.frame.width > 0, content.frame.height > 0,
              app.windows.firstMatch.frame.contains(content.frame),
              bar.exists, header.exists else { return false }
        if content.elementType == .button && !observedControlIsUsable(content, in: app) {
            return false
        }
        if tab == "tab.hoje" {
            // Refresh is a toolbar action. Its full hit target belongs inside
            // the header; the loaded energy value belongs in the content area.
            let remaining = app.descendants(matching: .any)["today.energy.remaining-food"].firstMatch
            // The recorded AX frame extends 0.333 pt above the UIKit header.
            // Allow at most one physical pixel, only for this header comparison.
            let scale = UIScreen.main.scale
            guard scale.isFinite, scale > 0 else { return false }
            let onePixel = 1 / scale
            return header.frame.insetBy(dx: -onePixel, dy: -onePixel).contains(content.frame)
                && remaining.exists && remaining.isHittable
                && remaining.value as? String == "731 kilocalories; exercise excluded"
                && remaining.frame.width > 0 && remaining.frame.height > 0
                && app.windows.firstMatch.frame.contains(remaining.frame)
                && remaining.frame.minY >= header.frame.maxY
                && remaining.frame.maxY <= bar.frame.minY
        }
        guard content.frame.minY >= header.frame.maxY,
              content.frame.maxY <= bar.frame.minY else { return false }
        if tab == "tab.perfil" {
            // The loaded Prompt 13 fixture resets the persona to nil. The
            // button is already tappable during loading, so require its
            // actual loaded value as well as its geometry.
            return content.label.contains("Not selected")
        }
        if tab == "tab.progresso" {
            // Weight can resolve independently. This marker exists only
            // when the progress snapshot itself has been published.
            return app.descendants(matching: .any)["progress.received-values"].firstMatch.exists
        }
        return true
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
            // Setup is outside measure. The frozen baseline has no Done accessory;
            // if one exists, the shared gate still validates its full geometry.
            guard waitForStableComposerKeyboard(
                composer, action: send, app: app, expectedComposer: "QA local \(index)",
                requiresKeyboardAccessory: false,
                diagnosticName: "performance-flow-exchange-\(index)-keyboard"
            ) else { return }
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
