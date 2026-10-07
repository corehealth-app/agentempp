import XCTest
import UIKit

@MainActor
final class FlowChatUITests: XCTestCase {
    private static var hasAcknowledgedQAOnboarding = false
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPendingOutboxAppearsBeforeReplyAndKeepsNewComposerOnLocalCancel() {
        let app = launchFlow(scenario: "pendingCancellation")
        let composer = app.textFields["flow.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(composer.frame.maxY, app.performeTabBar.frame.minY,
                                "The composer must stay above the floating navigation before focusing")
        composer.tap()
        composer.typeText("Mensagem A")
        guard waitForStableComposerKeyboard(composer, action: app.buttons["flow.send"], app: app,
                                           expectedComposer: "Mensagem A",
                                           diagnosticName: "flow-pending-before-send") else { return }
        capture("flow-pending-stable-before-send", app: app)
        app.buttons["flow.send"].tap()
        let outbox = element("flow.outbox", app: app)
        XCTAssertTrue(outbox.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Mensagem A"].exists)
        XCTAssertNotEqual(composer.value as? String, "Mensagem A")
        composer.tap()
        composer.typeText("Rascunho B")
        guard waitForStableComposerKeyboard(composer, action: app.buttons["flow.cancel"], app: app,
                                           expectedComposer: "Rascunho B",
                                           diagnosticName: "flow-pending-before-cancel") else { return }
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.performeTabBar.exists, "The custom navigation must not form a second bar above the composer")
        XCTAssertTrue(app.buttons["flow.cancel"].isHittable)
        app.buttons["flow.cancel"].tap()
        XCTAssertTrue(element("flow.error", app: app).waitForExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, "Rascunho B")
        XCTAssertTrue(outbox.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "QA_REPLY_VISIBLE")).firstMatch.exists)
        capture("flow-outbox-local-cancel-keeps-new-composer", app: app)
        app.buttons["keyboard.done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.performeTabBar.waitForExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, "Rascunho B")
    }

    func testAXCancelActionContainsItsWholeNativeLabelWhilePending() {
        let setup = launchFlow(scenario: "empty")
        setup.terminate()
        let app = support.launch(arguments: ["--ui-testing", "--ui-testing-preserve-state", "--ui-testing-flow-pendingCancellation"],
                                 language: "en-US", dark: false,
                                 category: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 5))
        tapVisible(app.buttons["today.flow-chat"], app: app)
        let composer = app.textFields["flow.composer"]
        composer.tap()
        composer.typeText("QA")
        let send = app.buttons["flow.send"]
        assertAXActionHasMinimumGlyphFootprint(send, app: app)
        guard waitForStableComposerKeyboard(composer, action: send, app: app) else { return }
        assertComposerContainedAboveKeyboard(composer, action: send, app: app)
        send.tap()
        let cancel = app.buttons["flow.cancel"]
        XCTAssertTrue(cancel.exists)
        assertAXActionHasMinimumGlyphFootprint(cancel, app: app,
                                             captureName: "flow-ax-pending-cancel-label")
        XCTAssertEqual(cancel.label, "Cancel waiting")
        cancel.tap()
        XCTAssertTrue(element("flow.error", app: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The remote operation may continue")).firstMatch.exists)
        capture("flow-ax-local-cancel", app: app)
    }

    func testEmptyAXComposerKeepsDisabledSendAboveDoneWithoutTyping() {
        let setup = launchFlow(scenario: "empty")
        setup.terminate()
        let app = support.launch(arguments: ["--ui-testing", "--ui-testing-preserve-state", "--ui-testing-flow-empty"],
                                 language: "en-US", dark: false,
                                 category: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 5))
        tapVisible(app.buttons["today.flow-chat"], app: app)
        let composer = app.textFields["flow.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        let send = app.buttons["flow.send"]
        // Keep the field blank: typing QA would trigger the observed reflow
        // and would no longer reproduce the pre-typing 20pt Done overlap.
        guard waitForStableComposerKeyboard(
            composer, action: send, app: app,
            expectedComposer: "Write a message", requiresEnabledAction: false,
            diagnosticName: "flow-empty-ax-before-typing"
        ) else { return }
        XCTAssertEqual(composer.value as? String, "Write a message")
        XCTAssertFalse(send.isEnabled)
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.exists)
        XCTAssertTrue(done.isHittable)
        let doneFrame = done.frame
        XCTAssertGreaterThanOrEqual(doneFrame.width, 44)
        XCTAssertGreaterThanOrEqual(doneFrame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(doneFrame))
        XCTAssertLessThanOrEqual(composer.frame.insetBy(dx: -16, dy: -16).maxY, doneFrame.minY)
        XCTAssertLessThanOrEqual(send.frame.maxY, doneFrame.minY)
        assertComposerContainedAboveKeyboard(composer, action: send, app: app)
        capture("flow-empty-ax-before-typing-settled-raster", app: app)
    }

    func testComposerCannotSubmitOverExisting4000Limit() {
        let app = launchFlow(scenario: "empty")
        let composer = app.textFields["flow.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        enterSyntheticMessageAcrossLimit(in: composer, app: app)
        XCTAssertFalse(app.buttons["flow.send"].isEnabled)
        XCTAssertTrue(element("flow.limit.detail", app: app).exists)
        capture("flow-limit-keyboard", app: app)
    }

    func testAXComposerAtLimitKeepsNativeControlsReachable() {
        let setup = launchFlow(scenario: "empty")
        setup.terminate()
        let app = support.launch(arguments: ["--ui-testing", "--ui-testing-preserve-state", "--ui-testing-flow-empty"],
                                 language: "en-US", dark: false,
                                 category: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 5))
        tapVisible(app.buttons["today.flow-chat"], app: app)
        let field = app.textFields["flow.composer"]
        enterSyntheticMessageAcrossLimit(in: field, app: app)
        let send = app.buttons["flow.send"]
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(element("flow.limit.detail", app: app).exists)
        capture("flow-ax-limit-keyboard-before-navigation", app: app)
        let adaptive = app.scrollViews["flow.composer-scroll"]
        XCTAssertTrue(adaptive.exists)
        guard revealComposerSurface(field, in: adaptive, app: app, padding: 16) else { return }
        XCTAssertTrue(field.isHittable, "The real AX input must remain reachable with its keyboard and limit feedback")
        assertControlContainedAboveKeyboard(field.frame.insetBy(dx: -16, dy: -16), app: app)
        XCTAssertLessThanOrEqual(field.frame.maxY + 16, app.buttons["keyboard.done"].frame.minY)
        guard revealComposerSurface(send, in: adaptive, app: app) else { return }
        XCTAssertTrue(send.isHittable, "The disabled Send still needs a fully reachable native presentation")
        assertAXActionHasMinimumGlyphFootprint(send, app: app)
        assertControlContainedAboveKeyboard(send.frame, app: app)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.buttons["keyboard.done"].frame.minY)
        capture("flow-ax-limit-native-send-reachable", app: app)
        let warning = element("flow.limit.detail", app: app)
        guard revealComposerSurface(warning, in: adaptive, app: app) else { return }
        assertControlContainedAboveKeyboard(warning.frame, app: app)
        XCTAssertLessThanOrEqual(warning.frame.maxY, app.buttons["keyboard.done"].frame.minY)
        XCTAssertEqual(field.value as? String, String(repeating: "a", count: 4_001))
        XCTAssertTrue(waitForKeyboardFocus(field))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(send.isEnabled)
        support.assertTarget(app.buttons["keyboard.done"])
        capture("flow-ax-limit-warning-reachable-with-keyboard", app: app)
    }

    func testHistoricalReadingAndExplicitLatestNavigation() {
        let app = launchFlow(scenario: "longHistory")
        let history = app.scrollViews["flow.history"]
        let lastRole = app.staticTexts["flow.role.qa-seed-39"]
        for _ in 0..<20 where !lastRole.isHittable { history.swipeUp() }
        XCTAssertTrue(lastRole.isHittable)
        history.swipeDown()
        XCTAssertTrue(app.buttons["flow.latest-message"].exists)
        XCTAssertFalse(lastRole.isHittable)
        capture("flow-reader-before-latest", app: app)
        app.buttons["flow.latest-message"].tap()
        XCTAssertTrue(lastRole.isHittable)
        capture("flow-reader-after-latest", app: app)
    }

    func testFiftyMessagesKeepUnsentComposerAndReadingPositionAcrossTabs() {
        let app = launchFlow(scenario: "longHistory")
        let composer = app.textFields["flow.composer"]
        let roles = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "flow.role."))
        XCTAssertEqual(roles.count, 40, "The existing longHistory fixture begins with forty messages")

        // Same preparation as the performance baseline: five local exchanges
        // grow the existing fixture to fifty messages, without a new provider.
        for index in 0..<5 {
            composer.tap()
            composer.typeText("QA local \(index)")
            guard waitForStableComposerKeyboard(composer, action: app.buttons["flow.send"], app: app,
                                               expectedComposer: "QA local \(index)",
                                               diagnosticName: "flow-fifty-before-send-\(index)") else { return }
            app.buttons["flow.send"].tap()
            let reconciled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count == %d", 42 + index * 2),
                object: roles
            )
            XCTAssertEqual(XCTWaiter.wait(for: [reconciled], timeout: 8), .completed)
            XCTAssertFalse(app.buttons["flow.cancel"].exists)
            XCTAssertFalse(app.buttons["flow.send"].isEnabled)
        }
        let persistedIDs = Set(roles.allElementsBoundByIndex.map(\.identifier))
        XCTAssertEqual(persistedIDs.count, 50)
        composer.tap()
        composer.typeText("Rascunho B")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let done = app.buttons["keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5),
                      "An unsent Flow draft needs a public keyboard dismissal action to reach other tabs")
        support.assertTarget(done)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.performeTabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Rascunho B")

        let history = app.scrollViews["flow.history"]
        let anchor = app.staticTexts["flow.role.qa-seed-35"]
        reveal(anchor, in: history)
        XCTAssertTrue(anchor.isHittable)
        XCTAssertTrue(app.buttons["flow.latest-message"].isHittable)
        let anchorBefore = anchor.frame
        capture("flow-unsent-draft-reader-before-tab-roundtrip", app: app)

        app.performeTabBar.buttons["tab.plano"].tap()
        XCTAssertTrue(element("screen.plano", app: app).waitForExistence(timeout: 5))
        app.performeTabBar.buttons["tab.perfil"].tap()
        XCTAssertTrue(element("screen.perfil", app: app).waitForExistence(timeout: 5))
        app.performeTabBar.buttons["tab.hoje"].tap()
        XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Rascunho B")
        XCTAssertTrue(anchor.isHittable, "Returning to Flow must not follow the last message automatically")
        XCTAssertEqual(anchor.frame.minY, anchorBefore.minY, accuracy: 2,
                       "The same historical reading position must survive tab changes")
        XCTAssertTrue(app.buttons["flow.latest-message"].isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["flow.cancel"].exists)
        XCTAssertFalse(element("flow.outbox", app: app).exists)
        XCTAssertFalse(app.staticTexts["Rascunho B"].exists, "B must remain in the composer, not become a sent message")
        XCTAssertEqual(Set(roles.allElementsBoundByIndex.map(\.identifier)), persistedIDs,
                       "Tab navigation must not append a new local send or replace the fifty persisted messages")
        capture("flow-unsent-draft-reader-after-tab-roundtrip", app: app)
    }

    func testEmptyStateStartsAtReadableContentAtAXXXXL() {
        let setup = launchFlow(scenario: "empty")
        setup.terminate()
        let app = support.launch(arguments: ["--ui-testing", "--ui-testing-preserve-state", "--ui-testing-flow-empty"],
                                 language: "en-US", dark: false,
                                 category: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 5))
        tapVisible(app.buttons["today.flow-chat"], app: app)
        XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 3))
        capture("flow-empty-ax-initial-reading", app: app)
        XCTAssertTrue(app.staticTexts["flow.role-line"].isHittable,
                      "An empty conversation must start at readable content, not a blank lazy-scroll tail")
        let title = app.staticTexts["Chat with Flow"]
        let history = app.scrollViews["flow.history"]
        for _ in 0..<12 where !title.isHittable { history.swipeUp() }
        XCTAssertTrue(title.isHittable)
        capture("flow-empty-ax-title-readable", app: app)
    }

    func testErrorAndOfflineStartAtReachableRecoveryAtAXXXXL() {
        let errorApp = launchFlow(scenario: "error", category: "UICTContentSizeCategoryAccessibilityXXXL")
        assertRecoveryIsVisible(app: errorApp, captureName: "flow-error-ax-recovery-visible")
        errorApp.terminate()

        let offlineApp = launchFlow(scenario: "offline", language: "en-US",
                                    category: "UICTContentSizeCategoryAccessibilityXXXL")
        assertRecoveryIsVisible(app: offlineApp, captureName: "flow-offline-ax-recovery-visible")
    }

    func testIncomingLocalReplyWhileHistoricalReaderHoldsPosition() {
        let app = launchFlow(scenario: "longHistory")
        let composer = app.textFields["flow.composer"]
        composer.tap()
        composer.typeText("QA")
        // A genuine native drag/hold spans the finite two-second mock response.
        // It does not change the provider delay or introduce a test-only event API.
        let history = app.scrollViews["flow.history"]
        guard waitForStableComposerKeyboard(composer, action: app.buttons["flow.send"], app: app,
                                           expectedComposer: "QA",
                                           diagnosticName: "flow-incoming-before-send") else { return }
        app.buttons["flow.send"].tap()
        let rectangle = history.frame
        let historicRole = app.staticTexts["flow.role.qa-seed-35"]
        let beforeY = historicRole.frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: rectangle.midX, dy: rectangle.minY + rectangle.height * 0.25))
        let end = origin.withOffset(CGVector(dx: rectangle.midX, dy: rectangle.minY + rectangle.height * 0.5))
        XCTAssertTrue(app.buttons["flow.cancel"].exists, "The response must still be pending before the native reader gesture")
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 3)
        XCTAssertFalse(app.buttons["flow.cancel"].exists)
        let afterY = historicRole.frame.minY
        // Finger distance is not a valid pixel-offset oracle while the keyboard,
        // native scroll physics and pending/footer layout change. Keep geometry
        // diagnostic; assert the exact historical identity and explicit navigation.
        let position = XCTAttachment(string: "anchor=\(historicRole.identifier); beforeY=\(beforeY); afterY=\(afterY); nativeDrag=\(rectangle.height * 0.25); viewportBefore=\(rectangle); viewportAfter=\(history.frame)")
        position.name = "flow-incoming-reader-native-positions"
        position.lifetime = .keepAlways
        add(position)
        let latest = app.buttons["flow.latest-message"]
        XCTAssertTrue(latest.isHittable)
        support.assertTarget(latest)
        XCTAssertTrue(historicRole.isHittable, "The exact historical reader anchor must remain visible")
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "QA_REPLY_VISIBLE")).firstMatch
        XCTAssertFalse(reply.isHittable)
        capture("flow-incoming-reader-preserved", app: app)
        latest.tap()
        XCTAssertTrue(reply.waitForExistence(timeout: 3))
        XCTAssertTrue(reply.isHittable)
        XCTAssertFalse(latest.exists)
        capture("flow-incoming-explicit-latest", app: app)
    }

    func testExplicitLocalCancelAndReopenDoNotSendAgain() {
        let app = launchFlow(scenario: "pendingCancellation")
        let composer = app.textFields["flow.composer"]
        composer.tap()
        composer.typeText("QA")
        guard waitForStableComposerKeyboard(composer, action: app.buttons["flow.send"], app: app,
                                           expectedComposer: "QA",
                                           diagnosticName: "flow-reopen-before-send") else { return }
        app.buttons["flow.send"].tap()
        let cancel = app.buttons["flow.cancel"]
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(app.staticTexts["Enviando e aguardando o Flow…"].exists)
        capture("flow-native-waiting-local-only", app: app)
        cancel.tap()
        let error = element("flow.error", app: app)
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "A operação remota pode continuar")).firstMatch.exists)
        XCTAssertTrue(element("flow.outbox", app: app).exists)
        capture("flow-local-cancel", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        tapVisible(app.buttons["today.flow-chat"], app: app)
        XCTAssertTrue(element("flow.outbox", app: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "QA_REPLY_VISIBLE")).firstMatch.exists)
        capture("flow-cancel-reopened-no-send", app: app)
    }

    func testLocalResponseAndExplicitRetryPreserveNativeContract() {
        let app = launchFlow(scenario: "retryOnce", language: "en-US", dark: true)
        let composer = app.textFields["flow.composer"]
        composer.tap()
        composer.typeText("QA")
        guard waitForStableComposerKeyboard(composer, action: app.buttons["flow.send"], app: app,
                                           expectedComposer: "QA",
                                           diagnosticName: "flow-retry-before-send") else { return }
        app.buttons["flow.send"].tap()
        XCTAssertTrue(element("flow.error", app: app).waitForExistence(timeout: 3))
        let retry = app.buttons["flow.retry"]
        support.assertTarget(retry)
        capture("flow-retry-explicit", app: app)
        retry.tap()
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "QA_REPLY_VISIBLE")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(reply.isHittable)
        XCTAssertFalse(element("flow.error", app: app).exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "You")).firstMatch.exists)
        capture("flow-local-response", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        tapVisible(app.buttons["today.flow-chat"], app: app)
        XCTAssertTrue(reply.waitForExistence(timeout: 3))
        capture("flow-response-reopened-local", app: app)
    }

    func testExistingReduceMotionOverrideKeepsHistoricalNavigationReachable() {
        let app = launchFlow(scenario: "longHistory", category: "UICTContentSizeCategoryAccessibilityXXXL",
                             extraArguments: ["--ui-testing-prompt13-reduce-motion"])
        let history = app.scrollViews["flow.history"]
        let last = app.staticTexts["flow.role.qa-seed-39"]
        reveal(last, in: history)
        XCTAssertTrue(last.isHittable)
        capture("flow-reduce-motion-final-role-reachable", app: app)
        history.swipeDown()
        let latest = app.buttons["flow.latest-message"]
        XCTAssertTrue(latest.exists)
        support.assertTarget(latest)
        latest.tap()
        let finalBody = finalHistoryBody(app: app)
        XCTAssertTrue(finalBody.isHittable)
        XCTAssertTrue(finalBody.frame.intersects(history.frame))
        XCTAssertFalse(latest.exists)
        capture("flow-reduce-motion-history-ax", app: app)
    }

    func testLocalSceneAndAccessibilityPresentationMatrixLight() {
        localSceneAndAccessibilityPresentationMatrix(dark: false)
    }

    func testLocalSceneAndAccessibilityPresentationMatrixDark() {
        localSceneAndAccessibilityPresentationMatrix(dark: true)
    }

    private func localSceneAndAccessibilityPresentationMatrix(dark: Bool) {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        defer { XCUIDevice.shared.appearance = .light }
        if !Self.hasAcknowledgedQAOnboarding {
            let bootstrap = support.launch(
                arguments: ["--ui-testing-fresh-auth"],
                language: "pt-BR",
                dark: dark
            )
            finishActualLocalOnboarding(app: bootstrap)
            bootstrap.terminate()
        }
        var previous: XCUIApplication?
        var regularComposerHeight: CGFloat?
        var cases: [(String, String, Bool, String)] = []
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            for language in ["pt-BR", "en-US"] {
                cases.append(("empty", language, dark, category))
            }
        }
        for (index, scenario) in ["loading", "processing", "response", "error", "offline", "longHistory", "retryOnce"].enumerated() {
            cases.append((scenario, index.isMultiple(of: 2) ? "pt-BR" : "en-US",
                          dark, "UICTContentSizeCategoryAccessibilityXXXL"))
        }
        for (index, entry) in cases.enumerated() {
            previous?.terminate()
            let (scenario, language, dark, category) = entry
            let args = [
                "--ui-testing",
                "--ui-testing-flow-\(scenario)",
                "--ui-testing-preserve-state",
            ]
            let app = support.launch(arguments: args, language: language, dark: dark, category: category)
            XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 5),
                          "Only the actual acknowledged QA finish may unlock the preserved session")
            XCTAssertEqual(element("screen.hoje", app: app).value as? String, dark ? "dark" : "light",
                           "The simulator appearance must really match the matrix; launch preferences are not proof")
            tapVisible(app.buttons["today.flow-chat"], app: app)
            if scenario == "loading" {
                XCTAssertTrue(element("flow.loading", app: app).exists)
                capture("flow-matrix-\(index)-loading", app: app)
            }
            XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 3))
            switch scenario {
            case "loading":
                XCTAssertTrue(element("flow.empty", app: app).waitForExistence(timeout: 5))
            case "processing":
                XCTAssertTrue(element("flow.message.processing", app: app).waitForExistence(timeout: 3))
            case "response":
                let raw = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "**QA literal**")).firstMatch
                XCTAssertTrue(raw.waitForExistence(timeout: 3))
                XCTAssertTrue(raw.label.contains("QA_END_OF_LONG_RESPONSE"))
            case "error", "offline":
                XCTAssertTrue(element("flow.error", app: app).waitForExistence(timeout: 3))
                support.assertTarget(app.buttons["flow.retry"])
            case "longHistory":
                let history = app.scrollViews["flow.history"]
                let last = app.staticTexts["flow.role.qa-seed-39"]
                reveal(last, in: history)
                XCTAssertTrue(last.isHittable)
            default:
                XCTAssertTrue(element("flow.empty", app: app).waitForExistence(timeout: 3))
            }
            let composer = app.textFields["flow.composer"]
            XCTAssertTrue(composer.exists)
            XCTAssertEqual(composer.placeholderValue,
                           language == "pt-BR" ? "Escreva uma mensagem" : "Write a message")
            if index == 0 { regularComposerHeight = composer.frame.height }
            if index == 2, let regularComposerHeight {
                XCTAssertGreaterThan(composer.frame.height, regularComposerHeight,
                                     "AXXXXL must increase the real rendered field, not only launch preferences")
            }
            let send = app.buttons["flow.send"]
            support.assertTarget(send)
            XCTAssertEqual(send.label, language == "pt-BR" ? "Enviar mensagem" : "Send message")
            XCTAssertFalse(send.isEnabled)
            if category == "UICTContentSizeCategoryAccessibilityXXXL" { assertAXActionHasMinimumGlyphFootprint(send, app: app) }
            capture("flow-matrix-\(index)-\(scenario)-\(language)-\(dark ? "dark" : "light")", app: app)
            if scenario == "empty" {
                composer.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
                XCTAssertTrue(send.isHittable)
                support.assertTarget(send)
                if category == "UICTContentSizeCategoryAccessibilityXXXL" { assertAXActionHasMinimumGlyphFootprint(send, app: app) }
                assertComposerContainedAboveKeyboard(composer, action: send, app: app)
                capture("flow-matrix-\(index)-keyboard", app: app)
            }
            previous = app
        }
    }

    private func launchFlow(scenario: String, language: String = "pt-BR",
                            dark: Bool = false,
                            category: String = "UICTContentSizeCategoryL",
                            extraArguments: [String] = []) -> XCUIApplication {
        // Flow preview scenarios require the generic UI-testing flag. Bootstrap
        // the actual local auth/onboarding journey once, then combine that flag
        // with the keychain-preservation flag so the scenario does not bypass it.
        if !Self.hasAcknowledgedQAOnboarding {
            let bootstrap = support.launch(
                arguments: ["--ui-testing-fresh-auth"],
                language: language,
                dark: dark,
                category: category
            )
            finishActualLocalOnboarding(app: bootstrap)
            bootstrap.terminate()
        }
        let arguments = ["--ui-testing", "--ui-testing-flow-\(scenario)"]
            + extraArguments
            + ["--ui-testing-preserve-state"]
        let app = support.launch(arguments: arguments,
                                 language: language, dark: dark, category: category)
        XCTAssertTrue(element("screen.hoje", app: app).waitForExistence(timeout: 5),
                      "Preserved QA state must still have the actual acknowledged finish")
        let entry = app.buttons["today.flow-chat"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        tapVisible(entry, app: app)
        XCTAssertTrue(element("screen.flow-chat", app: app).waitForExistence(timeout: 3))
        return app
    }

    private func finishActualLocalOnboarding(app: XCUIApplication) {
        Self.hasAcknowledgedQAOnboarding = false
        let welcome = element("screen.onboarding.welcome", app: app)
        if !welcome.waitForExistence(timeout: 1) {
            XCTAssertTrue(
                element("screen.auth.sign-in", app: app)
                    .waitForExistence(timeout: 3)
            )
            tapVisible(app.buttons["auth.open-sign-up"], app: app)
            let email = app.textFields["auth.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 3))
            email.tap()
            email.typeText("flow-slice9@example.invalid")
            enterSecure("local-pass", in: app.secureTextFields["auth.password"])
            enterSecure(
                "local-pass",
                in: app.secureTextFields["auth.password-confirmation"]
            )
            tapVisible(app.buttons["auth.sign-up.submit"], app: app)
            XCTAssertTrue(
                element("screen.auth.email-confirmation", app: app)
                    .waitForExistence(timeout: 3)
            )
            tapVisible(app.buttons["auth.confirm-development"], app: app)
        }
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))
        let name = app.textFields["onboarding.display-name"]
        tapVisible(name, app: app)
        name.typeText("QA Flow\n")
        let next = app.buttons["onboarding.continue"]
        tapVisible(next, app: app)
        XCTAssertTrue(element("screen.onboarding.body-data", app: app).waitForExistence(timeout: 3))
        tapVisible(next, app: app)
        XCTAssertTrue(element("screen.onboarding.routine", app: app).waitForExistence(timeout: 3))
        tapVisible(next, app: app)
        XCTAssertTrue(element("screen.onboarding.persona", app: app).waitForExistence(timeout: 3))
        waitUntilEnabled(next)
        let style = app.buttons["persona.focus"]
        tapVisible(style, app: app)
        XCTAssertTrue(style.isSelected)
        tapVisible(next, app: app)
        XCTAssertTrue(element("screen.onboarding.consent", app: app).waitForExistence(timeout: 3))
        XCTAssertFalse(next.isEnabled)
        for key in ["qa_onboarding_required", "qa_onboarding_notice", "qa_onboarding_consent"] {
            let action = app.buttons["onboarding.legal-action.\(key)"]
            XCTAssertFalse(action.isSelected)
            tapVisible(action, app: app)
            XCTAssertTrue(action.isSelected)
        }
        tapVisible(next, app: app)
        XCTAssertTrue(element("screen.onboarding.objective", app: app).waitForExistence(timeout: 3))
        waitUntilEnabled(next)
        let objective = app.buttons["onboarding.objective.recomposicao"]
        tapVisible(objective, app: app)
        XCTAssertTrue(objective.isSelected)
        tapVisible(next, app: app)
        XCTAssertTrue(element("screen.onboarding.completion", app: app).waitForExistence(timeout: 3))
        XCTAssertFalse(element("screen.hoje", app: app).exists)
        tapVisible(app.buttons["onboarding.go-to-today"], app: app)
        let acknowledged = element("screen.hoje", app: app).waitForExistence(timeout: 5)
        XCTAssertTrue(acknowledged)
        if acknowledged { Self.hasAcknowledgedQAOnboarding = true }
    }

    /// Both the synthetic setup and the 4,001st character use native input,
    /// avoiding cross-process paste permission during this boundary test.
    /// No model injection, send, measurement or accessibility assertion changes.
    private func enterSyntheticMessageAcrossLimit(
        in field: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let atLimit = String(repeating: "a", count: 4_000)
        XCTAssertTrue(field.waitForExistence(timeout: 3), file: file, line: line)
        field.tap()
        XCTAssertTrue(waitForKeyboardFocus(field), file: file, line: line)
        field.typeText(atLimit)
        XCTAssertTrue(
            waitForExactComposerValue(atLimit, in: field),
            "The focused native composer must contain exactly the synthetic 4,000-character setup",
            file: file, line: line
        )
        XCTAssertTrue(app.buttons["flow.send"].isEnabled, file: file, line: line)
        XCTAssertFalse(element("flow.limit.detail", app: app).exists, file: file, line: line)
        XCTAssertTrue(waitForKeyboardFocus(field), file: file, line: line)
        field.typeText("a")
        XCTAssertTrue(
            waitForExactComposerValue(atLimit + "a", in: field),
            "One native keystroke must produce exactly 4,001 characters without trimming or losing input",
            file: file, line: line
        )
    }

    private func waitForExactComposerValue(_ expected: String, in field: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                (object as? XCUIElement)?.value as? String == expected
            },
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func enterSecure(_ text: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        XCTAssertTrue(waitForKeyboardFocus(field))
        if field.identifier == "auth.password" {
            field.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(waitForKeyboardFocus(field))
        }
        UIPasteboard.general.string = text
        defer { UIPasteboard.general.string = nil }
        field.typeKey("v", modifierFlags: .command)
        if !waitForSecureEntry(field, characterCount: text.count, timeout: 1) {
            field.typeKey("a", modifierFlags: .command)
            field.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
            for character in text {
                field.typeText(String(character))
            }
        }
        XCTAssertTrue(waitForSecureEntry(field, characterCount: text.count))
    }

    private func waitForKeyboardFocus(_ field: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

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

    private func tapVisible(_ control: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(control.exists || control.waitForExistence(timeout: 3))
        func isClearOfNavigation() -> Bool {
            let bar = app.performeTabBar
            return !bar.exists || control.frame.maxY <= bar.frame.minY
        }
        for _ in 0..<40 where !control.isHittable || !isClearOfNavigation() {
            // A partly visible action can report hittable while its center is
            // under the floating navigation. Scroll its whole target into view.
            if control.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        if !control.isHittable || !isClearOfNavigation() {
            capture("flow-setup-unreachable-\(control.identifier)", app: app)
        }
        XCTAssertTrue(control.isHittable && isClearOfNavigation(), "Unreachable native control: \(control.identifier)")
        if control.elementType == .button { waitUntilEnabled(control) }
        control.tap()
    }

    private func waitUntilEnabled(_ control: XCUIElement) {
        if control.isEnabled { return }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func finalHistoryBody(app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@",
            "QA histórico local 39. Leitura preservada, sem dados reais ou rede.")).firstMatch
    }

    private func assertRecoveryIsVisible(app: XCUIApplication, captureName: String) {
        let error = element("flow.error", app: app)
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue(error.isHittable, "The real error copy must start inside the readable viewport")
        let retry = app.buttons["flow.retry"]
        XCTAssertTrue(retry.isHittable, "The explicit recovery action must start inside the readable viewport")
        support.assertTarget(retry)
        capture(captureName, app: app)
    }

    private func reveal(_ control: XCUIElement, in history: XCUIElement) {
        // A large AX bubble's tail can be at the end while its role is above
        // the viewport. Navigate the actual native scroll in either direction.
        for _ in 0..<40 where !control.isHittable {
            let above = control.frame.midY < history.frame.midY
            let start = history.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.35 : 0.65))
            let end = history.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.65 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    /// The whole decorated surface must fit; a partially visible target can
    /// already be hittable. Drag the outer gutter, outside the field's own scroll.
    private func revealComposerSurface(_ control: XCUIElement, in scroll: XCUIElement,
                                       app: XCUIApplication, padding: CGFloat = 0) -> Bool {
        var lastGeometry = "not read"
        func valid(_ frame: CGRect) -> Bool {
            !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
                && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
        }
        for _ in 0..<40 {
            let keyboard = app.keyboards.firstMatch
            let done = app.buttons["keyboard.done"]
            guard control.exists, scroll.exists, keyboard.exists, done.exists else { break }
            let raw = control.frame
            let scroller = scroll.frame
            let window = app.windows.firstMatch.frame
            let header = app.navigationBars.firstMatch.frame
            let keyboardFrame = keyboard.frame
            let doneFrame = done.frame
            lastGeometry = "raw=\(raw); scroll=\(scroller); window=\(window); header=\(header); keyboard=\(keyboardFrame); done=\(doneFrame)"
            guard [raw, scroller, window, header, keyboardFrame, doneFrame].allSatisfy(valid),
                  keyboard.isHittable, done.isHittable else { break }
            let top = max(scroller.minY, window.minY, header.maxY)
            let bottom = min(scroller.maxY, window.maxY, keyboardFrame.minY, doneFrame.minY)
            let left = max(scroller.minX, window.minX)
            let right = min(scroller.maxX, window.maxX)
            let viewport = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            let surface = raw.insetBy(dx: -padding, dy: -padding)
            guard valid(viewport), surface.height <= viewport.height,
                  surface.minX >= viewport.minX, surface.maxX <= viewport.maxX else { break }
            if viewport.contains(surface), control.isHittable { return true }
            let movingDown = surface.minY < viewport.minY
            let missing = movingDown ? viewport.minY - surface.minY : surface.maxY - viewport.maxY
            guard missing > 0 else { break }
            let distance = min(viewport.height * 0.45, max(20, missing + 2))
            let startY = viewport.minY + viewport.height * (movingDown ? 0.25 : 0.75)
            let endY = startY + (movingDown ? distance : -distance)
            let x = viewport.minX + min(12, viewport.width / 4)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: x, dy: startY))
            let end = origin.withOffset(CGVector(dx: x, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let diagnostic = XCTAttachment(string: lastGeometry)
        diagnostic.name = "flow-composer-unreachable-\(control.identifier)-geometry"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        capture("flow-composer-unreachable-\(control.identifier)", app: app)
        XCTFail("The entire composer surface must be reachable above Done with its keyboard still open")
        return false
    }

    private func assertAXActionHasMinimumGlyphFootprint(_ action: XCUIElement, app: XCUIApplication,
                                                       captureName: String? = nil) {
        // A native minimum glyph-painting bound, NOT equality between UIKit's
        // paragraph layout and SwiftUI's line metrics. Raster inspection and
        // native keyboard/viewport containment remain independent gates.
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let scaled = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
        var descriptorTraits = scaled.fontDescriptor.object(forKey: .traits)
            as? [UIFontDescriptor.TraitKey: Any] ?? [:]
        let preferredWeight = (descriptorTraits[.weight] as? NSNumber)?.doubleValue
        descriptorTraits[.weight] = UIFont.Weight.semibold.rawValue
        let font = preferredWeight == UIFont.Weight.semibold.rawValue ? scaled
            : UIFont(descriptor: scaled.fontDescriptor.addingAttributes([.traits: descriptorTraits]),
                     size: scaled.pointSize)
        let actualTraits = font.fontDescriptor.object(forKey: .traits)
            as? [UIFontDescriptor.TraitKey: Any]
        let actualWeight = actualTraits?[.weight] as? NSNumber
        XCTAssertNotNil(actualWeight)
        if let actualWeight {
            XCTAssertEqual(actualWeight.doubleValue, UIFont.Weight.semibold.rawValue, accuracy: 0.01)
        }
        let text = NSAttributedString(string: action.label, attributes: [.font: font])
        let bounds = text.boundingRect(
            with: CGSize(width: action.frame.width - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesDeviceMetrics], context: nil)
        let typographic = text.boundingRect(
            with: CGSize(width: action.frame.width - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], context: nil)
        let withLeading = text.boundingRect(
            with: CGSize(width: action.frame.width - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let reconstructed = UIFont.systemFont(ofSize: scaled.pointSize, weight: .semibold)
        let systemBounds = NSAttributedString(string: action.label, attributes: [.font: reconstructed]).boundingRect(
            with: CGSize(width: action.frame.width - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], context: nil)
        let screenshot = XCUIScreen.main.screenshot()
        let pixelWidth = screenshot.image.cgImage.map { CGFloat($0.width) }
            ?? screenshot.image.size.width * screenshot.image.scale
        let scale = pixelWidth / app.frame.width
        let requiredHeight = ceil(bounds.height * scale) / scale + 24
        let diagnostic = "action=\(action.identifier); frame=\(action.frame); glyphBounds=\(bounds); glyphMinY=\(bounds.minY); glyphMaxY=\(bounds.maxY); typographic=\(typographic.height); withLeading=\(withLeading.height); ascender=\(font.ascender); descender=\(font.descender); leading=\(font.leading); scale=\(scale); requiredHeight=\(requiredHeight); observed68ptRedFits=\(68 + 1 >= requiredHeight); preferredName=\(scaled.fontName); preferredWeight=\(String(describing: preferredWeight)); measuredName=\(font.fontName); measuredWeight=\(String(describing: actualWeight)); pointSize=\(font.pointSize); semanticStyle=\(String(describing: font.fontDescriptor.object(forKey: .textStyle))); reconstructedName=\(reconstructed.fontName); reconstructedGlyphHeight=\(systemBounds.height)"
        print(diagnostic)
        let metrics = XCTAttachment(string: diagnostic)
        metrics.name = "flow-native-ax-action-metrics-\(action.identifier)"
        metrics.lifetime = .keepAlways
        add(metrics)
        let raster = XCTAttachment(screenshot: screenshot)
        raster.name = captureName ?? "flow-native-ax-action-\(action.identifier)"
        raster.lifetime = .keepAlways
        add(raster)
        XCTAssertGreaterThan(requiredHeight, 68 + 1,
                             "The same glyph formula must reject the preserved 68pt compression RED")
        XCTAssertGreaterThanOrEqual(action.frame.height + 1, requiredHeight,
                                    "The AX button needs at least the native glyph footprint plus DS padding")
    }

    private func assertComposerContainedAboveKeyboard(_ field: XCUIElement, action: XCUIElement,
                                                      app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        let lowerEdge = keyboard.frame.minY
        let upperEdge = app.navigationBars.firstMatch.frame.maxY
        XCTAssertGreaterThan(lowerEdge, upperEdge)
        // The native editable text rect excludes the immutable DS's 16pt
        // field background padding. Check that whole surface, not just glyphs.
        assertControlContainedAboveKeyboard(field.frame.insetBy(dx: -16, dy: -16), app: app)
        assertControlContainedAboveKeyboard(action.frame, app: app)
    }

    private func assertControlContainedAboveKeyboard(_ rectangle: CGRect, app: XCUIApplication) {
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertGreaterThanOrEqual(rectangle.minY, app.navigationBars.firstMatch.frame.maxY - 1,
                                    "The whole composer control must remain below native navigation")
        XCTAssertLessThanOrEqual(rectangle.maxY, app.keyboards.firstMatch.frame.minY + 1,
                                 "The whole composer control must remain above the actual keyboard")
        XCTAssertGreaterThanOrEqual(rectangle.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(rectangle.maxX, app.frame.maxX)
    }

    private var support: PremiumUIUXUITestSupport { .init(testCase: self) }
    private func element(_ id: String, app: XCUIApplication) -> XCUIElement {
        support.element(id, app: app)
    }
    private func capture(_ name: String, app: XCUIApplication) { support.capture(name, app: app) }
}

@MainActor
extension XCTestCase {
    /// Same bounded 250ms/8s readiness pattern used by MealCaptureUITests.
    /// AX queries are sequential; the final reread must match before assertions.
    func waitForStableComposerKeyboard(_ field: XCUIElement, action: XCUIElement,
                                               app: XCUIApplication, expectedComposer: String = "QA",
                                               requiresEnabledAction: Bool = true,
                                               requiresKeyboardAccessory: Bool = true,
                                               diagnosticName: String = "flow-composer-keyboard") -> Bool {
        func readGeometry() -> FlowComposerKeyboardGeometry? {
            let keyboard = app.keyboards.firstMatch
            let header = app.navigationBars.firstMatch
            let window = app.windows.firstMatch
            let done = app.buttons["keyboard.done"]
            let hasAccessory = done.exists
            guard keyboard.exists, header.exists, window.exists,
                  hasAccessory || !requiresKeyboardAccessory,
                  field.exists, action.exists, action.isEnabled == requiresEnabledAction,
                  field.value as? String == expectedComposer else { return nil }
            return FlowComposerKeyboardGeometry(
                field: field.frame.insetBy(dx: -16, dy: -16), action: action.frame,
                keyboard: keyboard.frame, header: header.frame, window: window.frame,
                done: hasAccessory ? done.frame : nil,
                keyboardHittable: keyboard.isHittable, fieldHittable: field.isHittable,
                actionHittable: action.isHittable, doneHittable: hasAccessory && done.isHittable,
                requiresKeyboardAccessory: requiresKeyboardAccessory
            )
        }
        func captureFailure(_ phase: String, geometry: FlowComposerKeyboardGeometry?) {
            let metrics = XCTAttachment(string: "phase=\(phase); geometry=\(String(describing: geometry))")
            metrics.name = "\(diagnosticName)-\(phase)-geometry"
            metrics.lifetime = .keepAlways
            add(metrics)
            let raster = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            raster.name = "\(diagnosticName)-\(phase)-raster"
            raster.lifetime = .keepAlways
            add(raster)
        }
        var readiness = FlowComposerKeyboardReadiness()
        var lastObservedGeometry: FlowComposerKeyboardGeometry?
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            lastObservedGeometry = readGeometry()
            return readiness.accepts(lastObservedGeometry, at: ProcessInfo.processInfo.systemUptime)
        }, object: nil)
        let result = XCTWaiter.wait(for: [settled], timeout: 8)
        if result != .completed {
            // Preserve invalid overlap frames before continueAfterFailure=false aborts.
            captureFailure("timeout", geometry: lastObservedGeometry)
        }
        XCTAssertEqual(result, .completed,
                       "Visible keyboard/composer must settle. Last geometry: \(String(describing: lastObservedGeometry))")
        guard result == .completed else { return false }
        let finalGeometry = readGeometry()
        if finalGeometry != readiness.lastGeometry || finalGeometry?.isUsable != true {
            captureFailure("changed-before-assertion", geometry: finalGeometry)
        }
        XCTAssertEqual(finalGeometry, readiness.lastGeometry, "Geometry changed before containment assertions")
        XCTAssertEqual(finalGeometry?.isUsable, true)
        guard let finalGeometry, finalGeometry == readiness.lastGeometry, finalGeometry.isUsable else { return false }
        let attachment = XCTAttachment(string: String(describing: finalGeometry))
        attachment.name = "\(diagnosticName)-settled-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        return true
    }
}

// Only this Flow UI gate uses these pure frames; no app layout is changed.
private struct FlowComposerKeyboardGeometry: Equatable {
    var field: CGRect // Whole field surface, including the existing 16pt padding.
    var action: CGRect
    var keyboard: CGRect
    var header: CGRect
    var window: CGRect
    var done: CGRect?
    var keyboardHittable: Bool
    var fieldHittable: Bool
    var actionHittable: Bool
    var doneHittable: Bool
    var requiresKeyboardAccessory = true

    var isUsable: Bool {
        let frames = [field, action, keyboard, header, window] + (done.map { [$0] } ?? [])
        guard frames.allSatisfy({ frame in
            [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy { $0.isFinite }
                && frame.width > 0 && frame.height > 0
        }), keyboardHittable, fieldHittable, actionHittable,
              window.contains(header), window.contains(keyboard),
              keyboard.minY > header.maxY else { return false }
        var lowerEdge = keyboard.minY
        if let done {
            // An optional accessory is still fully checked whenever present.
            guard doneHittable, window.contains(done), done.width >= 44, done.height >= 44,
                  done.minY >= header.maxY, done.maxY <= keyboard.minY else { return false }
            lowerEdge = min(lowerEdge, done.minY)
        } else if requiresKeyboardAccessory {
            return false
        }
        return [field, action].allSatisfy {
            $0.width >= 44 && $0.height >= 44 && window.contains($0)
                && $0.minY >= header.maxY && $0.maxY <= lowerEdge
        }
    }
}

private struct FlowComposerKeyboardReadiness {
    private(set) var lastGeometry: FlowComposerKeyboardGeometry?
    private var unchangedSince: TimeInterval?

    mutating func accepts(_ geometry: FlowComposerKeyboardGeometry?, at now: TimeInterval) -> Bool {
        guard let geometry, geometry.isUsable else {
            lastGeometry = nil
            unchangedSince = nil
            return false
        }
        guard geometry == lastGeometry, let since = unchangedSince else {
            lastGeometry = geometry
            unchangedSince = now
            return false
        }
        return now - since >= 0.25
    }
}

final class FlowComposerKeyboardReadinessTests: XCTestCase {
    func testRecordedKeyboard590To918To590RequiresANewStableInterval() {
        let visible = readyGeometry()
        var offscreen = visible
        offscreen.keyboard.origin.y = 918
        offscreen.keyboardHittable = false
        XCTAssertFalse(offscreen.isUsable)
        var gate = FlowComposerKeyboardReadiness()
        XCTAssertFalse(gate.accepts(visible, at: 0))
        XCTAssertTrue(gate.accepts(visible, at: 0.25))
        XCTAssertFalse(gate.accepts(offscreen, at: 0.30))
        XCTAssertFalse(gate.accepts(visible, at: 0.40))
        XCTAssertFalse(gate.accepts(visible, at: 0.64))
        XCTAssertTrue(gate.accepts(visible, at: 0.65))
    }

    func testRecordedStaleComposer622Point667DoesNotPassWithKeyboard590() {
        var stale = readyGeometry()
        stale.field = CGRect(x: 24, y: 526.6666666666666, width: 354, height: 96)
        stale.action = CGRect(x: 24, y: 630.6666666666666, width: 354, height: 149.33333333333337)
        XCTAssertEqual(stale.field.maxY, 622.6666666666666)
        XCTAssertFalse(stale.isUsable)
        var gate = FlowComposerKeyboardReadiness()
        XCTAssertFalse(gate.accepts(stale, at: 0))
        XCTAssertFalse(gate.accepts(stale, at: 8))
        XCTAssertFalse(gate.accepts(readyGeometry(), at: 8.1))
        XCTAssertTrue(gate.accepts(readyGeometry(), at: 8.4))
    }

    func testRecordedPreTypingDoneOverlapIsNotUsableGeometry() {
        // Observation only: this gate runs after QA is typed. This test does
        // not claim that the pre-typing product overlap has been fixed.
        var overlap = readyGeometry()
        overlap.field = CGRect(x: 24, y: 266.66666666666663, width: 354, height: 96)
        overlap.action = CGRect(x: 24, y: 370.6666666666667, width: 354, height: 149.33333333333331)
        XCTAssertEqual(overlap.action.maxY, 520)
        XCTAssertEqual(overlap.done?.minY, 500)
        XCTAssertFalse(overlap.isUsable)
    }

    func testMissingKeyboardAccessoryIsRejectedByDefault() {
        var missing = readyGeometry()
        missing.done = nil
        missing.doneHittable = false
        XCTAssertFalse(missing.isUsable)
        var gate = FlowComposerKeyboardReadiness()
        XCTAssertFalse(gate.accepts(missing, at: 0))
        XCTAssertFalse(gate.accepts(missing, at: 8))
    }

    func testExplicitBenchmarkPolicyAllowsMissingAccessoryAfterFullStableInterval() {
        var missing = readyGeometry()
        missing.done = nil
        missing.doneHittable = false
        missing.requiresKeyboardAccessory = false
        XCTAssertTrue(missing.isUsable)
        var gate = FlowComposerKeyboardReadiness()
        XCTAssertFalse(gate.accepts(missing, at: 0))
        XCTAssertFalse(gate.accepts(missing, at: 0.249))
        XCTAssertTrue(gate.accepts(missing, at: 0.25))
    }

    func testOptionalAccessoryDoesNotAllowRecordedSend758OverVisibleKeyboard590() {
        var moving = readyGeometry()
        moving.done = nil
        moving.doneHittable = false
        moving.requiresKeyboardAccessory = false
        // The failed benchmark synthesized a tap at (356, 758) while the
        // keyboard was moving. It must not be a valid target over visible keys.
        moving.action = CGRect(x: 334, y: 736, width: 44, height: 44)
        XCTAssertEqual(moving.action.midX, 356)
        XCTAssertEqual(moving.action.midY, 758)
        XCTAssertFalse(moving.isUsable)
        var gate = FlowComposerKeyboardReadiness()
        XCTAssertFalse(gate.accepts(moving, at: 0))
        XCTAssertFalse(gate.accepts(moving, at: 8))
    }

    func testOptionalAccessoryStillRequiresVisibleSoftwareKeyboard() {
        var missing = readyGeometry()
        missing.done = nil
        missing.doneHittable = false
        missing.requiresKeyboardAccessory = false
        missing.keyboardHittable = false
        XCTAssertFalse(missing.isUsable)
        missing.keyboardHittable = true
        missing.keyboard.origin.y = 918
        XCTAssertFalse(missing.isUsable)
    }

    func testOptionalButPresentAccessoryStillChecksContainmentSizeAndHittability() {
        var visible = readyGeometry()
        visible.requiresKeyboardAccessory = false
        XCTAssertTrue(visible.isUsable)
        let invalidFrames: [CGRect] = [
            CGRect(x: 331, y: 440, width: 50, height: 44), // overlaps Send
            CGRect(x: 331, y: 560, width: 50, height: 44), // overlaps keyboard
            CGRect(x: 331, y: 100, width: 50, height: 44), // overlaps navigation
            CGRect(x: 380, y: 500, width: 50, height: 44), // outside window
            CGRect(x: 331, y: 500, width: 43, height: 44),
            CGRect(x: 331, y: 500, width: 50, height: 43),
            CGRect(x: CGFloat.nan, y: 500, width: 50, height: 44),
        ]
        for frame in invalidFrames {
            var invalid = visible
            invalid.done = frame
            XCTAssertFalse(invalid.isUsable, "Present accessory must be checked: \(frame)")
        }
        visible.doneHittable = false
        XCTAssertFalse(visible.isUsable)
    }

    func testOptionalAccessoryAppearingResetsTheStableInterval() {
        var missing = readyGeometry()
        missing.done = nil
        missing.doneHittable = false
        missing.requiresKeyboardAccessory = false
        var visible = readyGeometry()
        visible.requiresKeyboardAccessory = false
        var gate = FlowComposerKeyboardReadiness()
        XCTAssertFalse(gate.accepts(missing, at: 0))
        XCTAssertTrue(gate.accepts(missing, at: 0.25))
        XCTAssertFalse(gate.accepts(visible, at: 0.30))
        XCTAssertFalse(gate.accepts(visible, at: 0.549))
        XCTAssertTrue(gate.accepts(visible, at: 0.55))
    }

    func testOptionalAccessoryDisappearingResetsTheStableInterval() {
        var visible = readyGeometry()
        visible.requiresKeyboardAccessory = false
        var missing = visible
        missing.done = nil
        missing.doneHittable = false
        var gate = FlowComposerKeyboardReadiness()
        XCTAssertFalse(gate.accepts(visible, at: 0))
        XCTAssertTrue(gate.accepts(visible, at: 0.25))
        XCTAssertFalse(gate.accepts(missing, at: 0.30))
        XCTAssertFalse(gate.accepts(missing, at: 0.549))
        XCTAssertTrue(gate.accepts(missing, at: 0.55))
    }

    private func readyGeometry() -> FlowComposerKeyboardGeometry {
        FlowComposerKeyboardGeometry(
            field: CGRect(x: 24, y: 198.66666666666666, width: 354, height: 96),
            action: CGRect(x: 24, y: 302.66666666666663, width: 354, height: 149.33333333333331),
            keyboard: CGRect(x: 0, y: 590, width: 402, height: 226),
            header: CGRect(x: 0, y: 62, width: 402, height: 54),
            window: CGRect(x: 0, y: 0, width: 402, height: 874),
            done: CGRect(x: 331, y: 500, width: 50, height: 44),
            keyboardHittable: true, fieldHittable: true,
            actionHittable: true, doneHittable: true
        )
    }
}
