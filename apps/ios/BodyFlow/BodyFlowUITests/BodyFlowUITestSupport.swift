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
    case reduceMotion = "--ui-testing-prompt13-reduce-motion"
}

@MainActor
struct BodyFlowUITestSupport {
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

    func captureScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    func attachAccessibilityTree(
        of app: XCUIApplication,
        named name: String
    ) {
        let attachment = XCTAttachment(
            data: Data(app.debugDescription.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
