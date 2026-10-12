import Foundation

struct SignupBodyPhotoCleanupAuthorization: Sendable {
    let validate: @MainActor @Sendable () throws -> Void
}

/// Retains one session owner for technical reads, repairs and protected state.
/// Every closure must be supplied explicitly; no noop local-state defaults.
struct SignupBodyPhotoCleanupScope: Sendable {
    let userID: String
    let validateSession: @Sendable () async throws -> Void
    let loadQueue: @Sendable () async throws -> SignupBodyPhotoCleanupQueue
    let observePending: @Sendable (String, SignupBodyPhotoCleanupAuthorization) async throws -> Void
    /// expectedRevision=nil means the generation was absent before the read.
    /// A live implementation persists observe+prepare in one gated RMW.
    let prepareRepair: @Sendable (String, UUID?, SignupBodyPhotoCleanupAuthorization) async throws -> SignupBodyPhotoCleanupTicket?
    let acknowledge: @Sendable (SignupBodyPhotoCleanupTicket, SignupBodyPhotoCleanupAuthorization) async throws -> Bool
    let resolveNotRequired: @Sendable (String, UUID, SignupBodyPhotoCleanupAuthorization) async throws -> Bool
    let readScope: @Sendable (String?) async throws -> OnboardingBodyPhotoCleanupScope?
    let repair: @Sendable (MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt
    let performWork: @Sendable (@escaping @Sendable () async throws -> Void) async throws -> Void
}

struct SignupBodyPhotoCleanupCapability: Sendable {
    let scoped: @Sendable (String) async throws -> SignupBodyPhotoCleanupScope

    /// A single lease is shared by every dependency. Old scopes never renew it.
    static func live(transport: MobileAPITransport,
        lifecycle: any SessionLifecycleProviding,
        store: SignupBodyPhotoCleanupStore,
        keyProvider: any IdempotencyKeyProviding,
        timeProvider: any TimeProviding) -> Self {
        Self { userID in
            try Task.checkCancellation()
            let lease = try await lifecycle.leaseForRequest()
            guard lease.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
            try await lifecycle.validate(lease)
            try Task.checkCancellation()
            let bound = transport.scoped(to: lease)
            let onboarding = MobileOnboardingRepository(transport: bound, deviceDraft: nil,
                sessionLifecycle: lifecycle, sessionLease: lease)
            let photos = MobileSignupBodyPhotoRepository(transport: bound)
            return SignupBodyPhotoCleanupScope(userID: userID,
                validateSession: { try Task.checkCancellation(); try await lifecycle.validate(lease) },
                loadQueue: {
                    try await lifecycle.performPatientStateOperation(lease: lease) { try store.load(for: userID) }
                },
                observePending: { generation, authorization in
                    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                        try authorization.validate()
                        try store.mutate(for: userID) { current in
                            _ = try current.observePending(generation, newRevision: UUID())
                        }
                    }
                },
                prepareRepair: { generation, expectedRevision, authorization in
                    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                        try authorization.validate()
                        return try store.mutate(for: userID) { (current: inout SignupBodyPhotoCleanupQueue) -> SignupBodyPhotoCleanupTicket? in
                            guard current.scope(generation)?.revision == expectedRevision else { return nil }
                            _ = try current.observePending(generation, newRevision: UUID())
                            guard let observed = current.scope(generation) else { return nil }
                            return try current.prepareRepair(generation, expectedRevision: observed.revision,
                                newRevision: UUID(), operationID: UUID(),
                                takeKey: { try keyProvider.nextKey() }, takeDate: { timeProvider.now })
                        }
                    }
                },
                acknowledge: { ticket, authorization in
                    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                        try authorization.validate()
                        return try store.mutate(for: userID) { current in
                            try current.acknowledge(ticket, newRevision: UUID())
                        }
                    }
                },
                resolveNotRequired: { generation, revision, authorization in
                    try await lifecycle.performVisiblePatientStateOperation(lease: lease) {
                        try authorization.validate()
                        return try store.mutate(for: userID) { current in
                            current.resolveNotRequired(generation, expectedRevision: revision)
                        }
                    }
                },
                readScope: { try await onboarding.loadBodyPhotoCleanupScope(generation: $0) },
                repair: { try await photos.repair($0) },
                performWork: { try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run($0) })
        }
    }
}
