import Foundation
import Observation

enum FeatureInvalidationKey: Hashable, Sendable {
    case today
    case history
    case routineList(kind: RoutineItemKind)
    case routineHistory(kind: RoutineItemKind, itemID: String)
}

enum FeatureInvalidation: Hashable, Sendable {
    case proposalCreated
    case proposalEdited
    case proposalCancelled
    case registrationConfirmed
    case hydrationRecorded
    case routineAction(kind: RoutineItemKind, itemID: String)
    case weightRecorded

    fileprivate var keys: Set<FeatureInvalidationKey> {
        switch self {
        case .proposalCreated, .proposalEdited, .proposalCancelled:
            [.today]
        case .registrationConfirmed:
            [.today, .history]
        case .hydrationRecorded:
            [.today]
        case let .routineAction(kind, itemID):
            [
                .today,
                .routineList(kind: kind),
                .routineHistory(kind: kind, itemID: itemID),
            ]
        case .weightRecorded:
            []
        }
    }
}

@MainActor
@Observable
final class FeatureInvalidationCenter {
    private var revisions: [FeatureInvalidationKey: Int] = [:]

    func revision(for key: FeatureInvalidationKey) -> Int {
        revisions[key, default: 0]
    }

    func record(_ invalidation: FeatureInvalidation) {
        record(keys: invalidation.keys)
    }

    func record(keys: Set<FeatureInvalidationKey>) {
        for key in keys {
            revisions[key, default: 0] += 1
        }
    }
}

enum FeatureLoadCompletion<Value: Sendable>: Sendable {
    case value(Value)
    case failure(any Error)
}

@MainActor
final class FeatureRevisionLoadController<Value: Sendable> {
    private enum Intention: Equatable {
        case revision
        case retry
    }

    private struct LoadIdentity {
        let revision: Int
        let intention: Intention
        let sequence: Int
        let ownership: FeatureLoadOwnership
    }

    private var activeLoad: LoadIdentity?
    private var completedRevisions: Set<Int> = []
    private var currentRevision: Int?
    private var sequence = 0

    func load(
        revision: Int,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async {
        await start(
            revision: revision,
            intention: .revision,
            operation: operation,
            publish: publish
        )
    }

    func retry(
        revision: Int,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async {
        await start(
            revision: revision,
            intention: .retry,
            operation: operation,
            publish: publish
        )
    }

    private func start(
        revision: Int,
        intention: Intention,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async {
        guard !Task.isCancelled else { return }
        let ownership = FeatureLoadOwnership()

        await withTaskCancellationHandler {
            guard !Task.isCancelled,
                  !ownership.isInvalidated,
                  prepare(revision: revision, intention: intention)
            else {
                return
            }

            sequence += 1
            let identity = LoadIdentity(
                revision: revision,
                intention: intention,
                sequence: sequence,
                ownership: ownership
            )
            activeLoad?.ownership.invalidate()
            activeLoad = identity

            await perform(
                identity: identity,
                operation: operation,
                publish: publish
            )
        } onCancel: {
            ownership.invalidate()
        }
    }

    private func prepare(
        revision: Int,
        intention: Intention
    ) -> Bool {
        switch intention {
        case .revision:
            if let highestRevision = currentRevision {
                guard revision >= highestRevision else { return false }

                if revision > highestRevision {
                    currentRevision = revision
                }
            } else {
                currentRevision = revision
            }

            guard !completedRevisions.contains(revision) else { return false }
            if let activeLoad,
               activeLoad.revision == revision,
               !activeLoad.ownership.isInvalidated {
                return false
            }
            return true
        case .retry:
            return revision == currentRevision
        }
    }

    private func perform(
        identity: LoadIdentity,
        operation: @escaping @Sendable () async throws -> Value,
        publish: @escaping @MainActor (FeatureLoadCompletion<Value>) -> Void
    ) async {
        guard !Task.isCancelled,
              !identity.ownership.isInvalidated
        else {
            clearActiveLoad(ifOwnedBy: identity)
            return
        }

        defer {
            clearActiveLoad(ifOwnedBy: identity)
        }

        do {
            let value = try await operation()
            try Task.checkCancellation()
            guard isCurrent(identity),
                  identity.ownership.claimPublication() else {
                return
            }

            completedRevisions.insert(identity.revision)
            publish(.value(value))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  isCurrent(identity),
                  identity.ownership.claimPublication()
            else {
                return
            }

            completedRevisions.insert(identity.revision)
            publish(.failure(error))
        }
    }

    private func isCurrent(_ identity: LoadIdentity) -> Bool {
        activeLoad?.sequence == identity.sequence
            && currentRevision == identity.revision
    }

    private func clearActiveLoad(ifOwnedBy identity: LoadIdentity) {
        if activeLoad?.sequence == identity.sequence {
            activeLoad = nil
        }
    }
}

final class FeatureLoadOwnership: @unchecked Sendable {
    private enum State {
        case active
        case invalidated
        case publicationCommitted
    }

    private let lock = NSLock()
    private var state = State.active

    var isInvalidated: Bool {
        lock.withLock {
            if case .invalidated = state {
                true
            } else {
                false
            }
        }
    }

    func invalidate() {
        lock.withLock {
            guard case .active = state else { return }
            state = .invalidated
        }
    }

    func claimPublication() -> Bool {
        lock.withLock {
            guard case .active = state else { return false }
            state = .publicationCommitted
            return true
        }
    }
}
