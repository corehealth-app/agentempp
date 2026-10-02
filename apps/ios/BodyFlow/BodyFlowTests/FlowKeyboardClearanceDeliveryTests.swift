import CoreGraphics
import XCTest
@testable import BodyFlow

@MainActor
final class FlowKeyboardClearanceDeliveryTests: XCTestCase {
    func testNewestZeroReplacesQueued34BeforeDelivery() {
        let scheduler = ManualScheduler()
        var published: [CGFloat] = []
        let delivery = FlowKeyboardClearanceDelivery(
            schedule: { scheduler.enqueue($0) }, publish: { published.append($0) }
        )

        delivery.submit(34)
        delivery.submit(0)
        scheduler.drain()

        XCTAssertEqual(published, [0])
    }

    func testInvalidationDropsQueuedPublication() {
        let scheduler = ManualScheduler()
        var published: [CGFloat] = []
        let delivery = FlowKeyboardClearanceDelivery(
            schedule: { scheduler.enqueue($0) }, publish: { published.append($0) }
        )

        delivery.submit(34)
        delivery.invalidate()
        scheduler.drain()

        XCTAssertEqual(published, [])
    }

    func testReturningToLastPublished34CancelsQueuedZeroWithoutDuplicate34() {
        let scheduler = ManualScheduler()
        var published: [CGFloat] = []
        let delivery = FlowKeyboardClearanceDelivery(
            schedule: { scheduler.enqueue($0) }, publish: { published.append($0) }
        )

        delivery.submit(34)
        scheduler.drain()
        XCTAssertEqual(published, [34])
        delivery.submit(0)
        delivery.submit(34)
        scheduler.drain()

        XCTAssertEqual(published, [34], "The pending zero must become stale even when 34 equals the last delivered value")
    }

    func testSubmissionAfterInvalidationUsesTheRetainedCallback() {
        let scheduler = ManualScheduler()
        var published: [CGFloat] = []
        let delivery = FlowKeyboardClearanceDelivery(
            schedule: { scheduler.enqueue($0) }, publish: { published.append($0) }
        )

        delivery.submit(34)
        delivery.invalidate()
        delivery.submit(0)
        scheduler.drain()

        XCTAssertEqual(published, [0])
    }

    func testInvalidationResetsTheLastPublishedValueForANewOwner() {
        let scheduler = ManualScheduler()
        var published: [CGFloat] = []
        let delivery = FlowKeyboardClearanceDelivery(
            schedule: { scheduler.enqueue($0) }, publish: { published.append($0) }
        )

        delivery.submit(0)
        scheduler.drain()
        XCTAssertEqual(published, [0])
        delivery.invalidate()
        delivery.submit(0)
        scheduler.drain()

        XCTAssertEqual(published, [0, 0], "A fresh binding must receive zero even when the previous binding last received zero")
    }

    @MainActor
    private final class ManualScheduler {
        private var jobs: [@MainActor @Sendable () -> Void] = []

        func enqueue(_ job: @escaping @MainActor @Sendable () -> Void) {
            jobs.append(job)
        }

        func drain() {
            let pending = jobs
            jobs.removeAll()
            for job in pending { job() }
        }
    }
}
