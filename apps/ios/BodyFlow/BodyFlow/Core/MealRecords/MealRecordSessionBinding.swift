import Foundation

/// One optional C11 activation, retained by its original session owner.
/// The parent gate is borrowed: ending this leaf never closes other features.
@MainActor
final class MealRecordSessionBinding {
    private weak var owner: Prompt14SessionOwner?
    private let ownerUserID: String
    private let parentGate: Prompt14SessionOperationGate
    private let leafGate = Prompt14SessionOperationGate()
    private var started = false
    private struct PatientWorkRegistration {
        let id: UUID
        let lifecycle: any SessionLifecycleProviding
    }
    private var patientWorkRegistration: PatientWorkRegistration?
    private var isFinishingPatientWork = false
    private var patientWorkFinishWaiters: [CheckedContinuation<Void, Never>] = []
    private var parentCapability: MealRecordSessionCapability?
    private(set) var capability: MealRecordSessionCapability?
    private(set) var capturedLease: SessionLease?

    init(owner: Prompt14SessionOwner, parentGate: Prompt14SessionOperationGate) {
        self.owner = owner
        ownerUserID = owner.userID
        self.parentGate = parentGate
    }

    var isOpen: Bool {
        !leafGate.isClosed && !parentGate.isClosed && owner?.isInvalidated == false
    }

    var hasRetainedCapability: Bool {
        capability != nil || parentCapability != nil
    }

    func bind(
        transport: MobileAPITransport,
        lifecycle: any SessionLifecycleProviding
    ) async throws -> MealRecordSessionCapability {
        guard !started, isOpen else { throw CancellationError() }
        started = true // synchronous reservation before the first await
        let leafGate = leafGate
        let parentGate = parentGate
        let expectedUserID = ownerUserID
        do {
            let result = try await withTaskCancellationHandler {
                try await leafGate.perform {
                    try await parentGate.perform {
                        let lease = try await lifecycle.leaseForRequest()
                        try Task.checkCancellation()
                        guard lease.userID == expectedUserID else {
                            throw SessionLifecycleError.sessionSuperseded
                        }
                        let leaf = try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                            guard self.isOpen, self.capability == nil,
                                  self.parentCapability == nil else {
                                throw CancellationError()
                            }
                            let parent = MealRecordSessionCapability(
                                provider: MobileMealRecordRepository(transport: transport.scoped(to: lease)),
                                gate: parentGate
                            )
                            let leaf = MealRecordSessionCapability(provider: parent, gate: leafGate)
                            self.parentCapability = parent
                            self.capability = leaf
                            self.capturedLease = lease
                            return leaf
                        }
                        try Task.checkCancellation()
                        let parent = try await self.retainedParent(for: leaf)
                        // The visible operation released its mutation gate. Keep
                        // admission inside this already tracked leaf/parent work
                        // so endSession drains it before finishing the UUID.
                        let workID = try await lifecycle.beginPatientWork(lease: lease) {
                            [weak leaf, weak parent] in
                            // Withdraw only this grant; closing either gate here
                            // could cancel the caller completing the real refresh.
                            leaf?.release()
                            parent?.release()
                        }
                        // Even a cancelled/ended bind must retain an admitted ID
                        // before throwing, so its exact entry can be joined.
                        await self.retainPatientWork(workID, lifecycle: lifecycle)
                        try Task.checkCancellation()
                        return leaf
                    }
                }
            } onCancel: {
                // NSLock-backed gate: immediate denied starts while the MainActor
                // catch waits for a resolver that ignores its cancellation.
                leafGate.close()
            }
            try Task.checkCancellation()
            guard isOpen, capability === result, result.hasRetainedCapability,
                  parentCapability?.hasRetainedCapability == true else {
                throw CancellationError()
            }
            return result
        } catch {
            // A visible commit can have happened before this throwing return.
            // Its grant is terminally withdrawn in one synchronous actor turn.
            invalidateSynchronously()
            await finishPatientWork()
            throw error
        }
    }

    func invalidateSynchronously() {
        leafGate.close()
        capability?.release()
        parentCapability?.release()
        capability = nil
        parentCapability = nil
        capturedLease = nil
    }

    func endSession() async {
        invalidateSynchronously()
        await leafGate.drain()
        await finishPatientWork()
        // Reentrant ends share the same monotonically closed gate and finish.
        invalidateSynchronously()
    }

    /// Preserve the original leaf Value at the observed visible boundary.
    /// Both wrappers belong to this one-shot binding, never a current lookup.
    private func retainedParent(for leaf: MealRecordSessionCapability) throws -> MealRecordSessionCapability {
        guard isOpen, capability === leaf, let parent = parentCapability,
              leaf.hasRetainedCapability, parent.hasRetainedCapability else {
            throw CancellationError()
        }
        return parent
    }

    private func retainPatientWork(_ id: UUID, lifecycle: any SessionLifecycleProviding) {
        patientWorkRegistration = PatientWorkRegistration(id: id, lifecycle: lifecycle)
    }

    /// One exact finish; reentrant bind/end cleanup joins without a new Task.
    private func finishPatientWork() async {
        if isFinishingPatientWork {
            await withCheckedContinuation { continuation in
                patientWorkFinishWaiters.append(continuation)
            }
            return
        }
        guard let registration = patientWorkRegistration else { return }
        patientWorkRegistration = nil
        isFinishingPatientWork = true
        await registration.lifecycle.finishPatientWork(registration.id)
        isFinishingPatientWork = false
        let waiters = patientWorkFinishWaiters
        patientWorkFinishWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
