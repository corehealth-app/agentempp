import Foundation
import Observation

/// Explicit source only; construction never resolves a lease or starts a request.
struct MealRecordSessionBindingSource: Sendable {
    private let transport: MobileAPITransport
    private let lifecycle: any SessionLifecycleProviding

    init(transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding) {
        self.transport = transport
        self.lifecycle = lifecycle
    }

    @MainActor
    func bind(_ binding: MealRecordSessionBinding) async throws -> MealRecordSessionCapability {
        try await binding.bind(transport: transport, lifecycle: lifecycle)
    }
}

/// Captures the exact original reservation before a caller can suspend.
@MainActor
final class MealRecordRootBindingOperation {
    let activation: MealRecordAuthenticatedActivation
    fileprivate let owner: Prompt14SessionOwner
    fileprivate let binding: MealRecordSessionBinding
    fileprivate let work: Task<MealRecordSessionCapability, any Error>

    fileprivate init(activation: MealRecordAuthenticatedActivation,
        owner: Prompt14SessionOwner, binding: MealRecordSessionBinding,
        source: MealRecordSessionBindingSource) {
        self.activation = activation
        self.owner = owner
        self.binding = binding
        work = Task { try await source.bind(binding) }
    }
}

/// An original grant; reading isActive never reads a lease or starts HTTP.
@MainActor
final class MealRecordReadyContext {
    let activation: MealRecordAuthenticatedActivation
    let capability: MealRecordSessionCapability
    private weak var owner: Prompt14SessionOwner?
    fileprivate let binding: MealRecordSessionBinding
    private let lifetime: MealRecordAuthenticationLifetime
    private let currentActivation: @MainActor @Sendable () -> MealRecordAuthenticatedActivation?

    fileprivate init(operation: MealRecordRootBindingOperation,
        capability: MealRecordSessionCapability, lifetime: MealRecordAuthenticationLifetime,
        currentActivation: @escaping @MainActor @Sendable () -> MealRecordAuthenticatedActivation?) {
        activation = operation.activation
        owner = operation.owner
        binding = operation.binding
        self.capability = capability
        self.lifetime = lifetime
        self.currentActivation = currentActivation
    }

    var isActive: Bool {
        guard currentActivation() == activation,
              lifetime.currentActivation == activation, lifetime.isCurrent(activation.ticket),
              let owner, owner.userID == activation.userID, !owner.isInvalidated,
              owner.mealRecordBinding === binding, binding.isOpen,
              binding.capability === capability, capability.hasRetainedCapability else {
            return false
        }
        return true
    }
}

/// Local Root glue, default source nil. No AppDependencies or view wiring here.
@MainActor
@Observable
final class MealRecordRootBindingCoordinator {
    @ObservationIgnored private let lifetime: MealRecordAuthenticationLifetime
    @ObservationIgnored private let source: MealRecordSessionBindingSource?
    @ObservationIgnored private let currentActivation:
        @MainActor @Sendable () -> MealRecordAuthenticatedActivation?
    @ObservationIgnored private var currentOperation: MealRecordRootBindingOperation?
    @ObservationIgnored private var retirementTail: Task<Void, Never>?
    @ObservationIgnored private var retirementSequence: UInt64 = 0
    private var installedContext: MealRecordReadyContext?

    init(lifetime: MealRecordAuthenticationLifetime,
        source: MealRecordSessionBindingSource? = nil,
        currentActivation: @escaping @MainActor @Sendable () -> MealRecordAuthenticatedActivation?) {
        self.lifetime = lifetime
        self.source = source
        self.currentActivation = currentActivation
    }

    var readyContext: MealRecordReadyContext? {
        guard let installedContext, installedContext.isActive else { return nil }
        return installedContext
    }

    /// Validate, reserve, register and capture in one synchronous MainActor turn.
    /// Stale input is rejected without withdrawing an unrelated current operation.
    func beginBinding(activation: MealRecordAuthenticatedActivation?,
        owner: Prompt14SessionOwner?) -> MealRecordRootBindingOperation? {
        guard let source, let activation, let owner,
              currentActivation() == activation,
              lifetime.currentActivation == activation, lifetime.isCurrent(activation.ticket),
              owner.userID == activation.userID, !owner.isInvalidated else { return nil }
        // Register refuses a second owner for this activation. Reject before
        // retiring the original, so a foreign same-user owner cannot revoke it.
        if let currentOperation, currentOperation.activation == activation,
           currentOperation.owner !== owner { return nil }
        if let currentOperation,
           currentOperation.activation == activation, currentOperation.owner === owner,
           owner.mealRecordBinding === currentOperation.binding, currentOperation.binding.isOpen {
            return currentOperation
        }
        retireCurrentOperation()
        guard let binding = owner.reserveNewMealRecordBinding(),
              lifetime.register(binding: binding, owner: owner, activation: activation) else {
            return nil
        }
        let operation = MealRecordRootBindingOperation(activation: activation,
            owner: owner, binding: binding, source: source)
        currentOperation = operation
        return operation
    }

    func completeBinding(_ operation: MealRecordRootBindingOperation) async throws
        -> MealRecordReadyContext? {
        // A borrowed/stale operation cannot withdraw somebody else's current grant.
        guard currentOperation === operation else { throw CancellationError() }
        let work = operation.work
        do {
            try Task.checkCancellation()
            if let readyContext, readyContext.activation == operation.activation,
               readyContext.binding === operation.binding { return readyContext }
            let capability = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: { work.cancel() }
            try Task.checkCancellation()
            guard currentOperation === operation,
                  currentActivation() == operation.activation,
                  lifetime.currentActivation == operation.activation,
                  lifetime.isCurrent(operation.activation.ticket),
                  operation.owner.userID == operation.activation.userID,
                  !operation.owner.isInvalidated,
                  operation.owner.mealRecordBinding === operation.binding,
                  operation.binding.isOpen, operation.binding.capability === capability else {
                throw CancellationError()
            }
            if let readyContext, readyContext.binding === operation.binding { return readyContext }
            let context = MealRecordReadyContext(operation: operation, capability: capability,
                lifetime: lifetime, currentActivation: currentActivation)
            guard context.isActive else { throw CancellationError() }
            installedContext = context
            return context
        } catch {
            // Only the captured reservation is terminal; a late A1 never removes A2.
            if currentOperation === operation {
                retireCurrentOperation()
            } else {
                operation.binding.invalidateSynchronously()
                operation.work.cancel()
                // The replacement already retains and joins this old operation.
            }
            throw error
        }
    }

    func invalidateSynchronously() { retireCurrentOperation() }

    func endSession() async {
        invalidateSynchronously()
        let pending = retirementTail
        let sequence = retirementSequence
        await pending?.value
        if retirementSequence == sequence { retirementTail = nil }
    }

    private func retireCurrentOperation() {
        guard let operation = currentOperation else {
            installedContext = nil
            return
        }
        currentOperation = nil
        installedContext = nil
        operation.binding.invalidateSynchronously()
        operation.work.cancel()
        let predecessor = retirementTail
        retirementSequence &+= 1
        retirementTail = Task {
            await predecessor?.value
            _ = await operation.work.result
            await operation.binding.endSession()
        }
    }
}
