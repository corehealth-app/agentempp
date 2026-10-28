import Foundation
import Observation

/// One instance belongs to one authenticated shell. Ending it is permanent.
@MainActor
@Observable
final class CurrentObjectiveModel {
    private struct Read {
        let sequence: Int
        let ownership: FeatureLoadOwnership
        let previousState: FeatureReadState<CurrentObjectiveSnapshot>
    }
    let userID: String
    let firstPhase: ClinicalFirstPhaseModel?
    private let provider: any CurrentObjectiveProviding
    private var sequence = 0
    private var activeRead: Read?
    private var ended = false
    private(set) var state: FeatureReadState<CurrentObjectiveSnapshot> = .idle
    var isLoading: Bool { activeRead != nil }

    init(userID: String, provider: any CurrentObjectiveProviding, firstPhase: ClinicalFirstPhaseModel? = nil) {
        self.userID = userID
        self.provider = provider
        self.firstPhase = firstPhase
    }

    func load() async {
        guard !ended, !Task.isCancelled else { return }
        if let activeRead {
            guard activeRead.ownership.isInvalidated else { return }
            restore(activeRead)
        }
        let ownership = FeatureLoadOwnership()
        await withTaskCancellationHandler {
            guard !ended, !Task.isCancelled, !ownership.isInvalidated else { return }
            sequence += 1
            let read = Read(sequence: sequence, ownership: ownership, previousState: state)
            activeRead = read
            if state.presentation.value == nil { state = .loading }
            defer {
                if activeRead?.sequence == read.sequence { activeRead = nil }
            }
            do {
                let snapshot = try await provider.currentObjective().validated()
                try Task.checkCancellation()
                guard canPublish(read) else { return }
                state = snapshot.isEmpty ? .empty : .loaded(snapshot)
            } catch is CancellationError {
                restore(read)
            } catch {
                guard !Task.isCancelled, canPublish(read) else { return }
                let previous = read.previousState.presentation.value
                switch error as? BodyFlowCapabilityError ?? .serviceUnavailable {
                case .offline: state = .offline(previousValue: previous)
                case .operationUnavailable: state = .unavailable
                case let failure: state = .failed(previousValue: previous, error: failure)
                }
            }
        } onCancel: {
            ownership.invalidate()
            Task { @MainActor [weak self] in
                guard let self, let read = self.activeRead,
                      read.ownership === ownership else { return }
                self.restore(read)
            }
        }
    }

    func cancelRead() {
        guard let read = activeRead else { return }
        read.ownership.invalidate()
        restore(read)
    }

    func invalidate() {
        ended = true
        firstPhase?.invalidate()
        cancelRead()
        state = .idle
    }

    private func canPublish(_ read: Read) -> Bool {
        !ended && activeRead?.sequence == read.sequence && read.ownership.claimPublication()
    }

    private func restore(_ read: Read) {
        guard activeRead?.sequence == read.sequence else { return }
        state = read.previousState
        activeRead = nil
    }
}
