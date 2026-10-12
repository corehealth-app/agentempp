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
    private var epoch = 0
    private var observerEpoch: Int?

    private(set) var choice: SignupBodyFatChoice?
    private(set) var capture: SignupBodyPhotoCaptureModel?
    private(set) var isActive = true
    private(set) var loadFailed = false

    var availability: SignupBodyPhotoAvailability {
        guard currentOwner, !flow.isReacceptance, !loadFailed else { return .unavailable }
        return .resolve(draft: flow.draft, state: capture?.state,
            hasCapability: capability != nil, now: timeProvider.now)
    }

    var route: SignupBodyPhotoRoute? {
        guard currentOwner, choice == .photos, availability == .available,
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
        guard currentOwner, !Task.isCancelled, let capability else { return }
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

    func invalidate() {
        epoch += 1; observerEpoch = nil; isActive = false
        bindingTask?.cancel()
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
        allowsAction && choice == .photos && availability == .available
    }

    private func checkLoad(_ loadingEpoch: Int) throws {
        guard currentOwner, epoch == loadingEpoch, !Task.isCancelled else { throw CancellationError() }
    }

    private func observe(_ state: SignupBodyPhotoState?) {
        guard currentOwner, choice == .photos, observerEpoch == epoch else { return }
        flow.reconcileBodyPhotoState(state)
    }

    private func leavePhotos(choice: SignupBodyFatChoice?) {
        epoch += 1; observerEpoch = nil; self.choice = choice
        capture?.declineConsent()
    }
}
