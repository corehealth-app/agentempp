#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

/// Additive PP05: no replacement, mode change, owner change or Core teardown.
@MainActor
@Suite("Signup producer authorization ends with caller cancellation", .serialized)
struct SignupBodyPhotoParentProducerCancellationTests {
    @Test("PP05 direct caller cancel revokes detached gallery/permission authorization",
        arguments: [MealSourceChannel.gallery, .camera])
    func callerCancelRevokesItsHeldSDKAuthorization(channel: MealSourceChannel) async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.hasAcceptedConsent && h.model.choice == .photos)
        let baseline = await h.peer.snapshot()
        let gate = CaptureConsentGate(holds: true), probe = SignupParentProducerProbe()
        let cancellation = SignupParentProducerCancellationBox()
        let input = CaptureModelHarness.data
        let caller = Task {
            await h.model.producePhoto(pose: .side, channel: channel) { authorization in
                try await withTaskCancellationHandler {
                    try await authorization.validate()
                    await probe.began()
                    await gate.enter() // SDK intentionally ignores cancellation until returning
                    let authorized = await Task.detached {
                        do { try await authorization.validate(); return true }
                        catch { return false }
                    }.value
                    await probe.postAwait(authorized: authorized, permissionResult: channel == .camera)
                    return authorized ? input : nil
                } onCancel: { cancellation.cancel() }
            }
            await gate.operationFinished()
        }
        let entered = await gate.entryOrOperationEnd()
        if !entered {
            await gate.release(); await caller.value
            try #require(entered, "Actual loader entry is required before caller cancellation")
        }
        do {
            let controller = try #require(h.model.deletion)
            try #require(controller.captureModel === core && controller.canCapture)
            caller.cancel() // only the operation changes; all current UI/session predicates remain true
            #expect(cancellation.isCancelled,
                "Registered loader onCancel must run synchronously before SDK release")
            #expect(h.model.isActive && h.model.capture === core && core.isActive && core.hasAcceptedConsent)
            #expect(h.model.deletion === controller && controller.canCapture)
            #expect(h.model.choice == .photos && h.model.availability == .available)
            #expect(h.ownerBox.current == h.owner)
            #expect(h.model.camera?.origin == MealCameraAccess.Origin.none)
            await gate.release(); await caller.value
            let report = await probe.report(), trace = await h.peer.snapshot()
            #expect(report.loads == 1 && report.authorizedBefore == 1)
            #expect(report.authorizedAfter == 0 && report.rejectedAfter == 1,
                "Cancelled operation must reject a detached noncancelled continuation")
            #expect(report.permissionPresentations == 0,
                "Cancelled granted permission must not authorize the old camera UI")
            #expect(trace.count(.stage) == 0 && trace.count(.create) == 0 && trace.count(.put) == 0)
            #expect(trace.count(.complete) == 0 && trace.count(.delete) == 0 && trace.count(.repair) == 0)
            #expect(trace.calls == baseline.calls, "No GET/consent/mutation compensation after cancel")
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil && input == CaptureModelHarness.data)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await h.model.waitForLocalCleanup()
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        } catch {
            await gate.release(); await caller.value
            throw error
        }
    }
}
#endif
