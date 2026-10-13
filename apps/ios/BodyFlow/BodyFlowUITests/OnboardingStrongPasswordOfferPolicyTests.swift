import XCTest

/// Query-shape selection only; actual tap/disappear/refetch is covered by the two UI preparer tests.
final class OnboardingStrongPasswordOfferPolicyTests: XCTestCase {
    func testNoOfferAndRecognizedSingletonHaveDifferentActions() {
        XCTAssertEqual(decision(0, 0, false, 0), .noOffer)
        XCTAssertEqual(decision(1, 1, true, 0), .dismissRecognizedOffer)
    }

    func testCloseWithoutTitleOrOtherModalBlocksBeforeTyping() {
        XCTAssertEqual(decision(0, 1, true, 0), .blocked)
        XCTAssertEqual(decision(0, 0, false, 1), .blocked)
        XCTAssertEqual(decision(1, 1, true, 1), .blocked)
    }

    func testIncompleteAmbiguousAndNonhittableOffersBlockBeforeTyping() {
        for input in [(1, 0, false), (1, 1, false), (1, 2, true), (2, 1, true),
                      (2, 2, true), (0, 2, true), (-1, 1, true)] {
            XCTAssertEqual(decision(input.0, input.1, input.2, 0), .blocked)
        }
    }

    func testUnknownModalAppearingAfterInitialApprovalBlocksBothActionBoundaries() {
        var currentOtherModalCount = 0
        let initial = decision(1, 1, true, currentOtherModalCount)
        XCTAssertEqual(initial, .dismissRecognizedOffer)
        currentOtherModalCount = 1 // Models a change during the Close wait, not a UI/API proof.
        var reads = 0
        XCTAssertFalse(OnboardingStrongPasswordOfferDecision.matchesCurrent(initial) {
            reads += 1
            return self.decision(1, 1, true, currentOtherModalCount)
        })
        XCTAssertEqual(reads, 1)

        currentOtherModalCount = 0
        let afterDismiss = decision(0, 0, false, currentOtherModalCount)
        XCTAssertEqual(afterDismiss, .noOffer)
        currentOtherModalCount = 1 // Models a change during the focus wait.
        reads = 0
        XCTAssertFalse(OnboardingStrongPasswordOfferDecision.matchesCurrent(afterDismiss) {
            reads += 1
            return self.decision(0, 0, false, currentOtherModalCount)
        })
        XCTAssertEqual(reads, 1)
    }

    private func decision(_ titles: Int, _ closes: Int, _ hittable: Bool, _ otherModals: Int)
        -> OnboardingStrongPasswordOfferDecision {
        OnboardingStrongPasswordOfferDecision.evaluate(
            promptCount: titles, closeCount: closes, closeHittable: hittable,
            otherModalCount: otherModals)
    }
}


extension OnboardingStrongPasswordOfferPolicyTests {
    func testKnownFalseHitValidatedCloseUsesExplicitPublicAlternative() {
        XCTAssertEqual(OnboardingStrongPasswordOfferDecision.evaluate(
            promptCount: 1, closeCount: 1, closeHittable: false, otherModalCount: 0), .blocked)
        let eligible = OnboardingStrongPasswordOfferDecision.knownPublicCloseEligible(
            knownXmark: true, enabled: true, frameFinite: true, framePositive: true, frameInsideWindow: true)
        XCTAssertTrue(eligible)
        XCTAssertEqual(OnboardingStrongPasswordOfferDecision.evaluate(
            promptCount: 1, closeCount: 1, closeHittable: false, otherModalCount: 0,
            publicCloseEligible: eligible), .dismissRecognizedOffer)
    }

    func testFalseHitPublicAlternativeRejectsInvalidEvidenceOrQueryShape() {
        // Unknown identifier, disabled, nonfinite, empty, and offscreen are distinct failed evidence.
        for evidence in [(false, true, true, true, true), (true, false, true, true, true),
                         (true, true, false, true, true), (true, true, true, false, true),
                         (true, true, true, true, false)] {
            let eligible = OnboardingStrongPasswordOfferDecision.knownPublicCloseEligible(
                knownXmark: evidence.0, enabled: evidence.1, frameFinite: evidence.2,
                framePositive: evidence.3, frameInsideWindow: evidence.4)
            XCTAssertFalse(eligible)
            XCTAssertEqual(OnboardingStrongPasswordOfferDecision.evaluate(
                promptCount: 1, closeCount: 1, closeHittable: false, otherModalCount: 0,
                publicCloseEligible: eligible), .blocked)
        }
        for shape in [(0, 1, 0), (1, 0, 0), (2, 1, 0), (1, 2, 0), (1, 1, 1), (-1, 1, 0)] {
            XCTAssertEqual(OnboardingStrongPasswordOfferDecision.evaluate(
                promptCount: shape.0, closeCount: shape.1, closeHittable: false,
                otherModalCount: shape.2, publicCloseEligible: true), .blocked)
        }
    }

    func testFalseHitPublicAlternativeConsultsChangedMetadataBeforeTapAndTyping() {
        var insideWindow = true
        var otherModals = 0
        let read = {
            let eligible = OnboardingStrongPasswordOfferDecision.knownPublicCloseEligible(
                knownXmark: true, enabled: true, frameFinite: true, framePositive: true,
                frameInsideWindow: insideWindow)
            return OnboardingStrongPasswordOfferDecision.evaluate(
                promptCount: 1, closeCount: 1, closeHittable: false, otherModalCount: otherModals,
                publicCloseEligible: eligible)
        }
        let initial = read()
        XCTAssertEqual(initial, .dismissRecognizedOffer)
        insideWindow = false // Synthetic query metadata changes during the wait, not a UIKit proof.
        var reads = 0
        XCTAssertFalse(OnboardingStrongPasswordOfferDecision.matchesCurrent(initial) {
            reads += 1
            return read()
        })
        XCTAssertEqual(reads, 1)
        insideWindow = true
        otherModals = 1
        XCTAssertFalse(OnboardingStrongPasswordOfferDecision.matchesCurrent(.dismissRecognizedOffer, read: read))
        XCTAssertFalse(OnboardingStrongPasswordOfferDecision.matchesCurrent(.noOffer) {
            OnboardingStrongPasswordOfferDecision.evaluate(
                promptCount: 0, closeCount: 0, closeHittable: false, otherModalCount: otherModals)
        })
    }
}
