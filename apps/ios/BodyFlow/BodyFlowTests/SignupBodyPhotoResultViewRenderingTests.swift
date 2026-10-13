#if DEBUG
import Foundation
import SwiftUI
import XCTest
@testable import BodyFlow

@MainActor
final class SignupBodyPhotoResultViewRenderingTests: XCTestCase {
    private static let valueIDs = ["onboarding.photos.result.reading.front",
        "onboarding.photos.result.reading.side", "onboarding.photos.result.reading.back"]
    private static let meanID = "onboarding.photos.result.mean"
    private static let confirmID = "onboarding.photos.result.confirm"

    func testTwentyFourRenderingVariantsKeepRealTriadAndOfficialMeanWithoutApplyingIt() async throws {
        let h = try await SignupPhotoViewHarness()
        do {
            await h.prepare()
            let core = try XCTUnwrap(h.model.capture), state = try XCTUnwrap(h.model.capture?.state)
            XCTAssertTrue(core.hasAcceptedConsent)
            XCTAssertEqual(h.model.route, .result)
            XCTAssertNotNil(OnboardingBodyPhotoConfirmation.candidate(from: state, sex: .masculine))
            let baseline = await h.base.peer.snapshot()
            var variants = 0
            for language in SupportedAppLanguage.allCases {
                for dark in [false, true] {
                    for width in [CGFloat(375), 393, 430] {
                        for size in [DynamicTypeSize.large, .accessibility5] {
                            let context = "\(language)/\(dark)/\(width)/\(size)"
                            let nodes = SignUpRenderingProbe.nodes(
                                SignupBodyPhotoResultView(photos: h.model).environment(\.locale, language.formattingLocale),
                                width: width, height: 3_000, size: size, dark: dark)
                            let values = try Self.valueIDs.map { id in try XCTUnwrap(nodes.first { $0.identifier == id }, context) }
                            XCTAssertEqual(try values.map { try number($0.label) }, [Decimal(18), Decimal(24), Decimal(30)], context)
                            XCTAssertEqual(values.map(\.frame.minY), values.map(\.frame.minY).sorted(), context)
                            let mean = try XCTUnwrap(nodes.first { $0.identifier == Self.meanID }, context)
                            XCTAssertEqual(try number(mean.label), Decimal(24), context)
                            let confirm = try XCTUnwrap(nodes.first { $0.identifier == Self.confirmID }, context)
                            XCTAssertTrue(confirm.isButton && confirm.isEnabled, context)
                            XCTAssertGreaterThanOrEqual(confirm.frame.height, 44, context)
                            for row in values + [mean, confirm] {
                                XCTAssertGreaterThanOrEqual(row.frame.minX, -0.5, context)
                                XCTAssertLessThanOrEqual(row.frame.maxX, width + 0.5, context)
                            }
                            let disclosureIDs = ["onboarding.photos.result.disclaimer.estimate",
                                "onboarding.photos.result.disclaimer.variation", "onboarding.photos.result.disclaimer.comparison",
                                "onboarding.photos.result.effect"]
                            let disclosures = try disclosureIDs.map { id in try XCTUnwrap(nodes.first { $0.identifier == id }, context) }
                            XCTAssertTrue(disclosures.allSatisfy { !$0.label.isEmpty }, context)
                            XCTAssertEqual(disclosures.map(\.frame.minY), disclosures.map(\.frame.minY).sorted(), context)
                            XCTAssertLessThanOrEqual(disclosures[2].frame.maxY, values[0].frame.minY + 0.5, context)
                            XCTAssertGreaterThanOrEqual(mean.frame.minY, values[2].frame.maxY - 0.5, context)
                            XCTAssertGreaterThanOrEqual(disclosures[3].frame.minY, mean.frame.maxY - 0.5, context)
                            XCTAssertLessThanOrEqual(disclosures[3].frame.maxY, confirm.frame.minY + 0.5, context)
                            XCTAssertNil(h.base.flow.draft.bodyFatPercent, context)
                            XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation, context)
                            variants += 1
                        }
                    }
                }
            }
            XCTAssertEqual(variants, 24)
            let after = await h.base.peer.snapshot(), binds = await h.factory.snapshot()
            XCTAssertEqual(after.calls, baseline.calls, "Rendering must not load/consent/apply/upload/delete")
            XCTAssertEqual(binds, [h.base.owner.userID])
            // Separate explicit model action, not an onAppear/render effect.
            let confirmed = h.model.confirmEstimate()
            XCTAssertTrue(confirmed)
            XCTAssertEqual(h.base.flow.draft.bodyFatPercent, 24)
            XCTAssertEqual(h.base.flow.draft.bodyFatOrigin, .photos)
            XCTAssertEqual(h.base.flow.draft.bodyPhotoConfirmation?.value, Decimal(24))
            await h.stop()
        } catch { await h.stop(); throw error }
    }

    func testCanonicalFractionComesFromOfficialDecisionNotAClientMean() async throws {
        let h = try await SignupPhotoViewHarness(fixture: .canonicalFraction)
        do {
            await h.prepare()
            let state = try XCTUnwrap(h.model.capture?.state)
            let expected = try XCTUnwrap(Decimal(string: "24.13"))
            XCTAssertEqual(state.estimate?.bySex.masculine.bodyFatPercent, expected)
            let nodes = SignUpRenderingProbe.nodes(SignupBodyPhotoResultView(photos: h.model), width: 393, height: 3_000)
            let mean = try XCTUnwrap(nodes.first { $0.identifier == Self.meanID })
            XCTAssertEqual(try number(mean.label), expected, "Never recompute24.125 or copy a per-pose reading")
            XCTAssertNil(h.base.flow.draft.bodyFatPercent)
            let confirmed = h.model.confirmEstimate()
            XCTAssertTrue(confirmed)
            XCTAssertEqual(h.base.flow.draft.bodyPhotoConfirmation?.value, expected)
            await h.stop()
        } catch { await h.stop(); throw error }
    }

    func testMissingReadingsUnusableAndObsoleteOwnerCannotOfferConfirmation() async throws {
        for fixture in [SignupPhotoViewFixture.legacyReadings, .unusable, .valid] {
            let h = try await SignupPhotoViewHarness(fixture: fixture, manual: 23)
            do {
                await h.prepare()
                XCTAssertEqual(h.model.route, .result, "Current result is a prerequisite before owner change")
                if fixture == .valid {
                    h.base.ownerBox.current = .init(userID: h.base.owner.userID, restoreGeneration: 2)
                }
                let nodes = SignUpRenderingProbe.nodes(SignupBodyPhotoResultView(photos: h.model), width: 393, height: 3_000)
                XCTAssertFalse(nodes.first { $0.identifier == Self.confirmID }?.isEnabled == true)
                if fixture == .legacyReadings {
                    XCTAssertFalse(nodes.contains { Self.valueIDs.contains($0.identifier) }, "No fabricated3x24 readings")
                } else if fixture == .unusable {
                    let values = try Self.valueIDs.map { id in try XCTUnwrap(nodes.first { $0.identifier == id }) }
                    XCTAssertEqual(try values.map { try number($0.label) }, [Decimal(2), Decimal(24), Decimal(46)])
                } else {
                    XCTAssertFalse(nodes.contains { $0.identifier.hasPrefix("onboarding.photos.result.") },
                        "Fresh rendering of an obsolete Parent must not expose its old result")
                    XCTAssertEqual(h.model.route, nil)
                }
                let confirmed = h.model.confirmEstimate()
                XCTAssertFalse(confirmed)
                XCTAssertEqual(h.base.flow.draft.bodyFatPercent, 23)
                XCTAssertEqual(h.base.flow.draft.bodyFatOrigin, .typed)
                XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
                let trace = await h.base.peer.snapshot()
                XCTAssertEqual(trace.mutationAndStageSteps, [.consent])
                await h.stop()
            } catch { await h.stop(); throw error }
        }
    }

    private func number(_ label: String) throws -> Decimal {
        let pattern = try NSRegularExpression(pattern: "[-+]?[0-9]+(?:[.,][0-9]+)?")
        let match = try XCTUnwrap(pattern.matches(in: label, range: NSRange(label.startIndex..., in: label)).last,
            "No number in the dedicated public value node: \(label)")
        let range = try XCTUnwrap(Range(match.range, in: label))
        return try XCTUnwrap(Decimal(string: String(label[range]).replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")))
    }
}
#endif
