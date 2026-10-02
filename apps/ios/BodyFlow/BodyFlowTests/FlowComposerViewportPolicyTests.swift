import CoreGraphics
import XCTest
@testable import BodyFlow

final class FlowComposerViewportPolicyTests: XCTestCase {
    func testObservedViewportReservesClearanceBeforeTheFirstMeasurement() {
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: nil, viewport: 416, clearance: 34), 382)
    }

    func testAXLimitDockScrollsWithinTheObservedProtectedViewport() {
        // Dock size reconstructed from the preserved AX field/action/warning geometry.
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 642.3, viewport: 416, clearance: 34), 382)
    }

    func testNaturalDockHeightLeavesRemainingSpaceForConversation() {
        let height = FlowComposerViewportPolicy.height(natural: 277.3, viewport: 416, clearance: 34)
        XCTAssertEqual(height, 277.3)
        XCTAssertEqual(416 - 34 - height, 104.7, accuracy: 0.0001)
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 80, viewport: 758, clearance: 0), 80)
    }

    func testNoAvailableWindowSpaceProducesZeroInsteadOfOverflow() {
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 642.3, viewport: 0, clearance: 0), 0)
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: nil, viewport: 0, clearance: 0), 0)
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 80, viewport: 34, clearance: 34), 0)
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 80, viewport: 34, clearance: 82), 0)
    }

    func testInvalidOrNonfiniteInputsNeverCreateAnInvalidFrame() {
        for invalid in [CGFloat.nan, CGFloat.infinity, -CGFloat.infinity, CGFloat(-1)] {
            XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 80, viewport: invalid, clearance: 0), 0)
            XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 80, viewport: 416, clearance: invalid), 0)
            XCTAssertEqual(FlowComposerViewportPolicy.height(natural: invalid, viewport: 416, clearance: 34), 0)
        }
        XCTAssertEqual(FlowComposerViewportPolicy.height(natural: 0, viewport: 416, clearance: 34), 0)
    }
}
