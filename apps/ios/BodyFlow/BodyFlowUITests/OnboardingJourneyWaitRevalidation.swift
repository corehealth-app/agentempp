import XCTest

/// UITest-only decision seam. One current predicate evaluation after timeout.
/// The production target has no dependency on this helper.
@MainActor
enum OnboardingJourneyWaitRevalidation {
    static func matches(result: XCTWaiter.Result, revalidate: () -> Bool) -> Bool {
        if result == .completed { return true }
        guard result == .timedOut else { return false }
        return revalidate()
    }
}
