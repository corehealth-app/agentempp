import Foundation
import Observation

enum SignupBodyPhotoExplicitDeletionPhase: Equatable, Sendable {
    case idle, draining, requesting, awaitingReload, ready
    case failed(SignupBodyPhotoFailure)
}

/// Internal UI composition only. Explicit deletion has an empty command and
/// counted receipt; it is not repair(G), consent revocation or remote absence.
@MainActor
@Observable
final class SignupBodyPhotoExplicitDeletionModel {
    private let scope: SignupBodyPhotoCaptureScope
    private let ownerToken: OnboardingOwnerToken
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let isCurrentOwner: @MainActor @Sendable (OnboardingOwnerToken) -> Bool
    private var epoch = 0
    private var producers: [UUID: Task<Void, Never>] = [:]
    private var latestProducer: [SignupBodyPhotoPose: UUID] = [:]
    private var deletionTask: Task<Void, Never>?
    private var deletionID: UUID?
    private var attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>?
    private var received: [UUID: SignupBodyPhotoDeleteReceipt] = [:]
    private var reloadCapture: SignupBodyPhotoCaptureModel?

    private(set) var captureModel: SignupBodyPhotoCaptureModel
    private(set) var phase = SignupBodyPhotoExplicitDeletionPhase.idle
    private(set) var receipt: SignupBodyPhotoDeleteReceipt?
    private(set) var isActive = true
    private(set) var producerFailure: SignupBodyPhotoFailure?

    var canCapture: Bool {
        currentOwner && (phase == .idle || phase == .ready)
            && captureModel.isActive && captureModel.hasAcceptedConsent
            && captureModel.state?.available == true
    }

    init(scope: SignupBodyPhotoCaptureScope, ownerToken: OnboardingOwnerToken,
         captureModel: SignupBodyPhotoCaptureModel,
         timeProvider: any TimeProviding = SystemTimeProvider(),
         keyProvider: any IdempotencyKeyProviding = RandomIdempotencyKeyProvider(),
         isCurrentOwner: @escaping @MainActor @Sendable (OnboardingOwnerToken) -> Bool) {
        self.scope = scope; self.ownerToken = ownerToken; self.captureModel = captureModel
        self.timeProvider = timeProvider; self.keyProvider = keyProvider
        self.isCurrentOwner = isCurrentOwner
    }

    /// One UI producer (picker, permission/camera result); nil means cancel.
    /// Superseded producers remain retained until their actual completion.
    func producePhoto(pose: SignupBodyPhotoPose, channel: MealSourceChannel,
                      load: @escaping @Sendable () async throws -> Data?) async {
        guard canCapture, channel.isPhoto, !Task.isCancelled else { return }
        if let previous = latestProducer[pose] { producers[previous]?.cancel() }
        let id = UUID(), operationEpoch = epoch
        latestProducer[pose] = id
        producerFailure = nil
        let work = Task {
            defer {
                self.producers[id] = nil
                if self.latestProducer[pose] == id { self.latestProducer[pose] = nil }
            }
            do {
                try await self.producerBoundary(operationEpoch, id: id, pose: pose)
                guard let data = try await load() else { return }
                try await self.producerBoundary(operationEpoch, id: id, pose: pose)
                await self.captureModel.capture(data, pose: pose, channel: channel)
                try await self.producerBoundary(operationEpoch, id: id, pose: pose)
            } catch {
                if self.currentOwner, self.epoch == operationEpoch, self.latestProducer[pose] == id,
                   !(error is CancellationError) {
                    self.producerFailure = SignupBodyPhotoFailure(error)
                }
            }
        }
        producers[id] = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// Only an explicit user action may start this operation.
    func deletePhotos() async {
        if let deletionTask { await deletionTask.value; return }
        guard currentOwner, !Task.isCancelled, phase == .idle || phase == .ready else { return }
        attempt = nil
        receipt = nil
        await beginDeletion()
    }

    /// The original attempt survives uncertain replies; a known receipt
    /// changes recovery to GET only, using the original retained scope.
    func retryDeletion() async {
        if let deletionTask { await deletionTask.value; return }
        guard currentOwner, !Task.isCancelled, case .failed = phase else { return }
        await beginDeletion()
    }

    private func beginDeletion() async {
        epoch += 1
        let operationEpoch = epoch, id = UUID()
        deletionID = id
        for producer in producers.values { producer.cancel() }
        latestProducer.removeAll()
        producerFailure = nil
        phase = receipt == nil ? .draining : .awaitingReload
        let work = Task {
            defer {
                self.received[id] = nil
                if self.deletionID == id { self.deletionTask = nil }
            }
            do {
                if self.receipt == nil {
                    let oldCapture = self.captureModel
                    let ownedProducers = Array(self.producers.values)
                    // Invalidate the consumer before waiting on a held picker.
                    // Cancellation alone does not establish its completion.
                    let drain = Task { await oldCapture.invalidateAndWaitForOwnedCaptureWork() }
                    for producer in ownedProducers { await producer.value }
                    await drain.value
                    try self.check(operationEpoch, id: id)
                    try await oldCapture.waitForLocalCleanup()
                    try await self.boundary(operationEpoch, id: id)
                    if self.attempt == nil {
                        self.attempt = MutationAttempt(operation: .mediaDelete,
                            key: try self.keyProvider.nextKey(), payload: SignupBodyPhotoDeleteCommand(),
                            createdAt: self.timeProvider.now)
                    }
                    guard let original = self.attempt else { throw SignupBodyPhotoFailure.unavailable }
                    self.phase = .requesting
                    try await self.scope.performWork {
                        try await self.request(original, epoch: operationEpoch, id: id)
                    }
                    try await self.boundary(operationEpoch, id: id)
                    guard let result = self.received.removeValue(forKey: id) else {
                        throw SignupBodyPhotoFailure.unavailable
                    }
                    // Publish only after the scope's real work registry finished.
                    self.receipt = result
                }
                try await self.reload(epoch: operationEpoch, id: id)
            } catch {
                guard self.currentOwner, self.epoch == operationEpoch, self.deletionID == id else { return }
                self.phase = .failed(SignupBodyPhotoFailure(error))
            }
        }
        deletionTask = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private func request(_ original: MutationAttempt<SignupBodyPhotoDeleteCommand>, epoch: Int, id: UUID) async throws {
        try await boundary(epoch, id: id)
        let result = try await scope.photos.delete(original)
        try await boundary(epoch, id: id)
        received[id] = result
    }

    private func reload(epoch: Int, id: UUID) async throws {
        try await boundary(epoch, id: id)
        phase = .awaitingReload
        let candidate = SignupBodyPhotoCaptureModel(scope: scope, ownerToken: ownerToken,
            timeProvider: timeProvider, keyProvider: keyProvider, isCurrentOwner: isCurrentOwner)
        reloadCapture = candidate
        var published = false
        defer {
            if !published { candidate.invalidate() }
            if reloadCapture === candidate { reloadCapture = nil }
        }
        await candidate.load()
        try await boundary(epoch, id: id)
        guard candidate.state != nil else {
            if case .failed(let failure) = candidate.phase { throw failure }
            throw SignupBodyPhotoFailure.unavailable
        }
        captureModel = candidate
        published = true
        phase = .ready
    }

    private func producerBoundary(_ epoch: Int, id: UUID, pose: SignupBodyPhotoPose) async throws {
        try checkProducer(epoch, id: id, pose: pose)
        try await scope.validateSession()
        try checkProducer(epoch, id: id, pose: pose)
    }

    private func checkProducer(_ epoch: Int, id: UUID, pose: SignupBodyPhotoPose) throws {
        guard currentOwner, self.epoch == epoch, latestProducer[pose] == id, canCapture else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func boundary(_ epoch: Int, id: UUID) async throws {
        try check(epoch, id: id)
        try await scope.validateSession()
        try check(epoch, id: id)
    }

    private func check(_ epoch: Int, id: UUID) throws {
        guard currentOwner, self.epoch == epoch, deletionID == id else { throw CancellationError() }
        try Task.checkCancellation()
    }

    /// Local route/owner exit only; zero automatic DELETE or repair.
    func invalidate() {
        epoch += 1
        isActive = false
        for producer in producers.values { producer.cancel() }
        latestProducer.removeAll()
        deletionTask?.cancel()
        reloadCapture?.invalidate()
        captureModel.invalidate()
    }

    private var currentOwner: Bool {
        isActive && scope.userID == ownerToken.userID && isCurrentOwner(ownerToken)
    }
}
