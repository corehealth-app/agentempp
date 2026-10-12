#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

enum PresentationUnavailableCase: CaseIterable, Sendable {
    case noCapability, disabled, missingDocument, localeMismatch, underage, missingBirthDate
}
enum PresentationLoadHold: CaseIterable, Sendable { case factory, state }

@MainActor
@Suite("Signup photo presentation guards and reentry", .serialized)
struct SignupBodyPhotoPresentationGuardTests {
    @Test("P03 photo preflight gates preserve manual/skip and cannot send without consent",
        arguments: PresentationUnavailableCase.allCases)
    func unavailablePhotosHaveNoMutationAuthority(reason: PresentationUnavailableCase) async throws {
        let h = try await PresentationHarness(manual: 24,
            available: reason != .disabled, missingDocument: reason == .missingDocument,
            documentLocale: reason == .localeMismatch ? "en-US" : "pt-BR",
            installsCapability: reason != .noCapability,
            birthDate: reason == .underage ? "2015-01-02" : (reason == .missingBirthDate ? "" : "1990-01-02"))
        defer { h.clean() }
        await h.model.load()
        let expected: SignupBodyPhotoAvailability
        switch reason {
        case .localeMismatch: expected = .consentLocaleMismatch
        case .underage: expected = .underage
        case .missingBirthDate: expected = .birthDateRequired
        default: expected = .unavailable
        }
        #expect(h.model.availability == expected)
        h.model.select(.photos)
        #expect(h.model.choice != .photos && h.model.route == nil)
        await h.model.acceptConsent()
        await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        h.model.select(.typed)
        #expect(h.model.choice == .typed && h.flow.draft.bodyFatPercent == 24)
        h.model.select(.skip)
        #expect(h.model.choice == .skip && h.flow.draft.bodyFatPercent == nil)
        #expect(h.flow.draft.bodyFatOrigin == nil && h.flow.draft.bodyPhotoConfirmation == nil)
        let trace = await h.peer.snapshot()
        #expect(trace.mutationAndStageSteps.isEmpty)
        if reason == .noCapability { #expect(await h.factory.snapshot().isEmpty) }
        else { #expect(await h.factory.snapshot() == [h.owner.userID]) }
    }

    @Test("P04 delayed factory/GET cannot publish after cancel or A to B to later A",
        arguments: PresentationLoadHold.allCases, [false, true])
    func delayedLoadHasOwnerAndEpochBoundaries(hold: PresentationLoadHold, cancel: Bool) async throws {
        let h = try await PresentationHarness(manual: 24, holdFactory: hold == .factory)
        defer { h.clean() }
        if hold == .state { await h.peer.holdNextState() }
        let gate = hold == .factory ? h.factory.gate : h.stateGate
        let originalDraft = h.flow.draft
        let loading = Task { await h.model.load(); await gate.operationFinished() }
        let entered = await gate.entryOrOperationEnd()
        if !entered {
            await gate.release(); await loading.value
            try #require(entered)
        }
        if cancel { h.model.invalidate(); loading.cancel() }
        else {
            h.ownerBox.current = .init(userID: CleanupProcessorHarness.b, restoreGeneration: 2)
            h.ownerBox.current = .init(userID: h.owner.userID, restoreGeneration: 3)
        }
        await gate.release(); await loading.value
        #expect(h.model.availability == .unavailable && h.model.route == nil)
        #expect(h.model.capture?.state == nil)
        #expect(h.flow.draft == originalDraft)
        let trace = await h.peer.snapshot()
        #expect(trace.count(.state) == (hold == .factory ? 0 : 1))
        #expect(trace.mutationAndStageSteps.isEmpty)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
    }

    @Test("P05 manual/skip fence pending receipt and reenter photos with the same capture/scope",
        arguments: [SignupBodyFatChoice.typed, .skip])
    func manualThenPhotosReusesCaptureWithoutOldConsentAuthority(exit: SignupBodyFatChoice) async throws {
        let h = try await PresentationHarness(manual: 24, holdConsent: true)
        defer { h.clean() }
        await h.model.load()
        h.model.select(.photos)
        let original = try #require(h.model.capture)
        let accepting = Task { await h.model.acceptConsent(); await h.consentGate.operationFinished() }
        let entered = await h.consentGate.entryOrOperationEnd()
        if !entered {
            await h.consentGate.release(); await accepting.value
            try #require(entered)
        }
        do {
            h.model.select(exit)
            #expect(h.model.choice == exit && h.model.route == nil)
            #expect(h.flow.draft.bodyFatPercent == (exit == .typed ? 24 : nil))
            #expect(h.flow.draft.bodyFatOrigin == (exit == .typed ? .typed : nil))
            await h.consentGate.release(); await accepting.value
            #expect(!original.hasAcceptedConsent)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
            let beforeReentry = await h.peer.snapshot()
            #expect(beforeReentry.count(.consent) == 1)
            #expect(beforeReentry.count(.stage) == 0 && beforeReentry.count(.create) == 0 && beforeReentry.count(.put) == 0)
            h.model.select(.photos)
            await h.model.load()
            let reused = try #require(h.model.capture)
            #expect(reused === original)
            #expect(!reused.hasAcceptedConsent && h.model.route == .consent)
            #expect(h.flow.draft.bodyFatPercent == (exit == .typed ? 24 : nil))
            await h.model.acceptConsent()
            #expect(reused.hasAcceptedConsent)
            await h.model.capture(CaptureModelHarness.data, pose: .front, channel: .gallery)
            let after = await h.peer.snapshot()
            #expect(after.count(.consent) == 2)
            #expect(after.count(.stage) == 1 && after.count(.create) == 1 && after.count(.put) == 1 && after.count(.complete) == 1)
            #expect(after.count(.delete) == 0 && after.count(.repair) == 0)
            #expect(h.flow.draft.bodyFatPercent == (exit == .typed ? 24 : nil))
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await h.model.waitForLocalCleanup()
        } catch {
            await h.consentGate.release(); await accepting.value
            throw error
        }
    }
}
#endif
