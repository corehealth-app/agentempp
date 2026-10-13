import Foundation
import Observation

enum SignupBodyPhotoRoute: Hashable, Sendable { case consent, capture, result }

struct SignupBodyPhotoProducerAuthorization: Sendable {
    private let validation: @Sendable () async throws -> Void
    init(validate: @escaping @Sendable () async throws -> Void) {
        validation = validate
    }
    func validate() async throws { try await validation() }
}

/// SDK callbacks can ignore cancellation or resume outside the producer task.
/// Revocation is synchronous; every access to the flag is protected by the lock.
private final class SignupBodyPhotoProducerLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var isActive = true

    func revoke() { lock.withLock { isActive = false } }

    func validate() throws {
        guard lock.withLock({ isActive }) else { throw CancellationError() }
    }
}

/// One retained session scope and capture model. Official publications can
/// revalidate a photo proof; only a separate explicit action confirms it.
@MainActor
@Observable
final class SignupBodyPhotoPresentationModel {
    private let flow: OnboardingFlowModel
    private let ownerToken: OnboardingOwnerToken
    private let capability: SignupBodyPhotoCaptureCapability?
    private let timeProvider: any TimeProviding
    private let keyProvider: any IdempotencyKeyProviding
    private let pollingTiming: SignupBodyPhotoPollingTiming
    private let isCurrentOwner: @MainActor @Sendable (OnboardingOwnerToken) -> Bool
    private var scope: SignupBodyPhotoCaptureScope?
    @ObservationIgnored private var bindingTask: Task<SignupBodyPhotoCaptureScope, Error>?
    @ObservationIgnored private var deletionTask: Task<Void, Never>?
    private var deletionIntent: OnboardingBodyPhotoDeletionIntent?
    // Presentation intent only; preserve the three official slots, including nil.
    private var retakeAnchor: [String?]?
    private var epoch = 0
    private var observerEpoch: Int?

    private(set) var choice: SignupBodyFatChoice?
    private(set) var capture: SignupBodyPhotoCaptureModel?
    private(set) var deletion: SignupBodyPhotoExplicitDeletionModel?
    private(set) var isActive = true
    private(set) var loadFailed = false

    var camera: MealCameraAccess? {
        guard allowsPhotoAction, capture?.hasAcceptedConsent == true else { return nil }
        return scope?.camera
    }

    /// The server's decision for the current draft sex, never a client mean.
    /// Readonly presentation eligibility; confirmation keeps its own guards.
    var currentEstimateDecision: SignupBodyPhotoEstimate.Decision? {
        guard allowsPhotoAction, !flow.hasPendingBodyPhotoDeletion,
              let capture, capture.isActive, capture.hasAcceptedConsent,
              let state = capture.state, state.available,
              let estimate = state.estimate, estimate.isEstimate,
              let sex = flow.draft.biologicalSex else { return nil }
        return sex == .masculine ? estimate.bySex.masculine : estimate.bySex.feminine
    }

    /// Candidate/proof validation remains in the existing canonical validator.
    /// The explicit action may still refuse a Flow cancellation at tap time.
    var confirmableEstimate: OnboardingBodyPhotoConfirmation? {
        guard route == .result, allowsPhotoAction, !flow.hasPendingBodyPhotoDeletion,
              let capture, capture.isActive, capture.hasAcceptedConsent,
              let state = capture.state, let sex = flow.draft.biologicalSex else { return nil }
        return OnboardingBodyPhotoConfirmation.candidate(from: state, sex: sex)
    }

    var resultRequiresBiologicalSex: Bool {
        currentOwner && route == .result && flow.draft.biologicalSex == nil
    }

    var availability: SignupBodyPhotoAvailability {
        guard currentOwner, !flow.isReacceptance, !loadFailed else { return .unavailable }
        return .resolve(draft: flow.draft, state: capture?.state,
            hasCapability: capability != nil, now: timeProvider.now)
    }

    var route: SignupBodyPhotoRoute? {
        guard currentOwner, deletionIntent == nil, choice == .photos, availability == .available,
              let capture else { return nil }
        guard capture.hasAcceptedConsent else { return .consent }
        if retakeAnchor != nil { return .capture }
        if let state = capture.state, state.estimate != nil,
           !state.poses.contains(where: { $0.photo?.status == "reading" }) {
            return .result
        }
        return .capture
    }

    init(flow: OnboardingFlowModel, ownerToken: OnboardingOwnerToken,
        capability: SignupBodyPhotoCaptureCapability?,
        timeProvider: any TimeProviding, keyProvider: any IdempotencyKeyProviding,
        pollingTiming: SignupBodyPhotoPollingTiming = .live(),
        isCurrentOwner: @escaping @MainActor @Sendable (OnboardingOwnerToken) -> Bool) {
        self.flow = flow; self.ownerToken = ownerToken; self.capability = capability
        self.timeProvider = timeProvider; self.keyProvider = keyProvider
        self.pollingTiming = pollingTiming; self.isCurrentOwner = isCurrentOwner
        choice = flow.draft.bodyFatOrigin == .photos ? .photos
            : (flow.draft.bodyFatPercent == nil ? nil : .typed)
    }

    func load() async {
        guard currentOwner, deletionIntent == nil, !Task.isCancelled, let capability else { return }
        epoch += 1
        let loadingEpoch = epoch
        observerEpoch = loadingEpoch
        loadFailed = false
        var resolvedBinding = false
        do {
            if capture == nil {
                if bindingTask == nil {
                    let userID = ownerToken.userID
                    bindingTask = Task { try await capability.scoped(userID) }
                }
                guard let bindingTask else { return }
                let bound = try await bindingTask.value
                resolvedBinding = true
                try checkLoad(loadingEpoch)
                guard bound.userID == ownerToken.userID else { throw CancellationError() }
                try await bound.validateSession()
                try checkLoad(loadingEpoch)
                scope = bound
                capture = SignupBodyPhotoCaptureModel(scope: bound, ownerToken: ownerToken,
                    timeProvider: timeProvider, keyProvider: keyProvider,
                    pollingTiming: pollingTiming,
                    onStateObserved: { [weak self] state in self?.observe(state) },
                    isCurrentOwner: isCurrentOwner)
            }
            try checkLoad(loadingEpoch)
            await capture?.load()
            try checkLoad(loadingEpoch)
            loadFailed = capture?.state == nil
        } catch {
            guard currentOwner, epoch == loadingEpoch else { return }
            // A cancelled initial caller still needs an explicit recovery
            // action. A successfully resolved immutable scope can be reused
            // and validated by that retry, without another factory binding.
            let retainBinding = resolvedBinding && Task.isCancelled && error is CancellationError
            if capture == nil, !retainBinding { bindingTask = nil }
            loadFailed = capture?.state == nil
        }
    }

    func select(_ choice: SignupBodyFatChoice) {
        guard allowsAction else { return }
        switch choice {
        case .photos:
            guard availability == .available else { return }
            self.choice = .photos
            // Core fences work canceled on mode exit. Reentry may accept
            // consent without another load, so its new publications count.
            observerEpoch = epoch
        case .typed:
            leavePhotos(choice: .typed)
            flow.updateBodyFatPercent(flow.draft.bodyFatPercent)
        case .skip:
            leavePhotos(choice: .skip)
            flow.updateBodyFatPercent(nil)
        }
    }

    func acceptConsent() async {
        guard allowsPhotoAction, let capture, let birthDate = flow.draft.birthDate,
              let civilBirthDate = OnboardingCivilDate.string(from: birthDate,
                timeZoneIdentifier: flow.draft.timeZoneIdentifier) else { return }
        await capture.acceptConsent(birthDate: civilBirthDate)
    }

    func declineConsent() {
        guard allowsAction else { return }
        flow.reconcileBodyPhotoState(nil)
        leavePhotos(choice: flow.draft.bodyFatPercent == nil ? .skip : .typed)
    }

    @discardableResult
    func beginRetake() -> Bool {
        guard route == .result, allowsPhotoAction, !flow.hasPendingBodyPhotoDeletion,
              let capture, capture.isActive, capture.hasAcceptedConsent,
              let state = capture.state else { return false }
        retakeAnchor = officialPhotoIDs(in: state)
        return true
    }

    @discardableResult
    func confirmEstimate() -> Bool {
        guard route == .result, allowsPhotoAction, let capture, capture.hasAcceptedConsent,
              let state = capture.state else { return false }
        return flow.confirmBodyPhotoEstimate(state)
    }

    func rejectEstimate() {
        guard allowsAction else { return }
        flow.reconcileBodyPhotoState(nil)
        leavePhotos(choice: flow.draft.bodyFatPercent == nil ? nil : .typed)
    }

    func producePhoto(pose: SignupBodyPhotoPose, channel: MealSourceChannel,
        load: @escaping @Sendable (SignupBodyPhotoProducerAuthorization) async throws -> Data?) async {
        guard allowsPhotoAction, channel.isPhoto, let scope, let capture,
              capture.hasAcceptedConsent else { return }
        let producerEpoch = epoch
        let controller = retainedDeletionController(scope: scope, capture: capture)
        let lifetime = SignupBodyPhotoProducerLifetime()
        let authorization = SignupBodyPhotoProducerAuthorization { [weak self, weak capture] in
            try lifetime.validate()
            guard let self, let capture else { throw CancellationError() }
            try await self.validateProducer(producerEpoch, capture: capture)
            try lifetime.validate()
        }
        // D1 retains the producer before its first await and drains it before
        // DELETE. The captured mode and consumer identity cannot revive on reentry.
        await controller.producePhoto(pose: pose, channel: channel) {
            try await withTaskCancellationHandler {
                defer { lifetime.revoke() }
                try await authorization.validate()
                let data: Data?
                do { data = try await load(authorization) }
                catch {
                    // A late SDK error has the same authority boundary as
                    // late bytes. Preserve errors only for the current loader.
                    try await authorization.validate()
                    throw error
                }
                try await authorization.validate()
                return data
            } onCancel: { lifetime.revoke() }
        }
    }

    func capture(_ data: Data, pose: SignupBodyPhotoPose, channel: MealSourceChannel) async {
        guard allowsPhotoAction, let capture, capture.hasAcceptedConsent else { return }
        await capture.capture(data, pose: pose, channel: channel)
    }

    func retry(pose: SignupBodyPhotoPose) async {
        guard allowsPhotoAction, let capture, capture.hasAcceptedConsent else { return }
        await capture.retry(pose: pose)
    }

    func deletePhotos() async {
        // Join before consulting phase: ready can be published before the
        // parent has adopted it, and must not start a second DELETE there.
        if let deletionTask { await deletionTask.value; return }
        guard allowsAction, deletionIntent == nil, let scope, let capture,
              let intent = flow.beginBodyPhotoDeletion(for: ownerToken) else { return }
        deletionIntent = intent
        retakeAnchor = nil
        let controller = retainedDeletionController(scope: scope, capture: capture)
        await runDeletion(controller, intent: intent, retry: false)
    }

    private func retainedDeletionController(scope: SignupBodyPhotoCaptureScope,
        capture: SignupBodyPhotoCaptureModel) -> SignupBodyPhotoExplicitDeletionModel {
        if let deletion { return deletion }
        let controller = SignupBodyPhotoExplicitDeletionModel(scope: scope, ownerToken: ownerToken,
            captureModel: capture, timeProvider: timeProvider, keyProvider: keyProvider,
            pollingTiming: pollingTiming,
            onStateObserved: { [weak self] state in self?.observe(state) },
            isCurrentOwner: isCurrentOwner)
        deletion = controller
        return controller
    }

    private func validateProducer(_ producerEpoch: Int,
        capture: SignupBodyPhotoCaptureModel) async throws {
        try checkProducer(producerEpoch, capture: capture)
        guard let scope else { throw CancellationError() }
        try await scope.validateSession()
        try checkProducer(producerEpoch, capture: capture)
    }

    private func checkProducer(_ producerEpoch: Int,
        capture: SignupBodyPhotoCaptureModel) throws {
        guard epoch == producerEpoch, allowsPhotoAction, self.capture === capture,
              capture.isActive, capture.hasAcceptedConsent, deletion?.canCapture == true else {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    func retryDeletion() async {
        if let deletionTask { await deletionTask.value; return }
        guard allowsAction, let deletion, let intent = deletionIntent else { return }
        await runDeletion(deletion, intent: intent, retry: true)
    }

    private func runDeletion(_ controller: SignupBodyPhotoExplicitDeletionModel,
        intent: OnboardingBodyPhotoDeletionIntent, retry: Bool) async {
        let work = Task {
            defer { self.deletionTask = nil }
            // A caller can cancel after installing the intent but before D1
            // starts. Idle has no attempt yet; recovery starts that dispatch.
            if retry && controller.phase != .idle { await controller.retryDeletion() }
            else { await controller.deletePhotos() }
            guard self.currentOwner, !Task.isCancelled, self.deletion === controller,
                  self.deletionIntent == intent, controller.phase == .ready,
                  controller.receipt != nil, controller.captureModel.state != nil,
                  self.flow.finishBodyPhotoDeletion(intent) else { return }
            // D1 already performed the guarded GET on the retained scope.
            // A mode change cannot invalidate this separate operation identity.
            self.capture = controller.captureModel
            self.deletionIntent = nil
            self.loadFailed = false
            self.observerEpoch = self.choice == .photos ? self.epoch : nil
        }
        deletionTask = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    func invalidate() {
        retakeAnchor = nil
        epoch += 1; observerEpoch = nil; isActive = false
        bindingTask?.cancel()
        deletionTask?.cancel()
        deletion?.invalidate()
        capture?.invalidate()
    }

    func waitForLocalCleanup() async throws {
        try await capture?.waitForLocalCleanup()
    }

    private var currentOwner: Bool {
        isActive && flow.isActive && flow.userID == ownerToken.userID && isCurrentOwner(ownerToken)
    }

    private var allowsAction: Bool {
        currentOwner && flow.allowsDraftEditing && !flow.isReacceptance
            && flow.operationState != .saving && !Task.isCancelled
    }

    private var allowsPhotoAction: Bool {
        allowsAction && deletionIntent == nil && choice == .photos && availability == .available
    }

    private func checkLoad(_ loadingEpoch: Int) throws {
        guard currentOwner, epoch == loadingEpoch, !Task.isCancelled else { throw CancellationError() }
    }

    private func observe(_ state: SignupBodyPhotoState?) {
        guard currentOwner, deletionIntent == nil, choice == .photos, observerEpoch == epoch else { return }
        flow.reconcileBodyPhotoState(state)
        if let anchor = retakeAnchor, let state,
           retakeResultIsReady(state, replacing: anchor) {
            retakeAnchor = nil
        }
    }

    private func officialPhotoIDs(in state: SignupBodyPhotoState) -> [String?] {
        SignupBodyPhotoPose.allCases.map { pose in
            state.poses.first { $0.pose == pose }?.photo?.id
        }
    }

    // Read the incoming official snapshot: Core publishes state before phase.
    // Usability/readings belong to the existing result/confirmation contracts.
    private func retakeResultIsReady(_ state: SignupBodyPhotoState,
        replacing anchor: [String?]) -> Bool {
        guard state.available, state.consent?.acceptedAt != nil, state.estimate != nil,
              state.poses.map(\.pose) == SignupBodyPhotoPose.allCases,
              officialPhotoIDs(in: state) != anchor else { return false }
        return state.poses.allSatisfy { slot in
            guard let photo = slot.photo else { return false }
            return !photo.id.isEmpty && photo.status == "read"
        }
    }

    private func leavePhotos(choice: SignupBodyFatChoice?) {
        retakeAnchor = nil
        epoch += 1; observerEpoch = nil; self.choice = choice
        capture?.declineConsent()
    }
}
