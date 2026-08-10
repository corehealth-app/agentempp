import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    private enum LoadIntention {
        case revision
        case retry
    }

    private struct LoadIdentity {
        let revision: Int
        let sequence: Int
        let ownership: FeatureLoadOwnership
        let previousState: FeatureReadState<TodaySnapshot>
    }

    private let provider: any TodayProviding
    private var activeLoad: LoadIdentity?
    private var completedRevisions: Set<Int> = []
    private var currentRevision: Int?
    private var sequence = 0

    private(set) var state: FeatureReadState<TodaySnapshot> = .idle

    init(provider: any TodayProviding) {
        self.provider = provider
    }

    func load(revision: Int) async {
        await start(revision: revision, intention: .revision)
    }

    func retry() async {
        guard let currentRevision else { return }
        await start(revision: currentRevision, intention: .retry)
    }

    private func start(
        revision: Int,
        intention: LoadIntention
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
            let previousState = activeLoad?.previousState ?? state
            let identity = LoadIdentity(
                revision: revision,
                sequence: sequence,
                ownership: ownership,
                previousState: previousState
            )
            activeLoad?.ownership.invalidate()
            activeLoad = identity
            publishLoadingState()
            await perform(identity)
        } onCancel: {
            ownership.invalidate()
            Task { @MainActor [weak self] in
                self?.restoreCancelledLoad(ownedBy: ownership)
            }
        }
    }

    private func prepare(
        revision: Int,
        intention: LoadIntention
    ) -> Bool {
        switch intention {
        case .revision:
            if let currentRevision {
                guard revision >= currentRevision else { return false }
            }
            if currentRevision.map({ revision > $0 }) ?? true {
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

    private func publishLoadingState() {
        if let previousValue = visibleSnapshot {
            state = .loaded(previousValue)
        } else {
            state = .loading
        }
    }

    private func perform(_ identity: LoadIdentity) async {
        defer {
            if activeLoad?.sequence == identity.sequence {
                activeLoad = nil
            }
        }

        do {
            let response = try await provider.today()
            try Task.checkCancellation()
            guard canPublish(identity) else { return }
            completedRevisions.insert(identity.revision)
            state = response.data.completionStatus.status == "no_records"
                ? .empty
                : .loaded(response.data)
        } catch is CancellationError {
            restoreCancelledLoad(identity)
            return
        } catch {
            if Task.isCancelled {
                restoreCancelledLoad(identity)
                return
            }
            guard canPublish(identity) else { return }
            completedRevisions.insert(identity.revision)
            publish(error: error, previousValue: visibleSnapshot)
        }
    }

    private func restoreCancelledLoad(_ identity: LoadIdentity) {
        guard activeLoad?.sequence == identity.sequence,
              currentRevision == identity.revision else {
            return
        }
        state = identity.previousState
        activeLoad = nil
    }

    private func restoreCancelledLoad(
        ownedBy ownership: FeatureLoadOwnership
    ) {
        guard let identity = activeLoad,
              identity.ownership === ownership else {
            return
        }
        restoreCancelledLoad(identity)
    }

    private func canPublish(_ identity: LoadIdentity) -> Bool {
        activeLoad?.sequence == identity.sequence
            && currentRevision == identity.revision
            && identity.ownership.claimPublication()
    }

    private func publish(error: any Error, previousValue: TodaySnapshot?) {
        let capabilityError = error as? BodyFlowCapabilityError
            ?? .serviceUnavailable
        switch capabilityError {
        case .operationUnavailable:
            state = .unavailable
        case .offline:
            state = .offline(previousValue: previousValue)
        default:
            state = .failed(
                previousValue: previousValue,
                error: capabilityError
            )
        }
    }

    private var visibleSnapshot: TodaySnapshot? {
        switch state {
        case let .loaded(value),
             let .offline(previousValue: value?),
             let .failed(previousValue: value?, error: _):
            value
        case .idle,
             .loading,
             .empty,
             .offline(previousValue: nil),
             .failed(previousValue: nil, error: _),
             .unavailable:
            nil
        }
    }
}
