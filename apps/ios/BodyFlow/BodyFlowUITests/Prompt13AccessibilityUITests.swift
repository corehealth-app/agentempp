import XCTest

final class Prompt13AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFiveTabsRetainIndependentNavigationAfterDeepUse() {
        XCUIDevice.shared.appearance = .light
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: [
                "-AppleInterfaceStyle", "Light",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryLarge",
            ]
        )

        for identifier in [
            "tab.hoje", "tab.registrar", "tab.plano", "tab.progresso",
            "tab.perfil",
        ] {
            let tab = app.tabBars.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            support.assertMinimumTapTarget(tab)
        }

        let history = element("today.history", in: app)
        reveal(history, in: app)
        XCTAssertTrue(history.isHittable)
        history.tap()
        let meal = element("history.meal.demo-history-meal-row-1", in: app)
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        XCTAssertTrue(
            app.navigationBars["Registro de alimento"]
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.plano"].tap()
        let planDetail = element("plan.detail", in: app)
        reveal(planDetail, in: app)
        XCTAssertTrue(planDetail.isHittable)
        planDetail.tap()
        XCTAssertTrue(
            element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.progresso"].tap()
        XCTAssertTrue(
            element("screen.progresso", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.registrar"].tap()
        XCTAssertTrue(
            element("screen.registrar", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.perfil"].tap()
        XCTAssertTrue(
            element("screen.perfil", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.hoje"].tap()
        XCTAssertTrue(
            app.navigationBars["Registro de alimento"]
                .waitForExistence(timeout: 5)
        )
        app.tabBars.buttons["tab.plano"].tap()
        XCTAssertTrue(
            element("screen.plan.detail", in: app)
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["tab.hoje"].tap()
        app.navigationBars["Registro de alimento"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            element("screen.history", in: app).waitForExistence(timeout: 5)
        )
        app.navigationBars["Histórico"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        support.captureEvidence(named: "13-final-simulator.png", of: app)
    }

    @MainActor
    func testDarkModeKeepsRepresentativeContentReachable() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }

        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: ["-AppleInterfaceStyle", "Dark"]
        )

        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            element("screen.hoje", in: app).value as? String,
            "dark",
            "The running app must resolve the effective SwiftUI color scheme as dark"
        )
        XCTAssertTrue(
            element("today.energy.remaining-food", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element("today.energy.net-balance", in: app)
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(named: "10-dark-mode.png", of: app)
    }

    @MainActor
    func testAccessibilityXXXLKeepsLabelsAndControlsReachable() {
        XCUIDevice.shared.appearance = .light
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(
            scenario: .loaded,
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )

        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        let navigationBar = app.navigationBars["Hoje"]
        let library = element("today.library", in: app)
        let tabBar = app.tabBars.element(boundBy: 0)
        let scrollView = app.scrollViews.element(boundBy: 0)
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        let remaining = element("today.energy.remaining-food", in: app)
        let remainingViewport = revealFully(
            remaining,
            in: scrollView,
            within: window,
            below: [navigationBar, library],
            above: tabBar
        )
        XCTAssertTrue(remaining.isHittable)
        XCTAssertFalse(remaining.label.isEmpty)
        XCTAssertTrue(remainingViewport.contains(remaining.frame))

        let history = element("today.history", in: app)
        let historyViewport = revealFully(
            history,
            in: scrollView,
            within: window,
            below: [navigationBar, library],
            above: tabBar
        )
        XCTAssertTrue(history.isHittable)
        XCTAssertTrue(historyViewport.contains(history.frame))
        support.assertMinimumTapTarget(history)

        let nextAction = element("today.next-action", in: app)
        let nextActionViewport = revealFully(
            nextAction,
            in: scrollView,
            within: window,
            below: [navigationBar, library],
            above: tabBar
        )
        XCTAssertTrue(nextAction.isHittable)
        XCTAssertFalse(nextAction.label.isEmpty)
        support.assertMinimumTapTarget(nextAction)
        XCTAssertTrue(nextActionViewport.contains(nextAction.frame))
        XCTAssertGreaterThanOrEqual(
            nextAction.frame.minY,
            navigationBar.frame.maxY,
            "Representative card must stay below the navigation bar"
        )
        XCTAssertLessThanOrEqual(
            nextAction.frame.maxY,
            tabBar.frame.minY,
            "Representative card must stay above the tab bar"
        )
        support.captureEvidence(named: "11-accessibility-xxxl.png", of: app)
    }

    @MainActor
    func testDebugReduceMotionPolicyPathKeepsAppUsable() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .reduceMotion)

        XCTAssertTrue(
            element("screen.hoje", in: app).waitForExistence(timeout: 5)
        )
        let refresh = app.buttons["today.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        support.assertMinimumTapTarget(refresh)
        refresh.tap()
        XCTAssertTrue(
            element("today.header.updated-at", in: app)
                .waitForExistence(timeout: 5)
        )
        support.captureEvidence(named: "12-reduce-motion.png", of: app)
    }

    @MainActor
    func testRecoverableAndSuccessSummariesStayVisibleWithMinimumTargets() {
        let support = BodyFlowUITestSupport(testCase: self)
        let app = support.launch(scenario: .registrationErrorOnce)

        let register = app.tabBars.buttons["tab.registrar"]
        XCTAssertTrue(register.waitForExistence(timeout: 5))
        register.tap()
        let meal = app.buttons["register.refeicao"]
        XCTAssertTrue(meal.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(meal)
        meal.tap()

        let textSource = app.buttons["registration.meal.source.text"]
        XCTAssertTrue(textSource.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(textSource)
        textSource.tap()
        let detect = app.buttons["registration.meal.detect"]
        XCTAssertTrue(detect.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(detect)
        detect.tap()

        let summary = element("registration.operation.summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Não foi possível concluir. Tente novamente."]
                .exists
        )
        let retry = app.buttons["registration.mutation.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        support.assertMinimumTapTarget(retry)
        retry.tap()

        XCTAssertTrue(
            element("registration.proposal", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Proposta criada. Revise antes de confirmar."]
                .waitForExistence(timeout: 3)
        )
        for identifier in [
            "registration.proposal.edit",
            "registration.proposal.confirm",
            "registration.proposal.cancel",
        ] {
            support.assertMinimumTapTarget(app.buttons[identifier])
        }
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 6
    ) {
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp()
        }
    }

    @MainActor
    private func revealFully(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        within window: XCUIElement,
        below topObstructions: [XCUIElement],
        above bottomObstruction: XCUIElement
    ) -> CGRect {
        let maximumGestureCount = 8
        let identifier = element.identifier

        for gestureIndex in 0..<maximumGestureCount {
            let viewport = usableViewport(
                within: window,
                below: topObstructions,
                above: bottomObstruction
            )
            guard element.exists else {
                XCTFail("\(identifier) disappeared before it could be revealed")
                return viewport
            }

            let frame = element.frame
            guard frame.width <= viewport.width, frame.height <= viewport.height else {
                XCTFail(
                    "\(identifier) frame \(frame) is larger than viewport \(viewport)"
                )
                return viewport
            }

            if element.isHittable, viewport.contains(frame) {
                return viewport
            }

            let containmentDeficit = verticalContainmentDeficit(
                of: frame,
                inside: viewport
            )

            let safeInset = min(
                max(0, viewport.height - frame.height) * 0.25,
                viewport.height * 0.08
            )
            let requiredDistance: CGFloat
            let movesContentUp: Bool
            if frame.maxY > viewport.maxY {
                requiredDistance = frame.maxY - viewport.maxY + safeInset
                movesContentUp = true
            } else if frame.minY < viewport.minY {
                requiredDistance = viewport.minY - frame.minY + safeInset
                movesContentUp = false
            } else {
                XCTFail(
                    "\(identifier) is inside viewport \(viewport) but is not hittable"
                )
                return viewport
            }

            let gestureBounds = viewport.intersection(scrollView.frame)
            guard !gestureBounds.isNull, gestureBounds.height > 0 else {
                XCTFail(
                    "ScrollView frame \(scrollView.frame) does not intersect viewport \(viewport)"
                )
                return viewport
            }

            let gestureDistance = min(
                requiredDistance,
                gestureBounds.height * 0.6
            )
            let startY = gestureBounds.midY
                + (movesContentUp ? gestureDistance / 2 : -gestureDistance / 2)
            let endY = gestureBounds.midY
                + (movesContentUp ? -gestureDistance / 2 : gestureDistance / 2)
            let start = scrollCoordinate(
                in: scrollView,
                x: gestureBounds.midX,
                y: startY
            )
            let end = scrollCoordinate(
                in: scrollView,
                x: gestureBounds.midX,
                y: endY
            )
            let velocity = XCUIGestureVelocity(
                rawValue: min(
                    max(requiredDistance, 50),
                    2_500
                )
            )

            start.press(
                forDuration: 0.05,
                thenDragTo: end,
                withVelocity: velocity,
                thenHoldForDuration: 0
            )

            let updatedViewport = usableViewport(
                within: window,
                below: topObstructions,
                above: bottomObstruction
            )
            guard element.exists else {
                XCTFail("\(identifier) disappeared after gesture \(gestureIndex + 1)")
                return updatedViewport
            }

            let updatedFrame = element.frame
            guard updatedFrame.width <= updatedViewport.width,
                  updatedFrame.height <= updatedViewport.height else {
                XCTFail(
                    "\(identifier) frame \(updatedFrame) is larger than updated "
                        + "viewport \(updatedViewport)"
                )
                return updatedViewport
            }
            if element.isHittable, updatedViewport.contains(updatedFrame) {
                return updatedViewport
            }

            let updatedContainmentDeficit = verticalContainmentDeficit(
                of: updatedFrame,
                inside: updatedViewport
            )
            let movement = updatedFrame.minY - frame.minY
            let progressThreshold = max(0.5, viewport.height * 0.001)
            guard containmentDeficit - updatedContainmentDeficit > progressThreshold else {
                XCTFail(
                    "Gesture \(gestureIndex + 1) did not reduce the containment "
                        + "deficit for \(identifier): before \(containmentDeficit) "
                        + "in \(viewport), after \(updatedContainmentDeficit) "
                        + "in \(updatedViewport); frames \(frame) -> \(updatedFrame)"
                )
                return updatedViewport
            }
            guard movesContentUp ? movement < 0 : movement > 0 else {
                XCTFail(
                    "Gesture \(gestureIndex + 1) moved \(identifier) in the wrong "
                        + "direction: before \(frame), after \(updatedFrame)"
                )
                return updatedViewport
            }
        }

        let finalViewport = usableViewport(
            within: window,
            below: topObstructions,
            above: bottomObstruction
        )
        XCTFail(
            "Unable to reveal \(identifier) inside \(finalViewport) after "
                + "\(maximumGestureCount) controlled gestures; final frame \(element.frame)"
        )
        return finalViewport
    }

    @MainActor
    private func usableViewport(
        within window: XCUIElement,
        below topObstructions: [XCUIElement],
        above bottomObstruction: XCUIElement
    ) -> CGRect {
        let windowFrame = window.frame
        let top = topObstructions.reduce(windowFrame.minY) { currentTop, obstruction in
            obstruction.exists ? max(currentTop, obstruction.frame.maxY) : currentTop
        }
        let bottom = bottomObstruction.exists
            ? min(windowFrame.maxY, bottomObstruction.frame.minY)
            : windowFrame.maxY

        guard bottom > top else {
            XCTFail(
                "Invalid usable viewport between top \(top) and bottom \(bottom)"
            )
            return .null
        }
        return CGRect(
            x: windowFrame.minX,
            y: top,
            width: windowFrame.width,
            height: bottom - top
        )
    }

    private func verticalContainmentDeficit(
        of frame: CGRect,
        inside viewport: CGRect
    ) -> CGFloat {
        max(0, viewport.minY - frame.minY)
            + max(0, frame.maxY - viewport.maxY)
    }

    @MainActor
    private func scrollCoordinate(
        in scrollView: XCUIElement,
        x: CGFloat,
        y: CGFloat
    ) -> XCUICoordinate {
        let frame = scrollView.frame
        return scrollView.coordinate(
            withNormalizedOffset: CGVector(
                dx: (x - frame.minX) / frame.width,
                dy: (y - frame.minY) / frame.height
            )
        )
    }
}
