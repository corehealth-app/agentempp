#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo presentation load and consent", .serialized)
struct SignupBodyPhotoPresentationLoadConsentTests {
    @Test("P01 load binds once and photo choice only navigates without changing BF",
        arguments: [false, true])
    func loadRetainsScopeAndPhotoChoicePreservesDraft(hasManual: Bool) async throws {
        let h = try await PresentationHarness(manual: hasManual ? 24 : nil)
        defer { h.clean() }
        let draft = h.flow.draft
        await h.model.load()
        let first = try #require(h.model.capture)
        #expect(h.model.availability == .available)
        #expect(h.model.choice == (hasManual ? .typed : nil))
        #expect(h.flow.draft == draft)
        h.model.select(.photos)
        #expect(h.model.choice == .photos && h.model.route == .consent)
        #expect(h.flow.draft == draft)
        await h.model.load()
        let second = try #require(h.model.capture)
        #expect(first === second)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        let trace = await h.peer.snapshot()
        #expect(trace.count(.state) == 2)
        #expect(trace.mutationAndStageSteps.isEmpty)
    }

    @Test("P02 consent delegates current document with civil DOB and never confirms BF or uploads")
    func consentIsSeparateFromEstimateConfirmation() async throws {
        let h = try await PresentationHarness(manual: 24, hasEstimate: true)
        defer { h.clean() }
        await h.model.load()
        let capture = try #require(h.model.capture)
        let document = try #require(capture.state?.consent)
        h.model.select(.photos)
        await h.model.acceptConsent()
        let trace = await h.peer.snapshot()
        let attempt = try #require(trace.consents.first)
        #expect(trace.consents.count == 1)
        #expect(attempt.payload.version == document.version && attempt.payload.bodyHash == document.bodyHash)
        #expect(attempt.payload.birthDate == "1990-01-02")
        #expect(capture.hasAcceptedConsent)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(trace.count(.stage) == 0 && trace.count(.create) == 0 && trace.count(.put) == 0)
        #expect(trace.count(.complete) == 0 && trace.count(.delete) == 0 && trace.count(.repair) == 0)
    }
}
#endif
