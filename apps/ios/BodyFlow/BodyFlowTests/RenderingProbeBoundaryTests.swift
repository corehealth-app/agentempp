import SwiftUI
import UIKit
import XCTest

@MainActor
final class RenderingProbeBoundaryTests: XCTestCase {
    func testFixedCommandMeasurementExcludesOnlyTheRealScrollSubtree() {
        let host = SignUpRenderingProbe.host(
            VStack {
                Button("Same action") {}.accessibilityIdentifier("shared.identifier")
                ScrollView {
                    VStack {
                        Button("Same action") {}.accessibilityIdentifier("shared.identifier")
                        Button("Another action") {}.accessibilityIdentifier("inside.other")
                    }
                }
            }, width: 393
        )
        defer { host.detach() }
        let all = host.nodes().filter { $0.isElement && $0.isButton }
        let fixed = host.nodes(excludingScrollingContent: true).filter { $0.isElement && $0.isButton }
        XCTAssertEqual(all.count, 3, "Fixture must expose scrolling content on this runtime")
        XCTAssertEqual(fixed.count, 1)
        XCTAssertEqual(fixed.first?.identifier, "shared.identifier")
    }

    func testACommandPlacedInsideTheScrollColumnCannotPassAsFixed() {
        let host = SignUpRenderingProbe.host(
            ScrollView {
                Button("Back to the previous step") {}
                    .accessibilityIdentifier("onboarding.back.top")
            }, width: 393
        )
        defer { host.detach() }
        XCTAssertTrue(host.nodes().contains { $0.identifier == "onboarding.back.top" })
        XCTAssertFalse(host.nodes(excludingScrollingContent: true).contains { $0.isElement && $0.isButton })
    }
}
