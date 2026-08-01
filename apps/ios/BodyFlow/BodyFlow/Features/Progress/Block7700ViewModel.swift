import Foundation
import Observation

struct Block7700Descriptor: Equatable, Sendable {
    let enabled: Bool
    let availability: String
    let targetKcal: Int?
    let currentKcal: Int?
    let percentage: Int?
    let completedBlocks: Int?
    let totalCreditedKcal: Int?
    let source: String

    init(block: TodayBlock7700) {
        enabled = block.enabled
        availability = block.availability
        targetKcal = block.targetKcal
        currentKcal = block.currentKcal
        percentage = block.percentage
        completedBlocks = block.completedBlocks
        totalCreditedKcal = block.totalCreditedKcal
        source = block.source
    }

    var targetText: String {
        TodayValueFormatter.optionalKcal(targetKcal)
    }

    var currentText: String {
        TodayValueFormatter.optionalKcal(currentKcal)
    }

    var creditedText: String? {
        totalCreditedKcal.map(TodayValueFormatter.kcal)
    }
}

@MainActor
@Observable
final class Block7700ViewModel {
    private struct LoadIdentity {
        let sequence: Int
        let ownership: FeatureLoadOwnership
        let previousState: FeatureReadState<Block7700Descriptor>
    }

    private let today: any TodayProviding
    private var activeLoad: LoadIdentity?
    private var sequence = 0

    private(set) var state: FeatureReadState<Block7700Descriptor> = .idle

    init(today: any TodayProviding) {
        self.today = today
    }

    var descriptor: Block7700Descriptor? {
        state.presentation.value
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
            state = descriptor.map(FeatureReadState.loaded) ?? .loading
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
            let response = try await today.today()
            try Task.checkCancellation()
            guard canPublish(identity) else { return }
            guard let block = response.data.block7700 else {
                state = .unavailable
                return
            }
            state = .loaded(Block7700Descriptor(block: block))
        } catch is CancellationError {
            restoreCancelledLoad(identity)
        } catch {
            guard !Task.isCancelled, canPublish(identity) else { return }
            publish(error: error, previousValue: descriptor)
        }
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

    private func publish(
        error: any Error,
        previousValue: Block7700Descriptor?
    ) {
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
}
