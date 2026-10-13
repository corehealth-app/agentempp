#if DEBUG
import Foundation
import SwiftUI
import XCTest
@testable import BodyFlow

@MainActor
final class SignupBodyPhotoResultCurrentSexRenderingTests: XCTestCase {
    private static let meanID = "onboarding.photos.result.mean"
    private static let confirmID = "onboarding.photos.result.confirm"

    func testCurrentSexSelectsTheOfficialDecisionWithoutRenderingSideEffects() async throws {
        let h = try await SignupPhotoCurrentSexViewHarness()
        do {
            await h.prepare()
            let state = try XCTUnwrap(h.model.capture?.state)
            let estimate = try XCTUnwrap(state.estimate)
            let expected = try XCTUnwrap(Decimal(string: "24.13", locale: Locale(identifier: "en_US_POSIX")))
            XCTAssertEqual(h.model.route, .result)
            XCTAssertTrue(h.model.capture?.hasAcceptedConsent == true)
            XCTAssertEqual(h.base.flow.draft.biologicalSex, .masculine)
            XCTAssertFalse(estimate.bySex.masculine.usable)
            XCTAssertNil(estimate.bySex.masculine.bodyFatPercent)
            XCTAssertTrue(estimate.bySex.feminine.usable)
            XCTAssertEqual(estimate.bySex.feminine.bodyFatPercent, expected)
            XCTAssertEqual(estimate.readings?.map(\.pose), SignupBodyPhotoPose.allCases)
            XCTAssertEqual(estimate.readings?.map(\.bodyFatPercent),
                try ["18.125", "24.125", "30.125"].map { text in
                    try XCTUnwrap(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
                })
            XCTAssertNil(OnboardingBodyPhotoConfirmation.candidate(from: state, sex: .masculine))
            let feminineCandidate = try XCTUnwrap(OnboardingBodyPhotoConfirmation.candidate(from: state, sex: .feminine))
            XCTAssertEqual(feminineCandidate.sex, .feminine)
            XCTAssertEqual(feminineCandidate.value, expected)
            assertNoAppliedEstimate(h)

            let baseline = await h.base.peer.snapshot()
            XCTAssertEqual(baseline.mutationAndStageSteps, [.consent])
            let host = SignUpRenderingProbe.host(
                SignupBodyPhotoResultView(photos: h.model).environment(\.locale, Locale(identifier: "pt-BR")),
                width: 393, height: 3_000)
            defer { host.detach() }

            // The same retained host must follow the draft's current sex.
            let masculineNodes = host.nodes()
            assertNoMeanOrEnabledConfirmation(masculineNodes)
            assertNoAppliedEstimate(h)
            await assertNoProviderWorkSince(baseline, h: h)

            h.base.flow.updateBiologicalSex(.feminine)
            XCTAssertEqual(h.base.flow.draft.biologicalSex, .feminine)
            let currentSex = try XCTUnwrap(h.base.flow.draft.biologicalSex)
            XCTAssertEqual(OnboardingBodyPhotoConfirmation.candidate(from: state, sex: currentSex), feminineCandidate)
            let feminineNodes = host.nodes()
            try assertCanonicalMeanAndEnabledConfirmation(feminineNodes, expected: expected)
            assertNoAppliedEstimate(h)
            await assertNoProviderWorkSince(baseline, h: h)

            // A permanently feminine selection must fail this return to masculine.
            h.base.flow.updateBiologicalSex(.masculine)
            XCTAssertEqual(h.base.flow.draft.biologicalSex, .masculine)
            let masculineAgainNodes = host.nodes()
            assertNoMeanOrEnabledConfirmation(masculineAgainNodes)
            XCTAssertNil(OnboardingBodyPhotoConfirmation.candidate(from: state, sex: .masculine))
            let rejected = h.model.confirmEstimate()
            XCTAssertFalse(rejected)
            assertNoAppliedEstimate(h)
            await assertNoProviderWorkSince(baseline, h: h)

            h.base.flow.updateBiologicalSex(.feminine)
            XCTAssertEqual(h.base.flow.draft.biologicalSex, .feminine)
            let feminineAgainNodes = host.nodes()
            try assertCanonicalMeanAndEnabledConfirmation(feminineAgainNodes, expected: expected)
            assertNoAppliedEstimate(h)
            await assertNoProviderWorkSince(baseline, h: h)

            // Explicit real Parent action; this is not a tap on the SwiftUI button.
            let confirmed = h.model.confirmEstimate()
            XCTAssertTrue(confirmed)
            XCTAssertEqual(h.base.flow.draft.bodyFatPercent, 24.13)
            XCTAssertEqual(h.base.flow.draft.bodyFatOrigin, .photos)
            XCTAssertEqual(h.base.flow.draft.bodyPhotoConfirmation, feminineCandidate)
            XCTAssertEqual(h.base.flow.draft.bodyPhotoConfirmation?.sex, .feminine)
            await assertNoProviderWorkSince(baseline, h: h)
            await h.stop()
        } catch {
            await h.stop()
            throw error
        }
    }

    private func assertNoAppliedEstimate(_ h: SignupPhotoCurrentSexViewHarness) {
        XCTAssertNil(h.base.flow.draft.bodyFatPercent)
        XCTAssertNil(h.base.flow.draft.bodyFatOrigin)
        XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
    }

    private func assertNoProviderWorkSince(_ baseline: CapturePeerSnapshot,
        h: SignupPhotoCurrentSexViewHarness) async {
        let after = await h.base.peer.snapshot()
        XCTAssertEqual(after.calls, baseline.calls, "Render/sex changes/confirmation must not GET, consent, stage, upload or delete")
        let binds = await h.factory.snapshot()
        XCTAssertEqual(binds, [h.base.owner.userID])
        let unusedBaseBinds = await h.base.factory.snapshot()
        XCTAssertTrue(unusedBaseBinds.isEmpty, "The base harness model/factory stays unbound")
        XCTAssertNil(h.base.model.capture)
    }

    private func assertNoMeanOrEnabledConfirmation(_ nodes: [SignUpRenderingProbe.Node]) {
        XCTAssertFalse(nodes.contains { $0.identifier == Self.meanID }, "The current unusable decision has no canonical mean")
        XCTAssertFalse(nodes.first { $0.identifier == Self.confirmID }?.isEnabled == true)
    }

    private func assertCanonicalMeanAndEnabledConfirmation(_ nodes: [SignUpRenderingProbe.Node], expected: Decimal) throws {
        let mean = try XCTUnwrap(nodes.first { $0.identifier == Self.meanID })
        XCTAssertEqual(try number(mean.label), expected, "Show canonical24.13; never recompute24.125")
        let confirm = try XCTUnwrap(nodes.first { $0.identifier == Self.confirmID })
        XCTAssertTrue(confirm.isButton && confirm.isEnabled)
    }

    private func number(_ label: String) throws -> Decimal {
        let pattern = try NSRegularExpression(pattern: "[-+]?[0-9]+(?:[.,][0-9]+)?")
        let match = try XCTUnwrap(pattern.matches(in: label, range: NSRange(label.startIndex..., in: label)).last,
            "No number in the dedicated canonical mean node: \(label)")
        let range = try XCTUnwrap(Range(match.range, in: label))
        return try XCTUnwrap(Decimal(string: String(label[range]).replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")))
    }
}

private enum SignupPhotoCurrentSexFixtureError: Error { case missingEstimate, invalidDecimal }

/// A public DTO selection script. It makes no claim about backend rules by sex.
private actor SignupPhotoCurrentSexDecisionPeer: SignupBodyPhotosProviding {
    let base: PresentationPhotoPeer
    init(base: PresentationPhotoPeer) { self.base = base }

    func state() async throws -> SignupBodyPhotoState {
        let raw = try await base.state()
        guard let source = raw.estimate else { throw SignupPhotoCurrentSexFixtureError.missingEstimate }
        guard let canonical = Decimal(string: "24.13", locale: Locale(identifier: "en_US_POSIX"))
        else { throw SignupPhotoCurrentSexFixtureError.invalidDecimal }
        let readings = try zip(SignupBodyPhotoPose.allCases, ["18.125", "24.125", "30.125"]).map { pose, text in
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
            else { throw SignupPhotoCurrentSexFixtureError.invalidDecimal }
            return SignupBodyPhotoEstimate.Reading(pose: pose, bodyFatPercent: value)
        }
        let masculine = SignupBodyPhotoEstimate.Decision(usable: false, bodyFatPercent: nil,
            reason: "synthetic-current-sex-control")
        let feminine = SignupBodyPhotoEstimate.Decision(usable: true, bodyFatPercent: canonical, reason: nil)
        let estimate = SignupBodyPhotoEstimate(isEstimate: source.isEstimate,
            bySex: .init(masculine: masculine, feminine: feminine), sourceIDs: source.sourceIDs,
            fingerprint: source.fingerprint, readings: readings)
        return .init(available: raw.available, unavailableReason: raw.unavailableReason, consent: raw.consent,
            minimumAge: raw.minimumAge, poses: raw.poses, estimate: estimate, remainingUploads: raw.remainingUploads)
    }

    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await base.consent(attempt) }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await base.create(attempt) }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(attempt) }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.delete(attempt) }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.repair(attempt) }
}

@MainActor
private struct SignupPhotoCurrentSexViewHarness {
    let base: PresentationHarness
    let factory: PresentationFactoryPeer
    let model: SignupBodyPhotoPresentationModel

    init() async throws {
        let base = try await PresentationHarness(hasEstimate: true)
        let peer = SignupPhotoCurrentSexDecisionPeer(base: base.peer)
        let factory = PresentationFactoryPeer(scope: presentationScope(base.scope, photos: peer))
        let box = base.ownerBox, clock = base.clock
        model = .init(flow: base.flow, ownerToken: base.owner, capability: factory.capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "result-current-sex-view"),
            pollingTiming: .init(elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }),
            isCurrentOwner: { $0 == box.current })
        self.base = base; self.factory = factory
    }

    func prepare() async { await model.load(); model.select(.photos); await model.acceptConsent() }

    func stop() async {
        model.invalidate()
        if let core = model.capture { await core.waitForStoppedPollingWork() }
        base.clean()
    }
}
#endif

#if DEBUG
extension SignupBodyPhotoResultCurrentSexRenderingTests {
    func testMissingCurrentSexKeepsThreeReadingsAndExplicitBodyDataInstructionInPortugueseAndEnglish() async throws {
        let h = try await SignupPhotoViewHarness(fixture: .valid)
        do {
            await h.prepare()
            let core = try XCTUnwrap(h.model.capture)
            XCTAssertTrue(core.isActive && core.hasAcceptedConsent)
            XCTAssertEqual(h.model.route, .result)
            XCTAssertNotNil(h.base.flow.draft.birthDate)
            let readings = try XCTUnwrap(core.state?.estimate?.readings)
            XCTAssertEqual(readings.map(\.pose), SignupBodyPhotoPose.allCases)
            XCTAssertEqual(readings.map(\.bodyFatPercent), [Decimal(18), Decimal(24), Decimal(30)])
            let baseline = await h.base.peer.snapshot()
            XCTAssertEqual(baseline.mutationAndStageSteps, [.consent])

            // Real draft mutation; public DTO/state stays the same three reads.
            h.base.flow.updateBiologicalSex(nil)
            XCTAssertNil(h.base.flow.draft.biologicalSex)
            XCTAssertEqual(h.model.route, .result)
            XCTAssertNil(h.model.currentEstimateDecision)
            XCTAssertNil(h.model.confirmableEstimate)
            XCTAssertTrue(h.model.capture === core && core.isActive && core.hasAcceptedConsent)
            let valueIDs = ["onboarding.photos.result.reading.front",
                "onboarding.photos.result.reading.side", "onboarding.photos.result.reading.back"]
            for language in [SupportedAppLanguage.portugueseBrazil, .englishUnitedStates] {
                let context = language.rawValue
                let expectedInstruction = language == .portugueseBrazil
                    ? "Escolha o sexo biológico nos dados corporais para revisar esta estimativa."
                    : "Choose your biological sex in body data to review this estimate."
                let nodes = SignUpRenderingProbe.nodes(
                    SignupBodyPhotoResultView(photos: h.model)
                        .environment(\.locale, language.formattingLocale),
                    width: 393, height: 3_000)
                let values = valueIDs.compactMap { id in nodes.first { $0.identifier == id } }
                // No throwing unwrap for absent product nodes: both locales
                // get their semantic RED assertions on the EmptyView baseline.
                XCTAssertEqual(values.count, 3, context)
                XCTAssertEqual(try values.map { try number($0.label) },
                    [Decimal(18), Decimal(24), Decimal(30)], context)
                XCTAssertEqual(nodes.first { $0.identifier == "onboarding.photos.result.sex-required" }?.label,
                    expectedInstruction, context)
                let confirm = nodes.first { $0.identifier == Self.confirmID }
                XCTAssertNotNil(confirm, context)
                XCTAssertTrue(confirm?.isButton == true, context)
                XCTAssertFalse(confirm?.isEnabled == true, context)
                for id in ["onboarding.photos.result.manual", "onboarding.photos.result.skip"] {
                    let action = nodes.first { $0.identifier == id }
                    XCTAssertNotNil(action, context)
                    XCTAssertTrue(action?.isButton == true && action?.isEnabled == true, context)
                }
                XCTAssertFalse(nodes.contains { $0.identifier == Self.meanID },
                    "No official decision can be selected without the current sex: \(context)")
                XCTAssertNil(h.base.flow.draft.bodyFatPercent, context)
                XCTAssertNil(h.base.flow.draft.bodyFatOrigin, context)
                XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation, context)
            }
            let confirmed = h.model.confirmEstimate()
            XCTAssertFalse(confirmed, "The real Parent must refuse an estimate without current biological sex")
            XCTAssertNil(h.base.flow.draft.bodyFatPercent)
            XCTAssertNil(h.base.flow.draft.bodyPhotoConfirmation)
            XCTAssertEqual(core.state?.estimate?.readings?.map(\.bodyFatPercent), readings.map(\.bodyFatPercent))
            let after = await h.base.peer.snapshot(), binds = await h.factory.snapshot()
            XCTAssertEqual(after.calls, baseline.calls, "Rendering/sex mutation/refused confirmation must not GET or mutate")
            XCTAssertEqual(after.count(.stage), 0)
            XCTAssertEqual(after.count(.create), 0)
            XCTAssertEqual(after.count(.put), 0)
            XCTAssertEqual(after.count(.complete), 0)
            XCTAssertEqual(after.count(.delete), 0)
            XCTAssertEqual(after.count(.repair), 0)
            XCTAssertEqual(binds, [h.base.owner.userID])
            XCTAssertNil(h.base.model.capture, "Unused base Parent must not be bound")
            await h.stop()
        } catch { await h.stop(); throw error }
    }
}
#endif
