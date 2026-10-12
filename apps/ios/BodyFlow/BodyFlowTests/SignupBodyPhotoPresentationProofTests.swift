#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo presentation confirmation and publications", .serialized)
struct SignupBodyPhotoPresentationProofTests {
    @Test("P06 only explicit confirmation delegates canonical 24; same-value typed clears intent")
    func confirmationAndManualProvenanceAreDistinct() async throws {
        let h = try await PresentationHarness(manual: 24, hasEstimate: true)
        defer { h.clean() }
        await h.model.load()
        h.model.select(.photos)
        #expect(!h.model.confirmEstimate())
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        await h.model.acceptConsent()
        let capture = try #require(h.model.capture)
        let state = try #require(capture.state)
        #expect(state.estimate?.readings?.map(\.pose) == SignupBodyPhotoPose.allCases)
        #expect(state.estimate?.readings?.map(\.bodyFatPercent) == [Decimal(18), Decimal(24), Decimal(30)])
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(h.model.confirmEstimate())
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
        let proof = try #require(h.flow.draft.bodyPhotoConfirmation)
        #expect(proof == OnboardingBodyPhotoConfirmation.candidate(from: state, sex: .masculine))
        #expect(!h.flow.requiresBodyPhotoRevalidation)
        h.model.select(.typed)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        h.model.select(.photos)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        let trace = await h.peer.snapshot()
        #expect(trace.mutationAndStageSteps == [.consent])
    }

    @Test("P07 reject preserves independent typed BF; explicit skip clears every origin",
        arguments: [OnboardingBodyFatOrigin.typed, .photos], PresentationRejectAction.allCases)
    func rejectAndSkipApplyDifferentProofRules(origin: OnboardingBodyFatOrigin, action: PresentationRejectAction) async throws {
        let h = try await PresentationHarness(manual: 24, hasEstimate: true)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        if origin == .photos { #expect(h.model.confirmEstimate()) }
        #expect(h.flow.draft.bodyFatOrigin == origin)
        switch action {
        case .reject:
            h.model.rejectEstimate()
            #expect(h.flow.draft.bodyFatPercent == (origin == .typed ? 24 : nil))
            #expect(h.flow.draft.bodyFatOrigin == (origin == .typed ? .typed : nil))
        case .skip:
            h.model.select(.skip)
            #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyFatOrigin == nil)
        }
        #expect(h.flow.draft.bodyPhotoConfirmation == nil && h.model.route == nil)
        let trace = await h.peer.snapshot()
        #expect(trace.mutationAndStageSteps == [.consent])
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
    }

    @Test("P08 changed IDs from real load/pipeline reconcile old proof even with same canonical mean",
        arguments: [false, true])
    func actualStatePublicationsInvalidateChangedProof(pipeline: Bool) async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let capture = try #require(h.model.capture)
        #expect(h.model.confirmEstimate())
        let old = try #require(h.flow.draft.bodyPhotoConfirmation)
        if pipeline { await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery) }
        else { await h.peer.replaceReadIDs(); await h.model.load() }
        let sameCapture = try #require(h.model.capture)
        #expect(sameCapture === capture)
        let current = try #require(capture.state)
        let next = try #require(OnboardingBodyPhotoConfirmation.candidate(from: current, sex: .masculine))
        #expect(next.value == old.value && next.sourceIDs != old.sourceIDs)
        #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyFatOrigin == nil)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(h.model.confirmEstimate())
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyPhotoConfirmation == next)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        let trace = await h.peer.snapshot()
        #expect(trace.count(.create) == (pipeline ? 1 : 0))
        #expect(trace.count(.put) == (pipeline ? 1 : 0) && trace.count(.complete) == (pipeline ? 1 : 0))
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
        try await h.model.waitForLocalCleanup()
    }

    @Test("P09 old missing readings or official unusable result never supplies a confirmation",
        arguments: PresentationEstimateVariant.allCases)
    func invalidOfficialCandidateIsNotInvented(variant: PresentationEstimateVariant) async throws {
        let h = try await PresentationHarness(manual: 24, hasEstimate: true)
        defer { h.clean() }
        let peer = PresentationVariantPeer(base: h.peer, variant: variant)
        let factory = PresentationFactoryPeer(scope: presentationScope(h.scope, photos: peer))
        let model = SignupBodyPhotoPresentationModel(flow: h.flow, ownerToken: h.owner, capability: factory.capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "presentation-variant"),
            isCurrentOwner: { $0 == h.ownerBox.current })
        defer { model.invalidate() }
        await model.load(); model.select(.photos); await model.acceptConsent()
        let state = try #require(model.capture?.state)
        if variant == .legacyReadings { #expect(state.estimate?.readings == nil) }
        else { #expect(state.estimate?.readings?.map(\.bodyFatPercent) == [Decimal(2), Decimal(24), Decimal(46)]) }
        #expect(!model.confirmEstimate())
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        let trace = await h.peer.snapshot()
        #expect(trace.mutationAndStageSteps == [.consent])
    }

    @Test("P10 Core observer comes from real load, consent and terminal poll publications")
    func observerUsesActualCapturePublications() async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        var observed: [SignupBodyPhotoState?] = []
        let capture = SignupBodyPhotoCaptureModel(scope: h.scope, ownerToken: h.owner,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "presentation-observer"),
            pollingTiming: .init(elapsed: { await h.clock.elapsed() }, sleep: { try await h.clock.sleep($0) }),
            onStateObserved: { observed.append($0) }, isCurrentOwner: { $0 == h.ownerBox.current })
        defer { capture.invalidate() }
        await capture.load()
        await capture.acceptConsent(birthDate: "1990-01-02")
        await h.peer.forceReading(true)
        await capture.load()
        #expect(observed.count == 3)
        let initialPublication = try #require(observed.last)
        #expect(initialPublication == capture.state)
        let started = await capture.waitForPollingEvent()
        try #require(started)
        let registered = await h.clock.waitForRegistrations(1)
        try #require(registered)
        await h.peer.replaceReadIDs()
        await h.clock.advance(by: .milliseconds(1_500))
        let stopped = await capture.waitForPollingEvent(untilStopped: true)
        try #require(stopped)
        #expect(observed.count == 4)
        let last = try #require(observed.last)
        #expect(last == capture.state)
        #expect(last?.poses.first?.photo?.id == "00000000-0000-4000-8000-000000002001")
        #expect(capture.phase == .ready)
        let trace = await h.peer.snapshot()
        #expect(trace.count(.state) == 3 && trace.mutationAndStageSteps == [.consent])
        #expect(await h.cleanup.registry.activeCount == 0)
    }

    @Test("P14 PP-R1-P2-01 photo reentry without reload invalidates the last proof after a real retake",
        arguments: [SignupBodyFatChoice.typed, .skip])
    func photoReentryWithoutReloadReconcilesRetakeProof(exit: SignupBodyFatChoice) async throws {
        let h = try await PresentationHarness(hasEstimate: true)
        defer { h.clean() }
        await h.model.load()
        h.model.select(.photos)
        await h.model.acceptConsent()
        let originalCapture = try #require(h.model.capture)
        #expect(h.model.confirmEstimate())
        let initial = try #require(h.flow.draft.bodyPhotoConfirmation)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .photos)
        #expect(!h.flow.requiresBodyPhotoRevalidation)

        h.model.select(exit)
        #expect(h.model.choice == exit && h.model.route == nil)
        #expect(h.flow.draft.bodyFatPercent == (exit == .typed ? 24 : nil))
        #expect(h.flow.draft.bodyFatOrigin == (exit == .typed ? .typed : nil))
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)

        // Reenter through the supported choice action without another load.
        h.model.select(.photos)
        let reenteredCapture = try #require(h.model.capture)
        #expect(reenteredCapture === originalCapture)
        #expect(!reenteredCapture.hasAcceptedConsent && h.model.route == .consent)
        await h.model.acceptConsent()
        #expect(reenteredCapture.hasAcceptedConsent)
        #expect(h.model.confirmEstimate())
        let old = try #require(h.flow.draft.bodyPhotoConfirmation)
        #expect(old.value == initial.value && old.sourceIDs == initial.sourceIDs)
        #expect(!h.flow.requiresBodyPhotoRevalidation)

        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
        let sameCapture = try #require(h.model.capture)
        #expect(sameCapture === originalCapture)
        let current = try #require(sameCapture.state)
        let next = try #require(OnboardingBodyPhotoConfirmation.candidate(from: current, sex: .masculine))
        #expect(next.value == old.value && next.sourceIDs != old.sourceIDs)
        #expect(h.flow.draft.bodyFatPercent == nil && h.flow.draft.bodyFatOrigin == nil)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        let trace = await h.peer.snapshot()
        #expect(trace.count(.state) == 2)
        #expect(trace.count(.consent) == 2)
        #expect(trace.count(.stage) == 1 && trace.count(.create) == 1)
        #expect(trace.count(.put) == 1 && trace.count(.complete) == 1)
        #expect(trace.count(.delete) == 0 && trace.count(.repair) == 0)
        try await h.model.waitForLocalCleanup()
        #expect(await h.cleanup.registry.activeCount == 0)
    }
}
#endif
