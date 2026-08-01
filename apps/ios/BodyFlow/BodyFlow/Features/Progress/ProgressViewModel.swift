import Foundation
import Observation

@MainActor
@Observable
final class ProgressViewModel {
    private struct LoadIdentity {
        let sequence: Int
        let ownership: FeatureLoadOwnership
        let previousState: FeatureReadState<ProgressSnapshot>
    }

    private let provider: any ProgressProviding
    private var activeLoad: LoadIdentity?
    private var sequence = 0

    private(set) var state: FeatureReadState<ProgressSnapshot> = .idle

    init(provider: any ProgressProviding) {
        self.provider = provider
    }

    func load() async {
        await start()
    }

    func retry() async {
        await start()
    }

    private func start() async {
        guard !Task.isCancelled else { return }
        let ownership = FeatureLoadOwnership()

        await withTaskCancellationHandler {
            guard !Task.isCancelled, !ownership.isInvalidated else { return }
            sequence += 1
            let identity = LoadIdentity(
                sequence: sequence,
                ownership: ownership,
                previousState: state
            )
            activeLoad?.ownership.invalidate()
            activeLoad = identity
            state = visibleSnapshot.map(FeatureReadState.loaded) ?? .loading
            await perform(identity)
        } onCancel: {
            ownership.invalidate()
            Task { @MainActor [weak self] in
                self?.restoreCancelledLoad(ownedBy: ownership)
            }
        }
    }

    private func perform(_ identity: LoadIdentity) async {
        defer {
            if activeLoad?.sequence == identity.sequence {
                activeLoad = nil
            }
        }

        do {
            let response = try await provider.progress()
            try Task.checkCancellation()
            guard canPublish(identity) else { return }
            state = isEmpty(response.data) ? .empty : .loaded(response.data)
        } catch is CancellationError {
            restoreCancelledLoad(identity)
        } catch {
            guard !Task.isCancelled, canPublish(identity) else { return }
            publish(error: error, previousValue: visibleSnapshot)
        }
    }

    private func isEmpty(_ snapshot: ProgressSnapshot) -> Bool {
        snapshot.xpTotal == 0
            && snapshot.level == 0
            && snapshot.currentStreak == 0
            && snapshot.longestStreak == 0
            && snapshot.blocksCompleted == 0
            && snapshot.deficitBlock == nil
            && snapshot.currentWeight == nil
            && snapshot.currentBodyFatPercent == nil
            && snapshot.badgesEarned.isEmpty
            && snapshot.lastActiveDate == nil
            && snapshot.nextReevaluation == nil
    }

    private func restoreCancelledLoad(_ identity: LoadIdentity) {
        guard activeLoad?.sequence == identity.sequence else { return }
        state = identity.previousState
        activeLoad = nil
    }

    private func restoreCancelledLoad(ownedBy ownership: FeatureLoadOwnership) {
        guard let activeLoad, activeLoad.ownership === ownership else { return }
        restoreCancelledLoad(activeLoad)
    }

    private func canPublish(_ identity: LoadIdentity) -> Bool {
        activeLoad?.sequence == identity.sequence
            && identity.ownership.claimPublication()
    }

    private func publish(error: any Error, previousValue: ProgressSnapshot?) {
        let capabilityError = error as? BodyFlowCapabilityError
            ?? .serviceUnavailable
        switch capabilityError {
        case .operationUnavailable:
            state = .unavailable
        case .offline:
            state = .offline(previousValue: previousValue)
        default:
            state = .failed(previousValue: previousValue, error: capabilityError)
        }
    }

    private var visibleSnapshot: ProgressSnapshot? {
        switch state {
        case let .loaded(value),
             let .offline(previousValue: value?),
             let .failed(previousValue: value?, error: _):
            value
        case .idle, .loading, .empty, .offline(previousValue: nil),
             .failed(previousValue: nil, error: _), .unavailable:
            nil
        }
    }
}
