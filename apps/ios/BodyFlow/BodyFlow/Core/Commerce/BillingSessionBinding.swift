import Foundation
import Observation

/// No lease, HTTP or SDK operation starts when this source is constructed.
struct BillingSessionSource: Sendable {
    let transport: MobileAPITransport
    let lifecycle: any SessionLifecycleProviding
    var coordinator: BillingSDKCoordinator = .live

    @MainActor
    func bind(_ binding: BillingSessionBinding) async throws -> BillingReadyContext {
        try await binding.bind(transport: transport, lifecycle: lifecycle, coordinator: coordinator)
    }

    @MainActor
    func retryMe(_ binding: BillingSessionBinding) async throws -> BillingReadyContext {
        try await binding.retryMe()
    }
}

@MainActor
protocol BillingProviding: EntitlementProviding {
    func offers() async throws -> BillingCatalog
    func purchase(productID: String, catalogRevision: UUID) async throws -> BillingStoreOutcome
    func restore() async throws -> BillingStoreOutcome
}

/// Auth cancellation can precede /me, and therefore precede the SDK grant.
/// Installing a later grant cannot reopen this original admission.
private final class BillingAdmissionFence: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true
    private var grant: BillingSessionGrant?
    var isOpen: Bool { lock.withLock { open } }
    func install(_ candidate: BillingSessionGrant) -> Bool {
        let accepted = lock.withLock {
            guard open, grant == nil else { return false }
            grant = candidate
            return true
        }
        if !accepted { candidate.close() }
        return accepted
    }
    func close() {
        let original = lock.withLock { open = false; return grant }
        original?.close()
    }
    func release() { close(); lock.withLock { grant = nil } }
}

@MainActor
@Observable
final class BillingSessionBinding {
    let activation: MealRecordAuthenticatedActivation
    private weak var owner: Prompt14SessionOwner?
    private let lifetime: MealRecordAuthenticationLifetime
    private let currentActivation: @MainActor @Sendable () -> MealRecordAuthenticatedActivation?
    private let parentGate: Prompt14SessionOperationGate
    private let leafGate = Prompt14SessionOperationGate()
    private let fence = BillingAdmissionFence()
    private var started = false
    private var resolving = false
    private var reader: MobileBodyFlowRepository?
    private var repository: MobileEntitlementRepository?
    private var lifecycle: (any SessionLifecycleProviding)?
    private var coordinator: BillingSDKCoordinator?
    private var sdkGrant: BillingSessionGrant?
    private var patientWork: (id: UUID, lifecycle: any SessionLifecycleProviding)?
    private var endTask: Task<Void, Never>?
    private var ended = false
    private(set) var capturedLease: SessionLease?
    private(set) var readyContext: BillingReadyContext?
    private(set) var storeCleanupFailed = false

    init(owner: Prompt14SessionOwner, parentGate: Prompt14SessionOperationGate,
         activation: MealRecordAuthenticatedActivation, lifetime: MealRecordAuthenticationLifetime,
         currentActivation: @escaping @MainActor @Sendable () -> MealRecordAuthenticatedActivation?) {
        self.owner = owner
        self.parentGate = parentGate
        self.activation = activation
        self.lifetime = lifetime
        self.currentActivation = currentActivation
    }

    var isOpen: Bool {
        !leafGate.isClosed && !parentGate.isClosed && fence.isOpen
            && owner?.isInvalidated == false && owner?.billingBinding === self
            && currentActivation() == activation && lifetime.currentActivation == activation
            && lifetime.isCurrent(activation.ticket)
    }
    var canRetryMe: Bool {
        isOpen && !resolving && readyContext == nil && patientWork != nil
            && reader != nil && capturedLease != nil
    }
    var hasRetainedCapability: Bool {
        reader != nil || repository != nil || lifecycle != nil || coordinator != nil
            || sdkGrant != nil || patientWork != nil || capturedLease != nil
    }

    func bind(transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
              coordinator: BillingSDKCoordinator) async throws -> BillingReadyContext {
        guard !started, isOpen else { throw CancellationError() }
        started = true
        self.coordinator = coordinator
        return try await resolve {
            let lease = try await lifecycle.leaseForRequest()
            try Task.checkCancellation()
            guard self.isOpen, lease.userID == self.activation.userID else { throw CancellationError() }
            try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                guard self.isOpen, self.capturedLease == nil else { throw CancellationError() }
                self.capturedLease = lease
                self.lifecycle = lifecycle
                let scoped = transport.scoped(to: lease)
                self.reader = MobileBodyFlowRepository(transport: scoped)
                self.repository = MobileEntitlementRepository(transport: scoped)
            }
            try await self.checkAuthority()
            let fence = self.fence
            let id = try await lifecycle.beginPatientWork(lease: lease) { fence.close() }
            // This assignment is inside the tracked operation, even when Auth
            // cancellation happened before beginPatientWork returned its ID.
            self.patientWork = (id, lifecycle)
            try await self.checkAuthority()
        }
    }

    func retryMe() async throws -> BillingReadyContext {
        guard canRetryMe else { throw CancellationError() }
        return try await resolve {}
    }

    private func resolve(_ admission: @escaping @MainActor @Sendable () async throws -> Void)
        async throws -> BillingReadyContext {
        resolving = true
        let leafGate = leafGate
        let parentGate = parentGate
        let fence = fence
        do {
            let context = try await withTaskCancellationHandler {
                try await leafGate.perform {
                    try await parentGate.perform {
                        try await admission()
                        return try await self.readMeAndPublish()
                    }
                }
            } onCancel: { fence.close(); leafGate.close() }
            resolving = false
            try await checkAuthority()
            return context
        } catch {
            resolving = false
            let failure: any Error
            do { try await checkAuthority(); failure = error }
            catch { failure = CancellationError() }
            if failure is CancellationError || !canRetryMe {
                // Both performs have exited. Joining here cannot drain itself.
                invalidateSynchronously()
                await endSession()
            }
            throw failure
        }
    }

    private func readMeAndPublish() async throws -> BillingReadyContext {
        try await checkAuthority()
        guard let reader, let lease = capturedLease, let lifecycle else { throw CancellationError() }
        let response = try await reader.me()
        try await checkAuthority()
        guard let patientID = UUID(uuidString: response.data.id) else { throw BodyFlowCapabilityError.serviceUnavailable }
        return try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
            guard self.isOpen, self.readyContext == nil else { throw CancellationError() }
            let grant = BillingSessionGrant(patientID: patientID) { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.checkAuthority()
            }
            guard self.fence.install(grant) else { throw CancellationError() }
            self.sdkGrant = grant
            let context = BillingReadyContext(binding: self)
            self.readyContext = context
            return context
        }
    }

    private func checkAuthority() async throws {
        try Task.checkCancellation()
        guard isOpen, let lease = capturedLease, let lifecycle else { throw CancellationError() }
        do {
            try await lifecycle.validate(lease)
            try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                guard self.isOpen else { throw CancellationError() }
            }
        } catch { throw CancellationError() }
        try Task.checkCancellation()
        guard isOpen else { throw CancellationError() }
    }

    /// Gates track the full callback; success AND errors must still belong to
    /// this original lease/ticket. SDK completion never becomes an access grant.
    fileprivate func perform<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            let value = try await leafGate.perform {
                try await self.parentGate.perform {
                    try await self.checkAuthority()
                    return try await operation()
                }
            }
            try await checkAuthority()
            return value
        } catch {
            try await checkAuthority()
            throw error
        }
    }

    fileprivate func entitlement() async throws -> EntitlementResponse {
        try await perform {
            guard let repository = self.repository else { throw CancellationError() }
            return try await repository.entitlement()
        }
    }

    fileprivate func store<Value: Sendable>(
        _ operation: @escaping @Sendable (BillingSDKCoordinator, BillingSessionGrant) async throws -> Value
    ) async throws -> Value {
        try await perform {
            guard let repository = self.repository, let coordinator = self.coordinator,
                  let grant = self.sdkGrant else { throw CancellationError() }
            let access = try await repository.entitlement()
            try await self.checkAuthority()
            guard access.data.mobileBilling.provider == "revenuecat", access.data.mobileBilling.available else {
                throw BillingStoreError.configurationUnavailable
            }
            return try await operation(coordinator, grant)
        }
    }

    func invalidateSynchronously() {
        fence.close()
        leafGate.close()
        readyContext = nil
        reader = nil
        repository = nil
        // Keep the original grant, lifecycle and work ID for joined cleanup.
    }

    func endSession() async {
        invalidateSynchronously()
        guard !ended else { return }
        if let endTask { await endTask.value; return }
        let task = Task {
            await leafGate.drain()
            if let coordinator, let sdkGrant {
                do { try await coordinator.release(sdkGrant) }
                catch { storeCleanupFailed = true }
            }
            if let work = patientWork {
                patientWork = nil
                await work.lifecycle.finishPatientWork(work.id)
            }
            fence.release()
            sdkGrant = nil
            coordinator = nil
            lifecycle = nil
            capturedLease = nil
            ended = true
        }
        endTask = task
        await task.value
        endTask = nil
    }
}

@MainActor
final class BillingReadyContext {
    let activation: MealRecordAuthenticatedActivation
    let provider: any BillingProviding
    private weak var binding: BillingSessionBinding?
    fileprivate init(binding: BillingSessionBinding) {
        self.binding = binding
        activation = binding.activation
        provider = BillingBoundProvider(binding: binding)
    }
    var isActive: Bool { binding?.isOpen == true }
}

@MainActor
private final class BillingBoundProvider: BillingProviding {
    private weak var binding: BillingSessionBinding?
    init(binding: BillingSessionBinding) { self.binding = binding }
    func entitlement() async throws -> EntitlementResponse {
        guard let binding else { throw CancellationError() }
        return try await binding.entitlement()
    }
    func offers() async throws -> BillingCatalog {
        guard let binding else { throw CancellationError() }
        return try await binding.store { try await $0.offers(for: $1) }
    }
    func purchase(productID: String, catalogRevision: UUID) async throws -> BillingStoreOutcome {
        guard let binding else { throw CancellationError() }
        return try await binding.store { try await $0.purchase(productID: productID, catalogRevision: catalogRevision, for: $1) }
    }
    func restore() async throws -> BillingStoreOutcome {
        guard let binding else { throw CancellationError() }
        return try await binding.store { try await $0.restore(for: $1) }
    }
}
