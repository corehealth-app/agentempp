import XCTest

enum Prompt13UITestScenario: String, CaseIterable {
    case loaded = "--ui-testing-prompt13-loaded"
    case loading = "--ui-testing-prompt13-loading"
    case empty = "--ui-testing-prompt13-empty"
    case offline = "--ui-testing-prompt13-offline"
    case staleOffline = "--ui-testing-prompt13-stale-offline"
    case error = "--ui-testing-prompt13-error"
    case staleError = "--ui-testing-prompt13-stale-error"
    case incomplete = "--ui-testing-prompt13-incomplete"
    case unavailable = "--ui-testing-prompt13-unavailable"
    case registrationErrorOnce = "--ui-testing-prompt13-registration-error-once"
    case routineConflictOnce = "--ui-testing-prompt13-routine-conflict-once"
    case routineActionUnavailable = "--ui-testing-prompt13-routine-action-unavailable"
    case reduceMotion = "--ui-testing-prompt13-reduce-motion"
}

@MainActor
struct BodyFlowUITestSupport {
    private static let approvedEvidenceNames: Set<String> = [
        "01-today.png",
        "02-meal-proposal-edit.png",
        "03-individual-meal-log-detail.png",
        "04-workout-proposal.png",
        "05-hydration-routine.png",
        "06-plan.png",
        "07-progress-block.png",
        "08-main-history.png",
        "09-offline-error-retry.png",
        "10-dark-mode.png",
        "11-accessibility-xxxl.png",
        "12-reduce-motion.png",
        "13-final-simulator.png",
    ]

    let testCase: XCTestCase

    func launch(
        scenario: Prompt13UITestScenario,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        precondition(
            !additionalArguments.contains { $0.hasPrefix("--ui-testing-prompt13-") },
            "Use exactly one Prompt 13 launch scenario"
        )

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", scenario.rawValue]
            + additionalArguments
        app.launch()
        return app
    }

    func assertMinimumTapTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
    }

    func captureEvidence(
        named name: String,
        of app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            Self.approvedEvidenceNames.contains(name),
            "Evidence name must be one of the 13 approved PNG names",
            file: file,
            line: line
        )
        guard Self.approvedEvidenceNames.contains(name) else { return }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        testCase.add(screenshot)

        let hierarchy = XCTAttachment(
            data: Data(app.debugDescription.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        hierarchy.name = String(name.dropLast(4)) + ".txt"
        hierarchy.lifetime = .keepAlways
        testCase.add(hierarchy)
    }
}
