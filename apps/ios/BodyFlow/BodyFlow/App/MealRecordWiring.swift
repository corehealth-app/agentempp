import Foundation
import Observation

/// Existing admission and original owner identity; no new auth generation.
struct MealRecordRootTaskID: Hashable, Sendable {
    let activation: MealRecordAuthenticatedActivation
    let owner: ObjectIdentifier
}

/// Thin consumer of the actual Model, existing Shell owner and Core binding.
/// Construction/getters never start work and hold no authority of their own.
@MainActor
final class MealRecordRootWiringDriver {
    private let model: AppFlowModel
    private let ownerCoordinator: Prompt14AuthenticatedShellCoordinator
    private let bindings: MealRecordRootBindingCoordinator?

    init(model: AppFlowModel, ownerCoordinator: Prompt14AuthenticatedShellCoordinator,
         lifetime: MealRecordAuthenticationLifetime?, source: MealRecordSessionBindingSource?) {
        self.model = model
        self.ownerCoordinator = ownerCoordinator
        if let lifetime, let source {
            bindings = MealRecordRootBindingCoordinator(lifetime: lifetime, source: source,
                currentActivation: { [weak model] in model?.mealRecordActivation })
        } else { bindings = nil }
    }

    var isEnabled: Bool { bindings != nil }
    var readyContext: MealRecordReadyContext? { bindings?.readyContext }
    var taskID: MealRecordRootTaskID? {
        guard bindings != nil, let activation = model.mealRecordActivation,
              let owner = ownerCoordinator.renderableOwner(for: activation.userID) else { return nil }
        return MealRecordRootTaskID(activation: activation, owner: ObjectIdentifier(owner))
    }

    func synchronize(expected: MealRecordRootTaskID?) async -> MealRecordReadyContext? {
        guard !Task.isCancelled, taskID == expected, let bindings else { return nil }
        guard let expected, let activation = model.mealRecordActivation,
              activation == expected.activation,
              let owner = ownerCoordinator.renderableOwner(for: activation.userID),
              ObjectIdentifier(owner) == expected.owner else {
            // Immediate removal. Its retained Core tail performs and owns the join.
            // No unscoped async end can later close a newly ready A2.
            bindings.invalidateSynchronously()
            return nil
        }
        // These are the original owner/activation, captured before the first await.
        guard let operation = bindings.beginBinding(activation: activation, owner: owner) else { return nil }
        do {
            let context = try await bindings.completeBinding(operation)
            guard !Task.isCancelled, taskID == expected,
                  context?.activation == activation, context?.isActive == true else { return nil }
            return context
        } catch {
            // Cancellation is normal. Other failures preserve History's read-only fallback.
            return nil
        }
    }

    func invalidateSynchronously() { bindings?.invalidateSynchronously() }
    func endSession() async { await bindings?.endSession() }
}

/// The Shell's existing invalidation center and one cache for an admitted grant.
/// It does not bind, refresh, mint a ticket or change any navigation stack.
@MainActor
@Observable
final class MealRecordShellSessionCoordinator {
    @ObservationIgnored private let time: any TimeProviding
    @ObservationIgnored private let keys: any IdempotencyKeyProviding
    @ObservationIgnored private let invalidation: FeatureInvalidationCenter
    @ObservationIgnored private var context: MealRecordReadyContext?
    @ObservationIgnored private weak var owner: Prompt14SessionOwner?
    @ObservationIgnored private var feature: MealRecordFeatureCoordinator?
    private(set) var activation: MealRecordAuthenticatedActivation?

    init(time: any TimeProviding, keys: any IdempotencyKeyProviding,
         invalidation: FeatureInvalidationCenter) {
        self.time = time
        self.keys = keys
        self.invalidation = invalidation
    }

    /// Called from a view effect, never an initializer/body/getter.
    func synchronize(context incoming: MealRecordReadyContext?, owner incomingOwner: Prompt14SessionOwner) {
        guard let incoming, accepts(incoming, owner: incomingOwner) else {
            // Old/nil effects cannot erase a current A2 whose original context is active.
            if context?.isActive == true { return }
            endSession()
            return
        }
        if let context, context.isActive, activation == incoming.activation,
           owner !== incomingOwner { return }
        if activation == incoming.activation, context?.capability === incoming.capability,
           owner === incomingOwner, feature != nil {
            context = incoming
            return
        }
        endSession()
        context = incoming
        owner = incomingOwner
        activation = incoming.activation
        let originalActivation = incoming.activation
        let originalCapability = incoming.capability
        feature = MealRecordFeatureCoordinator(provider: originalCapability, time: time, keys: keys,
            invalidation: invalidation, isSessionActive: { [weak self, weak originalCapability] in
                guard let self, let originalCapability else { return false }
                return self.isActive(activation: originalActivation, capability: originalCapability)
            })
    }

    /// Explicit presentation effect: the existing coordinator allocates/caches once.
    /// No meal request starts until the real DetailView's existing load task.
    func prepareModel(recordID: String, context: MealRecordReadyContext,
                      owner: Prompt14SessionOwner) -> MealRecordModel? {
        guard isCurrent(context: context, owner: owner) else { return nil }
        return feature?.model(id: recordID)
    }

    func isCurrent(context: MealRecordReadyContext, owner: Prompt14SessionOwner) -> Bool {
        self.owner === owner && activation == context.activation
            && self.context?.capability === context.capability
            && accepts(context, owner: owner) && self.context?.isActive == true && feature != nil
    }

    func endSession() {
        feature?.endSession()
        feature = nil
        context = nil
        owner = nil
        activation = nil
    }

    private func accepts(_ context: MealRecordReadyContext, owner: Prompt14SessionOwner) -> Bool {
        context.isActive && context.activation.userID == owner.userID && !owner.isInvalidated
            && owner.mealRecordBinding?.capability === context.capability
    }

    private func isActive(activation: MealRecordAuthenticatedActivation,
                          capability: MealRecordSessionCapability) -> Bool {
        guard let context, let owner else { return false }
        return self.activation == activation && context.activation == activation
            && context.capability === capability && accepts(context, owner: owner)
    }
}
