import Foundation
import Observation

enum SignupBodyPhotoRoute: Hashable, Sendable { case consent, capture, result }

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
    private var epoch = 0
    private var observerEpoch: Int?

    private(set) var choice: SignupBodyFatChoice?
    private(set) var capture: SignupBodyPhotoCaptureModel?
    private(set) var deletion: SignupBodyPhotoExplicitDeletionModel?
    private(set) var isActive = true
    private(set) var loadFailed = false

    var availability: SignupBodyPhotoAvailability {
        guard currentOwner, !flow.isReacceptance, !loadFailed else { return .unavailable }
        return .resolve(draft: flow.draft, state: capture?.state,
            hasCapability: capability != nil, now: timeProvider.now)
    }

    var route: SignupBodyPhotoRoute? {
        guard currentOwner, deletionIntent == nil, choice == .photos, availability == .available,
              let capture else { return nil }
        guard capture.hasAcceptedConsent else { return .consent }
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
        do {
            if capture == nil {
                if bindingTask == nil {
                    let userID = ownerToken.userID
                    bindingTask = Task { try await capability.scoped(userID) }
                }
                guard let bindingTask else { return }
                let bound = try await bindingTask.value
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
            guard currentOwner, epoch == loadingEpoch, !Task.isCancelled else { return }
            if capture == nil { bindingTask = nil }
            loadFailed = true
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
    func confirmEstimate() -> Bool {
        guard allowsPhotoAction, let capture, capture.hasAcceptedConsent,
              let state = capture.state else { return false }
        return flow.confirmBodyPhotoEstimate(state)
    }

    func rejectEstimate() {
        guard allowsAction else { return }
        flow.reconcileBodyPhotoState(nil)
        leavePhotos(choice: flow.draft.bodyFatPercent == nil ? nil : .typed)
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
        let controller: SignupBodyPhotoExplicitDeletionModel
        if let deletion { controller = deletion }
        else {
            controller = SignupBodyPhotoExplicitDeletionModel(scope: scope, ownerToken: ownerToken,
                captureModel: capture, timeProvider: timeProvider, keyProvider: keyProvider,
                pollingTiming: pollingTiming,
                onStateObserved: { [weak self] state in self?.observe(state) },
                isCurrentOwner: isCurrentOwner)
            deletion = controller
        }
        await runDeletion(controller, intent: intent, retry: false)
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
    }

    private func leavePhotos(choice: SignupBodyFatChoice?) {
        epoch += 1; observerEpoch = nil; self.choice = choice
        capture?.declineConsent()
    }
}
