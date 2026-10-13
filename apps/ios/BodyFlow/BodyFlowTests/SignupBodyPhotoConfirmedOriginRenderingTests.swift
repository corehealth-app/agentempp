#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

/// PRIVATE, UNCOMPILED CANDIDATE. User-facing BodyData provenance card.
/// The existing declared estimate peer tests explicit confirmation/rendering;
/// it is not used as evidence of three captures, AI, backend or JWT.
@MainActor
final class SignupBodyPhotoConfirmedOriginRenderingTests: XCTestCase {
    func testConfirmedPhotoOriginIsVisibleOnlyAfterExplicitParentConfirmationAndDisappearsForManualOrSkipInBothLanguages() async throws {
        for language in SupportedAppLanguage.allCases {
            let h = try await PresentationHarness(hasEstimate: true)
            defer { h.clean() }
            await h.model.load()
            h.model.select(.photos)
            await h.model.acceptConsent()
            let core = try XCTUnwrap(h.model.capture)
            let baseline = await h.peer.snapshot()
            XCTAssertEqual(h.model.route, .result)
            XCTAssertNil(h.flow.draft.bodyFatPercent)
            XCTAssertNil(h.flow.draft.bodyFatOrigin)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            let before = SignUpRenderingProbe.nodes(
                BodyDataStepView(model: h.flow, photos: h.model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            XCTAssertFalse(before.contains { $0.identifier == "onboarding.body-fat.photos.confirmed" },
                "Choosing photos or viewing the official estimate must not claim confirmed provenance")

            XCTAssertTrue(h.model.confirmEstimate(), "Only the existing explicit Parent action may apply canonical BF")
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)
            XCTAssertEqual(h.flow.draft.bodyFatOrigin, .photos)
            let proof = try XCTUnwrap(h.flow.draft.bodyPhotoConfirmation)
            XCTAssertTrue(proof.matches(h.flow.draft))
            XCTAssertFalse(h.flow.requiresBodyPhotoRevalidation)
            let confirmed = SignUpRenderingProbe.nodes(
                BodyDataStepView(model: h.flow, photos: h.model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            let card = try XCTUnwrap(confirmed.first { $0.identifier == "onboarding.body-fat.photos.confirmed" })
            XCTAssertEqual(confirmed.filter { $0.identifier == "onboarding.body-fat.photos.confirmed" }.count, 1)
            XCTAssertEqual(card.label, language == .portugueseBrazil
                ? "Você confirmou a estimativa por fotos: 24%"
                : "You confirmed the photo estimate: 24%",
                "Show the actual canonical percentage and the user's explicit confirmation, in the view language")
            XCTAssertTrue(h.model.capture === core)

            h.model.select(.typed)
            XCTAssertEqual(h.flow.draft.bodyFatPercent, 24)
            XCTAssertEqual(h.flow.draft.bodyFatOrigin, .typed)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            let typed = SignUpRenderingProbe.nodes(
                BodyDataStepView(model: h.flow, photos: h.model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            XCTAssertFalse(typed.contains { $0.identifier == "onboarding.body-fat.photos.confirmed" },
                "Same-value manual entry is manual provenance, even though the number remains 24")

            h.model.select(.skip)
            XCTAssertNil(h.flow.draft.bodyFatPercent)
            XCTAssertNil(h.flow.draft.bodyFatOrigin)
            XCTAssertNil(h.flow.draft.bodyPhotoConfirmation)
            let skipped = SignUpRenderingProbe.nodes(
                BodyDataStepView(model: h.flow, photos: h.model)
                    .environment(\.locale, language.formattingLocale), width: 393, height: 3_000)
            XCTAssertFalse(skipped.contains { $0.identifier == "onboarding.body-fat.photos.confirmed" })
            let after = await h.peer.snapshot(), binds = await h.factory.snapshot()
            XCTAssertEqual(after.calls, baseline.calls,
                "Rendering the real card/manual/skip does not trigger another GET or mutation")
            XCTAssertEqual(binds, [h.owner.userID])
        }
    }
}
#endif
