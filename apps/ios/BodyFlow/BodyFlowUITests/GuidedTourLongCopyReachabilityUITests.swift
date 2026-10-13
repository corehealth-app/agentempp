import CoreGraphics
import Foundation
import XCTest

/// Current visual tutorial only. No product IDs/hooks, auth, provider or data
/// writes. Geometry plus synthetic screenshots; not physical VoiceOver proof.
@MainActor
final class GuidedTourLongCopyReachabilityUITests: XCTestCase {
    private var support: PremiumUIUXUITestSupport { .init(testCase: self) }
    private let eligible = ["--ui-testing", "--ui-testing-tutorial-eligible"]
    private enum HarnessFailure: Error { case missingElement, ambiguousScrollView, invalidViewport, unexpectedAlert }

    func testPortugueseAXXXLLongCopyEndsAndEntryHeadingsStayReachable() throws {
        try check(language: "pt-BR")
    }

    func testEnglishAXXXLLongCopyEndsAndEntryHeadingsStayReachable() throws {
        try check(language: "en-US")
    }

    private func check(language: String) throws {
        continueAfterFailure = false
        let app = support.launch(arguments: eligible, language: language, dark: false,
            category: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        _ = try required("tour.step.welcome", app: app, timeout: 10)
        try assertEntry("welcome", index: 1, language: language, app: app)
        try assertActions(["tour.later", "tour.start"], app: app)
        app.buttons["tour.start"].tap()
        let ids = ["flow", "library", "register", "plan", "progress", "profile", "trail"]
        let targets = ["flow": "today.flow-chat", "library": "today.library",
            "register": "tab.registrar", "plan": "tab.plano",
            "progress": "tab.progresso", "profile": "tab.perfil"]
        for (index, step) in ids.enumerated() {
            // BEFORE any gesture in the new step. In particular Flow is
            // scrolled to its end before Next opens Library on the SAME tour.
            try assertEntry(step, index: index + 2, language: language, app: app)
            let actionIDs = ["tour.skip", "tour.back", step == "trail" ? "tour.finish" : "tour.next"]
            try assertActions(actionIDs, app: app)
            if let target = targets[step] { try assertCalloutClearOf(target, app: app) }
            try assertNoActionOpened(app)
            if ["flow", "register", "trail"].contains(step) {
                var swipes = 0 // MAX8 total for this step, including trail caption.
                let body = try required("tour.body." + step, app: app)
                XCTAssertTrue(body.label.hasSuffix(expectedLastSentence(step, language: language)))
                let viewport = try scrollView(app)
                try scrollEnd(of: body, inside: viewport, actionIDs: actionIDs,
                    step: step, phase: "body-end", swipes: &swipes, app: app, fullNode: false)
                XCTAssertTrue(body.isHittable)
                captureScreenshot("tour-" + language + "-axxxl-" + step + "-body-end", app: app)
                if step == "trail" {
                    let expected = language == "pt-BR"
                        ? "O Plano é o seu protocolo: treino e alimentação atuais."
                        : "Plan is your protocol: your current workout and nutrition."
                    // Predicate avoids the SDK string-identifier length limit.
                    let matches = viewport.descendants(matching: .staticText)
                        .matching(NSPredicate(format: "label == %@", expected))
                    XCTAssertEqual(matches.count, 1, "One actual current-only final caption")
                    guard matches.count == 1 else { throw HarnessFailure.missingElement }
                    let caption = matches.element(boundBy: 0)
                    XCTAssertEqual(caption.label, expected)
                    try scrollEnd(of: caption, inside: viewport, actionIDs: actionIDs,
                        step: step, phase: "caption-end", swipes: &swipes, app: app, fullNode: true)
                    XCTAssertTrue(caption.isHittable)
                    captureScreenshot("tour-" + language + "-axxxl-trail-final-caption", app: app)
                }
                XCTAssertLessThanOrEqual(swipes, 8)
                try assertActions(actionIDs, app: app)
                if let target = targets[step] { try assertCalloutClearOf(target, app: app) }
                try assertNoActionOpened(app)
            }
            if step == "trail" {
                app.buttons["tour.finish"].tap()
            } else {
                app.buttons["tour.next"].tap()
            }
        }
        XCTAssertFalse(support.element("tour.overlay", app: app).waitForExistence(timeout: 2))
        XCTAssertTrue(support.element("screen.hoje", app: app).waitForExistence(timeout: 5))
        try assertNoActionOpened(app)
    }

    private func assertEntry(_ step: String, index: Int, language: String,
                             app: XCUIApplication) throws {
        let title = try required("tour.step." + step, app: app)
        let position = try required("tour.position", app: app)
        let viewport = try scrollView(app)
        XCTAssertEqual(position.label, language == "pt-BR"
            ? "Etapa \(index) de 8" : "Step \(index) of 8")
        try geometryReceipt(step: step, phase: "entry-before-gesture", node: title,
            viewport: viewport, actionTop: nil, app: app)
        XCTAssertTrue(valid(title.frame) && valid(position.frame))
        XCTAssertLessThanOrEqual(title.frame.height, viewport.frame.height + 1,
            "Oversized heading bounds: separate from retained scroll offset")
        XCTAssertLessThanOrEqual(position.frame.height, viewport.frame.height + 1)
        XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(title.frame),
            "New semantic step must show its WHOLE first title before any gesture")
        XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(position.frame),
            "New semantic step must show its WHOLE position before any gesture")
        XCTAssertTrue(title.isHittable && position.isHittable)
    }

    private func scrollEnd(of node: XCUIElement, inside viewport: XCUIElement,
                           actionIDs: [String], step: String, phase: String,
                           swipes: inout Int, app: XCUIApplication, fullNode: Bool) throws {
        func reached() throws -> Bool {
            let top = try actionTop(actionIDs, app: app)
            let f = node.frame, v = viewport.frame
            guard valid(f), valid(v), node.isHittable else { return false }
            let bottomVisible = f.maxY >= v.minY - 1 && f.maxY <= v.maxY + 1
                && f.maxY <= top + 1 && f.maxY <= app.frame.maxY + 1
            return bottomVisible && (!fullNode || v.insetBy(dx: -1, dy: -1).contains(f))
        }
        while !(try reached()) && swipes < 8 {
            // Gesture targets ONLY the callout's actual, unique ScrollView.
            viewport.swipeUp()
            swipes += 1
        }
        let top = try actionTop(actionIDs, app: app)
        try geometryReceipt(step: step, phase: phase, node: node,
            viewport: viewport, actionTop: top, app: app)
        XCTAssertTrue(valid(node.frame))
        XCTAssertGreaterThanOrEqual(node.frame.maxY, viewport.frame.minY - 1)
        XCTAssertLessThanOrEqual(node.frame.maxY, viewport.frame.maxY + 1,
            "The actual text end must be in its ScrollView viewport after at most8swipes")
        XCTAssertLessThanOrEqual(node.frame.maxY, top + 1,
            "The end must be above ALL pinned actions, not merely above Next")
        XCTAssertLessThanOrEqual(node.frame.maxY, app.frame.maxY + 1)
        if fullNode {
            XCTAssertLessThanOrEqual(node.frame.height, viewport.frame.height + 1,
                "Oversized final caption cannot be mistaken for a retained offset")
            XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(node.frame),
                "The entire final caption must be visible, not just its bottom")
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(node.frame))
        }
    }

    private func assertActions(_ ids: [String], app: XCUIApplication) throws {
        for id in ids {
            let button = try required(id, app: app)
            XCTAssertTrue(button.isHittable)
            support.assertTarget(button)
            XCTAssertTrue(app.frame.contains(button.frame), "Pinned action outside actual window")
        }
    }

    private func actionTop(_ ids: [String], app: XCUIApplication) throws -> CGFloat {
        var tops: [CGFloat] = []
        for id in ids { tops.append(try required(id, app: app).frame.minY) }
        return try XCTUnwrap(tops.min())
    }

    private func scrollView(_ app: XCUIApplication) throws -> XCUIElement {
        let callout = try required("tour.callout", app: app)
        let matches = callout.descendants(matching: .scrollView)
        XCTAssertEqual(matches.count, 1, "Select the callout ScrollView, never an underlying Today scroll")
        guard matches.count == 1 else { throw HarnessFailure.ambiguousScrollView }
        let scroll = matches.element(boundBy: 0)
        XCTAssertTrue(valid(scroll.frame))
        guard valid(scroll.frame) else { throw HarnessFailure.invalidViewport }
        return scroll
    }

    private func required(_ id: String, app: XCUIApplication,
                          timeout: TimeInterval = 5) throws -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: id)
        XCTAssertTrue(query.element(boundBy: 0).waitForExistence(timeout: timeout), id)
        XCTAssertEqual(query.count, 1, "Expected one known tutorial node: " + id)
        guard query.count == 1 else { throw HarnessFailure.missingElement }
        return query.element(boundBy: 0)
    }

    private func assertCalloutClearOf(_ id: String, app: XCUIApplication) throws {
        let callout = try required("tour.callout", app: app)
        let target = support.element(id, app: app)
        XCTAssertTrue(target.exists)
        XCTAssertFalse(callout.frame.intersects(target.frame))
        XCTAssertTrue(app.frame.contains(callout.frame))
        XCTAssertTrue(app.frame.contains(target.frame))
        let bar = app.otherElements["navigation.tab-bar"].firstMatch
        if bar.exists, !bar.frame.contains(target.frame) {
            XCTAssertLessThanOrEqual(target.frame.maxY, bar.frame.minY + 0.5)
        }
    }

    private func assertNoActionOpened(_ app: XCUIApplication) throws {
        XCTAssertFalse(support.element("sheet.fechar", app: app).exists)
        XCTAssertFalse(support.element("screen.flow-chat", app: app).exists)
        let alerts = app.alerts
        let count = alerts.count
        let callout = support.element("tour.callout", app: app)
        // The tour's isModal accessibility trait is exposed as an Alert by
        // this SDK. Permit ONLY that exact modal; never an unrelated alert.
        if callout.exists && callout.elementType == .alert {
            let own = alerts.matching(identifier: "tour.callout")
            XCTAssertEqual(count, 1, "No alert may appear alongside the tutorial modal")
            XCTAssertEqual(own.count, 1, "The only alert must be the known tour callout")
            guard count == 1 && own.count == 1 else { throw HarnessFailure.unexpectedAlert }
            let ownFrame = own.element(boundBy: 0).frame
            let calloutFrame = callout.frame
            XCTAssertEqual(ownFrame, calloutFrame)
            guard ownFrame == calloutFrame else { throw HarnessFailure.unexpectedAlert }
        } else {
            XCTAssertEqual(count, 0, "No unexpected alert during or after the tour")
            guard count == 0 else { throw HarnessFailure.unexpectedAlert }
        }
    }

    private func expectedLastSentence(_ step: String, language: String) -> String {
        if language == "pt-BR" {
            switch step {
            case "flow": return "Cancelar espera para de aguardar a resposta neste aparelho, mas não garante que o pedido foi cancelado."
            case "register": return "Peso e hidratação são salvos quando você toca em Registrar peso ou Registrar hidratação."
            default: return "O Histórico reúne as refeições e os treinos confirmados."
            }
        }
        switch step {
        case "flow": return "Cancel waiting stops waiting for the answer on this device, but does not guarantee the request was cancelled."
        case "register": return "Weight and hydration are saved when you tap Record weight or Record hydration."
        default: return "History lists your confirmed meals and workouts."
        }
    }

    private func valid(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite
            && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }

    private func geometryReceipt(step: String, phase: String, node: XCUIElement,
                                 viewport: XCUIElement, actionTop: CGFloat?,
                                 app: XCUIApplication) throws {
        func n(_ value: CGFloat) -> Any { value.isFinite ? Double(value) as Any : NSNull() }
        func rect(_ f: CGRect) -> [String: Any] {
            ["x": n(f.minX), "y": n(f.minY), "width": n(f.width), "height": n(f.height), "maxY": n(f.maxY)]
        }
        let payload: [String: Any] = ["step": step, "phase": phase,
            "node": rect(node.frame), "viewport": rect(viewport.frame), "window": rect(app.frame),
            "actionTop": actionTop.map(n) ?? NSNull(), "hittable": node.isHittable,
            "nodeExceedsViewportHeight": node.frame.height > viewport.frame.height + 1]
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: payload,
            options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        receipt.name = "tour-geometry-" + step + "-" + phase
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    private func captureScreenshot(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
