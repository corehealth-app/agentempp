import Foundation

/// Finite session-owned events. ACK keeps G known for later resweeps; an
/// uncertain create is never resolved by a negative observation of another G.
@MainActor
final class SignupBodyPhotoCleanupCoordinator {
    private let scope: SignupBodyPhotoCleanupScope
    private let isCurrentOwner: @MainActor @Sendable () -> Bool
    private var handledEvents: Set<UUID> = []
    private var epoch = UUID()
    private var work: Task<Void, Never>?
    private var pendingOfficial: [String: OnboardingBodyPhotoCleanupScope] = [:]

    init(scope: SignupBodyPhotoCleanupScope,
        isCurrentOwner: @escaping @MainActor @Sendable () -> Bool) {
        self.scope = scope
        self.isCurrentOwner = isCurrentOwner
    }

    func run(eventID: UUID, freshObservation: SignupBodyPhotoCleanupFreshObservation? = nil) async {
        guard isCurrentOwner(), handledEvents.insert(eventID).inserted else { return }
        work?.cancel()
        let operation = UUID()
        epoch = operation
        let task = Task { [weak self, scope] in
            guard let self else { return }
            do {
                try await scope.performWork { [weak self] in
                    guard let self else { return }
                    try await self.processEvent(operation, freshObservation: freshObservation)
                }
                try await self.boundary(operation)
            } catch {
                // The next explicit event may try again. Cancellation requests
                // stopping locally, without proving any remote cancellation.
            }
        }
        work = task
        await task.value
        if epoch == operation { work = nil }
    }

    /// Keep an accepted official observation in memory before attempting disk.
    /// Failure never turns the accepted completion into another completion POST.
    func observeOfficial(_ observation: OnboardingBodyPhotoCleanupScope?) async {
        guard isCurrentOwner(), let observation, observation.state == .pending,
              SignupBodyPhotoCleanupQueue.validGeneration(observation.generation) else { return }
        pendingOfficial[observation.generation] = observation
        let operation = epoch
        do {
            try await boundary(operation)
            try await scope.observePending(observation.generation, authorization(operation))
            try await boundary(operation)
            if pendingOfficial[observation.generation] == observation {
                pendingOfficial.removeValue(forKey: observation.generation)
            }
        } catch {
            // Retain this owner-bound observation for the next event.
        }
    }

    func invalidate() {
        epoch = UUID()
        work?.cancel()
        work = nil
    }

    private func boundary(_ operation: UUID) async throws {
        try requireCurrent(operation)
        try await scope.validateSession()
        try requireCurrent(operation)
    }

    private func requireCurrent(_ operation: UUID) throws {
        try Task.checkCancellation()
        guard epoch == operation, isCurrentOwner() else { throw CancellationError() }
    }

    private func authorization(_ operation: UUID) -> SignupBodyPhotoCleanupAuthorization {
        SignupBodyPhotoCleanupAuthorization { [weak self] in
            guard let self else { throw CancellationError() }
            try self.requireCurrent(operation)
        }
    }

    private func processEvent(_ operation: UUID,
        freshObservation: SignupBodyPhotoCleanupFreshObservation?) async throws {
        try await boundary(operation)
        let buffered = Array(pendingOfficial.values)
        for observation in buffered {
            try await boundary(operation)
            try await scope.observePending(observation.generation, authorization(operation))
            try await boundary(operation)
            if pendingOfficial[observation.generation] == observation {
                pendingOfficial.removeValue(forKey: observation.generation)
            }
        }
        let snapshot = try await scope.loadQueue()
        try await boundary(operation)
        var visited: Set<String> = []
        if let freshObservation {
            if let current = freshObservation.currentScope,
               SignupBodyPhotoCleanupQueue.validGeneration(current.generation) {
                visited.insert(current.generation)
                // Reuse the accepted positive result. A snapshot obtained after
                // that response cannot authorize negative revision-based clearing.
                if current.state == .pending {
                    do {
                        try await apply(current, expectedRevision: snapshot.scope(current.generation)?.revision,
                            operation: operation)
                    } catch { try await boundary(operation) }
                }
            }
        } else if !snapshot.unboundCreates.isEmpty {
            do {
                let current = try await scope.readScope(nil)
                try await boundary(operation)
                if let current, SignupBodyPhotoCleanupQueue.validGeneration(current.generation) {
                    visited.insert(current.generation)
                    try await apply(current, expectedRevision: snapshot.scope(current.generation)?.revision,
                        operation: operation)
                }
            } catch { try await boundary(operation) }
        }
        // The snapshot is finite and includes previously acknowledged scopes.
        // Entries added during the event are considered by a later event.
        for known in snapshot.knownScopes where !visited.contains(known.generation) {
            try await boundary(operation)
            do {
                let observation = try await scope.readScope(known.generation)
                try await boundary(operation)
                guard let observation, observation.generation == known.generation else { continue }
                try await apply(observation, expectedRevision: known.revision, operation: operation)
            } catch { try await boundary(operation) }
        }
    }

    private func apply(_ observation: OnboardingBodyPhotoCleanupScope,
        expectedRevision: UUID?, operation: UUID) async throws {
        try await boundary(operation)
        switch observation.state {
        case .unknown:
            return
        case .notRequired:
            guard let expectedRevision else { return }
            _ = try await scope.resolveNotRequired(observation.generation, expectedRevision, authorization(operation))
            try await boundary(operation)
        case .pending:
            let prepared = try await scope.prepareRepair(observation.generation, expectedRevision, authorization(operation))
            try await boundary(operation)
            guard let ticket = prepared,
                  ticket.generation == observation.generation,
                  ticket.userHash == SignupBodyPhotoCleanupStore.userHash(scope.userID) else { return }
            let receipt = try await scope.repair(ticket.mutationAttempt())
            try await boundary(operation)
            guard receipt.deleted >= 0 else { throw SignupBodyPhotoFailure.cleanupPending }
            _ = try await scope.acknowledge(ticket, authorization(operation))
            try await boundary(operation)
        }
    }
}
