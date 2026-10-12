import Foundation

/// Confirmed authentication activation, independent of onboarding presentation.
struct SignupBodyPhotoCleanupOwnerToken: Equatable, Sendable {
    let userID: String
    let activationID: UUID
}

/// Retains one session scope through onboarding, home and foreground events.
@MainActor
final class SignupBodyPhotoCleanupRootCoordinator {
    private let capability: SignupBodyPhotoCleanupCapability?
    private var owner: SignupBodyPhotoCleanupOwnerToken?
    private var bindingID = UUID()
    private var binding: Task<SignupBodyPhotoCleanupScope, Error>?
    private var processor: SignupBodyPhotoCleanupCoordinator?
    private var pendingOfficial: [String: OnboardingBodyPhotoCleanupScope] = [:]
    private var active = false
    private var restoreReady = false
    private var activeEventID = UUID()
    private var scheduledEvents: Set<UUID> = []
    private var event: Task<Void, Never>?

    init(capability: SignupBodyPhotoCleanupCapability?) {
        self.capability = capability
    }

    func transition(to requested: SignupBodyPhotoCleanupOwnerToken?) async {
        if owner == requested, processor != nil { return }
        if owner != requested {
            invalidate()
            owner = requested
        }
        guard let requested, let capability else { return }
        binding?.cancel()
        let id = UUID()
        bindingID = id
        let task = Task { try await capability.scoped(requested.userID) }
        binding = task
        do {
            let scope = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            guard current(requested, id), !Task.isCancelled,
                  scope.userID == requested.userID else { return }
            try await scope.validateSession()
            guard current(requested, id), !Task.isCancelled else { return }
            let consumer = SignupBodyPhotoCleanupCoordinator(scope: scope, isCurrentOwner: { [weak self] in
                self?.current(requested, id) == true
            })
            processor = consumer
            binding = nil
            for observation in Array(pendingOfficial.values) {
                guard current(requested, id), !Task.isCancelled else { return }
                await consumer.observeOfficial(observation)
                guard current(requested, id), !Task.isCancelled else { return }
                if pendingOfficial[observation.generation] == observation {
                    pendingOfficial.removeValue(forKey: observation.generation)
                }
            }
        } catch {
            if current(requested, id) { binding = nil }
        }
    }

    func observeOfficial(_ observation: OnboardingBodyPhotoCleanupScope?,
        owner requested: SignupBodyPhotoCleanupOwnerToken) async {
        guard owner == requested, let observation, observation.state == .pending,
              SignupBodyPhotoCleanupQueue.validGeneration(observation.generation) else { return }
        pendingOfficial[observation.generation] = observation
        guard let processor else { return }
        let id = bindingID
        await processor.observeOfficial(observation)
        guard current(requested, id) else { return }
        // The bound processor retains a failed disk write in its own buffer.
        if pendingOfficial[observation.generation] == observation {
            pendingOfficial.removeValue(forKey: observation.generation)
        }
    }

    @discardableResult
    func finishRestore(owner: SignupBodyPhotoCleanupOwnerToken,
        freshObservation: SignupBodyPhotoCleanupFreshObservation?) -> Task<Void, Never>? {
        guard self.owner == owner else { return nil }
        restoreReady = true
        return schedule(activeEventID, owner: owner, freshObservation: freshObservation)
    }

    @discardableResult
    func completionObserved(owner: SignupBodyPhotoCleanupOwnerToken,
        freshObservation: SignupBodyPhotoCleanupFreshObservation?) -> Task<Void, Never>? {
        schedule(UUID(), owner: owner, freshObservation: freshObservation)
    }

    @discardableResult
    func setActive(_ requested: Bool) -> Task<Void, Never>? {
        guard active != requested else { return nil }
        active = requested
        if !requested {
            event?.cancel()
            event = nil
            processor?.invalidate()
            return nil
        }
        activeEventID = UUID()
        guard let owner else { return nil }
        return schedule(activeEventID, owner: owner, freshObservation: nil)
    }

    func invalidate() {
        owner = nil
        bindingID = UUID()
        binding?.cancel()
        binding = nil
        event?.cancel()
        event = nil
        processor?.invalidate()
        processor = nil
        pendingOfficial.removeAll()
        restoreReady = false
        activeEventID = UUID()
        scheduledEvents.removeAll()
    }

    private func current(_ requested: SignupBodyPhotoCleanupOwnerToken, _ id: UUID) -> Bool {
        owner == requested && bindingID == id
    }

    private func schedule(_ id: UUID, owner requested: SignupBodyPhotoCleanupOwnerToken,
        freshObservation: SignupBodyPhotoCleanupFreshObservation?) -> Task<Void, Never>? {
        guard owner == requested, active, restoreReady, let processor,
              scheduledEvents.insert(id).inserted else { return nil }
        event?.cancel()
        let bound = bindingID
        let task = Task { [weak self, processor] in
            guard let self, self.current(requested, bound), self.active, !Task.isCancelled else { return }
            await processor.run(eventID: id, freshObservation: freshObservation)
        }
        event = task
        return task
    }
}
