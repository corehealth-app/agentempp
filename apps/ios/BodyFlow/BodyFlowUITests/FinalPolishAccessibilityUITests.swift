import UIKit
import XCTest

final class FinalPolishAccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabLongPressReleasesToItsExistingDestinationAtAXXXL() {
        let app = PremiumUIUXUITestSupport(testCase: self).launch(
            arguments: ["--ui-testing-prompt13-loaded"], language: "en-US", dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(app.performeTabBar.waitForExistence(timeout: 5))
        for (tab, screen) in [("tab.progresso", "screen.progresso"), ("tab.registrar", "screen.registrar")] {
            let action = app.performeTabBar.buttons[tab]
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.width, 44)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            XCTAssertTrue(app.frame.contains(action.frame))
            // Keep the native hold visible in the recorded test video so the
            // Large Content Viewer can also be inspected independently.
            print("LCV_HOLD_BEGIN \(tab)")
            action.press(forDuration: 8)
            XCTAssertTrue(app.descendants(matching: .any)[screen].firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(app.performeTabBar.buttons.count, 5)
        }
    }

    @MainActor
    func testLargeContentGestureCanMoveBetweenTabsBeforeRelease() {
        let app = PremiumUIUXUITestSupport(testCase: self).launch(
            arguments: ["--ui-testing-prompt13-loaded"], language: "en-US", dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(app.performeTabBar.waitForExistence(timeout: 5))
        let progress = app.performeTabBar.buttons["tab.progresso"]
        let register = app.performeTabBar.buttons["tab.registrar"]
        XCTAssertTrue(progress.isHittable)
        XCTAssertTrue(register.isHittable)
        progress.press(forDuration: 2, thenDragTo: register, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(app.descendants(matching: .any)["screen.registrar"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["screen.progresso"].firstMatch.exists)
        XCTAssertEqual(app.performeTabBar.buttons.count, 5)
    }

    @MainActor
    func testSplashLandscapeAXXXLScrollsToCompleteLoadingDescription() {
        let label = "Preparando sua interface com os dados desta sessão"
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-final-polish-splash-landscape",
            "-AppleLanguages", "(pt-BR)",
            "-AppleLocale", "pt_BR",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()

        let splash = app.descendants(matching: .any)["screen.splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        for _ in 0..<20 where app.frame.width <= app.frame.height {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertGreaterThan(app.frame.width, app.frame.height)

        let description = app.staticTexts[label]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where !description.isHittable || !app.frame.contains(description.frame) {
            XCTAssertTrue(scrollView.exists, "Short landscape viewport must use the real Splash scroll view")
            scrollView.swipeUp()
        }
        XCTAssertTrue(description.isHittable, "The complete loading label must be reachable by scrolling")
        XCTAssertEqual(description.label, label)
        XCTAssertGreaterThanOrEqual(description.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(description.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(description.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(description.frame.maxY, app.frame.maxY)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "splash-landscape-complete-axxxl"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
