import XCTest

enum Prompt14UITestScenario: String, CaseIterable {
    case loaded = "--ui-testing-prompt14-loaded"
    case loading = "--ui-testing-prompt14-loading"
    case empty = "--ui-testing-prompt14-empty"
    case offline = "--ui-testing-prompt14-offline"
    case error = "--ui-testing-prompt14-error"
    case stale = "--ui-testing-prompt14-stale"
    case unavailable = "--ui-testing-prompt14-unavailable"
    case openedError = "--ui-testing-prompt14-opened-error"
    case contentNotFound = "--ui-testing-prompt14-content-not-found"
    case subscriptionRequired = "--ui-testing-prompt14-subscription-required"
    case markdownInvalid = "--ui-testing-prompt14-markdown-invalid"
    case coverInvalid = "--ui-testing-prompt14-cover-invalid"
    case mascotVariants = "--ui-testing-prompt14-mascot-variants"
    case progressEmpty = "--ui-testing-prompt14-progress-empty"
    case progressMinimum = "--ui-testing-prompt14-progress-minimum"
    case streakZero = "--ui-testing-prompt14-streak-zero"
    case conflict = "--ui-testing-prompt14-conflict"
    case reduceMotion = "--ui-testing-prompt14-reduce-motion"
    case differentiateWithoutColor =
        "--ui-testing-prompt14-differentiate-without-color"
    case todayRecommendationsStale =
        "--ui-testing-prompt14-today-recommendations-stale"
    case nextPageFailureOnce =
        "--ui-testing-prompt14-next-page-failure-once"
    case invalidCursorRecovery =
        "--ui-testing-prompt14-invalid-cursor-recovery"
    case incompleteDetail = "--ui-testing-prompt14-incomplete-detail"
    case mutationFailureOnce =
        "--ui-testing-prompt14-mutation-failure-once"
    case markdownExternalLink =
        "--ui-testing-prompt14-markdown-external-link"
    case coverExpired = "--ui-testing-prompt14-cover-expired"
    case coverTooLarge = "--ui-testing-prompt14-cover-too-large"
    case coverMIMEMismatch =
        "--ui-testing-prompt14-cover-mime-mismatch"
    case coverAbusiveDimensions =
        "--ui-testing-prompt14-cover-abusive-dimensions"
    case coverExternalPath = "--ui-testing-prompt14-cover-external-path"
    case mascotFocusActive = "--ui-testing-prompt14-mascot-focus-active"
    case mascotZenNeglected =
        "--ui-testing-prompt14-mascot-zen-neglected"
    case progressCompleteDuplicateBadges =
        "--ui-testing-prompt14-progress-complete-duplicate-badges"
}

enum Prompt14UIEvidenceName: String, CaseIterable {
    case todayRecommendations = "01-today-recommendations.png"
    case libraryAll = "02-library-all.png"
    case librarySavedEmpty = "03-library-saved-empty.png"
    case libraryCategoryPagination = "04-library-category-pagination.png"
    case contentDetailMarkdown = "05-content-detail-markdown.png"
    case openedErrorNonblocking = "06-opened-error-nonblocking.png"
    case coverFailurePlaceholder = "07-cover-failure-placeholder.png"
    case mascotFocusActive = "08-mascot-focus-active.png"
    case mascotZenNeglected = "09-mascot-zen-neglected.png"
    case mascotEvolvingNeutral = "10-mascot-evolving-neutral.png"
    case progressGamification = "11-progress-gamification.png"
    case streakZeroMissions = "12-streak-zero-missions.png"
    case offlineErrorRetry = "13-offline-error-retry.png"
    case conflictReload = "14-conflict-reload.png"
    case darkMode = "15-dark-mode.png"
    case accessibilityXXXL = "16-accessibility-xxxl.png"
    case increaseContrast = "17-increase-contrast.png"
    case differentiateWithoutColor =
        "18-differentiate-without-color.png"
    case reduceMotion = "19-reduce-motion.png"
    case unavailable = "20-unavailable.png"
    case finalSimulator = "21-final-simulator.png"
}

struct Prompt14RevealGestureBudget {
    let limit: Int
    private(set) var used = 0

    init(requested: Int) {
        limit = min(max(requested, 0), 8)
    }

    mutating func consume() -> Bool {
        guard used < limit else {
            return false
        }
        used += 1
        return true
    }
}

@MainActor
struct Prompt14UITestSupport {
    let testCase: XCTestCase

    func launch(
        scenario: Prompt14UITestScenario,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        precondition(
            !additionalArguments.contains {
                $0.hasPrefix("--ui-testing-prompt14-")
            },
            "Use exactly one Prompt 14 launch scenario"
        )
        precondition(
            !additionalArguments.contains {
                $0.hasPrefix("--ui-testing-prompt13-")
            },
            "Prompt 14 already composes the Prompt 13 loaded repository"
        )

        let launchArguments = ["--ui-testing", scenario.rawValue]
            + additionalArguments
        precondition(
            launchArguments.filter {
                $0.hasPrefix("--ui-testing-prompt14-")
            }.count == 1,
            "Use exactly one Prompt 14 launch scenario"
        )

        let app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()
        return app
    }

    func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    func openLibrary(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let today = element("screen.hoje", in: app)
        XCTAssertTrue(
            today.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        let library = element("today.library", in: app)
        XCTAssertTrue(
            library.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        assertMinimumTapTarget(library, file: file, line: line)
        library.tap()
        XCTAssertTrue(
            element("screen.library", in: app).waitForExistence(timeout: 5),
            file: file,
            line: line
        )
    }

    func openContentDetail(
        _ publicationID: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let card = element("library.card.\(publicationID)", in: app)
        reveal(card, in: app, attempts: 12)
        XCTAssertTrue(
            card.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        XCTAssertTrue(card.isHittable, file: file, line: line)
        card.tap()
        XCTAssertTrue(
            element("screen.content-detail.\(publicationID)", in: app)
                .waitForExistence(timeout: 5),
            file: file,
            line: line
        )
    }

    func openProgress(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let progress = app.tabBars.buttons["tab.progresso"]
        XCTAssertTrue(
            progress.waitForExistence(timeout: 5),
            file: file,
            line: line
        )
        assertMinimumTapTarget(progress, file: file, line: line)
        progress.tap()
        XCTAssertTrue(
            element("screen.progresso", in: app).waitForExistence(timeout: 5),
            file: file,
            line: line
        )
    }

    func reveal(
        _ target: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 8
    ) {
        var gestureBudget = Prompt14RevealGestureBudget(
            requested: attempts
        )
        let resolvedTarget = target.firstMatch
        let window = app.windows.firstMatch
        let scrollView = app.scrollViews.firstMatch
        let tabBar = app.tabBars.firstMatch
        let brand = element("brand.product-name", in: app)
        let navigationBar = app.navigationBars.firstMatch
        guard window.exists,
              scrollView.exists,
              tabBar.exists else {
            XCTFail(
                "Cannot reveal \(resolvedTarget.identifier) without an authenticated viewport"
            )
            return
        }

        while !resolvedTarget.exists, gestureBudget.consume() {
            app.swipeUp()
        }
        guard resolvedTarget.exists else {
            XCTFail(
                "\(resolvedTarget.identifier) did not appear after "
                    + "\(gestureBudget.used) discovery gestures"
            )
            return
        }
        let viewport = usableViewport(
            within: window,
            below: [brand, navigationBar].filter(\.exists),
            above: tabBar
        )
        let revealTarget: XCUIElement
        let targetFitsViewport = resolvedTarget.frame.width <= viewport.width
            && resolvedTarget.frame.height <= viewport.height
        if targetFitsViewport
            || !Self.allowsSemanticRepresentative(
                for: resolvedTarget.elementType
            ) {
            revealTarget = resolvedTarget
        } else {
            let representatives = [
                resolvedTarget.buttons.firstMatch,
                resolvedTarget.links.firstMatch,
                resolvedTarget.staticTexts.firstMatch,
            ]
            guard let representative = representatives.first(where: \.exists) else {
                XCTFail(
                    "\(resolvedTarget.identifier) is larger than viewport \(viewport) "
                        + "and has no semantic descendant to reveal"
                )
                return
            }
            revealTarget = representative
        }
        _ = revealFully(
            revealTarget,
            in: scrollView,
            within: window,
            below: [brand, navigationBar].filter(\.exists),
            above: tabBar,
            gestureBudget: &gestureBudget
        )
    }

    nonisolated static func allowsSemanticRepresentative(
        for elementType: XCUIElement.ElementType
    ) -> Bool {
        elementType != .button && elementType != .link
    }

    func revealFully(
        _ target: XCUIElement,
        in scrollView: XCUIElement,
        within window: XCUIElement,
        below topObstructions: [XCUIElement],
        above bottomObstruction: XCUIElement,
        clearingUpperChromeFor leadingContent: XCUIElement? = nil,
        attempts: Int = 8
    ) -> CGRect {
        var gestureBudget = Prompt14RevealGestureBudget(
            requested: attempts
        )
        return revealFully(
            target,
            in: scrollView,
            within: window,
            below: topObstructions,
            above: bottomObstruction,
            clearingUpperChromeFor: leadingContent,
            gestureBudget: &gestureBudget
        )
    }

    func revealFully(
        _ targets: [XCUIElement],
        in scrollView: XCUIElement,
        within window: XCUIElement,
        below topObstructions: [XCUIElement],
        above bottomObstruction: XCUIElement,
        attempts: Int = 8
    ) -> CGRect {
        var gestureBudget = Prompt14RevealGestureBudget(
            requested: attempts
        )
        let identifiers = targets.map(\.identifier).joined(separator: ", ")

        guard !targets.isEmpty else {
            XCTFail("At least one element is required for a shared reveal")
            return usableViewport(
                within: window,
                below: topObstructions,
                above: bottomObstruction
            )
        }

        while true {
            let viewport = usableViewport(
                within: window,
                below: topObstructions,
                above: bottomObstruction
            )
            guard targets.allSatisfy(\.exists) else {
                XCTFail(
                    "Elements [\(identifiers)] must all exist before a shared reveal"
                )
                return viewport
            }

            let frames = targets.map(\.frame)
            let combinedFrame = frames.dropFirst().reduce(frames[0]) {
                $0.union($1)
            }
            guard combinedFrame.width <= viewport.width,
                  combinedFrame.height <= viewport.height else {
                XCTFail(
                    "Combined frame \(combinedFrame) for [\(identifiers)] is larger "
                        + "than viewport \(viewport)"
                )
                return viewport
            }

            let allContainedAndHittable = zip(targets, frames).allSatisfy {
                element,
                frame in
                element.isHittable && viewport.contains(frame)
            }
            if allContainedAndHittable {
                return viewport
            }

            let containmentDeficit = verticalContainmentDeficit(
                of: combinedFrame,
                inside: viewport
            )
            guard containmentDeficit > 0 else {
                XCTFail(
                    "Elements [\(identifiers)] are geometrically inside \(viewport) "
                        + "but at least one is not hittable"
                )
                return viewport
            }
            guard gestureBudget.consume() else {
                XCTFail(
                    "Unable to reveal [\(identifiers)] together inside \(viewport) "
                        + "after \(gestureBudget.used) controlled gestures; final "
                        + "combined frame \(combinedFrame)"
                )
                return viewport
            }
            let gestureIndex = gestureBudget.used

            let gestureBounds = viewport.intersection(scrollView.frame)
            guard !gestureBounds.isNull,
                  gestureBounds.width > 0,
                  gestureBounds.height > 0 else {
                XCTFail(
                    "ScrollView frame \(scrollView.frame) does not intersect "
                        + "viewport \(viewport)"
                )
                return viewport
            }

            let desiredTranslation = viewport.midY - combinedFrame.midY
            let movesContentUp = desiredTranslation < 0
            let requiredDistance = abs(desiredTranslation)
            guard requiredDistance > 0 else {
                XCTFail(
                    "Elements [\(identifiers)] have containment deficit "
                        + "\(containmentDeficit) without a vertical correction"
                )
                return viewport
            }
            let activationThreshold = gestureBounds.height * 0.04
            let activationDistance = requiredDistance < activationThreshold
                ? gestureBounds.height * 0.02
                : 0
            let gestureDistance = min(
                requiredDistance + activationDistance,
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
                rawValue: min(max(requiredDistance, 50), 2_500)
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
            guard targets.allSatisfy(\.exists) else {
                XCTFail(
                    "Elements [\(identifiers)] changed after gesture \(gestureIndex)"
                )
                return updatedViewport
            }
            let updatedFrames = targets.map(\.frame)
            let updatedCombinedFrame = updatedFrames.dropFirst().reduce(
                updatedFrames[0]
            ) {
                $0.union($1)
            }
            guard updatedCombinedFrame.width <= updatedViewport.width,
                  updatedCombinedFrame.height <= updatedViewport.height else {
                XCTFail(
                    "Combined frame \(updatedCombinedFrame) for [\(identifiers)] "
                        + "is larger than updated viewport \(updatedViewport)"
                )
                return updatedViewport
            }
            let updatedAllContainedAndHittable = zip(
                targets,
                updatedFrames
            ).allSatisfy { element, frame in
                element.isHittable && updatedViewport.contains(frame)
            }
            if updatedAllContainedAndHittable {
                return updatedViewport
            }

            let updatedContainmentDeficit = verticalContainmentDeficit(
                of: updatedCombinedFrame,
                inside: updatedViewport
            )
            let progressThreshold = max(0.5, viewport.height * 0.001)
            guard containmentDeficit - updatedContainmentDeficit
                    > progressThreshold else {
                XCTFail(
                    "Gesture \(gestureIndex) did not reduce the shared containment "
                        + "deficit for [\(identifiers)]: before "
                        + "\(containmentDeficit) in \(viewport), after "
                        + "\(updatedContainmentDeficit) in \(updatedViewport); frames "
                        + "\(combinedFrame) -> \(updatedCombinedFrame)"
                )
                return updatedViewport
            }
            let movement = updatedCombinedFrame.minY - combinedFrame.minY
            guard movesContentUp ? movement < 0 : movement > 0 else {
                XCTFail(
                    "Gesture \(gestureIndex) moved [\(identifiers)] in the wrong "
                        + "direction: before \(combinedFrame), after "
                        + "\(updatedCombinedFrame)"
                )
                return updatedViewport
            }
        }
    }

    private func revealFully(
        _ target: XCUIElement,
        in scrollView: XCUIElement,
        within window: XCUIElement,
        below topObstructions: [XCUIElement],
        above bottomObstruction: XCUIElement,
        clearingUpperChromeFor leadingContent: XCUIElement? = nil,
        gestureBudget: inout Prompt14RevealGestureBudget
    ) -> CGRect {
        let identifier = target.identifier

        while true {
            let viewport = usableViewport(
                within: window,
                below: topObstructions,
                above: bottomObstruction
            )
            guard target.exists else {
                XCTFail("\(identifier) disappeared before it could be revealed")
                return viewport
            }

            let frame = target.frame
            guard frame.width <= viewport.width,
                  frame.height <= viewport.height else {
                XCTFail(
                    "\(identifier) frame \(frame) is larger than viewport \(viewport)"
                )
                return viewport
            }
            let targetIsContained = target.isHittable
                && viewport.contains(frame)
            let topChromeStart = viewport.minY
            let leadingFrame = leadingContent.flatMap { content in
                content.exists ? content.frame : nil
            }
            let leadingContentCrossesChrome = leadingFrame.map {
                $0.maxY > topChromeStart
            } ?? false
            if targetIsContained, !leadingContentCrossesChrome {
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
            let clearsUpperChrome = targetIsContained
                && leadingContentCrossesChrome
            if clearsUpperChrome, let leadingFrame {
                let clearanceMargin = min(10, viewport.height * 0.02)
                requiredDistance = leadingFrame.maxY - topChromeStart
                    + clearanceMargin
                movesContentUp = true
                guard frame.minY - requiredDistance >= viewport.minY else {
                    XCTFail(
                        "Clearing upper chrome for \(leadingContent?.identifier ?? "content") "
                            + "would move \(identifier) outside viewport \(viewport)"
                    )
                    return viewport
                }
            } else if frame.maxY > viewport.maxY {
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

            guard gestureBudget.consume() else {
                XCTFail(
                    "Unable to reveal \(identifier) inside \(viewport) after "
                        + "\(gestureBudget.used) controlled gestures; final frame "
                        + "\(target.frame)"
                )
                return viewport
            }
            let gestureIndex = gestureBudget.used

            let gestureBounds = viewport.intersection(scrollView.frame)
            guard !gestureBounds.isNull,
                  gestureBounds.width > 0,
                  gestureBounds.height > 0 else {
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
                rawValue: min(max(requiredDistance, 50), 2_500)
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
            guard target.exists else {
                XCTFail(
                    "\(identifier) disappeared after gesture \(gestureIndex)"
                )
                return updatedViewport
            }

            let updatedFrame = target.frame
            guard updatedFrame.width <= updatedViewport.width,
                  updatedFrame.height <= updatedViewport.height else {
                XCTFail(
                    "\(identifier) frame \(updatedFrame) is larger than updated "
                        + "viewport \(updatedViewport)"
                )
                return updatedViewport
            }
            let updatedTargetIsContained = target.isHittable
                && updatedViewport.contains(updatedFrame)
            let updatedTopChromeStart = updatedViewport.minY
            let updatedLeadingFrame = leadingContent.flatMap { content in
                content.exists ? content.frame : nil
            }
            let leadingContentIsClear = updatedLeadingFrame.map {
                $0.maxY <= updatedTopChromeStart
            } ?? true
            if updatedTargetIsContained,
               leadingContent == nil || leadingContentIsClear {
                return updatedViewport
            }

            let movement = updatedFrame.minY - frame.minY
            let progressThreshold = max(0.5, viewport.height * 0.001)
            if clearsUpperChrome, let leadingFrame {
                guard let updatedLeadingFrame else {
                    continue
                }
                let leadingMovement =
                    updatedLeadingFrame.maxY - leadingFrame.maxY
                guard leadingMovement < -progressThreshold else {
                    XCTFail(
                        "Gesture \(gestureIndex) did not move "
                            + "\(leadingContent?.identifier ?? "content") above the "
                            + "upper chrome: frames \(leadingFrame) -> "
                            + "\(updatedLeadingFrame)"
                    )
                    return updatedViewport
                }
                guard updatedTargetIsContained else {
                    XCTFail(
                        "Clearing upper chrome moved \(identifier) outside "
                            + "viewport \(updatedViewport): \(updatedFrame)"
                    )
                    return updatedViewport
                }
            } else {
                let updatedContainmentDeficit = verticalContainmentDeficit(
                    of: updatedFrame,
                    inside: updatedViewport
                )
                guard containmentDeficit - updatedContainmentDeficit
                        > progressThreshold else {
                    XCTFail(
                        "Gesture \(gestureIndex) did not reduce the containment "
                            + "deficit for \(identifier): before \(containmentDeficit) "
                            + "in \(viewport), after \(updatedContainmentDeficit) "
                            + "in \(updatedViewport); frames \(frame) -> \(updatedFrame)"
                    )
                    return updatedViewport
                }
            }
            guard movesContentUp ? movement < 0 : movement > 0 else {
                XCTFail(
                    "Gesture \(gestureIndex) moved \(identifier) in the wrong "
                        + "direction: before \(frame), after \(updatedFrame)"
                )
                return updatedViewport
            }
        }
    }

    func usableViewport(
        within window: XCUIElement,
        below topObstructions: [XCUIElement],
        above bottomObstruction: XCUIElement
    ) -> CGRect {
        let windowFrame = window.frame
        let top = topObstructions.reduce(windowFrame.minY) {
            currentTop,
            obstruction in
            obstruction.exists
                ? max(currentTop, obstruction.frame.maxY)
                : currentTop
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

    func assertAccessibilityOrder(
        _ orderedFragments: [String],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hierarchy = app.debugDescription
        var lowerBound = hierarchy.startIndex
        for fragment in orderedFragments {
            guard let range = hierarchy.range(
                of: fragment,
                range: lowerBound..<hierarchy.endIndex
            ) else {
                XCTFail(
                    "Accessibility hierarchy is missing or misorders \(fragment)",
                    file: file,
                    line: line
                )
                return
            }
            lowerBound = range.upperBound
        }
    }

    func waitForLabel(
        containing value: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", value)
        ).firstMatch.waitForExistence(timeout: timeout)
    }

    func assertMinimumTapTarget(
        _ target: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            target.frame.width,
            44,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            target.frame.height,
            44,
            file: file,
            line: line
        )
    }

    private func verticalContainmentDeficit(
        of frame: CGRect,
        inside viewport: CGRect
    ) -> CGFloat {
        max(0, viewport.minY - frame.minY)
            + max(0, frame.maxY - viewport.maxY)
    }

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

    func captureEvidence(
        _ evidence: Prompt14UIEvidenceName,
        of app: XCUIApplication
    ) {
        precondition(
            Prompt14UIEvidenceName.allCases.map(\.rawValue).contains(
                evidence.rawValue
            ),
            "Evidence name must belong to the closed Prompt 14 allowlist"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = evidence.rawValue
        screenshot.lifetime = .keepAlways
        testCase.add(screenshot)

        let hierarchy = XCTAttachment(
            data: Data(app.debugDescription.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        hierarchy.name = String(evidence.rawValue.dropLast(4)) + ".txt"
        hierarchy.lifetime = .keepAlways
        testCase.add(hierarchy)
    }
}
