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
        for _ in 0..<attempts where !target.isHittable {
            app.swipeUp()
        }
    }

    func revealFully(
        _ target: XCUIElement,
        in app: XCUIApplication,
        within window: XCUIElement,
        attempts: Int = 8
    ) {
        for _ in 0..<attempts where !window.frame.contains(target.frame) {
            app.swipeUp()
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
