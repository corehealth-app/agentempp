import XCTest

/// Real ProgressRootView, model, numeric presentation and API decoder.
/// The root uses a ScrollView whose virtual AX rows cannot be enumerated
/// by the project's UIKit rendering probes. No credentials or network.
final class ProgressBodyFatOriginUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    /// Run this method alone first. A valid RED has already proved that the
    /// real Measurements section displays the fixture's official 24%.
    @MainActor
    func testConfirmedPhotoEstimateAppearsBesideOfficialBodyFatInPortuguese() throws {
        try verify(scenario: "photos", language: "pt-BR", expectsPhotoOrigin: true)
    }

    @MainActor
    func testConfirmedPhotoEstimateAppearsInEnglishAtAccessibilityXXXL() throws {
        try verify(scenario: "photos", language: "en-US", expectsPhotoOrigin: true,
                   category: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    @MainActor
    func testSameOfficialBodyFatEnteredManuallyDoesNotInferPhotoOrigin() throws {
        for language in ["pt-BR", "en-US"] {
            try verify(scenario: "manual", language: language, expectsPhotoOrigin: false)
        }
    }

    @MainActor
    func testAbsentAndUnknownOriginRemainCompatibleWithoutPhotoLabel() throws {
        for scenario in ["legacy", "unknown"] {
            for language in ["pt-BR", "en-US"] {
                try verify(scenario: scenario, language: language, expectsPhotoOrigin: false)
            }
        }
    }

    @MainActor
    private func verify(scenario: String, language: String, expectsPhotoOrigin: Bool,
                        category: String = "UICTContentSizeCategoryL") throws {
        let app = support.launch(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded",
                        "--ui-testing-progress-body-fat-origin-\(scenario)"],
            language: language, dark: language == "en-US", category: category)
        defer { app.terminate() }
        let progressTab = app.buttons["tab.progresso"]
        guard progressTab.waitForExistence(timeout: 8) else {
            try failSetup("Authenticated demo tab did not appear", app)
        }
        progressTab.tap()
        guard element("progress.received-values", app).waitForExistence(timeout: 8) else {
            try failSetup("Actual ProgressRootView did not publish its official snapshot", app)
        }
        let measurements = element("progress.measurements", app)
        guard measurements.waitForExistence(timeout: 5) else {
            try failSetup("Actual Measurements section was not rendered", app)
        }
        let title = language == "pt-BR" ? "Gordura corporal" : "Body fat"
        let bodyFat = measurements.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        // Permit existing split Text nodes or a combined accessible metric
        // row. Neither punctuation nor a merged origin string is prescribed.
        let numericBodyFat = measurements.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)",
                        "24%", title, "24%")).firstMatch
        reveal(numericBodyFat, app)
        guard bodyFat.exists, numericBodyFat.exists, numericBodyFat.isHittable,
              numericBodyFat.frame.width > 0, numericBodyFat.frame.height > 0,
              app.frame.contains(numericBodyFat.frame) else {
            try failSetup("Official body-fat 24% must be visible before interpreting origin", app)
        }
        XCTAssertTrue(measurements.frame.contains(numericBodyFat.frame),
                      "The unchanged official value must belong to Measurements")
        support.capture("progress-origin-prerequisite-\(scenario)-\(language)", app: app)

        let expected = language == "pt-BR" ? "Estimativa por fotos" : "Photo estimate"
        let origin = measurements.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
        if expectsPhotoOrigin {
            guard origin.waitForExistence(timeout: 2) else {
                support.capture("progress-origin-causal-red-\(scenario)-\(language)", app: app)
                XCTFail("P_DEPOIS_1_CAUSAL: official BF 24% is visible in real Measurements, but confirmed photo origin is absent")
                return
            }
            reveal(origin, app)
            XCTAssertTrue(origin.isHittable,
                          "The photo estimate must be readable in the actual screen and its accessibility tree")
            XCTAssertTrue(app.frame.contains(origin.frame),
                          "The entire photo-origin target must be inside the screen after normal scrolling")
            XCTAssertTrue(measurements.frame.contains(origin.frame),
                          "Origin belongs beside body fat inside Measurements, not in an unrelated banner")
            XCTAssertGreaterThan(origin.frame.width, 0)
            XCTAssertGreaterThan(origin.frame.height, 0)
            let wrongLanguage = language == "pt-BR" ? "Photo estimate" : "Estimativa por fotos"
            XCTAssertFalse(measurements.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", wrongLanguage)).firstMatch.exists)
        } else {
            // Same number in every fixture: equality never proves origin.
            for phrase in ["Estimativa por fotos", "Photo estimate"] {
                XCTAssertFalse(measurements.descendants(matching: .any).matching(
                    NSPredicate(format: "label CONTAINS %@", phrase)).firstMatch.exists,
                    "Manual, absent and unknown origins cannot be represented as confirmed photos")
            }
        }
        support.capture("progress-origin-\(scenario)-\(language)", app: app)
    }

    @MainActor
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        support.element(id, app: app)
    }

    @MainActor
    private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<10 {
            if target.exists, target.isHittable,
               target.frame.width > 0, target.frame.height > 0,
               app.frame.contains(target.frame) { return }
            // Use the observed frame to avoid moving a partially visible
            // target farther out of view. No coordinates or timing delay.
            if target.exists, target.frame.height > 0,
               target.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
    }

    @MainActor
    private func failSetup(_ reason: String, _ app: XCUIApplication) throws -> Never {
        support.capture("progress-origin-setup-not-red", app: app)
        XCTFail("SETUP_NOT_RED: \(reason)")
        throw ProgressOriginSetupError.unavailable
    }
}

private enum ProgressOriginSetupError: Error { case unavailable }
