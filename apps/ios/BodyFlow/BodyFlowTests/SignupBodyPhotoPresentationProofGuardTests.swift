#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo presentation current draft and proof owner", .serialized)
struct SignupBodyPhotoPresentationProofGuardTests {
    @Test("P11 accepted old consent cannot bypass the current DOB/locale preflight",
        arguments: [false, true])
    func currentDraftGateAppliesBeforeEveryCaptureAndConfirm(changeLocale: Bool) async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let capture = try #require(h.model.capture)
        #expect(capture.hasAcceptedConsent)
        let before = await h.peer.snapshot()
        if changeLocale { h.flow.updateLocaleIdentifier("en-US") }
        else {
            h.flow.updateBirthDate(OnboardingCivilDate.date(from: "2015-01-02", timeZoneIdentifier: h.flow.draft.timeZoneIdentifier))
        }
        #expect(h.model.availability == (changeLocale ? .consentLocaleMismatch : .underage))
        #expect(!h.model.confirmEstimate())
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
        let after = await h.peer.snapshot()
        #expect(after.calls == before.calls)
        #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(after.count(.delete) == 0 && after.count(.repair) == 0)
    }

    @Test("P12 old held state and stale controls cannot clear/apply a proof after owner generation changes")
    func obsoletePhotoObserverHasNoFlowAuthority() async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        #expect(h.model.confirmEstimate())
        let capture = try #require(h.model.capture)
        let oldState = try #require(capture.state)
        let oldDraft = h.flow.draft
        await h.peer.replaceReadIDs()
        await h.peer.holdNextState()
        let load = Task { await h.model.load(); await h.stateGate.operationFinished() }
        let entered = await h.stateGate.entryOrOperationEnd()
        if !entered {
            await h.stateGate.release(); await load.value
            try #require(entered)
        }
        h.ownerBox.current = .init(userID: h.owner.userID, restoreGeneration: h.owner.restoreGeneration + 1)
        await h.stateGate.release(); await load.value
        #expect(capture.state == oldState)
        #expect(h.model.availability == .unavailable && h.model.route == nil)
        #expect(!h.model.confirmEstimate())
        h.model.select(.skip)
        h.model.rejectEstimate()
        #expect(h.flow.draft == oldDraft)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        let trace = await h.peer.snapshot()
        #expect(trace.mutationAndStageSteps == [.consent])
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
    }
}
#endif
