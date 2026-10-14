import CoreGraphics
import Foundation
import XCTest

/// Actual existing Profile replay, with C11's real opt-in SourceON/OFF
/// fixture. No tutorial body clone, invented facts, new app flag or authority.
/// Four XCTest methods, each with two language launches: eight planned cases.
final class ConfirmedMealTutorialUIReachabilityTests: XCTestCase {
    @MainActor private var support: PremiumUIUXUITestSupport { .init(testCase: self) }
    private enum Failure: Error { case missingElement, ambiguousScrollView, invalidViewport }
    private enum Language: CaseIterable {
        case portuguese, english
        var launch: String { self == .portuguese ? "pt-BR" : "en-US" }
        func position(_ index: Int) -> String {
            self == .portuguese ? "Etapa \(index) de 8" : "Step \(index) of 8"
        }
        var confirmedMealCopy: String {
            self == .portuguese
                ? "Em Hoje, abra o Histórico e escolha uma refeição confirmada. Se o registro permitir alterações, corrija um alimento por vez e revise antes de salvar. Para apagar, selecione os itens e confirme. Registros somente para consulta não oferecem essas ações."
                : "In Today, open History and choose a confirmed meal. If the record allows changes, correct one food item at a time and review before saving. To delete, select items and confirm. View-only records do not offer these actions."
        }
    }

    /// Global-actor ownership makes the async XCTest teardown capture
    /// sendable; no unsafe XCUIApplication transfer or detached cleanup.
    @MainActor private final class AppTermination {
        private var app: XCUIApplication?
        init(_ app: XCUIApplication) { self.app = app }
        func terminate() {
            let original = app
            app = nil
            original?.terminate()
        }
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testTextualTodayReadySourceExplainsConfirmedMealInBothLanguagesAXXXL() throws {
        for language in Language.allCases { try checkText(language: language, sourceOn: true) }
    }

    @MainActor
    func testTextualTodaySourceOFFPreservesReadOnlyExplanationInBothLanguagesAXXXL() throws {
        for language in Language.allCases { try checkText(language: language, sourceOn: false) }
    }

    @MainActor
    func testSpotlightTrailReadySourceExplainsConfirmedMealInBothLanguagesAXXXL() throws {
        for language in Language.allCases { try checkTrail(language: language, sourceOn: true) }
    }

    @MainActor
    func testSpotlightTrailSourceOFFPreservesExistingTrailInBothLanguagesAXXXL() throws {
        for language in Language.allCases { try checkTrail(language: language, sourceOn: false) }
    }

    @MainActor
    private func checkText(language: Language, sourceOn: Bool) throws {
        let launched = try launch(language: language, sourceOn: sourceOn, textual: true)
        let app = launched.app
        defer { launched.termination.terminate() }
        try openProfileReplay(app)
        let welcome = try required("tutorial.step.welcome", app: app)
        XCTAssertFalse(app.buttons["tutorial.later"].exists, "Profile replay preserves its Close-only entry")
        XCTAssertTrue(welcome.isHittable)
        let start = try requiredButton("tutorial.start", app: app)
        try assertActions(["tutorial.start"], app: app)
        try assertActions(["tutorial.close"], app: app)
        start.tap()
        let title = try required("tutorial.step.today", app: app)
        let position = try required("tutorial.position", app: app)
        XCTAssertEqual(position.label, language.position(2))
        let screen = try required("screen.tutorial", app: app)
        let viewport = try uniqueScroll(in: screen)
        try assertEntry(title: title, position: position, viewport: viewport, app: app)
        let actionIDs = ["tutorial.back", "tutorial.next"]
        try assertActions(actionIDs, app: app)
        try assertActions(["tutorial.close"], app: app)
        let identifier = "tutorial.line.tutorial.history.confirmed-meal-editing"
        if sourceOn {
            // Query by short identifier only: the approved paragraph label
            // exceeds XCTest's String-identifier128 limit.
            let line = try required(identifier, app: app)
            XCTAssertEqual(line.label, language.confirmedMealCopy)
            try reachWholeTextInReadingArea(line, viewport: viewport, actionIDs: actionIDs,
                maxSwipes: 12, receipt: "text-" + language.launch + "-on", app: app)
        } else {
            XCTAssertFalse(support.element(identifier, app: app).exists)
            let existing = try required("tutorial.line.tutorial.today.details", app: app)
            XCTAssertFalse(existing.label.isEmpty, "OFF must mount the actual current Today explanation")
            try reachWholeTextInReadingArea(existing, viewport: viewport, actionIDs: actionIDs,
                maxSwipes: 12, receipt: "text-" + language.launch + "-off", app: app)
        }
        try assertActions(actionIDs, app: app)
        // Exercise actual preserved footer callbacks after the long paragraph.
        app.buttons["tutorial.next"].tap()
        _ = try required("tutorial.step.flow", app: app)
        XCTAssertEqual(try required("tutorial.position", app: app).label, language.position(3))
        app.buttons["tutorial.back"].tap()
        _ = try required("tutorial.step.today", app: app)
        XCTAssertEqual(try required("tutorial.position", app: app).label, language.position(2))
        XCTAssertEqual(support.element(identifier, app: app).exists, sourceOn)
        try assertActions(actionIDs, app: app)
        try assertActions(["tutorial.close"], app: app)
        try requiredButton("tutorial.close", app: app).tap()
        _ = try required("screen.perfil", app: app)
        XCTAssertFalse(support.element("screen.tutorial", app: app).exists)
        try assertCounts(sourceOn: sourceOn, app: app)
        assertNoRecordActionOpened(app)
        support.capture("c11-tutorial-text-" + language.launch + (sourceOn ? "-on" : "-off") + "-returned-profile", app: app)
    }

    @MainActor
    private func checkTrail(language: Language, sourceOn: Bool) throws {
        let launched = try launch(language: language, sourceOn: sourceOn, textual: false)
        let app = launched.app
        defer { launched.termination.terminate() }
        try openProfileReplay(app)
        _ = try required("tour.step.welcome", app: app)
        XCTAssertEqual(try required("tour.position", app: app).label, language.position(1))
        XCTAssertFalse(app.buttons["tour.later"].exists)
        try assertActions(["tour.close", "tour.start"], app: app)
        app.buttons["tour.start"].tap()
        // All original eight IDs/order are traversed through real controls.
        for (index, step) in ["flow", "library", "register", "plan", "progress", "profile", "trail"].enumerated() {
            _ = try required("tour.step." + step, app: app)
            XCTAssertEqual(try required("tour.position", app: app).label, language.position(index + 2))
            if step != "trail" {
                try assertActions(["tour.skip", "tour.back", "tour.next"], app: app)
                app.buttons["tour.next"].tap()
            }
        }
        let title = try required("tour.step.trail", app: app)
        let position = try required("tour.position", app: app)
        let callout = try required("tour.callout", app: app)
        let viewport = try uniqueScroll(in: callout)
        try assertEntry(title: title, position: position, viewport: viewport, app: app)
        let actionIDs = ["tour.skip", "tour.back", "tour.finish"]
        try assertActions(actionIDs, app: app)
        let identifier = "tour.additional.trail"
        if sourceOn {
            let line = try required(identifier, app: app)
            XCTAssertEqual(line.label, language.confirmedMealCopy)
            try reachWholeTextByScrolling(line, viewport: viewport, actionIDs: actionIDs,
                maxSwipes: 8, receipt: "trail-" + language.launch + "-on", app: app)
        } else {
            XCTAssertFalse(support.element(identifier, app: app).exists)
            _ = try required("tour.trail.diagram", app: app)
            let body = try required("tour.body.trail", app: app)
            XCTAssertFalse(body.label.isEmpty, "OFF keeps its actual trail body and diagram")
            try reachWholeTextByScrolling(body, viewport: viewport, actionIDs: actionIDs,
                maxSwipes: 8, receipt: "trail-" + language.launch + "-off", app: app)
        }
        try assertActions(actionIDs, app: app)
        app.buttons["tour.back"].tap()
        _ = try required("tour.step.profile", app: app)
        XCTAssertEqual(try required("tour.position", app: app).label, language.position(7))
        app.buttons["tour.next"].tap()
        _ = try required("tour.step.trail", app: app)
        XCTAssertEqual(try required("tour.position", app: app).label, language.position(8))
        XCTAssertEqual(support.element(identifier, app: app).exists, sourceOn)
        try assertActions(actionIDs, app: app)
        app.buttons["tour.finish"].tap()
        _ = try required("screen.perfil", app: app)
        XCTAssertFalse(support.element("tour.overlay", app: app).exists)
        try assertCounts(sourceOn: sourceOn, app: app)
        assertNoRecordActionOpened(app)
        support.capture("c11-tutorial-trail-" + language.launch + (sourceOn ? "-on" : "-off") + "-finished-profile", app: app)
    }

    @MainActor
    private func launch(language: Language, sourceOn: Bool, textual: Bool) throws -> (app: XCUIApplication, termination: AppTermination) {
        var arguments = ["--ui-testing", sourceOn
            ? "--ui-testing-c11-root-source-on" : "--ui-testing-c11-root-source-off"]
        if textual { arguments.append("--ui-testing-tutorial-text") }
        let app = support.launch(arguments: arguments, language: language.launch, dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL")
        let termination = AppTermination(app)
        // Guaranteed on XCTest interruption as well as explicit Swift errors;
        // normal defer clears this exact app before a second language launch.
        addTeardownBlock { await termination.terminate() }
        do {
            _ = try required("screen.hoje", app: app, timeout: 10)
            // This packet claims the current402point portrait native window;
            // no320point render, compact hardware or landscape claim.
            XCTAssertTrue(valid(app.frame))
            XCTAssertEqual(app.frame.width, 402, accuracy: 0.5,
                "SETUP: this matrix is only the current402point simulator viewport")
            guard valid(app.frame), abs(app.frame.width - 402) <= 0.5 else { throw Failure.invalidViewport }
            XCTAssertFalse(support.element("screen.tutorial", app: app).exists)
            XCTAssertFalse(support.element("tour.overlay", app: app).exists)
            try assertCounts(sourceOn: sourceOn, app: app)
            return (app, termination)
        } catch { termination.terminate(); throw error }
    }

    @MainActor
    private func openProfileReplay(_ app: XCUIApplication) throws {
        try requiredButton("tab.perfil", app: app).tap()
        _ = try required("screen.perfil", app: app)
        let replay = support.element("profile.tutorial", app: app)
        for _ in 0..<12 {
            if replay.exists && replay.isHittable { break }
            app.swipeUp() // Existing Profile replay recipe, before any modal.
        }
        XCTAssertTrue(replay.exists && replay.isHittable,
            "SETUP: actual Profile replay must be available without adding a fixture capability")
        guard replay.exists && replay.isHittable else { throw Failure.missingElement }
        support.assertTarget(replay)
        replay.tap()
    }

    @MainActor
    private func assertCounts(sourceOn: Bool, app: XCUIApplication) throws {
        let status = try required("c11.fixture.status", app: app)
        let expected = sourceOn ? "C11 on: get=0 bind=1 refresh=0 blocked=0"
            : "C11 off: get=0 bind=0 refresh=0 blocked=0"
        let reached = expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: status)
        wait(for: [reached], timeout: 5)
        XCTAssertEqual(status.label, expected)
        // Current diagnostic has no mutation/key count. Do not claim those
        // counters; fixture handler policy is a separate source safeguard.
    }

    @MainActor
    private func required(_ id: String, app: XCUIApplication, timeout: TimeInterval = 5) throws -> XCUIElement {
        let node = support.element(id, app: app)
        XCTAssertTrue(node.waitForExistence(timeout: timeout), "Missing actual View element: " + id)
        guard node.exists else { throw Failure.missingElement }
        return node
    }

    @MainActor
    private func requiredButton(_ id: String, app: XCUIApplication) throws -> XCUIElement {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        guard button.exists else { throw Failure.missingElement }
        return button
    }

    @MainActor
    private func uniqueScroll(in container: XCUIElement) throws -> XCUIElement {
        let query = container.descendants(matching: .scrollView)
        XCTAssertEqual(query.count, 1, "SETUP: select actual tutorial/callout ScrollView, not underlying Profile/Today")
        guard query.count == 1 else { throw Failure.ambiguousScrollView }
        let viewport = query.element(boundBy: 0)
        XCTAssertTrue(valid(viewport.frame))
        guard valid(viewport.frame) else { throw Failure.invalidViewport }
        return viewport
    }

    @MainActor
    private func assertEntry(title: XCUIElement, position: XCUIElement, viewport: XCUIElement, app: XCUIApplication) throws {
        XCTAssertTrue(valid(title.frame) && valid(position.frame))
        XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(title.frame), "Whole fresh-step heading before any gesture")
        XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(position.frame))
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(title.frame))
        XCTAssertTrue(title.isHittable && position.isHittable)
    }

    @MainActor
    private func assertActions(_ ids: [String], app: XCUIApplication) throws {
        for id in ids {
            let button = try requiredButton(id, app: app)
            XCTAssertTrue(valid(button.frame) && button.isHittable, id)
            support.assertTarget(button)
            XCTAssertTrue(app.frame.contains(button.frame), "Full pinned action frame outside native viewport: " + id)
        }
    }

    @MainActor
    private func actionTop(_ ids: [String], app: XCUIApplication) throws -> CGFloat {
        try XCTUnwrap(ids.map { try requiredButton($0, app: app).frame.minY }.min())
    }

    @MainActor
    private func reachWholeTextByScrolling(_ node: XCUIElement, viewport: XCUIElement,
        actionIDs: [String], maxSwipes: Int, receipt: String, app: XCUIApplication) throws {
        var swipes = 0
        let originalLabel = node.label
        func topVisible() throws -> Bool {
            let f = node.frame, v = viewport.frame, top = try actionTop(actionIDs, app: app)
            return valid(f) && valid(v) && node.isHittable && f.minY >= v.minY - 1
                && f.minY <= min(v.maxY, top) + 1
        }
        while !(try topVisible()) && swipes < maxSwipes {
            if valid(node.frame), node.frame.minY < viewport.frame.minY { viewport.swipeDown() }
            else { viewport.swipeUp() }
            swipes += 1
        }
        XCTAssertTrue(try topVisible(), "The actual paragraph START must be reachable")
        guard try topVisible() else { throw Failure.invalidViewport }
        let fullHeight = node.frame.height
        XCTAssertGreaterThanOrEqual(node.frame.minX, viewport.frame.minX - 1)
        XCTAssertLessThanOrEqual(node.frame.maxX, viewport.frame.maxX + 1)
        try geometry(receipt + "-start", node: node, viewport: viewport,
            actionTop: try actionTop(actionIDs, app: app), swipes: swipes, app: app)
        support.capture("c11-tutorial-" + receipt + "-start", app: app)
        func endVisible() throws -> Bool {
            let f = node.frame, v = viewport.frame, top = try actionTop(actionIDs, app: app)
            return valid(f) && valid(v) && node.isHittable && f.maxY >= v.minY - 1
                && f.maxY <= v.maxY + 1 && f.maxY <= top + 1 && f.maxY <= app.frame.maxY + 1
        }
        while !(try endVisible()) && swipes < maxSwipes { viewport.swipeUp(); swipes += 1 }
        XCTAssertTrue(try endVisible(), "The entire actual paragraph END must be reachable above ALL pinned actions")
        XCTAssertEqual(node.label, originalLabel, "Scrolling preserves the entire original spoken paragraph")
        XCTAssertGreaterThanOrEqual(node.frame.minX, viewport.frame.minX - 1)
        XCTAssertLessThanOrEqual(node.frame.maxX, viewport.frame.maxX + 1)
        XCTAssertEqual(node.frame.height, fullHeight, accuracy: 1,
            "Scrolling must not replace the full label/frame with a clipped subset")
        // Same semantic oracle as existing LongCopy: large paragraphs may
        // need several scroll positions; a paragraph that fits must also
        // fit as one complete rect. Never pretend the tall one fits at once.
        if node.frame.height <= viewport.frame.height + 1 {
            XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(node.frame))
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(node.frame))
        }
        XCTAssertLessThanOrEqual(swipes, maxSwipes)
        try assertActions(actionIDs, app: app)
        try geometry(receipt + "-end", node: node, viewport: viewport,
            actionTop: try actionTop(actionIDs, app: app), swipes: swipes, app: app)
        support.capture("c11-tutorial-" + receipt + "-end", app: app)
    }

    /// Textual ScrollView's AX frame includes the native navigation and
    /// opaque pinned footer. Measure the actual reading interval instead.
    /// Source contract: GuidedTutorialView.actions has vertical sm padding12.
    /// This is an observer of the current source, not a cloned View layout.
    @MainActor
    private func textualReadingRect(viewport: XCUIElement, actionIDs: [String],
        app: XCUIApplication) throws -> CGRect {
        let bars = app.navigationBars.containing(.button, identifier: "tutorial.close")
        XCTAssertEqual(bars.count, 1, "SETUP: select actual tutorial navigation by its Close button")
        guard bars.count == 1 else { throw Failure.invalidViewport }
        let navigation = bars.element(boundBy: 0).frame
        let raw = viewport.frame, window = app.frame
        let footerPadding: CGFloat = 12 // BodyFlowSpacing.sm, pinned in the proposal proof.
        let footerTop = try actionTop(actionIDs, app: app) - footerPadding
        guard valid(navigation), valid(raw), valid(window), footerTop.isFinite else {
            XCTFail("SETUP: finite actual navigation, scroll, window and footer geometry")
            throw Failure.invalidViewport
        }
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(navigation))
        XCTAssertGreaterThan(footerTop, navigation.maxY)
        XCTAssertLessThanOrEqual(footerTop, min(raw.maxY, window.maxY) + 1)
        let visible = raw.intersection(window)
        let top = max(visible.minY, navigation.maxY)
        let bottom = min(visible.maxY, footerTop)
        let reading = CGRect(x: visible.minX, y: top, width: visible.width, height: bottom - top)
        XCTAssertTrue(valid(reading), "SETUP: real unobscured textual reading area must exist")
        guard valid(reading), window.insetBy(dx: -1, dy: -1).contains(navigation),
            footerTop <= min(raw.maxY, window.maxY) + 1 else { throw Failure.invalidViewport }
        return reading
    }

    @MainActor
    private func reachWholeTextInReadingArea(_ node: XCUIElement, viewport: XCUIElement,
        actionIDs: [String], maxSwipes: Int, receipt: String, app: XCUIApplication) throws {
        let reading = try textualReadingRect(viewport: viewport, actionIDs: actionIDs, app: app)
        var swipes = 0
        let originalLabel = node.label
        func topVisible() -> Bool {
            let f = node.frame
            return valid(f) && node.isHittable && f.minY >= reading.minY - 1
                && f.minY < reading.maxY - 1
        }
        while !topVisible() && swipes < maxSwipes {
            if valid(node.frame), node.frame.minY < reading.minY { viewport.swipeDown() }
            else { viewport.swipeUp() }
            swipes += 1
        }
        XCTAssertTrue(topVisible(), "The actual paragraph START must be reachable below navigation and above the opaque footer")
        guard topVisible() else { throw Failure.invalidViewport }
        let fullHeight = node.frame.height
        XCTAssertGreaterThanOrEqual(node.frame.minX, reading.minX - 1)
        XCTAssertLessThanOrEqual(node.frame.maxX, reading.maxX + 1)
        try textReadingGeometry(receipt + "-start", node: node, viewport: viewport,
            reading: reading, actionIDs: actionIDs, swipes: swipes, app: app)
        support.capture("c11-tutorial-" + receipt + "-start", app: app)
        func endVisible() -> Bool {
            let f = node.frame
            return valid(f) && node.isHittable && f.maxY > reading.minY + 1
                && f.maxY <= reading.maxY + 1 && f.maxY <= app.frame.maxY + 1
        }
        while !endVisible() && swipes < maxSwipes { viewport.swipeUp(); swipes += 1 }
        XCTAssertTrue(endVisible(), "The entire actual paragraph END must be reachable above the opaque pinned footer")
        XCTAssertEqual(node.label, originalLabel, "Scrolling preserves the entire original spoken paragraph")
        XCTAssertGreaterThanOrEqual(node.frame.minX, reading.minX - 1)
        XCTAssertLessThanOrEqual(node.frame.maxX, reading.maxX + 1)
        XCTAssertEqual(node.frame.height, fullHeight, accuracy: 1,
            "Scrolling must not replace the full label/frame with a clipped subset")
        // A tall paragraph requires multiple positions. Only one that fits
        // the real reading interval must be simultaneously wholly visible.
        if node.frame.height <= reading.height + 1 {
            // A normal END swipe can overshoot the START even when the
            // whole paragraph fits. Reposition with the same TOTAL cap.
            while !reading.insetBy(dx: -1, dy: -1).contains(node.frame) && swipes < maxSwipes {
                if valid(node.frame), node.frame.minY < reading.minY { viewport.swipeDown() }
                else { viewport.swipeUp() }
                swipes += 1
            }
            XCTAssertTrue(topVisible())
            XCTAssertTrue(endVisible())
            XCTAssertTrue(reading.insetBy(dx: -1, dy: -1).contains(node.frame))
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(node.frame))
        }
        XCTAssertLessThanOrEqual(swipes, maxSwipes)
        try assertActions(actionIDs, app: app)
        let finalReading = try textualReadingRect(viewport: viewport, actionIDs: actionIDs, app: app)
        XCTAssertEqual(finalReading.minX, reading.minX, accuracy: 1)
        XCTAssertEqual(finalReading.minY, reading.minY, accuracy: 1)
        XCTAssertEqual(finalReading.width, reading.width, accuracy: 1)
        XCTAssertEqual(finalReading.height, reading.height, accuracy: 1,
            "Scrolling must preserve the measured native navigation/footer interval")
        try textReadingGeometry(receipt + "-end", node: node, viewport: viewport,
            reading: finalReading, actionIDs: actionIDs, swipes: swipes, app: app)
        support.capture("c11-tutorial-" + receipt + "-end", app: app)
    }

    @MainActor
    private func textReadingGeometry(_ name: String, node: XCUIElement, viewport: XCUIElement,
        reading: CGRect, actionIDs: [String], swipes: Int, app: XCUIApplication) throws {
        func rect(_ f: CGRect) -> [String: Double] {
            ["x": Double(f.minX), "y": Double(f.minY), "width": Double(f.width), "height": Double(f.height)]
        }
        guard valid(node.frame), valid(viewport.frame), valid(reading), valid(app.frame) else {
            XCTFail("SETUP: safe finite actual textual geometry required before JSON receipt")
            throw Failure.invalidViewport
        }
        let record: [String: Any] = ["node": rect(node.frame), "viewport": rect(viewport.frame),
            "readable": rect(reading), "window": rect(app.frame),
            "navigationBottom": Double(reading.minY),
            "opaqueFooterTop": Double(reading.maxY), "sourceFooterPadding": 12,
            "actionTop": Double(try actionTop(actionIDs, app: app)), "swipes": swipes,
            "hittable": node.isHittable,
            "paragraphTallerThanReadableArea": node.frame.height > reading.height + 1]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "c11-tutorial-geometry-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func valid(_ f: CGRect) -> Bool {
        f.minX.isFinite && f.minY.isFinite && f.width.isFinite && f.height.isFinite && f.width > 0 && f.height > 0
    }

    @MainActor
    private func geometry(_ name: String, node: XCUIElement, viewport: XCUIElement,
        actionTop: CGFloat, swipes: Int, app: XCUIApplication) throws {
        func rect(_ f: CGRect) -> [String: Double] {
            ["x": Double(f.minX), "y": Double(f.minY), "width": Double(f.width), "height": Double(f.height)]
        }
        guard valid(node.frame), valid(viewport.frame), valid(app.frame), actionTop.isFinite else {
            XCTFail("SETUP: safe finite geometry required before JSON receipt")
            throw Failure.invalidViewport
        }
        let record: [String: Any] = ["node": rect(node.frame), "viewport": rect(viewport.frame),
            "window": rect(app.frame), "actionTop": Double(actionTop), "swipes": swipes,
            "hittable": node.isHittable, "paragraphTallerThanViewport": node.frame.height > viewport.frame.height + 1]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "c11-tutorial-geometry-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func assertNoRecordActionOpened(_ app: XCUIApplication) {
        for id in ["screen.meal-record", "screen.flow-chat", "sheet.fechar"] {
            XCTAssertFalse(support.element(id, app: app).exists, "Tutorial explanation must not open a data action: " + id)
        }
    }
}
