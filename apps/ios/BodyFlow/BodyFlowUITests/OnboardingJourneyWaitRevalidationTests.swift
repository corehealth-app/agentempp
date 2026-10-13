import XCTest

/// Pure decision controls. No app, device, auth, wait or typed input.
@MainActor
final class OnboardingJourneyWaitRevalidationTests: XCTestCase {
    func testOnlyTimeoutRevalidatesOnceAndPreservesAllOtherSDKResults() {
        // Preserve every assertion and collect all fifteen combinations.
        continueAfterFailure = true
        let results: [XCTWaiter.Result] = [
            .completed, .timedOut, .incorrectOrder, .invertedFulfillment, .interrupted
        ]
        let samples: [(label: String, value: String?)] = [
            ("positive10", "xxxxxxxxxx"), ("negative1", "x"), ("nil", nil)
        ]
        for result in results {
            for sample in samples {
                var callbackCalls = 0
                let answer = OnboardingJourneyWaitRevalidation.matches(result: result) {
                    callbackCalls += 1
                    return sample.value?.count == 10
                }
                let expected = result == .completed
                    || (result == .timedOut && sample.label == "positive10")
                let expectedCalls = result == .timedOut ? 1 : 0
                XCTAssertEqual(answer, expected,
                    "SDK result \(result.rawValue), \(sample.label): predicate remains strict")
                XCTAssertEqual(callbackCalls, expectedCalls,
                    "SDK result \(result.rawValue), \(sample.label): only timeout calls once")
            }
        }
    }
}
