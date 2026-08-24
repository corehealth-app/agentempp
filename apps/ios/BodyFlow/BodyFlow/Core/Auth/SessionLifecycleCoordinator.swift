import Foundation

actor SessionLifecycleCoordinator: SessionLifecycleProviding {
    private struct RefreshOperation {
        let id: UUID
        let userID: String
        let generation: UInt64
        let revision: UInt64
        let task: Task<SessionLease, Error>
    }

    private enum LocalInvalidationCommit {
        case failed
        case committed(accessToken: String?)
    }

    private let store: AuthenticationSessionStore
    private let remote: any SupabaseAuthRemoteOperating
    private let patientWorkRegistry: PatientWorkRegistry
    private let sensitiveStateClearer: any SensitiveStateClearing
    private let refreshPolicy: SessionRefreshPolicy
    private let mutationGate = SessionLifecycleMutationGate()

    private var record: AuthenticationSessionRecord?
    private var didBootstrap = false
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0
    private var refreshOperation: RefreshOperation?
    private var logoutAttemptInProgress = false
    private var localInvalidationInProgress = false

    init(
        store: AuthenticationSessionStore,
        remote: any SupabaseAuthRemoteOperating,
        patientWorkRegistry: PatientWorkRegistry = PatientWorkRegistry(),
        sensitiveStateClearer: any SensitiveStateClearing =
            NoopSensitiveStateClearer(),
        refreshPolicy: SessionRefreshPolicy = .production
    ) {
        self.store = store
        self.remote = remote
        self.patientWorkRegistry = patientWorkRegistry
        self.sensitiveStateClearer = sensitiveStateClearer
        self.refreshPolicy = refreshPolicy
    }

    func currentBearerToken() async -> String? {
        try? await leaseForRequest().bearer
    }

    func restorePublicSession() async throws -> AuthSession? {
        try await ensureBootstrapped()
        guard record != nil else { return nil }
        do {
            _ = try await leaseForRequest()
            return record?.publicSession
        } catch SessionLifecycleError.missingSession {
            return nil
        }
    }

    func leaseForRequest() async throws -> SessionLease {
        try Task.checkCancellation()
        if logoutAttemptInProgress {
            await mutationGate.acquire()
            await mutationGate.release()
            try Task.checkCancellation()
        }
        guard !localInvalidationInProgress else {
            throw SessionLifecycleError.missingSession
        }
        try await ensureBootstrapped()
        guard let record else { throw SessionLifecycleError.missingSession }
        if record.expiresAt.timeIntervalSince(refreshPolicy.now())
            <= refreshPolicy.leeway {
            return try await refresh(record: record, generation: generation)
        }
        return lease(for: record)
    }

    func refreshAfterUnauthorized(lease: SessionLease) async throws
        -> SessionLease {
        try await validate(lease)
        guard let record else { throw SessionLifecycleError.missingSession }
        if record.accessToken != lease.bearer {
            return self.lease(for: record)
        }
        return try await refresh(record: record, generation: generation)
    }

    func validate(_ lease: SessionLease) async throws {
        if logoutAttemptInProgress {
            await mutationGate.acquire()
            await mutationGate.release()
        }
        guard !localInvalidationInProgress else {
            throw SessionLifecycleError.sessionSuperseded
        }
        guard let record else { throw SessionLifecycleError.missingSession }
        guard record.userID == lease.userID,
              generation == lease.generation
        else { throw SessionLifecycleError.sessionSuperseded }
    }

    func `switch`(to newRecord: AuthenticationSessionRecord) async throws {
        await mutationGate.acquire()
        do {
            try Task.checkCancellation()
            if !didBootstrap {
                record = try await store.bootstrapRecord()
                didBootstrap = true
            }
            let oldRecord = record
            try await store.replace(with: newRecord)
            record = newRecord
            revision &+= 1

            let priorRefresh = refreshOperation
            refreshOperation = nil
            if let oldRecord, oldRecord.userID != newRecord.userID {
                let oldGeneration = generation
                generation &+= 1
                priorRefresh?.task.cancel()
                await patientWorkRegistry.cancelAll(
                    userID: oldRecord.userID,
                    generation: oldGeneration
                )
                await sensitiveStateClearer.clearSensitiveState()
            }
            await mutationGate.release()
        } catch {
            await mutationGate.release()
            throw error
        }
    }

    func signOut() async -> RemoteRevocationOutcome {
        await mutationGate.acquire()
        let commit = await commitLocalInvalidationWhileHoldingGate()
        await mutationGate.release()
        return await classifyRemoteRevocation(after: commit)
    }

    func beginPatientWork(
        lease: SessionLease,
        cancel: @escaping @Sendable () -> Void
    ) async throws -> UUID {
        try await validate(lease)
        guard let id = await patientWorkRegistry.begin(
            userID: lease.userID,
            generation: lease.generation,
            cancel: cancel
        ) else {
            throw SessionLifecycleError.sessionSuperseded
        }
        do {
            try await validate(lease)
            return id
        } catch {
            if await patientWorkRegistry.finish(id) {
                cancel()
            }
            throw error
        }
    }

    func finishPatientWork(_ id: UUID) async {
        _ = await patientWorkRegistry.finish(id)
    }

    private func refresh(
        record expectedRecord: AuthenticationSessionRecord,
        generation expectedGeneration: UInt64
    ) async throws -> SessionLease {
        let operation: RefreshOperation
        if let current = refreshOperation,
           current.userID == expectedRecord.userID,
           current.generation == expectedGeneration {
            operation = current
        } else {
            let id = UUID()
            let operationUserID = expectedRecord.userID
            let operationRevision = revision
            let remote = self.remote
            let task = Task {
                do {
                    let refreshed = try await remote.refresh(record: expectedRecord)
                    try Task.checkCancellation()
                    return try await self.commitRefresh(
                        refreshed,
                        expectedRecord: expectedRecord,
                        operationID: id,
                        operationUserID: operationUserID,
                        operationGeneration: expectedGeneration,
                        operationRevision: operationRevision
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch SupabaseAuthRemoteError.invalidGrant {
                    return try await self.handleInvalidGrant(
                        operationID: id,
                        operationUserID: operationUserID,
                        operationGeneration: expectedGeneration,
                        operationRevision: operationRevision,
                        expectedRecord: expectedRecord
                    )
                } catch let error as SessionLifecycleError {
                    throw error
                } catch {
                    await self.clearRefreshOperation(id: id)
                    throw SessionLifecycleError.refreshFailed
                }
            }
            operation = RefreshOperation(
                id: id,
                userID: operationUserID,
                generation: expectedGeneration,
                revision: operationRevision,
                task: task
            )
            refreshOperation = operation
        }

        do {
            let committedLease = try await operation.task.value
            try Task.checkCancellation()
            return committedLease
        } catch is CancellationError {
            if Task.isCancelled { throw CancellationError() }
            if let record,
               record.userID == expectedRecord.userID,
               generation == expectedGeneration {
                return lease(for: record)
            }
            throw SessionLifecycleError.sessionSuperseded
        } catch let error as SessionLifecycleError {
            if Task.isCancelled { throw CancellationError() }
            throw error
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if refreshOperation?.id == operation.id {
                refreshOperation = nil
            }
            throw SessionLifecycleError.refreshFailed
        }
    }

    private func commitRefresh(
        _ refreshed: AuthenticationSessionRecord,
        expectedRecord: AuthenticationSessionRecord,
        operationID: UUID,
        operationUserID: String,
        operationGeneration: UInt64,
        operationRevision: UInt64
    ) async throws -> SessionLease {
        await mutationGate.acquire()
        do {
            guard refreshOperation?.id == operationID,
                  revision == operationRevision,
                  generation == operationGeneration,
                  record?.userID == operationUserID,
                  refreshed.userID == operationUserID
            else {
                if let record,
                   record.userID == expectedRecord.userID,
                   generation == operationGeneration {
                    let currentLease = lease(for: record)
                    await mutationGate.release()
                    return currentLease
                }
                throw SessionLifecycleError.sessionSuperseded
            }
            try await store.replace(with: refreshed)
            record = refreshed
            refreshOperation = nil
            revision &+= 1
            let committedLease = lease(for: refreshed)
            await mutationGate.release()
            return committedLease
        } catch {
            if refreshOperation?.id == operationID {
                refreshOperation = nil
            }
            await mutationGate.release()
            throw error
        }
    }

    private func handleInvalidGrant(
        operationID: UUID,
        operationUserID: String,
        operationGeneration: UInt64,
        operationRevision: UInt64,
        expectedRecord: AuthenticationSessionRecord
    ) async throws -> SessionLease {
        await mutationGate.acquire()
        guard refreshOperation?.id == operationID,
              revision == operationRevision,
              generation == operationGeneration,
              record?.userID == operationUserID
        else {
            if let record,
               record.userID == expectedRecord.userID,
               generation == operationGeneration {
                let currentLease = lease(for: record)
                await mutationGate.release()
                return currentLease
            }
            await mutationGate.release()
            throw SessionLifecycleError.sessionSuperseded
        }

        refreshOperation = nil
        let commit = await commitLocalInvalidationWhileHoldingGate()
        await mutationGate.release()
        let outcome = await classifyRemoteRevocation(after: commit)
        if outcome == .localInvalidationFailed {
            throw SessionLifecycleError.localInvalidationFailed
        }
        throw SessionLifecycleError.missingSession
    }

    private func clearRefreshOperation(id: UUID) {
        if refreshOperation?.id == id {
            refreshOperation = nil
        }
    }

    private func commitLocalInvalidationWhileHoldingGate() async
        -> LocalInvalidationCommit {
        guard !localInvalidationInProgress else { return .failed }
        do {
            if !didBootstrap {
                record = try await store.bootstrapRecord()
                didBootstrap = true
            }
        } catch {
            return .failed
        }
        let oldRecord = record
        logoutAttemptInProgress = true
        do {
            _ = try await store.beginLocalInvalidation()
        } catch {
            logoutAttemptInProgress = false
            return .failed
        }

        logoutAttemptInProgress = false
        localInvalidationInProgress = true
        record = nil
        let oldGeneration = generation
        generation &+= 1
        revision &+= 1
        refreshOperation?.task.cancel()
        refreshOperation = nil
        if let oldRecord {
            await patientWorkRegistry.cancelAll(
                userID: oldRecord.userID,
                generation: oldGeneration
            )
        }
        await sensitiveStateClearer.clearSensitiveState()
        do {
            try await store.finishLocalInvalidation()
        } catch {
            // The durable marker remains the fail-closed bootstrap authority.
        }
        localInvalidationInProgress = false
        return .committed(accessToken: oldRecord?.accessToken)
    }

    private func classifyRemoteRevocation(
        after commit: LocalInvalidationCommit
    ) async -> RemoteRevocationOutcome {
        switch commit {
        case .failed:
            return .localInvalidationFailed
        case .committed(nil):
            return .unconfirmed
        case .committed(let accessToken?):
            return await remote.revokeCurrentSession(accessToken: accessToken)
        }
    }

    private func ensureBootstrapped() async throws {
        guard !didBootstrap else { return }
        await mutationGate.acquire()
        do {
            if !didBootstrap {
                record = try await store.bootstrapRecord()
                didBootstrap = true
            }
            await mutationGate.release()
        } catch {
            await mutationGate.release()
            throw error
        }
    }

    private func lease(for record: AuthenticationSessionRecord) -> SessionLease {
        SessionLease(
            userID: record.userID,
            generation: generation,
            bearer: record.accessToken
        )
    }
}

private actor SessionLifecycleMutationGate {
    private var isAcquired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isAcquired else {
            isAcquired = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard !waiters.isEmpty else {
            isAcquired = false
            return
        }
        waiters.removeFirst().resume()
    }
}
