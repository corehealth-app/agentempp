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
                        return try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
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
                    }
                }
            } onCancel: {
                // NSLock-backed gate: immediate denied starts while the MainActor
                // catch waits for a resolver that ignores its cancellation.
                leafGate.close()
            }
            try Task.checkCancellation()
            guard isOpen, capability === result else { throw CancellationError() }
            return result
        } catch {
            // A visible commit can have happened before this throwing return.
            // Its grant is terminally withdrawn in one synchronous actor turn.
            invalidateSynchronously()
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
        // Reentrant ends share the same monotonically closed gate.
        invalidateSynchronously()
    }
}
