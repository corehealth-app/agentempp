#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

/// One additive regression method. Original PP01-PP03/support stay unchanged.
@MainActor
@Suite("Signup parent producer authorization cannot revive after same-pose replacement", .serialized)
struct SignupBodyPhotoParentProducerSupersessionTests {
    @Test("PP04 replaced gallery/permission cannot authorize its old SDK continuation",
        arguments: [MealSourceChannel.gallery, .camera])
    func samePoseReplacementRevokesOldAuthorization(channel: MealSourceChannel) async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.hasAcceptedConsent && h.model.choice == .photos)
        let baseline = await h.peer.snapshot()
        let gate = CaptureConsentGate(holds: true)
        let oldProbe = SignupParentProducerProbe(), replacementProbe = SignupParentProducerProbe()
        let cancellation = SignupParentProducerCancellationBox()
        let input = CaptureModelHarness.data
        let first = Task {
            await h.model.producePhoto(pose: .side, channel: channel) { authorization in
                try await withTaskCancellationHandler {
                    try await authorization.validate()
                    await oldProbe.began()
                    await gate.enter() // SDK/gallery result deliberately ignores cancellation
                    let authorized = await Task.detached {
                        do { try await authorization.validate(); return true }
                        catch { return false }
                    }.value
                    await oldProbe.postAwait(authorized: authorized, permissionResult: channel == .camera)
                    // A broken authorization may return bytes, yet D1's later
                    // pose boundary can still block staging. Test both layers.
                    return authorized ? input : nil
                } onCancel: { cancellation.cancel() }
            }
            await gate.operationFinished()
        }
        let entered = await gate.entryOrOperationEnd()
        if !entered {
            await gate.release(); await first.value
            try #require(entered, "The first real producer must enter before replacement")
        }
        do {
            let controller = try #require(h.model.deletion)
            try #require(controller.captureModel === core && controller.canCapture)
            // Same pose; valid replacement finishes with nil. This must not
            // leave the older producer authorized while the current UI is valid.
            await h.model.producePhoto(pose: .side, channel: channel) { authorization in
                try await authorization.validate()
                await replacementProbe.began()
                try await authorization.validate()
                await replacementProbe.postAwait(authorized: true, permissionResult: false)
                return nil
            }
            let replacement = await replacementProbe.report()
            try #require(replacement.loads == 1 && replacement.authorizedBefore == 1,
                "Replacement is a real admitted producer, not a no-op control")
            #expect(replacement.authorizedAfter == 1 && replacement.rejectedAfter == 0)
            #expect(cancellation.isCancelled, "Existing D1 must supersede the old same-pose task")
            #expect(h.model.deletion === controller && controller.canCapture)
            #expect(h.model.capture === core && core.isActive && core.hasAcceptedConsent)
            #expect(h.model.choice == .photos && h.model.availability == .available)
            #expect(h.model.camera?.origin == MealCameraAccess.Origin.none)
            await gate.release(); await first.value
            let old = await oldProbe.report(), trace = await h.peer.snapshot()
            #expect(old.loads == 1 && old.authorizedBefore == 1)
            #expect(old.authorizedAfter == 0 && old.rejectedAfter == 1,
                "An old authorization must reject even on a detached noncancelled continuation")
            #expect(old.permissionPresentations == 0,
                "A late granted permission must not authorize the obsolete camera UI")
            #expect(trace.count(.stage) == 0 && trace.count(.create) == 0 && trace.count(.put) == 0)
            #expect(trace.count(.complete) == 0 && trace.count(.delete) == 0 && trace.count(.repair) == 0)
            #expect(trace.calls == baseline.calls, "No new state/consent/mutation follows either nil/replaced source")
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil && input == CaptureModelHarness.data)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await h.model.waitForLocalCleanup()
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await gate.release(); await first.value
            throw error
        }
    }
}
#endif
