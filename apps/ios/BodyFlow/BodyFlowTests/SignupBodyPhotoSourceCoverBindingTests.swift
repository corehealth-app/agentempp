#if DEBUG
import Foundation
import Observation
import SwiftUI
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup source cover binding UUID lifetime", .serialized)
struct SignupBodyPhotoSourceCoverBindingTests {
    @Test("H01 an obsolete cover binding cannot cancel the next real Parent/Source request")
    func obsoleteNilSetterKeepsTheNextRequestAndCurrentNilCancelsOnce() async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.isActive && core.hasAcceptedConsent && h.model.route == .capture)
        let baseline = await h.peer.snapshot()
        #expect(baseline.count(.state) == 1 && baseline.mutationAndStageSteps == [.consent])
        let source = SignupBodyPhotoSourcePresentationModel()
        let completion = SourceCoverBindingCompletion()
        var workA: Task<Void, Never>?
        var workB: Task<Void, Never>?
        do {
            let eventA = sourceCoverBindingEvent(source)
            let a = Task {
                await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
                    await completion.loaderEntered()
                    let bytes = try await source.request(channel: .gallery, camera: nil,
                        authorization: authorization)
                    await completion.loaderReturned(bytes)
                    return bytes
                }
                completion.producerEnds += 1
                await eventA.operationEnded()
            }
            workA = a
            let presentationA = try #require(await eventA.presentationOrOperationEnd(),
                "Prerequisite: actual registered Parent loader publishes Source request A")
            #expect(presentationA.channel == .gallery && presentationA.camera == nil)
            let controller = try #require(h.model.deletion)
            #expect(controller.captureModel === core && controller.canCapture)
            let bindingA = SignupBodyPhotoFlowSurface.presentationBinding(for: source)
            #expect(bindingA.wrappedValue?.id == presentationA.id)
            bindingA.wrappedValue = nil // current A cancellation must really resolve its choice
            await a.value
            #expect(source.presentation == nil)
            #expect(completion.producerEnds == 1 && completion.nilReturns == 1)
            #expect(completion.loaderEntries == 1 && completion.byteReturns == 0)

            let eventB = sourceCoverBindingEvent(source)
            let b = Task {
                await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
                    await completion.loaderEntered()
                    let bytes = try await source.request(channel: .gallery, camera: nil,
                        authorization: authorization)
                    await completion.loaderReturned(bytes)
                    return bytes
                }
                completion.producerEnds += 1
                await eventB.operationEnded()
            }
            workB = b
            let presentationB = try #require(await eventB.presentationOrOperationEnd(),
                "Prerequisite: actual registered Parent loader publishes distinct Source request B")
            #expect(presentationB.id != presentationA.id)
            #expect(source.presentation?.id == presentationB.id)
            #expect(completion.producerEnds == 1 && completion.loaderEntries == 2)
            #expect(h.model.deletion === controller && controller.captureModel === core)
            let bindingB = SignupBodyPhotoFlowSurface.presentationBinding(for: source)
            #expect(bindingB.wrappedValue?.id == presentationB.id)

            // Exact old-setter trace: retain binding A, publish B, then issue
            // A's obsolete nil event. It must not consult B's current UUID.
            bindingA.wrappedValue = nil
            #expect(source.presentation?.id == presentationB.id,
                "An old cover's nil setter must leave the next Source request intact")

            // The current binding can cancel B; a duplicate nil cannot
            // resolve its continuation twice or end a third producer.
            bindingB.wrappedValue = nil
            bindingB.wrappedValue = nil
            await b.value
            #expect(source.presentation == nil)
            #expect(completion.loaderEntries == 2 && completion.nilReturns == 2)
            #expect(completion.byteReturns == 0 && completion.producerEnds == 2)
            #expect(controller.producerFailure == nil && controller.canCapture)
            #expect(h.model.capture === core && h.model.deletion === controller)
            #expect(core.isActive && core.hasAcceptedConsent && h.model.route == .capture)
            let after = await h.peer.snapshot()
            #expect(after.calls == baseline.calls, "Binding events do not GET, consent or mutate the capture pipeline")
            #expect(after.count(.state) == 1 && after.count(.stage) == 0)
            #expect(after.count(.create) == 0 && after.count(.put) == 0 && after.count(.complete) == 0)
            #expect(after.count(.delete) == 0 && after.count(.repair) == 0)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            try await h.model.waitForLocalCleanup()
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
            #expect(await h.cleanup.registry.activeCount == 0)
        } catch {
            workA?.cancel(); workB?.cancel()
            if let id = source.presentation?.id { source.cancel(requestID: id) }
            await workA?.value; await workB?.value
            throw error
        }
    }
}

@MainActor
private final class SourceCoverBindingCompletion {
    var loaderEntries = 0
    var nilReturns = 0
    var byteReturns = 0
    var producerEnds = 0
    func loaderEntered() { loaderEntries += 1 }
    func loaderReturned(_ bytes: Data?) {
        if bytes == nil { nilReturns += 1 } else { byteReturns += 1 }
    }
}

/// Observe actual Source publication or actual outer producer completion.
/// This duplicates only the private event observer pattern in S01; no timer,
/// polling, yield, phase setter, model-only hook or prefix signal.
private actor SourceCoverBindingEvent {
    private var value: SignupBodyPhotoSourcePresentation?
    private var ended = false
    private var waiters: [CheckedContinuation<SignupBodyPhotoSourcePresentation?, Never>] = []
    func publish(_ value: SignupBodyPhotoSourcePresentation) {
        guard self.value == nil, !ended else { return }
        self.value = value
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume(returning: value) }
    }
    func operationEnded() {
        ended = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume(returning: value) }
    }
    func presentationOrOperationEnd() async -> SignupBodyPhotoSourcePresentation? {
        if let value { return value }
        if ended { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
private func sourceCoverBindingEvent(_ source: SignupBodyPhotoSourcePresentationModel) -> SourceCoverBindingEvent {
    let event = SourceCoverBindingEvent()
    withObservationTracking { _ = source.presentation } onChange: {
        // Sample after Observation's pre-mutation notification on MainActor.
        Task { @MainActor in
            if let current = source.presentation { await event.publish(current) }
        }
    }
    return event
}
#endif
