import Foundation
import Observation

/// Construction is lazy; the original owner reserves the binding before any await.
struct WorkoutRegistrationSessionBindingSource: Sendable {
    let transport: MobileAPITransport
    let lifecycle: any SessionLifecycleProviding

    @MainActor
    func bind(_ binding: WorkoutRegistrationSessionBinding) async throws -> WorkoutRegistrationReadyContext {
        try await binding.bind(transport: transport, lifecycle: lifecycle)
    }

    @MainActor
    func retryMe(_ binding: WorkoutRegistrationSessionBinding) async throws -> WorkoutRegistrationReadyContext {
        try await binding.retryMe()
    }
}

fileprivate final class WorkoutRegistrationGrant: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true
    var isOpen: Bool { lock.withLock { open } }
    func release() { lock.withLock { open = false } }
}

/// Intercept superseded sessions before the repository's capability mapper.
/// The gate guards success; the catch also guards late errors against the
/// original lease and grant. It never obtains a replacement lease to do so.
private struct WorkoutRegistrationScopedEnvelope: MobileAPIEnvelopeExecuting {
    let transport: MobileAPITransport
    let lifecycle: any SessionLifecycleProviding
    let lease: SessionLease
    let grant: WorkoutRegistrationGrant
    let parentGate: Prompt14SessionOperationGate
    let leafGate: Prompt14SessionOperationGate

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        do {
            return try await leafGate.perform {
                try await parentGate.perform {
                    guard grant.isOpen else { throw CancellationError() }
                    return try await transport.executeEnvelope(request)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch MobileAPITransportError.sessionSuperseded {
            throw CancellationError()
        } catch {
            guard grant.isOpen, !leafGate.isClosed, !parentGate.isClosed,
                  !Task.isCancelled else { throw CancellationError() }
            do { try await lifecycle.validate(lease) }
            catch { throw CancellationError() }
            guard grant.isOpen, !leafGate.isClosed, !parentGate.isClosed,
                  !Task.isCancelled else { throw CancellationError() }
            throw error
        }
    }
}

@MainActor
@Observable
final class WorkoutRegistrationSessionBinding {
    let activation: MealRecordAuthenticatedActivation
    private weak var owner: Prompt14SessionOwner?
    private let lifetime: MealRecordAuthenticationLifetime
    private let currentActivation: @MainActor @Sendable () -> MealRecordAuthenticatedActivation?
    private let timeZoneStore: PatientTimeZoneStore
    private let parentGate: Prompt14SessionOperationGate
    private let leafGate = Prompt14SessionOperationGate()
    private var started = false
    private var resolving = false
    private var grant: WorkoutRegistrationGrant?
    private var reader: MobileBodyFlowRepository?
    private var repository: MobileRegistrationRepository?
    private var clarificationRepository: MobileWorkoutStrengthClarificationRepository?
    private var lifecycle: (any SessionLifecycleProviding)?
    private var patientWork: (id: UUID, lifecycle: any SessionLifecycleProviding)?
    private var finishing = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var capturedLease: SessionLease?
    private(set) var readyContext: WorkoutRegistrationReadyContext?

    init(owner: Prompt14SessionOwner, parentGate: Prompt14SessionOperationGate,
         activation: MealRecordAuthenticatedActivation,
         lifetime: MealRecordAuthenticationLifetime,
         currentActivation: @escaping @MainActor @Sendable () -> MealRecordAuthenticatedActivation?,
         timeZoneStore: PatientTimeZoneStore) {
        self.owner = owner
        self.parentGate = parentGate
        self.activation = activation
        self.lifetime = lifetime
        self.currentActivation = currentActivation
        self.timeZoneStore = timeZoneStore
    }

    var isOpen: Bool {
        !leafGate.isClosed && !parentGate.isClosed
            && owner?.isInvalidated == false
            && owner?.workoutRegistrationBinding === self
            && currentActivation() == activation
            && lifetime.currentActivation == activation
            && lifetime.isCurrent(activation.ticket)
    }

    var canRetryMe: Bool {
        isOpen && !resolving && readyContext == nil && patientWork != nil
            && grant?.isOpen == true && reader != nil && capturedLease != nil
    }

    var hasRetainedCapability: Bool { repository != nil || clarificationRepository != nil || reader != nil || grant != nil }

    func bind(transport: MobileAPITransport,
              lifecycle: any SessionLifecycleProviding) async throws -> WorkoutRegistrationReadyContext {
        guard !started, isOpen else { throw CancellationError() }
        started = true
        return try await resolve {
            try await self.admit(transport: transport, lifecycle: lifecycle)
        }
    }

    func retryMe() async throws -> WorkoutRegistrationReadyContext {
        guard canRetryMe else { throw CancellationError() }
        return try await resolve {}
    }

    /// The full admission/read is tracked so teardown joins a late admitted UUID.
    private func resolve(_ admission: @escaping @MainActor @Sendable () async throws -> Void)
        async throws -> WorkoutRegistrationReadyContext {
        resolving = true
        let leafGate = leafGate
        let parentGate = parentGate
        do {
            let result = try await withTaskCancellationHandler {
                try await leafGate.perform {
                    try await parentGate.perform {
                        try await admission()
                        return try await self.readMeAndPublish()
                    }
                }
            } onCancel: {
                leafGate.close()
            }
            resolving = false
            guard result.isActive else { throw CancellationError() }
            return result
        } catch {
            resolving = false
            // Network/decoding errors keep the one admitted scope for explicit GET retry.
            if error is CancellationError || !canRetryMe {
                invalidateSynchronously()
                await finishPatientWork()
            }
            throw error
        }
    }

    private func admit(transport: MobileAPITransport,
                       lifecycle: any SessionLifecycleProviding) async throws {
        let lease = try await lifecycle.leaseForRequest()
        try Task.checkCancellation()
        guard isOpen, lease.userID == activation.userID else { throw CancellationError() }
        let grant = WorkoutRegistrationGrant()
        let envelope = WorkoutRegistrationScopedEnvelope(
            transport: transport.scoped(to: lease), lifecycle: lifecycle, lease: lease,
            grant: grant, parentGate: parentGate, leafGate: leafGate)
        try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
            guard self.isOpen, self.capturedLease == nil else { throw CancellationError() }
            self.capturedLease = lease
            self.lifecycle = lifecycle
            self.grant = grant
            self.reader = MobileBodyFlowRepository(transport: envelope)
            self.repository = MobileRegistrationRepository(transport: envelope)
            self.clarificationRepository = MobileWorkoutStrengthClarificationRepository(transport: envelope)
        }
        try Task.checkCancellation()
        guard isOpen, grant.isOpen else { throw CancellationError() }
        let workID = try await lifecycle.beginPatientWork(lease: lease) {
            // Do not close gates in a callback that may be completing a real refresh.
            grant.release()
        }
        patientWork = (workID, lifecycle) // retain a late UUID before any throwing check
        try Task.checkCancellation()
        guard isOpen, grant.isOpen else { throw CancellationError() }
    }

    private func readMeAndPublish() async throws -> WorkoutRegistrationReadyContext {
        guard isOpen, let reader, let repository, let clarificationRepository, let grant,
              let lease = capturedLease, let lifecycle, patientWork != nil else {
            throw CancellationError()
        }
        let response = try await reader.me()
        try Task.checkCancellation()
        // `/me.id` is the patient row key, not the Supabase Auth subject.
        // The original scoped transport and lease govern session ownership.
        guard !response.data.id.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        return try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
            guard self.isOpen, grant.isOpen, self.readyContext == nil else { throw CancellationError() }
            let context = WorkoutRegistrationReadyContext(binding: self, provider: repository,
                clarificationProvider: clarificationRepository,
                registrationProtocol: response.data.supportsVersionedWorkoutRegistration ? .uiV1 : nil,
                grant: grant)
            self.timeZoneStore.resolve(documentedIANAIdentifier: response.data.timezone)
            self.readyContext = context
            return context
        }
    }

    func invalidateSynchronously() {
        leafGate.close()
        grant?.release()
        readyContext?.endStrengthQuestions()
        readyContext = nil
        repository = nil
        clarificationRepository = nil
        reader = nil
        grant = nil
        capturedLease = nil
        lifecycle = nil
    }

    /// Foreground timezone refresh uses this original scope and never changes
    /// the protocol already selected for a visible workout/model.
    func refreshPatientTimeZone() async {
        guard readyContext?.isActive == true, let reader, let lifecycle,
              let lease = capturedLease, let grant else { return }
        do {
            let response = try await reader.me()
            guard !response.data.id.isEmpty else { return }
            try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                guard self.isOpen, grant.isOpen else { throw CancellationError() }
                self.timeZoneStore.resolve(documentedIANAIdentifier: response.data.timezone)
            }
        } catch { /* A failed refresh leaves the documented snapshot intact. */ }
    }

    func endSession() async {
        invalidateSynchronously()
        await leafGate.drain()
        await finishPatientWork()
        invalidateSynchronously()
    }

    private func finishPatientWork() async {
        if finishing {
            await withCheckedContinuation { finishWaiters.append($0) }
            return
        }
        guard let work = patientWork else { return }
        patientWork = nil
        finishing = true
        await work.lifecycle.finishPatientWork(work.id)
        finishing = false
        let waiters = finishWaiters
        finishWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

@MainActor
final class WorkoutRegistrationReadyContext {
    let activation: MealRecordAuthenticatedActivation
    let provider: MobileRegistrationRepository
    let clarificationProvider: MobileWorkoutStrengthClarificationRepository
    let registrationProtocol: WorkoutRegistrationProtocol?
    private weak var binding: WorkoutRegistrationSessionBinding?
    private let grant: WorkoutRegistrationGrant
    private var strengthQuestionStorage: WorkoutStrengthQuestionSession?

    fileprivate init(binding: WorkoutRegistrationSessionBinding, provider: MobileRegistrationRepository,
                     clarificationProvider: MobileWorkoutStrengthClarificationRepository,
                     registrationProtocol: WorkoutRegistrationProtocol?, grant: WorkoutRegistrationGrant) {
        self.binding = binding
        activation = binding.activation
        self.provider = provider
        self.clarificationProvider = clarificationProvider
        self.registrationProtocol = registrationProtocol
        self.grant = grant
    }

    var isActive: Bool { binding?.isOpen == true && grant.isOpen }

    func strengthQuestionSession() -> WorkoutStrengthQuestionSession? {
        guard isActive else { return nil }
        if let strengthQuestionStorage { return strengthQuestionStorage }
        let session = WorkoutStrengthQuestionSession(provider: clarificationProvider,
            isSessionActive: { [weak self] in self?.isActive == true })
        strengthQuestionStorage = session
        return session
    }

    fileprivate func endStrengthQuestions() {
        strengthQuestionStorage?.close()
        strengthQuestionStorage = nil
    }
}
