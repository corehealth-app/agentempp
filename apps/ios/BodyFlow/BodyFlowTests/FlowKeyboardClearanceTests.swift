import CoreGraphics
import XCTest
@testable import BodyFlow

final class FlowKeyboardClearanceTests: XCTestCase {
    private let viewport = CGRect(x: 0, y: 116, width: 402, height: 416)
    private let dockedKeyboard = CGRect(x: 0, y: 498, width: 402, height: 376)

    func testScreenAFrameCannotBeConvertedAsScreenB() throws {
        let screenA = NSObject(), screenB = NSObject()
        let sample = try XCTUnwrap(FlowKeyboardScreenFrame(frame: dockedKeyboard, screenID: ObjectIdentifier(screenA)))
        XCTAssertNil(sample.frame(on: ObjectIdentifier(screenB)))
        XCTAssertEqual(sample.frame(on: ObjectIdentifier(screenA)), dockedKeyboard)
    }

    func testKeyboardFrameWithoutAScreenIsRejected() {
        XCTAssertNil(FlowKeyboardScreenFrame(frame: dockedKeyboard, screenID: nil))
    }

    func testObservedEmptyAXViewportOverlapsDockedKeyboardBy34Points() {
        // Exact native probe: viewport ends 532; keyboard starts 498.
        XCTAssertEqual(FlowKeyboardClearance.overlap(viewport: viewport, keyboard: dockedKeyboard), 34)
    }

    func testAlreadyAvoidedViewportDoesNotApplyKeyboardHeightAgain() {
        let avoided = CGRect(x: 0, y: 116, width: 402, height: 348) // ends 464
        XCTAssertEqual(FlowKeyboardClearance.overlap(viewport: avoided, keyboard: dockedKeyboard), 0)
    }

    func testHiddenOrOffscreenKeyboardLeavesNoResidualClearance() {
        for keyboard in [
            CGRect(x: 0, y: 874, width: 402, height: 0),
            CGRect(x: 0, y: 918, width: 402, height: 226),
            CGRect.zero
        ] {
            XCTAssertEqual(FlowKeyboardClearance.overlap(viewport: viewport, keyboard: keyboard), 0)
        }
    }

    func testPartialWidthAndDetachedFramesDoNotLiftTheWholeComposer() {
        for keyboard in [
            CGRect(x: 90, y: 400, width: 222, height: 250), // floating, partial x coverage
            CGRect(x: 0, y: 300, width: 402, height: 100), // does not reach viewport bottom
            CGRect(x: 402, y: 498, width: 402, height: 376) // horizontally disjoint
        ] {
            XCTAssertEqual(FlowKeyboardClearance.overlap(viewport: viewport, keyboard: keyboard), 0)
        }
    }

    func testFullWidthKeyboardClipsResidualToTheViewportHeight() {
        let encompassing = CGRect(x: -20, y: 80, width: 442, height: 900)
        XCTAssertEqual(FlowKeyboardClearance.overlap(viewport: viewport, keyboard: encompassing), 416)
        let touching = CGRect(x: 0, y: viewport.maxY, width: 402, height: 342)
        XCTAssertEqual(FlowKeyboardClearance.overlap(viewport: viewport, keyboard: touching), 0)
    }

    func testSameLocalCoordinateTranslationPreservesResidual() {
        XCTAssertEqual(FlowKeyboardClearance.overlap(
            viewport: viewport.offsetBy(dx: 37, dy: -84),
            keyboard: dockedKeyboard.offsetBy(dx: 37, dy: -84)
        ), 34)
    }

    func testRemainingAccessoryUsesOnlyItsIntersection() {
        let accessory = CGRect(x: 0, y: 792, width: 402, height: 82)
        let partlyAvoided = CGRect(x: 0, y: 116, width: 402, height: 710) // ends 826
        XCTAssertEqual(FlowKeyboardClearance.overlap(viewport: partlyAvoided, keyboard: accessory), 34)
    }

    func testInvalidFramesFailClosedWithFiniteZero() {
        let invalid: [CGRect] = [
            .null, .infinite, .zero,
            CGRect(x: CGFloat.nan, y: 116, width: 402, height: 416),
            CGRect(x: 0, y: CGFloat.infinity, width: 402, height: 416),
            CGRect(x: 0, y: 116, width: -CGFloat.infinity, height: 416),
            CGRect(x: 0, y: 116, width: -402, height: 416),
            CGRect(x: 0, y: 116, width: 402, height: -416),
            CGRect(x: 0, y: 116, width: 402, height: CGFloat.nan),
            // Finite stored components can still produce a nonfinite edge.
            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 116, width: CGFloat.greatestFiniteMagnitude, height: 416)
        ]
        for rectangle in invalid {
            let invalidViewport = FlowKeyboardClearance.overlap(viewport: rectangle, keyboard: dockedKeyboard)
            let invalidKeyboard = FlowKeyboardClearance.overlap(viewport: viewport, keyboard: rectangle)
            XCTAssertTrue(invalidViewport.isFinite)
            XCTAssertTrue(invalidKeyboard.isFinite)
            XCTAssertEqual(invalidViewport, 0)
            XCTAssertEqual(invalidKeyboard, 0)
        }
    }
}
