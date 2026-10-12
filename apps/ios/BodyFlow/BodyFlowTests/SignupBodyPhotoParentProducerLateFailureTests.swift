#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

enum SignupParentProducerLateFailureExit: String, CaseIterable, Sendable {
    case modeReentry, callerCancel, samePoseReplacement
}
private enum SignupParentProducerScriptedSDKError: Error, Sendable { case failed }

@MainActor
@Suite("Signup parent producer scopes late SDK errors", .serialized)
struct SignupBodyPhotoParentProducerLateFailureTests {
    @Test("PP06 obsolete SDK throw cannot publish producerFailure after mode/cancel/replacement",
        arguments: SignupParentProducerLateFailureExit.allCases)
    func obsoleteSDKErrorIsNotPublished(_ exit: SignupParentProducerLateFailureExit) async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.hasAcceptedConsent && h.model.choice == .photos)
        let gate = CaptureConsentGate(holds: true), probe = SignupParentProducerProbe()
        let cancellation = SignupParentProducerCancellationBox()
        let caller = Task {
            await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
                try await withTaskCancellationHandler {
                    try await authorization.validate()
                    await probe.began()
                    await gate.enter() // SDK ignores cancellation; throws a non-CancellationError afterward
                    throw SignupParentProducerScriptedSDKError.failed
                } onCancel: { cancellation.cancel() }
            }
            await gate.operationFinished()
        }
        let entered = await gate.entryOrOperationEnd()
        if !entered {
            await gate.release(); await caller.value
            try #require(entered, "Real SDK loader must begin before obsolescence")
        }
        do {
            let controller = try #require(h.model.deletion)
            try #require(controller.captureModel === core && controller.canCapture)
            #expect(controller.producerFailure == nil)
            switch exit {
            case .modeReentry:
                h.model.select(.typed)
                h.model.select(.photos)
                await h.model.acceptConsent()
                try #require(core.hasAcceptedConsent && h.model.choice == .photos)
                #expect(!cancellation.isCancelled,
                    "Mode exit is fenced by Parent epoch; it did not cancel this held D1 loader")
            case .callerCancel:
                caller.cancel()
                #expect(cancellation.isCancelled,
                    "Actual SDK cancellation handler must run synchronously before release")
            case .samePoseReplacement:
                let replacement = SignupParentProducerProbe()
                await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
                    try await authorization.validate()
                    await replacement.began()
                    return nil
                }
                let report = await replacement.report()
                try #require(report.loads == 1 && report.authorizedBefore == 1,
                    "Replacement control must be a real admitted loader")
                #expect(cancellation.isCancelled)
            }
            // All present-day eligibility stays valid. Only the old operation
            // is obsolete; a generic SDK throw must not revive its error UI.
            try #require(h.model.isActive && h.model.capture === core && core.isActive && core.hasAcceptedConsent)
            try #require(h.model.choice == .photos && h.model.availability == .available)
            #expect(h.ownerBox.current == h.owner)
            #expect(h.model.deletion === controller && controller.canCapture)
            let beforeReturn = await h.peer.snapshot()
            await gate.release(); await caller.value
            let report = await probe.report(), trace = await h.peer.snapshot()
            #expect(report.loads == 1 && report.authorizedBefore == 1)
            #expect(controller.producerFailure == nil,
                "Obsolete loader's non-CancellationError must be fenced before D1 publishes it")
            #expect(trace.calls == beforeReturn.calls)
            #expect(trace.count(.stage) == 0 && trace.count(.create) == 0 && trace.count(.put) == 0)
            #expect(trace.count(.complete) == 0 && trace.count(.delete) == 0 && trace.count(.repair) == 0)
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await h.model.waitForLocalCleanup()
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await gate.release(); await caller.value
            throw error
        }
    }

    @Test("PP06 current SDK throw still publishes its mapped failure")
    func currentSDKErrorIsStillPublished() async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.hasAcceptedConsent && h.model.choice == .photos)
        let before = await h.peer.snapshot(), probe = SignupParentProducerProbe()
        await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
            try await authorization.validate()
            await probe.began()
            throw SignupParentProducerScriptedSDKError.failed
        }
        let controller = try #require(h.model.deletion)
        let report = await probe.report(), trace = await h.peer.snapshot()
        #expect(report.loads == 1 && report.authorizedBefore == 1)
        #expect(controller.producerFailure == .unavailable,
            "Current generic SDK failures must remain visible; blanket suppression is invalid")
        #expect(controller.captureModel === core && core.isActive && core.hasAcceptedConsent)
        #expect(trace.calls == before.calls)
        #expect(trace.count(.stage) == 0 && trace.count(.create) == 0 && trace.count(.put) == 0)
        #expect(trace.count(.complete) == 0 && trace.count(.delete) == 0 && trace.count(.repair) == 0)
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        #expect(h.flow.draft.bodyPhotoConfirmation == nil)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        try await h.model.waitForLocalCleanup()
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
    }
}
#endif
