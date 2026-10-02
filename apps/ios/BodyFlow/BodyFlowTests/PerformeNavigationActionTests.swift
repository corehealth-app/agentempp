import UIKit
import XCTest
@testable import BodyFlow

@MainActor
final class PerformeNavigationActionTests: XCTestCase {
    func testSharedLargeContentGestureMovesFromOriginToDestinationExactlyOnce() {
        let bar = makeBar()
        var selections = [0, 0, 0, 0, 0]
        bar.configure(itemsWithActions { selections[$0] += 1 })
        bar.layoutIfNeeded()
        let origin = bar.buttons[0]
        let destination = bar.buttons[1]
        let point = destination.convert(
            CGPoint(x: destination.bounds.midX, y: destination.bounds.midY), to: bar
        )
        let selectedItem = bar.largeContentViewerInteraction(bar.largeContentInteraction, itemAt: point)
        XCTAssertTrue((selectedItem as? UIView) === destination)

        origin.sendActions(for: .touchDown)
        bar.largeContentViewerInteraction(bar.largeContentInteraction, didEndOn: selectedItem, at: point)
        origin.sendActions(for: .touchUpInside)
        destination.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [0, 1, 0, 0, 0])

        destination.sendActions(for: .touchDown)
        destination.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [0, 2, 0, 0, 0])
    }

    func testSharedLargeContentCancellationOutsideDoesNotSelectAndKeepsNextTap() {
        let bar = makeBar()
        var selections = [0, 0, 0, 0, 0]
        bar.configure(itemsWithActions { selections[$0] += 1 })
        bar.layoutIfNeeded()
        let origin = bar.buttons[0]
        let outside = CGPoint(x: -1, y: bar.bounds.midY)
        XCTAssertNil(bar.largeContentViewerInteraction(bar.largeContentInteraction, itemAt: outside))

        origin.sendActions(for: .touchDown)
        bar.largeContentViewerInteraction(bar.largeContentInteraction, didEndOn: nil, at: outside)
        origin.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [0, 0, 0, 0, 0])

        origin.sendActions(for: .touchDown)
        origin.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [1, 0, 0, 0, 0])
        bar.clearActions()
        XCTAssertFalse(origin.accessibilityActivate())
    }

    func testSharedTouchUpBeforeLargeContentReleaseDoesNotSelectDestination() {
        let bar = makeBar()
        var selections = [0, 0, 0, 0, 0]
        bar.configure(itemsWithActions { selections[$0] += 1 })
        bar.layoutIfNeeded()
        let origin = bar.buttons[0]
        let destination = bar.buttons[1]
        let point = destination.convert(
            CGPoint(x: destination.bounds.midX, y: destination.bounds.midY), to: bar
        )

        origin.sendActions(for: .touchDown)
        origin.sendActions(for: .touchUpInside)
        bar.largeContentViewerInteraction(bar.largeContentInteraction, didEndOn: destination, at: point)
        destination.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [1, 0, 0, 0, 0])

        destination.sendActions(for: .touchDown)
        destination.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [1, 1, 0, 0, 0])
    }

    func testSharedLargeContentDuplicateEndCallbackSelectsOnlyOnce() {
        let bar = makeBar()
        var selections = [0, 0, 0, 0, 0]
        bar.configure(itemsWithActions { selections[$0] += 1 })
        bar.layoutIfNeeded()
        let origin = bar.buttons[0]
        let destination = bar.buttons[1]
        let point = destination.convert(
            CGPoint(x: destination.bounds.midX, y: destination.bounds.midY), to: bar
        )

        origin.sendActions(for: .touchDown)
        bar.largeContentViewerInteraction(bar.largeContentInteraction, didEndOn: destination, at: point)
        bar.largeContentViewerInteraction(bar.largeContentInteraction, didEndOn: destination, at: point)
        origin.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [0, 1, 0, 0, 0])

        destination.sendActions(for: .touchDown)
        destination.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, [0, 2, 0, 0, 0])
    }

    func testLargeContentReleaseAndTouchUpActivateOnlyOnceForOnePress() {
        let button = PerformeNavigationButton(frame: CGRect(x: 0, y: 0, width: 76, height: 68))
        var selections = 0
        button.activate = { selections += 1 }

        button.sendActions(for: .touchDown)
        button.largeContentViewerInteraction(button.largeContentInteraction, didEndOn: button, at: CGPoint(x: 38, y: 34))
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, 1)

        // A later deliberate tap must still work after the long press.
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, 2)
    }

    func testTouchUpFollowedByLargeContentReleaseDoesNotSelectTwice() {
        let button = PerformeNavigationButton(frame: CGRect(x: 0, y: 0, width: 76, height: 68))
        var selections = 0
        button.activate = { selections += 1 }
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        button.largeContentViewerInteraction(button.largeContentInteraction, didEndOn: button, at: CGPoint(x: 38, y: 34))
        XCTAssertEqual(selections, 1)
    }

    func testLargeContentReleaseOutsideButtonOrOnDifferentItemDoesNotSelect() {
        let button = PerformeNavigationButton(frame: CGRect(x: 0, y: 0, width: 76, height: 68))
        let other = UIButton(frame: button.bounds)
        var selections = 0
        button.activate = { selections += 1 }
        let releases: [(UILargeContentViewerItem?, CGPoint)] = [
            (nil, CGPoint(x: 38, y: 34)),
            (other, CGPoint(x: 38, y: 34)),
            (button, CGPoint(x: -1, y: 34)),
            (button, CGPoint(x: 38, y: 69)),
        ]
        for (item, point) in releases {
            button.sendActions(for: .touchDown)
            button.largeContentViewerInteraction(button.largeContentInteraction, didEndOn: item, at: point)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(selections, 0)
        }
    }

    func testCancelledTouchDoesNotSelectAndNextTapRemainsAvailable() {
        let button = PerformeNavigationButton(frame: CGRect(x: 0, y: 0, width: 76, height: 68))
        var selections = 0
        button.activate = { selections += 1 }
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchCancel)
        XCTAssertEqual(selections, 0)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpOutside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, 0)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(selections, 1)
    }

    func testVoiceOverActivationSelectsOncePerActionAndRespectsDisabledState() {
        let button = PerformeNavigationButton(frame: CGRect(x: 0, y: 0, width: 76, height: 68))
        var selections = 0
        button.activate = { selections += 1 }
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(selections, 2)
        button.isEnabled = false
        XCTAssertFalse(button.accessibilityActivate())
        button.sendActions(for: .touchDown)
        button.largeContentViewerInteraction(button.largeContentInteraction, didEndOn: button, at: CGPoint(x: 38, y: 34))
        XCTAssertEqual(selections, 2)
    }

    private func makeBar() -> PerformeNavigationBarView {
        PerformeNavigationBarView(frame: CGRect(x: 0, y: 0, width: 380, height: 68))
    }

    private func itemsWithActions(_ activate: @escaping @MainActor (Int) -> Void) -> [PerformeNavigationBarItem] {
        (0..<5).map { index in
            PerformeNavigationBarItem(
                title: "Tab \(index)", image: nil, selected: index == 0,
                identifier: "tab.\(index)",
                action: { activate(index) },
                highlightChanged: { _ in }
            )
        }
    }
}
