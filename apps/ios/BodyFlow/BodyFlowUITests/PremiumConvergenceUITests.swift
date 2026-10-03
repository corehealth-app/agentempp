import XCTest
import UIKit

final class PremiumConvergenceUITests: XCTestCase {
    private var permitsAuditExecutionRecovery = true

    override func setUpWithError() throws {
        continueAfterFailure = false
        permitsAuditExecutionRecovery = true
    }

    @MainActor
    func testEnglishOnboardingUsesReviewedLocalizedCopyAtAXXXL() {
        let app = support.launch(
            arguments: ["--ui-testing-fresh-auth"],
            language: "en-US",
            dark: true,
            category: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        let openSignUp = app.buttons["auth.open-sign-up"]
        reach(openSignUp, in: app)
        openSignUp.tap()
        enter("slice9@example.invalid", in: app.textFields["auth.email"])
        enterSecure("local-pass", in: app.secureTextFields["auth.password"])
        enterSecure("local-pass", in: app.secureTextFields["auth.password-confirmation"])
        let signUp = app.buttons["auth.sign-up.submit"]
        reach(signUp, in: app)
        signUp.tap()
        let confirm = app.buttons["auth.confirm-development"]
        reach(confirm, in: app)
        confirm.tap()

        XCTAssertTrue(
            support.element("screen.onboarding.welcome", app: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["What would you like us to call you?"].exists)
        XCTAssertTrue(app.staticTexts["App language"].exists)
        XCTAssertTrue(app.staticTexts["Country"].exists)
        XCTAssertTrue(app.staticTexts["Time zone"].exists)
        XCTAssertFalse(app.staticTexts["Como você quer ser chamado?"].exists)
        support.capture("s9-onboarding-en-dark-axxxl", app: app)
    }

    @MainActor
    func testThemeLocaleMatrixAndSupportedRotations() {
        let cases = [
            (language: "pt-BR", dark: false, title: "Hoje"),
            (language: "pt-BR", dark: true, title: "Hoje"),
            (language: "en-US", dark: false, title: "Today"),
            (language: "en-US", dark: true, title: "Today"),
        ]
        defer { XCUIDevice.shared.orientation = .portrait }

        for item in cases {
            let app = support.launch(
                arguments: ["--ui-testing-prompt13-loaded"],
                language: item.language,
                dark: item.dark
            )
            XCTAssertTrue(
                support.element("screen.hoje", app: app)
                    .waitForExistence(timeout: 8)
            )
            XCTAssertEqual(
                support.element("screen.hoje", app: app).value as? String,
                item.dark ? "dark" : "light",
                "The matrix must verify the app's effective theme, not just a launch argument"
            )
            XCTAssertTrue(app.navigationBars[item.title].exists)
            for orientation in [
                UIDeviceOrientation.landscapeLeft,
                UIDeviceOrientation.landscapeRight,
                UIDeviceOrientation.portrait,
            ] {
                XCUIDevice.shared.orientation = orientation
                XCTAssertTrue(
                    support.element("screen.hoje", app: app)
                        .waitForExistence(timeout: 5)
                )
            }
            support.capture(
                "s9-shell-\(item.language)-\(item.dark ? "dark" : "light")",
                app: app
            )
            app.terminate()
        }
    }


    @MainActor
    func testRepresentativeLoadedTabsPassAutomatedAccessibilityAudit() throws {
        let app = support.launch(
            arguments: ["--ui-testing-prompt13-loaded"],
            language: "pt-BR",
            dark: false
        )
        XCTAssertTrue(
            support.element("screen.hoje", app: app)
                .waitForExistence(timeout: 8)
        )

        try performConvergenceAudit(app, screen: "today")
        for tab in ["tab.registrar", "tab.plano", "tab.progresso", "tab.perfil"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            try performConvergenceAudit(app, screen: tab)
        }
    }

    @MainActor
    func testRepresentativeStateFamiliesPassAutomatedAccessibilityAudit() throws {
        let cases = [
            (argument: "--ui-testing-prompt13-empty", identifier: "state.empty"),
            (argument: "--ui-testing-prompt13-offline", identifier: "state.offline"),
            (argument: "--ui-testing-prompt13-error", identifier: "state.error"),
            (argument: "--ui-testing-prompt13-unavailable", identifier: "state.unavailable"),
        ]

        for item in cases {
            let app = support.launch(
                arguments: [item.argument],
                language: "en-US",
                dark: true,
                category: "UICTContentSizeCategoryAccessibilityXXXL"
            )
            XCTAssertTrue(
                support.element(item.identifier, app: app)
                    .waitForExistence(timeout: 8)
            )
            try performConvergenceAudit(app, screen: item.identifier)
            app.terminate()
        }
    }

    func testStateAuditViewportRejectsErrorTextBehindPinnedShortcutsAtAXXXL() {
        // Captured on iPhone 17e, iOS 26.5, English AX5. The Library shortcut
        // ends at 349.7; its opaque inset has another 8 points of bottom padding.
        let screenFrame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let libraryFrame = CGRect(x: 16, y: 265.7, width: 358, height: 84)
        let errorTextFrame = CGRect(x: 45.2, y: 333, width: 299.7, height: 249.3)
        let top = ConvergenceAuditViewport.topEdge(
            screen: "state.error", navigationBarBottom: 101,
            pinnedShortcutFrames: [libraryFrame]
        )

        XCTAssertEqual(top, 357.7, accuracy: 0.01)
        XCTAssertFalse(ConvergenceAuditViewport.containsFullFrame(
            errorTextFrame, screenFrame: screenFrame,
            top: top, bottom: 729.7, margin: 16
        ), "The complete error message must clear the opaque pinned shortcuts")
        // At AX5 this paragraph is taller than the preferred 64-point-margin
        // area, but can still be completely exposed with the existing 16-point
        // boundary rule. It must then pass a fresh native contrast audit.
        XCTAssertTrue(ConvergenceAuditViewport.containsFullFrame(
            CGRect(x: 45.2, y: 419.05, width: 299.7, height: 249.3),
            screenFrame: screenFrame, top: top, bottom: 729.7, margin: 16
        ))
    }

    func testLoadedAuditViewportDoesNotTreatScrollableShortcutsAsPinned() {
        let top = ConvergenceAuditViewport.topEdge(
            screen: "today", navigationBarBottom: 101,
            pinnedShortcutFrames: [CGRect(x: 16, y: 265.7, width: 358, height: 84)]
        )
        XCTAssertEqual(top, 101)
    }

    @MainActor
    private var support: PremiumUIUXUITestSupport {
        PremiumUIUXUITestSupport(testCase: self)
    }

    @MainActor
    private func enter(_ value: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(value)
    }

    @MainActor
    private func enterSecure(_ value: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(waitForKeyboardFocus(field))
        if field.identifier == "auth.password" {
            field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(waitForKeyboardFocus(field))
        }
        UIPasteboard.general.string = value
        defer { UIPasteboard.general.string = nil }
        field.typeKey("v", modifierFlags: .command)
        if !waitForSecureEntry(field, characterCount: value.count, timeout: 1) {
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            for character in value {
                field.typeText(String(character))
            }
        }
        XCTAssertTrue(waitForSecureEntry(field, characterCount: value.count))
    }

    @MainActor
    private func waitForKeyboardFocus(_ field: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    @MainActor
    private func waitForSecureEntry(
        _ field: XCUIElement,
        characterCount: Int,
        timeout: TimeInterval = 3
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard
                    let element = object as? XCUIElement,
                    let value = element.value as? String
                else {
                    return false
                }
                return value.count == characterCount
            },
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func reach(
        _ element: XCUIElement,
        in app: XCUIApplication,
        attempts: Int = 24
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<attempts where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element.identifier) must remain reachable")
    }

    @MainActor
    private func performConvergenceAudit(
        _ app: XCUIApplication,
        screen: String
    ) throws {
        let tabBar = app.performeTabBar
        let tabBarFrame = tabBar.exists ? tabBar.frame : .null
        let screenFrame = app.frame
        var occluded: [XCUIElement] = []
        var pendingKeys = Set<String>()
        var validatedKeys = Set<String>()
        var validatedFrames: [String: CGRect] = [:]
        var verifyingKeys = Set<String>()
        var reportedContrastKeys = Set<String>()
        let navigationBarBottom = app.navigationBars.firstMatch.exists
            ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY
        let pinnedShortcutFrames: [CGRect]
        if ConvergenceAuditViewport.hasPinnedTodayShortcuts(screen: screen) {
            pinnedShortcutFrames = ["today.flow-chat", "today.library"].map { identifier in
                let shortcut = app.buttons[identifier]
                XCTAssertTrue(shortcut.exists, "The pinned Today shortcut must remain resolvable")
                return shortcut.frame
            }
        } else {
            // In loaded Today these actions belong to scrolling content.
            pinnedShortcutFrames = []
        }
        let top = ConvergenceAuditViewport.topEdge(
            screen: screen, navigationBarBottom: navigationBarBottom,
            pinnedShortcutFrames: pinnedShortcutFrames
        )
        func identity(in description: String) -> String {
            // XCTest binds findings to an AX node; labels are not identities
            // (several routine rows intentionally share the same title).
            // Read the public diagnostic's binding, fail closed if unavailable.
            guard let binding = description.components(separatedBy: "elementOrHash.elementID: ").dropFirst().first else {
                XCTFail("Audit finding has no resolvable XCTest identity binding")
                return "unresolved"
            }
            let identity = String(binding.prefix { $0.isNumber || $0 == "." })
            XCTAssertFalse(identity.isEmpty, "Audit identity binding must not be empty")
            return identity
        }
        func key(_ element: XCUIElement) -> String { identity(in: element.debugDescription) }
        // Conservative evaluation margin, not an assumed native blur size.
        // Each finding still has to pass while exposed in this central area.
        func frameIsVisible(_ frame: CGRect) -> Bool {
            ConvergenceAuditViewport.containsFullFrame(
                frame, screenFrame: screenFrame, top: top,
                bottom: tabBarFrame.minY, margin: 64
            )
        }
        func frameIsExposed(_ frame: CGRect) -> Bool {
            ConvergenceAuditViewport.containsFullFrame(
                frame, screenFrame: screenFrame, top: top,
                bottom: tabBarFrame.minY, margin: 16
            )
        }
        func audit(_ types: XCUIAccessibilityAuditType = .all) throws {
            reportedContrastKeys.removeAll()
            var findings: [XCUIAccessibilityAuditIssue] = []
            // The handler only retains findings, avoiding nested AX queries
            // while the system audit owns the service. Execution failures
            // still propagate; every finding is handled before any UI moves.
            func collectFindings() throws {
                try app.performAccessibilityAudit(for: types) { issue in
                    findings.append(issue)
                    return true
                }
            }
            do {
                try collectFindings()
            } catch {
                let executionError = error as NSError
                guard permitsAuditExecutionRecovery,
                      executionError.domain == "com.apple.xcode.xctest.accessibilityAudit",
                      executionError.code == -56 else { throw error }
                permitsAuditExecutionRecovery = false
                let attachment = XCTAttachment(string: """
                screen: \(screen)
                auditType: \(types.rawValue)
                executionError: \(executionError.domain) / \(executionError.code)
                recoveryAttempt: 1 of 1 for this entire test method
                retainedFindings: \(findings.count)
                """)
                attachment.name = "accessibility-audit-execution-recovery"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                // Retry only the incomplete native execution. Preserve every
                // finding from both attempts and require a complete second
                // pass. No relaunch, scrolling or changed acceptance rules.
                try collectFindings()
            }
            func accepts(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
                let element = issue.element
                let identifier = element?.identifier ?? ""
                let label = element?.label ?? ""
                let description = element?.debugDescription ?? "none"
                let frame = element?.frame ?? .null
                let diagnostic = [
                    "screen: \(screen)",
                    "type: \(issue.auditType.rawValue)",
                    "summary: \(issue.compactDescription)",
                    "detail: \(issue.detailedDescription)",
                    "element: \(description)",
                    "tabBarFrame: \(tabBarFrame)",
                ].joined(separator: "\n")
                let attachment = XCTAttachment(string: diagnostic)
                attachment.name = "slice9-accessibility-audit-\(screen)"
                attachment.lifetime = .keepAlways
                self.add(attachment)

                // XCTest's Dynamic Type audit treats icon-only SwiftUI buttons as
                // scalable text. This control contains no visible text, preserves a
                // 44+ point target, and exposes a localized spoken label.
                let iconOnlyDynamicTypeFindings = [
                    "Dynamic Type font sizes are partially unsupported",
                    "Text clipped",
                ]
                let isIconOnlyFalsePositive =
                    iconOnlyDynamicTypeFindings.contains(issue.compactDescription)
                    && identifier == "today.refresh"
                let isElementlessContrastLimitation =
                    ["Contrast failed", "Contrast nearly passed"]
                    .contains(issue.compactDescription)
                    && issue.element == nil
                let isCombinedMetricDynamicTypeFalsePositive =
                    screen == "tab.perfil"
                    && [
                        "Dynamic Type font sizes are partially unsupported",
                        "Text clipped",
                    ].contains(issue.compactDescription)
                    && ["Notificações da demonstração", "Ativadas"].contains(label)
                // A scrollable row can be partially behind the floating bar, or
                // (direction v2, taller Today) scrolled just past the top edge
                // behind the navigation bar. Its occluded pixels cannot
                // establish text contrast. Defer this exact finding, reveal the
                // complete element, then audit it again. Every deferred element
                // must complete that second pass below; nothing is waived.
                if issue.auditType == .contrast, let element,
                   !tabBarFrame.isNull,
                   !["tab.hoje", "tab.plano", "tab.registrar", "tab.progresso", "tab.perfil"].contains(identifier),
                   frame.intersects(screenFrame) || frame.maxY <= top || frame.minY >= tabBarFrame.minY {
                    let identity = identity(in: description)
                    reportedContrastKeys.insert(identity)
                    guard !verifyingKeys.contains(identity) else { return false }
                    if validatedKeys.contains(identity) {
                        // A recurring warning at its verified position, or
                        // anywhere in the central viewport, remains a failure.
                        return !frameIsVisible(frame) && validatedFrames[identity] != frame
                    }
                    if pendingKeys.insert(identity).inserted { occluded.append(element) }
                    return true
                }
                return isIconOnlyFalsePositive
                    || isElementlessContrastLimitation
                    || isCombinedMetricDynamicTypeFalsePositive
            }
            var failures: [String] = []
            for issue in findings where !accepts(issue) {
                failures.append("\(issue.compactDescription): \(issue.element?.debugDescription ?? "no element")")
            }
            if !failures.isEmpty {
                throw NSError(domain: "Performe.ConvergenceAudit", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "; ")])
            }
        }
        func fullyVisible(_ element: XCUIElement) -> Bool {
            element.exists && element.isHittable && frameIsVisible(element.frame)
        }
        try audit()
        var resolved = 0
        while !occluded.isEmpty {
            guard resolved < 32 else {
                XCTFail("The audit must close every occluded finding in a bounded number of passes")
                return
            }
            let element = occluded.removeFirst()
            let queuedKey = key(element)
            XCTAssertTrue(element.exists, "The original audit element must remain resolvable")
            var reachedScrollBoundary = false
            // A prior pass may reveal the bottom of a long screen. Allow
            // the same bounded reach used elsewhere to return to this node.
            for _ in 0..<24 {
                if fullyVisible(element) { break }
                let scroll = app.scrollViews.firstMatch
                XCTAssertTrue(scroll.exists, "An occluded element must be revealable by its real scroll view")
                let previous = element.frame
                // Center the reported element without jumping an entire page.
                // Native scroll-edge effects can extend beyond the bar frame.
                let center = (top + app.performeTabBar.frame.minY) / 2
                let delta = max(-240, min(240, center - previous.midY))
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(
                    forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.1
                )
                if element.frame == previous {
                    // The last row can already be fully exposed while the
                    // scroll limit prevents centering it. Audit those actual
                    // pixels; never waive the finding at the boundary.
                    XCTAssertTrue(element.isHittable && frameIsExposed(element.frame),
                                  "A scroll boundary must not conceal any part of the audited element")
                    reachedScrollBoundary = true
                    break
                }
            }
            XCTAssertTrue(fullyVisible(element) || reachedScrollBoundary,
                          "The complete audited element must be exposed before re-auditing: \(element)")
            let auditedFrame = element.frame
            support.capture("s9-audit-revealed-\(screen)-\(resolved)", app: app)
            let visibleCandidates = occluded.filter { fullyVisible($0) }
            verifyingKeys = Set(([element] + visibleCandidates).map(key))
            try audit(.contrast)
            XCTAssertEqual(element.frame, auditedFrame, "The audit must verify the revealed position")
            XCTAssertTrue(element.isHittable && frameIsExposed(element.frame),
                          "The validated element must remain exposed for the whole second pass")
            pendingKeys.remove(queuedKey)
            validatedKeys.insert(queuedKey)
            validatedFrames[queuedKey] = element.frame
            // The same contrast audit covers the entire visible viewport.
            // Close other queued nodes only if they too were fully visible
            // and had no finding in this pass; unseen nodes stay pending.
            occluded.removeAll { candidate in
                let identity = key(candidate)
                guard verifyingKeys.contains(identity), fullyVisible(candidate),
                      !reportedContrastKeys.contains(identity) else { return false }
                validatedKeys.insert(identity)
                validatedFrames[identity] = candidate.frame
                pendingKeys.remove(identity)
                return true
            }
            verifyingKeys.removeAll()
            resolved += 1
        }
    }
}

/// Geometry used only by the audit harness; never changes app layout.
private enum ConvergenceAuditViewport {
    static func hasPinnedTodayShortcuts(screen: String) -> Bool {
        ["state.empty", "state.offline", "state.error", "state.unavailable"].contains(screen)
    }

    static func topEdge(
        screen: String,
        navigationBarBottom: CGFloat,
        pinnedShortcutFrames: [CGRect]
    ) -> CGFloat {
        guard hasPinnedTodayShortcuts(screen: screen),
              let shortcutsBottom = pinnedShortcutFrames.map(\.maxY).max() else {
            return navigationBarBottom
        }
        // TodayRootView adds BodyFlowSpacing.xs (8 pt) below the fixed
        // shortcuts and paints that entire safe-area inset opaquely.
        return max(navigationBarBottom, shortcutsBottom + 8)
    }

    static func containsFullFrame(
        _ frame: CGRect,
        screenFrame: CGRect,
        top: CGFloat,
        bottom: CGFloat,
        margin: CGFloat
    ) -> Bool {
        frame.minY >= top + margin && frame.maxY < bottom - margin
            && frame.minX >= screenFrame.minX && frame.maxX <= screenFrame.maxX
    }
}
