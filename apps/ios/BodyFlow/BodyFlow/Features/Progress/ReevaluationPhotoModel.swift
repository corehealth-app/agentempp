import Foundation
import Observation

struct ReevaluationPhotoProducer: Identifiable, Equatable, Sendable {
    let id:UUID; let pose:ReevaluationPhotoPose; let channel:MealSourceChannel
}
@MainActor @Observable
final class ReevaluationPhotoModel {
    let cycleID:String
    private let userID:String
    private let capability:ReevaluationPhotoCaptureCapability
    private let keys:any IdempotencyKeyProviding
    private let onMutation:@MainActor () -> Void
    private let onReconciled:@MainActor () async -> Void
    private var scope:ReevaluationPhotoCaptureScope?
    private var ended = false
    private(set) var consent:ReevaluationPhotoConsent?
    private(set) var snapshot:ReevaluationPhotoSnapshot?
    private(set) var consentChecked = false
    private(set) var producer:ReevaluationPhotoProducer?
    private(set) var isBusy = false
    private(set) var error:ReevaluationPhotoFailure?
    private(set) var analysisFailure:ReevaluationPhotoProcessing.Reason?
    private(set) var lastDiscard:ReevaluationPhotoDiscard?
    private struct Accept { let input:ReevaluationPhotoConsentInput; let key:IdempotencyKey }
    private struct Discard { let input:ReevaluationPhotoDiscardInput; let key:IdempotencyKey }
    private struct Capture {
        let media:StagedMedia; let input:ReevaluationPhotoAllocationInput
        let allocateKey:IdempotencyKey; let uploadKey:IdempotencyKey; let completeKey:IdempotencyKey; let processKey:IdempotencyKey
        var asset:ReevaluationPhotoAsset?; var completion:ReevaluationPhotoCompletion?; var uploadUncertain = false
        var processing:ReevaluationPhotoProcessing?
    }
    private var pendingAccept:Accept?
    private var pendingDiscard:Discard?
    private var pendingCapture:Capture?
    private var producerLoad:Task<Void,Never>?
    private var loadingProducerID:UUID?
    var hasPendingIntent:Bool { producer != nil || pendingAccept != nil || pendingDiscard != nil || pendingCapture != nil }
    var hasBlockingWork:Bool { isBusy || hasPendingIntent }
    var canCapture:Bool {
        !ended && !hasBlockingWork && error != .quota && consent?.availability == .available && consent?.acceptance?.acceptanceID == snapshot?.acceptanceID
            && snapshot?.acceptanceID != nil
    }
    var camera:MealCameraAccess { scope?.camera ?? .unavailable }
    init(userID:String,cycleID:String,capability:ReevaluationPhotoCaptureCapability,keys:any IdempotencyKeyProviding,
         onMutation:@escaping @MainActor () -> Void = {},onReconciled:@escaping @MainActor () async -> Void = {}) {
        self.userID = userID; self.cycleID = cycleID.lowercased(); self.capability = capability; self.keys = keys
        self.onMutation = onMutation; self.onReconciled = onReconciled
    }
    private func bound() async throws -> ReevaluationPhotoCaptureScope {
        guard !ended else { throw ReevaluationPhotoFailure.sessionEnded }
        if let scope { try await scope.validateSession(); return scope }
        let value = try await capability.scoped(userID,cycleID)
        guard !ended, value.userID == userID, value.cycleID == cycleID else { throw ReevaluationPhotoFailure.sessionEnded }
        try await value.validateSession(); scope = value; return value
    }
    private func publish(_ scope:ReevaluationPhotoCaptureScope,_ operation:@MainActor @Sendable () throws -> Void) async throws {
        try await scope.photos.publish { [self] in guard !ended else { throw CancellationError() }; try operation() }
    }
    private func readState(_ scope:ReevaluationPhotoCaptureScope) async throws {
        let legal = try await scope.photos.consent().validated(cycleID:cycleID)
        // The server exposes photos only after the current document is accepted.
        // Publish a pending document without retaining an older photo authority.
        let current:ReevaluationPhotoSnapshot?
        if legal.availability == .available {
            current = try await scope.photos.snapshot().validated(cycleID:cycleID)
        } else {
            current = nil
        }
        try await publish(scope) { [self] in
            if consent?.document != legal.document || consent?.acceptance?.acceptanceID != legal.acceptance?.acceptanceID { consentChecked = false }
            consent = legal; snapshot = current
        }
    }
    func load() async {
        guard !ended, !hasBlockingWork else { return }
        isBusy = true; error = nil; defer { isBusy = false }
        do { try await readState(bound()); await onReconciled() } catch { await failed(error) }
    }
    func setConsentChecked(_ value:Bool) { guard !ended, !hasBlockingWork, consent?.document != nil else { return }; consentChecked = value }
    func acceptConsent() async {
        guard !ended, !isBusy, pendingCapture == nil, pendingDiscard == nil, producer == nil else { return }
        if pendingAccept == nil {
            guard consentChecked, let consent else { return }
            do { pendingAccept = Accept(input:try ReevaluationPhotoConsentInput(state:consent),key:try keys.nextKey()) }
            catch { await failed(error); return }
        }
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            guard let attempt = pendingAccept else { return }
            let scope = try await bound(), receipt = try await scope.photos.accept(attempt.input,key:attempt.key).validated(cycleID:cycleID)
            try await publish(scope) { [self] in consent = receipt; pendingAccept = nil; consentChecked = false; lastDiscard = nil }
            try await readState(scope)
        } catch { await failed(error) }
    }
    func beginProducer(pose:ReevaluationPhotoPose,channel:MealSourceChannel) async -> ReevaluationPhotoProducer? {
        guard canCapture, channel.isPhoto else { return nil }
        let request = ReevaluationPhotoProducer(id:UUID(),pose:pose,channel:channel)
        producer = request
        isBusy = true; error = nil; defer { isBusy = false }
        do {
            let scope = try await bound()
            if channel == .camera {
                guard scope.camera.isAvailable(), await scope.camera.requestAccess() else { throw ReevaluationPhotoFailure.unavailable }
                try await scope.validateSession()
            }
            try await publish(scope) { [self] in guard producer == request else { throw CancellationError() } }
            return request
        } catch { cancelProducer(request.id); await failed(error); return nil }
    }
    func validateProducer(_ request:ReevaluationPhotoProducer) async throws {
        guard !ended, producer == request, let scope else { throw CancellationError() }
        try await scope.validateSession()
        guard !ended, producer == request else { throw CancellationError() }
    }
    func cancelProducer(_ id:UUID) {
        if producer?.id == id { producer = nil }
        if loadingProducerID == id { producerLoad?.cancel(); producerLoad = nil; loadingProducerID = nil }
    }
    func receivePicked(_ request:ReevaluationPhotoProducer,load:@escaping @MainActor @Sendable () async throws -> Data) async {
        guard !ended, producer == request, producerLoad == nil, let scope else { return }
        let task = Task { [self] in
            do {
                try await validateProducer(request)
                let bytes = try await scope.loadData { try await load() }
                try await validateProducer(request)
                await receive(request,data:bytes)
            } catch { await producerFailed(request,error:error) }
        }
        producerLoad = task; loadingProducerID = request.id
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if loadingProducerID == request.id { producerLoad = nil; loadingProducerID = nil }
    }
    func producerFailed(_ request:ReevaluationPhotoProducer,error:any Error) async {
        guard !ended, producer == request else { return }
        cancelProducer(request.id); await failed(error)
    }
    func receive(_ request:ReevaluationPhotoProducer,data:Data) async {
        guard !ended, !isBusy, producer == request, pendingCapture == nil, let scope, let revision = snapshot?.cycleRevision,
              let acceptance = consent?.acceptance?.acceptanceID, acceptance == snapshot?.acceptanceID else { return }
        producer = nil; isBusy = true; error = nil; analysisFailure = nil
        var staged:StagedMedia?, retained = false
        defer { isBusy = false }
        do {
            try await scope.validateSession()
            guard !ended else { throw CancellationError() }
            let media = try await scope.stagePhoto(data,request.channel); staged = media
            guard !ended else { throw CancellationError() }
            let input = ReevaluationPhotoAllocationInput(expectedRevision:revision,acceptanceId:acceptance,pose:request.pose,mimeType:media.mimeType,sizeBytes:media.sizeBytes)
            try input.validate()
            let attempt = Capture(media:media,input:input,allocateKey:try keys.nextKey(),uploadKey:try keys.nextKey(),completeKey:try keys.nextKey(),processKey:try keys.nextKey())
            try await publish(scope) { [self] in pendingCapture = attempt; onMutation() }
            retained = true; try await continueCapture(scope)
        } catch {
            if !retained, let staged { try? await scope.discardStaged(staged.fileURL) }
            await failed(error)
        }
    }
    private func store(_ attempt:Capture,_ scope:ReevaluationPhotoCaptureScope) async throws {
        try await publish(scope) { [self] in pendingCapture = attempt }
    }
    private func continueCapture(_ scope:ReevaluationPhotoCaptureScope) async throws {
        guard var attempt = pendingCapture, !ended else { throw CancellationError() }
        if attempt.asset == nil {
            do {
                let allocation = try await scope.photos.allocate(attempt.input,key:attempt.allocateKey).validated(cycleID:cycleID,input:attempt.input)
                attempt.asset = allocation.asset; try await store(attempt,scope)
            } catch ReevaluationPhotoFailure.quota {
                // This specific SQL-authoritative receipt follows allocation
                // replay checks: no new asset was created. Keep the already
                // selected photos usable instead of trapping the whole form.
                try await scope.discardStaged(attempt.media.fileURL)
                try await publish(scope) { [self] in pendingCapture = nil; error = .quota }
                try await readState(scope); await onReconciled(); return
            }
        }
        guard let asset = attempt.asset else { throw ReevaluationPhotoFailure.invalidResponse }
        if attempt.completion == nil {
            if attempt.uploadUncertain {
                do { attempt.completion = try await scope.photos.complete(assetID:asset.id,acceptanceID:asset.acceptanceID,key:attempt.completeKey) }
                catch let failure as ReevaluationPhotoFailure where failure == .changed { /* Missing bytes can be retried only after fresh upload authority. */ }
                if attempt.completion != nil { try await store(attempt,scope) }
            }
            if attempt.completion == nil {
                let ticket = try await scope.photos.issueUpload(assetID:asset.id,acceptanceID:asset.acceptanceID,key:attempt.uploadKey)
                    .validated(cycleID:cycleID,assetID:asset.id,acceptanceID:asset.acceptanceID)
                guard ticket.asset.pose == asset.pose, ticket.asset.mimeType == asset.mimeType, ticket.asset.sizeBytes == asset.sizeBytes else { throw ReevaluationPhotoFailure.invalidResponse }
                attempt.uploadUncertain = true; try await store(attempt,scope)
                do { try await scope.upload(attempt.media,ticket) }
                catch {
                    if error is CancellationError || error is SessionLifecycleError || error as? ReevaluationPhotoFailure == .sessionEnded || ended { throw error }
                    // A timed-out/duplicate PUT may have succeeded. Inspect the
                    // exact asset instead of allocating or overwriting again.
                    do { attempt.completion = try await scope.photos.complete(assetID:asset.id,acceptanceID:asset.acceptanceID,key:attempt.completeKey) }
                    catch { throw ReevaluationPhotoFailure.offline }
                    try await store(attempt,scope)
                }
                if attempt.completion == nil {
                    do { attempt.completion = try await scope.photos.complete(assetID:asset.id,acceptanceID:asset.acceptanceID,key:attempt.completeKey) }
                    catch let failure as ReevaluationPhotoFailure where failure == .changed { throw ReevaluationPhotoFailure.unavailable }
                    try await store(attempt,scope)
                }
            }
        }
        guard let completion = attempt.completion else { throw ReevaluationPhotoFailure.invalidResponse }
        _ = try completion.validated(cycleID:cycleID,assetID:asset.id,acceptanceID:asset.acceptanceID)
        if attempt.processing == nil {
            let result = try await scope.photos.process(assetID:asset.id,key:attempt.processKey).validated(cycleID:cycleID,assetID:asset.id)
            if result.status == .skipped { throw ReevaluationPhotoFailure.busy }
            attempt.processing = result; try await store(attempt,scope)
        }
        try await scope.discardStaged(attempt.media.fileURL)
        let reason = attempt.processing?.reason
        try await publish(scope) { [self] in pendingCapture = nil; analysisFailure = reason; error = reason == nil ? nil : .unavailable }
        try await readState(scope); guard !ended else { throw CancellationError() }; await onReconciled()
    }
    func discard() async {
        guard !ended, !isBusy, pendingAccept == nil else { return }
        producer = nil; isBusy = true; error = nil; defer { isBusy = false }
        do {
            let scope = try await bound()
            if pendingDiscard == nil {
                let current = try await scope.photos.snapshot().validated(cycleID:cycleID)
                guard let acceptance = current.acceptanceID else { throw ReevaluationPhotoFailure.changed }
                let attempt = Discard(input:.init(acceptanceId:acceptance,expectedRevision:current.cycleRevision),key:try keys.nextKey())
                try await publish(scope) { [self] in pendingDiscard = attempt; onMutation() }
            }
            guard let attempt = pendingDiscard else { return }
            let receipt = try await scope.photos.discard(attempt.input,key:attempt.key).validated(cycleID:cycleID,acceptanceID:attempt.input.acceptanceId)
            if let media = pendingCapture?.media { try await scope.discardStaged(media.fileURL) }
            try await publish(scope) { [self] in pendingDiscard = nil; pendingCapture = nil; lastDiscard = receipt; consentChecked = false }
            try await readState(scope); await onReconciled()
        } catch { await failed(error) }
    }
    func retry() async {
        guard !ended, !isBusy else { return }
        if pendingAccept != nil { await acceptConsent() }
        else if pendingDiscard != nil { await discard() }
        else if pendingCapture != nil {
            isBusy = true; error = nil; defer { isBusy = false }
            do { try await continueCapture(bound()) } catch { await failed(error) }
        } else { await load() }
    }
    func invalidate() {
        ended = true; producer = nil; producerLoad?.cancel(); producerLoad = nil; loadingProducerID = nil
        if let scope, let url = pendingCapture?.media.fileURL { Task { try? await scope.discardStaged(url) } }
        pendingCapture = nil; pendingAccept = nil; pendingDiscard = nil; consent = nil; snapshot = nil; consentChecked = false
        lastDiscard = nil; analysisFailure = nil; error = nil; scope = nil
    }
    private func failed(_ failure:any Error) async {
        guard !ended else { return }
        if failure is CancellationError || Task.isCancelled { return }
        if failure is SessionLifecycleError || failure as? ReevaluationPhotoFailure == .sessionEnded { invalidate(); return }
        guard let scope else { error = failure as? ReevaluationPhotoFailure ?? .unavailable; return }
        do {
            if failure as? ReevaluationPhotoFailure == .changed {
                if let url = pendingCapture?.media.fileURL { try await scope.discardStaged(url) }
                try await publish(scope) { [self] in pendingCapture = nil; pendingAccept = nil; pendingDiscard = nil; producer = nil; consentChecked = false; consent = nil; snapshot = nil; error = .changed }
            } else { try await publish(scope) { [self] in error = failure as? ReevaluationPhotoFailure ?? .unavailable } }
        } catch { invalidate() }
    }
}
