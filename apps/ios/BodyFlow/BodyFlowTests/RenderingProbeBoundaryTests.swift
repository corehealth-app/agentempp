import SwiftUI
import UIKit
import XCTest

@MainActor
final class RenderingProbeBoundaryTests: XCTestCase {
    func testFixedCommandMeasurementExcludesOnlyTheRealScrollSubtree() {
        let host = SignUpRenderingProbe.host(ScrollBoundaryFixture(hasFixedCommand: true), width: 393)
        defer { host.detach() }
        XCTAssertEqual(host.scrollViews().count, 1)
        let all = host.nodes().filter { $0.isElement && $0.isButton }
        let fixed = host.nodes(excludingScrollingContent: true).filter { $0.isElement && $0.isButton }
        XCTAssertEqual(all.count, 3, "Both equal identifiers and the distinct inner command must be observed: \(host.nodes())")
        XCTAssertEqual(all.filter { $0.identifier == "shared.identifier" }.count, 2)
        XCTAssertEqual(fixed.count, 1)
        XCTAssertEqual(fixed.first?.identifier, "shared.identifier")
    }

    func testACommandPlacedInsideTheScrollColumnCannotPassAsFixed() {
        let host = SignUpRenderingProbe.host(ScrollBoundaryFixture(hasFixedCommand: false), width: 393)
        defer { host.detach() }
        XCTAssertEqual(host.scrollViews().count, 1)
        XCTAssertTrue(host.nodes().contains { $0.identifier == "onboarding.back.top" })
        XCTAssertFalse(host.nodes(excludingScrollingContent: true).contains { $0.isElement && $0.isButton })
    }
}

/// The probe's exclusion contract concerns the native scrolling subtree.
/// SwiftUI may render ScrollView geometry without exposing its interior AX
/// nodes to an in-process walk (observed again on iOS 26.5). Use actual UIKit
/// scrolling children as a deterministic oracle, keeping every positive and
/// negative assertion. OnboardingBackUITests separately exercises real SwiftUI.
private struct ScrollBoundaryFixture: UIViewRepresentable {
    let hasFixedCommand: Bool
    func makeUIView(context: Context) -> UIView {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 800))
        func button(_ title: String, _ identifier: String, _ y: CGFloat) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.isAccessibilityElement = true
            button.accessibilityTraits = .button
            button.accessibilityLabel = title
            button.accessibilityIdentifier = identifier
            button.frame = CGRect(x: 20, y: y, width: 300, height: 44)
            return button
        }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 60, width: 393, height: 700))
        scroll.contentSize = CGSize(width: 393, height: 900)
        if hasFixedCommand {
            root.addSubview(button("Same action", "shared.identifier", 0))
            scroll.addSubview(button("Same action", "shared.identifier", 0))
            scroll.addSubview(button("Another action", "inside.other", 60))
        } else {
            scroll.addSubview(button("Back to the previous step", "onboarding.back.top", 0))
        }
        root.addSubview(scroll)
        return root
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
