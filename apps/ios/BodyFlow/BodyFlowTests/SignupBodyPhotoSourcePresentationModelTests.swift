#if DEBUG
import Foundation
import PhotosUI
import Testing
import UIKit
@testable import BodyFlow

@MainActor
@Suite("Signup source presentation and SDK leaf", .serialized)
struct SignupBodyPhotoSourcePresentationModelTests {
    @Test("S01 registered Parent loader owns two library requests; old reply/cancel cannot close the next")
    func libraryCancellationAndOldRepliesKeepTheOriginalParentScope() async throws {
        let h = try await PresentationHarness(manual: 24)
        defer { h.clean() }
        await h.model.load(); h.model.select(.photos); await h.model.acceptConsent()
        let core = try #require(h.model.capture)
        try #require(core.hasAcceptedConsent)
        let baseline = await h.peer.snapshot()
        let source = SignupBodyPhotoSourcePresentationModel()
        var firstID: UUID?
        for round in 0..<2 {
            let event = sourcePresentationEvent(source)
            let work = Task {
                await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
                    try await source.request(channel: .gallery, camera: nil, authorization: authorization)
                }
                await event.operationEnded()
            }
            let published = await event.presentationOrOperationEnd()
            guard let published else {
                work.cancel(); if let id = source.presentation?.id { source.cancel(requestID: id) }
                await work.value
                try #require(published != nil, "Real presentation must publish before the registered producer can finish")
                return
            }
            do {
                #expect(published.channel == .gallery && published.camera == nil)
                #expect(source.presentation?.id == published.id)
                let d1 = try #require(h.model.deletion)
                #expect(d1.captureModel === core && d1.canCapture)
                if round == 0 {
                    firstID = published.id
                    source.cancel(requestID: published.id)
                    source.finishLibrary(requestID: published.id, result: .success(nil))
                } else {
                    let old = try #require(firstID)
                    #expect(old != published.id)
                    source.cancel(requestID: old)
                    source.finishLibrary(requestID: old, result: .success(nil))
                    #expect(source.presentation?.id == published.id,
                        "Stale SDK/dismiss callbacks must not resolve the current UI request")
                    source.finishLibrary(requestID: published.id, result: .success(nil))
                    source.finishLibrary(requestID: published.id, result: .success(nil))
                }
                await work.value
                #expect(source.presentation == nil)
            } catch {
                work.cancel(); source.cancel(requestID: published.id); await work.value
                throw error
            }
        }
        let after = await h.peer.snapshot()
        #expect(after.calls == baseline.calls)
        #expect(after.count(.stage) == 0 && after.count(.create) == 0 && after.count(.put) == 0)
        #expect(after.count(.complete) == 0 && after.count(.delete) == 0 && after.count(.repair) == 0)
        #expect(h.model.capture === core && core.isActive)
        #expect(await h.factory.snapshot() == [h.owner.userID])
        #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
        try await h.model.waitForLocalCleanup()
        try await h.cleanup.lifecycle.validate(h.cleanup.lease)
        #expect(await h.cleanup.registry.activeCount == 0)
    }

    @Test("S02 actual NSItemProvider data/error callback validates before and after its await")
    func heldProviderPreservesBytesAndRejectsRevokedAuthorization() async throws {
        for scenario in 0..<3 { // authorized bytes, revoked bytes, authorized SDK error
            let auth = SourceAuthorizationCounter(), callback = SourceProviderCallback()
            let selected = SignupBodyPhotoPickedImage(itemProvider: sourceProvider(callback))
            let input = Data([1, 2, 3, 4]) // loader bytes only, not a JPEG/normalizer proof
            let work = Task { () -> Result<Data, any Error> in
                let result: Result<Data, any Error>
                do { result = .success(try await selected.loadData(authorization: auth.authorization)) }
                catch { result = .failure(error) }
                await callback.gate.operationFinished()
                return result
            }
            let entered = await callback.gate.entryOrOperationEnd()
            guard entered else {
                callback.release(.failure(CancellationError())); _ = await work.value
                try #require(entered, "The actual registered provider callback must be entered")
                return
            }
            #expect(auth.count >= 1, "Authorization is validated before asking the provider")
            if scenario == 1 { auth.revoke() }
            callback.release(scenario == 2 ? .failure(SourceLeafScriptError.supplied) : .success(input))
            let result = await work.value
            #expect(auth.count >= 2, "Success and error returns both validate after the SDK await")
            switch (scenario, result) {
            case (0, .success(let value)): #expect(value == input)
            case (1, .failure(let error)): #expect(error is CancellationError)
            case (2, .failure(let error)):
                // NSItemProvider wraps registration-handler errors. Preserve
                // its actual callback error and require the supplied cause.
                let callbackError = error as NSError
                #expect(callbackError.domain == NSItemProvider.errorDomain)
                #expect(callbackError.code == NSItemProvider.ErrorCode.itemUnavailableError.rawValue)
                let underlying = try #require(callbackError.userInfo[NSUnderlyingErrorKey] as? NSError)
                let supplied = SourceLeafScriptError.supplied as NSError
                #expect(underlying.domain == supplied.domain && underlying.code == supplied.code)
            default: Issue.record("Wrong current/revoked provider outcome for scenario \(scenario)")
            }
            #expect(input == Data([1, 2, 3, 4]))
        }
    }

    @Test("S03 empty PHPicker delegate finishes once with nil, without creating a PHPickerResult")
    func emptyLibraryDelegateIsAOneShotCancellation() {
        let id = UUID()
        var calls = 0, cancellations = 0
        let wrapper = SignupBodyPhotoLibraryPicker(requestID: id) { replyID, result in
            calls += 1
            #expect(replyID == id)
            switch result {
            case .success(let selected):
                if selected == nil { cancellations += 1 }
                else { Issue.record("Empty SDK results cannot fabricate an image") }
            case .failure: Issue.record("Empty SDK results are cancellation, not a scripted failure")
            }
        }
        let coordinator = wrapper.makeCoordinator()
        let controller = PHPickerViewController(configuration: PHPickerConfiguration())
        coordinator.picker(controller, didFinishPicking: [])
        coordinator.picker(controller, didFinishPicking: [])
        #expect(calls == 1 && cancellations == 1)
    }

    @Test("S04 unavailable/denied never request access; held notAsked revalidates before camera presentation")
    func cameraAvailabilityPermissionAndLateGrantUseOnlyTheSuppliedAccess() async throws {
        for scenario in 0..<4 { // none, denied device, synthetic grant, synthetic revoked grant
            let source = SignupBodyPhotoSourcePresentationModel(), auth = SourceAuthorizationCounter()
            let permission = SourcePermissionCounter(), gate = CaptureConsentGate(holds: true)
            let event = sourcePresentationEvent(source)
            let camera = MealCameraAccess(
                origin: scenario == 0 ? .none : (scenario == 1 ? .device : .synthetic),
                isAvailable: { scenario != 0 },
                permission: { scenario < 2 ? .denied : .notAsked },
                requestAccess: { permission.record(); await gate.enter(); return true })
            let work = Task { () -> Result<Data?, any Error> in
                let result: Result<Data?, any Error>
                do { result = .success(try await source.request(channel: .camera,
                    camera: camera, authorization: auth.authorization)) }
                catch { result = .failure(error) }
                await gate.operationFinished(); await event.operationEnded()
                return result
            }
            if scenario < 2 {
                let unexpectedlyAsked = await gate.entryOrOperationEnd()
                #expect(!unexpectedlyAsked,
                    "Unavailable/known-denied camera must never ask the permission SDK")
                if unexpectedlyAsked {
                    // A regression must fail without leaving its fake SDK held.
                    auth.revoke(); await gate.release()
                    if let obsolete = await event.presentationOrOperationEnd() {
                        source.cancel(requestID: obsolete.id)
                    }
                    _ = await work.value
                    #expect(permission.count == 0)
                } else {
                    let result = await work.value
                    #expect(source.presentation == nil && permission.count == 0)
                    switch result {
                    case .success(let bytes): #expect(bytes == nil)
                    case .failure(let error): #expect((error as? SignupBodyPhotoFailure) == .unavailable)
                    }
                }
                continue
            }
            let entered = await gate.entryOrOperationEnd()
            guard entered else {
                await gate.release(); _ = await work.value
                try #require(entered, "notAsked must use the injected permission request, not fabricate a camera")
                return
            }
            #expect(permission.count == 1 && auth.count >= 1)
            #expect(source.presentation == nil, "Camera cannot be presented before permission returns")
            if scenario == 3 { auth.revoke() }
            await gate.release()
            if scenario == 3 {
                let result = await work.value
                if case .failure(let error) = result { #expect(error is CancellationError) }
                else { Issue.record("A revoked late permission result must reject its authorization") }
                #expect(source.presentation == nil && auth.count >= 2)
            } else {
                let published = await event.presentationOrOperationEnd()
                guard let published else {
                    work.cancel(); if let id = source.presentation?.id { source.cancel(requestID: id) }
                    _ = await work.value
                    try #require(published != nil, "Authorized late permission must publish its actual camera request")
                    return
                }
                #expect(published.channel == .camera && published.camera?.origin == .synthetic)
                #expect(auth.count >= 2)
                source.finishCamera(requestID: published.id, data: nil)
                source.finishCamera(requestID: published.id, data: nil)
                let result = await work.value
                if case .success(let bytes) = result { #expect(bytes == nil) }
                else { Issue.record("Current SDK camera cancellation should finish with nil") }
                #expect(source.presentation == nil)
            }
        }
    }
}
#endif

#if DEBUG
import Foundation
import Observation
import UniformTypeIdentifiers
@testable import BodyFlow

/// One actual Observable presentation event, or actual outer operation end.
/// No polling, Task.yield, timer, sleep or model test-only hook.
private actor SourcePresentationEvent {
    private var value: SignupBodyPhotoSourcePresentation?
    private var ended = false
    private var waiters: [CheckedContinuation<SignupBodyPhotoSourcePresentation?, Never>] = []
    func publish(_ presentation: SignupBodyPhotoSourcePresentation) {
        guard value == nil, !ended else { return }
        value = presentation
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume(returning: presentation) }
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
private func sourcePresentationEvent(_ model: SignupBodyPhotoSourcePresentationModel) -> SourcePresentationEvent {
    let event = SourcePresentationEvent()
    withObservationTracking { _ = model.presentation } onChange: {
        // onChange runs before storage is changed. Read the real publication
        // on MainActor after that mutation; never signal from request prefix.
        Task { @MainActor in
            if let presentation = model.presentation { await event.publish(presentation) }
        }
    }
    return event
}

private final class SourceAuthorizationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = true
    private var validations = 0
    var count: Int { lock.withLock { validations } }
    func revoke() { lock.withLock { allowed = false } }
    func validate() throws {
        let accepted = lock.withLock { validations += 1; return allowed }
        if !accepted { throw CancellationError() }
    }
    var authorization: SignupBodyPhotoProducerAuthorization { .init { try self.validate() } }
}

private final class SourceProviderCallback: @unchecked Sendable {
    let gate = CaptureConsentGate(holds: false)
    private let lock = NSLock()
    private var completion: (@Sendable (Data?, (any Error)?) -> Void)?
    func install(_ completion: @escaping @Sendable (Data?, (any Error)?) -> Void) {
        lock.withLock { self.completion = completion }
        Task { await gate.enter() }
    }
    func release(_ result: Result<Data, any Error>) {
        let once = lock.withLock { let value = completion; completion = nil; return value }
        guard let once else { return }
        switch result {
        case .success(let data): once(data, nil)
        case .failure(let error): once(nil, error)
        }
    }
}

@MainActor
private func sourceProvider(_ callback: SourceProviderCallback) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { completion in
        callback.install(completion)
        return nil
    }
    return provider
}
private enum SourceLeafScriptError: Error, Sendable { case supplied }
private final class SourcePermissionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    var count: Int { lock.withLock { requests } }
    func record() { lock.withLock { requests += 1 } }
}
#endif

#if DEBUG
import Observation

extension SignupBodyPhotoSourcePresentationModelTests {
    @Test("S05 selected NSItemProvider remains owned through Parent/D1 DELETE until its real callback returns")
    func selectedProviderCallbackMustFinishBeforeExplicitDeletion() async throws {
        let h = try await SignupDeleteCompositionHarness()
        defer { h.removeFolder() }
        try await h.prepare()
        let original = try #require(h.model.capture)
        try #require(original.isActive && original.hasAcceptedConsent)
        let source = SignupBodyPhotoSourcePresentationModel()
        let callback = SourceProviderCallback()
        let selected = SignupBodyPhotoPickedImage(itemProvider: sourceProvider(callback))
        let input = CaptureModelHarness.data // SDK bytes only; no JPEG/normalizer claim
        let publication = sourcePresentationEvent(source)
        let completion = SourceDeleteDrainCompletion()
        var deleting: Task<Void, Never>?
        var selectedID: UUID?
        let producer = Task {
            await h.model.producePhoto(pose: .side, channel: .gallery) { authorization in
                try await source.request(channel: .gallery, camera: nil, authorization: authorization)
            }
            completion.producerFinished = true
            await callback.gate.operationFinished()
            await publication.operationEnded()
        }
        do {
            let presentation = try #require(await publication.presentationOrOperationEnd(),
                "Prerequisite: the registered Parent loader must publish its actual library request")
            selectedID = presentation.id
            #expect(presentation.channel == .gallery && presentation.camera == nil)
            source.finishLibrary(requestID: presentation.id, result: .success(selected))
            let entered = await callback.gate.entryOrOperationEnd()
            try #require(entered, "Prerequisite: the real NSItemProvider callback is installed and held")
            #expect(source.presentation == nil && !completion.producerFinished)
            let controller = try #require(h.model.deletion)
            #expect(controller.captureModel === original && controller.canCapture)
            let before = await h.photos.report()
            #expect(before.attempts.isEmpty && before.postDeleteReads == 0)

            let invalidated = CaptureConsentGate(holds: false)
            withObservationTracking { _ = original.isActive } onChange: {
                // Observation fires before storage mutation. Sample the actual
                // old Core and retained D1 on MainActor after invalidation.
                Task { @MainActor in
                    if !original.isActive && controller.phase == .draining {
                        await invalidated.enter()
                    }
                }
            }
            deleting = Task {
                await h.model.deletePhotos()
                completion.deletionFinished = true
                await invalidated.operationFinished()
            }
            let drainEntered = await invalidated.entryOrOperationEnd()
            try #require(drainEntered, "D1 must invalidate the real consumer before waiting on the selected SDK loader")
            #expect(!original.isActive && controller.phase == .draining && !controller.canCapture)
            #expect(!completion.producerFinished && !completion.deletionFinished)
            // Matching cancellation after selection closes no new UI and must
            // not invent the SDK completion that D1 is currently draining.
            source.cancel(requestID: presentation.id)
            let held = await h.photos.report()
            let heldPipeline = await h.base.snapshot()
            #expect(source.presentation == nil)
            #expect(!completion.producerFinished && !completion.deletionFinished)
            #expect(held.attempts.isEmpty && held.postDeleteReads == 0 && held.repairs == 0)
            #expect(held.stateReads == before.stateReads)
            #expect(heldPipeline.count(.stage) == 0 && heldPipeline.count(.create) == 0)
            #expect(heldPipeline.count(.put) == 0 && heldPipeline.count(.complete) == 0)

            callback.release(.success(input)) // only this real callback releases D0
            await producer.value
            if let deleting { await deleting.value }
            let after = await h.photos.report()
            let pipeline = await h.base.snapshot()
            #expect(completion.producerFinished && completion.deletionFinished)
            #expect(after.attempts.count == 1 && after.postDeleteReads == 1 && after.repairs == 0)
            #expect(after.stateReads == before.stateReads + 1)
            let attempt = try #require(after.attempts.first)
            #expect(attempt.operation == .mediaDelete && attempt.payload == SignupBodyPhotoDeleteCommand())
            #expect(controller.receipt == SignupBodyPhotoDeleteReceipt(deleted: 0))
            #expect(controller.phase == .ready && h.model.capture === controller.captureModel)
            #expect(controller.captureModel !== original && !original.isActive)
            #expect(pipeline.count(.stage) == 0 && pipeline.count(.create) == 0)
            #expect(pipeline.count(.put) == 0 && pipeline.count(.complete) == 0)
            #expect(source.presentation == nil && input == CaptureModelHarness.data)
            #expect(h.flow.draft.bodyFatPercent == 24 && h.flow.draft.bodyFatOrigin == .typed)
            #expect(h.flow.draft.bodyPhotoConfirmation == nil)
            #expect(await h.factory.snapshot() == [h.owner.userID])
            try await h.model.waitForLocalCleanup()
            try await h.cleanup.lifecycle.validate(h.cleanup.lease)
            #expect(await h.cleanup.registry.activeCount == 0)
        } catch {
            // A semantic failure must still release the actual SDK callback,
            // join its producer and DELETE, then remove the synthetic folder.
            producer.cancel()
            if let selectedID { source.cancel(requestID: selectedID) }
            callback.release(.failure(CancellationError()))
            await producer.value
            if let deleting { await deleting.value }
            throw error
        }
    }
}

@MainActor
private final class SourceDeleteDrainCompletion {
    var producerFinished = false
    var deletionFinished = false
}
#endif
