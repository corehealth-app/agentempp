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
        app.buttons["flow.send"].tap()
        let outbox = element("flow.outbox", app: app)
        XCTAssertTrue(outbox.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Mensagem A"].exists)
        XCTAssertNotEqual(composer.value as? String, "Mensagem A")
        composer.tap()
        composer.typeText("Rascunho B")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.performeTabBar.exists, "The custom navigation must not form a second bar above the composer")
        XCTAssertTrue(app.buttons["flow.cancel"].isHittable)
        app.buttons["flow.cancel"].tap()
        XCTAssertTrue(element("flow.error", app: app).waitForExistence(timeout: 3))
        XCTAssertEqual(composer.value as? String, "Rascunho B")
        XCTAssertTrue(outbox.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "QA_REPLY_VISIBLE")).firstMatch.exists)
        capture("flow-outbox-local-cancel-keeps-new-composer", app: app)
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
        if adaptive.exists { reveal(field, in: adaptive) }
        XCTAssertTrue(field.isHittable, "The real AX input must remain reachable with its keyboard and limit feedback")
        assertControlContainedAboveKeyboard(field.frame.insetBy(dx: -16, dy: -16), app: app)
        if adaptive.exists { reveal(send, in: adaptive) }
        XCTAssertTrue(send.isHittable, "The disabled Send still needs a fully reachable native presentation")
        assertAXActionHasMinimumGlyphFootprint(send, app: app)
        assertControlContainedAboveKeyboard(send.frame, app: app)
        capture("flow-ax-limit-native-send-reachable", app: app)
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
        app.buttons["flow.send"].tap()
        let rectangle = history.frame
        let historicRole = app.staticTexts["flow.role.qa-seed-35"]
        let beforeY = historicRole.frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: rectangle.midX, dy: rectangle.minY + rectangle.height * 0.25))
        let end = origin.withOffset(CGVector(dx: rectangle.midX, dy: rectangle.minY + rectangle.height * 0.5))
        XCTAssertTrue(app.buttons["flow.cancel"].exists, "The response must still be pending before the native reader gesture")
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 3)
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
        XCTAssertTrue(element("screen.onboarding.objective", app: app).waitForExistence(timeout: 3))
        waitUntilEnabled(next)
        let objective = app.buttons["onboarding.objective.recomposicao"]
        tapVisible(objective, app: app)
        XCTAssertTrue(objective.isSelected)
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
