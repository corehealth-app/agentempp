import XCTest

/// The meal capture of a real account, over synthetic candidates: text is
/// read, the patient reviews, and only then a proposal exists.
final class MealCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWrittenMealIsReviewedBeforeAnyProposal() {
        let app = launchCapture(language: "pt-BR")

        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        XCTAssertEqual(write.label, "Escrever")
        support.assertTarget(write)
        // No local sample is offered where the capture is the real one.
        XCTAssertFalse(app.buttons["registration.meal.source.photo"].exists)
        XCTAssertFalse(app.buttons["registration.meal.source.audio"].exists)
        XCTAssertFalse(app.staticTexts["Demonstração local; sem permissão de mídia ou upload."].exists)
        write.tap()

        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, field.placeholderValue)
        let read = app.buttons["registration.meal.detect"]
        XCTAssertFalse(read.isEnabled)
        field.tap()
        field.typeText("2 ovos mexidos e granola")
        XCTAssertEqual(field.value as? String, "2 ovos mexidos e granola")
        XCTAssertTrue(read.isEnabled)
        tapDetectWithVisibleKeyboard(read, app: app)

        let eggs = app.textFields["registration.review.item.c1-0a1b2c3d.name"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 8))
        XCTAssertEqual(eggs.value as? String, "ovos mexidos")
        XCTAssertFalse(element("registration.proposal", app: app).exists)
        XCTAssertTrue(app.staticTexts["Revise os alimentos"].exists)
        support.capture("c1-review-pt-light", app: app)

        let submit = app.buttons["registration.review.submit"]
        reveal(submit, app: app)
        XCTAssertFalse(submit.isEnabled)

        let confirmEggs = app.switches["registration.review.item.c1-0a1b2c3d.confirm"]
        reveal(confirmEggs, app: app, direction: .down)
        turnOn(confirmEggs)
        reveal(submit, app: app)
        XCTAssertFalse(submit.isEnabled, "granola still has no quantity")

        let granola = app.textFields["registration.review.item.c2-1b2c3d4e.quantity"]
        reveal(granola, app: app, direction: .down)
        XCTAssertFalse(app.switches["registration.review.item.c2-1b2c3d4e.confirm"].exists)
        granola.tap()
        granola.typeText("30")
        dismissKeyboard(app)

        reveal(submit, app: app)
        XCTAssertTrue(submit.isEnabled)
        support.assertTarget(submit)
        submit.tap()

        XCTAssertTrue(element("registration.proposal", app: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["registration.proposal.confirm"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("registration.proposal.confirmed", app: app).exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testUnrecognizedTextSaysSoAndStartsOver() {
        let app = launchCapture(language: "pt-BR")
        app.buttons["registration.meal.source.text"].tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("xyz")
        XCTAssertEqual(field.value as? String, "xyz")
        let read = app.buttons["registration.meal.detect"]
        XCTAssertTrue(read.isEnabled)
        tapDetectWithVisibleKeyboard(read, app: app)

        let failure = element("registration.meal.capture.failure", app: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[
            "Nenhum alimento foi identificado. Tente descrever de outra forma."
        ].exists)
        XCTAssertFalse(app.buttons["registration.meal.capture.retry"].exists)
        XCTAssertFalse(element("registration.proposal", app: app).exists)

        let startOver = app.buttons["registration.meal.capture.start-over"]
        XCTAssertTrue(startOver.exists)
        support.assertTarget(startOver)
        startOver.tap()
        XCTAssertTrue(app.buttons["registration.meal.source.text"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewAtAccessibilitySizeKeepsTargetsInEnglish() {
        let app = launchCapture(
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        let write = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        XCTAssertEqual(write.label, "Write")
        write.tap()
        let field = app.textFields["registration.meal.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2 eggs")
        dismissKeyboard(app)
        let read = app.buttons["registration.meal.detect"]
        reveal(read, app: app)
        read.tap()

        let eggs = app.textFields["registration.review.item.c1-0a1b2c3d.name"]
        XCTAssertTrue(eggs.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Review the foods"].exists)
        let confirm = app.switches["registration.review.item.c1-0a1b2c3d.confirm"]
        reveal(confirm, app: app)
        support.assertTarget(confirm)
        let remove = app.buttons["registration.review.item.c2-1b2c3d4e.remove"]
        reveal(remove, app: app)
        support.assertTarget(remove)
        support.capture("c1-review-en-dark-axxxl", app: app)
        remove.tap()
        XCTAssertFalse(app.textFields["registration.review.item.c2-1b2c3d4e.name"].exists)
    }

    @MainActor
    private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    @MainActor
    private func launchCapture(
        language: String,
        dark: Bool = false,
        category: String = "UICTContentSizeCategoryL"
    ) -> XCUIApplication {
        let app = support.launch(
            arguments: [
                "--ui-testing", "--ui-testing-prompt13-loaded", "--ui-testing-meal-capture",
            ],
            language: language,
            dark: dark,
            category: category
        )
        let tab = app.buttons["tab.registrar"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        XCTAssertTrue(element("sheet.registrar.refeicao", app: app).waitForExistence(timeout: 5))
        return app
    }

    /// iOS 27 can accept typeText before the medium sheet finishes moving
    /// above the software keyboard. The failing recordings tapped during
    /// that transition. Keep the keyboard open and wait for the actual
    /// target geometry, rather than changing the capture scenario or retrying.
    private struct CaptureTapGeometry: Equatable {
        let button: CGRect
        let keyboard: CGRect
        let header: CGRect
        let window: CGRect
    }

    @MainActor
    private func tapDetectWithVisibleKeyboard(
        _ button: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let keyboard = app.keyboards.firstMatch
        let window = app.windows.firstMatch
        var lastGeometry: CaptureTapGeometry?
        var unchangedSince: TimeInterval?

        func readyGeometry() -> CaptureTapGeometry? {
            guard keyboard.exists, button.exists, button.isEnabled,
                  button.isHittable, window.exists else { return nil }
            // A presented sheet and its underlying tab can both expose a
            // navigation bar; query order does not identify the visible one.
            let bars = app.navigationBars.containing(.button, identifier: "sheet.fechar")
            guard bars.count == 1 else { return nil }
            let header = bars.firstMatch
            let geometry = CaptureTapGeometry(
                button: button.frame, keyboard: keyboard.frame,
                header: header.frame, window: window.frame
            )
            guard geometry.header.width > 0, geometry.header.height > 0,
                  geometry.window.contains(geometry.header),
                  geometry.keyboard.height > 0,
                  geometry.window.intersects(geometry.keyboard),
                  geometry.keyboard.minY > geometry.header.maxY,
                  geometry.button.width >= 44, geometry.button.height >= 44,
                  geometry.window.contains(geometry.button),
                  geometry.button.minY >= geometry.header.maxY,
                  geometry.button.maxY <= geometry.keyboard.minY else { return nil }
            return geometry
        }

        let geometrySettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let geometry = readyGeometry() else {
                lastGeometry = nil
                unchangedSince = nil
                return false
            }
            let now = ProcessInfo.processInfo.systemUptime
            guard geometry == lastGeometry, let since = unchangedSince else {
                lastGeometry = geometry
                unchangedSince = now
                return false
            }
            return now - since >= 0.25
        }, object: nil)
        let result = XCTWaiter.wait(for: [geometrySettled], timeout: 8)
        XCTAssertEqual(result, .completed,
                       "Keyboard and detect target must settle before a single tap. Last geometry: \(String(describing: lastGeometry))",
                       file: file, line: line)
        guard result == .completed else { return }
        let finalGeometry = readyGeometry()
        XCTAssertNotNil(finalGeometry, file: file, line: line)
        XCTAssertEqual(finalGeometry, lastGeometry,
                       "Geometry changed between readiness and tap", file: file, line: line)
        guard finalGeometry == lastGeometry, let finalGeometry else { return }
        let attachment = XCTAttachment(string: String(describing: finalGeometry))
        attachment.name = "meal-detect-with-visible-keyboard-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        button.tap()
    }

    private enum Direction { case up, down }

    /// Scrolls the sheet in short steps until the element can be tapped:
    /// visible, below the sheet's header and above the keyboard.
    @MainActor
    private func reveal(
        _ target: XCUIElement,
        app: XCUIApplication,
        direction: Direction = .up
    ) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.firstMatch
        func scroll(_ direction: Direction) {
            let window = visibleWindow(app)
            let x = sheet.frame.midX
            let middle = (window.top + window.bottom) / 2
            let step = min((window.bottom - window.top) / 3, 120)
            let from = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x, dy: middle))
            let to = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x, dy: direction == .up ? middle - step : middle + step))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow,
                       thenHoldForDuration: 0.1)
        }
        for _ in 0..<20 where !isReachable(target, app: app) {
            scroll(direction)
        }
        for _ in 0..<40 where !isReachable(target, app: app) {
            scroll(direction == .up ? .down : .up)
        }
        let window = visibleWindow(app)
        XCTAssertTrue(
            isReachable(target, app: app),
            "\(target) not reachable: frame \(target.frame), window \(window), "
                + "hittable \(target.isHittable)"
        )
    }

    /// The part of the sheet between its header and the keyboard.
    @MainActor
    private func visibleWindow(_ app: XCUIApplication) -> (top: CGFloat, bottom: CGFloat) {
        let bars = app.navigationBars
        let header = bars.element(boundBy: max(bars.count - 1, 0))
        let top = header.exists ? header.frame.maxY : 0
        let keyboard = app.keyboards.firstMatch
        let keyboardIsUp = keyboard.exists && keyboard.frame.height > 0
            && keyboard.frame.minY > top && keyboard.frame.minY < app.frame.maxY
        return (top, keyboardIsUp ? keyboard.frame.minY : app.frame.maxY)
    }

    @MainActor
    private func isReachable(_ target: XCUIElement, app: XCUIApplication) -> Bool {
        guard target.exists, target.isHittable else { return false }
        let window = visibleWindow(app)
        return target.frame.minY >= window.top && target.frame.maxY <= window.bottom
    }

    @MainActor
    private func turnOn(_ toggle: XCUIElement) {
        toggle.tap()
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: toggle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [enabled], timeout: 5),
            .completed,
            "O item deve ficar confirmado após um único toque"
        )
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let header = app.navigationBars.firstMatch
        if header.exists {
            header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if app.keyboards.count > 0, app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
    }

    @MainActor
    private func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        support.element(id, app: app)
    }
}
