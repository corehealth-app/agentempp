import Foundation
import Observation

struct HistoryPresentation: Equatable, Sendable {
    let meals: [HistoryMealLogRow]
    let workouts: [HistoryWorkoutLogRow]

    init(snapshot: HistorySnapshot) {
        meals = snapshot.meals
        workouts = snapshot.workouts
    }

    var isGloballyEmpty: Bool {
        meals.isEmpty && workouts.isEmpty
    }

    var sectionTitles: [String] {
        ["Registros de alimentos", "Treinos"]
    }
}

@MainActor
@Observable
final class HistoryViewModel {
    private let provider: any HistoryProviding
    private let controller = FeatureRevisionLoadController<HistoryResponse>()

    private(set) var state: FeatureReadState<HistorySnapshot> = .idle

    init(provider: any HistoryProviding) {
        self.provider = provider
    }

    func load(revision: Int) async {
        guard !Task.isCancelled else { return }
        currentRevision = max(currentRevision, revision)
        if case .idle = state {
            state = .loading
        }
        await controller.load(
            revision: revision,
            operation: { [provider] in
                try await provider.history(.firstPage)
            },
            publish: publish
        )
    }

    func retry() async {
        await controller.retry(
            revision: currentRevision,
            operation: { [provider] in
                try await provider.history(.firstPage)
            },
            publish: publish
        )
    }

    func mealLogRow(id: String) -> HistoryMealLogRow? {
        currentSnapshot?.meals.first { $0.id == id }
    }

    func workoutLogRow(id: String) -> HistoryWorkoutLogRow? {
        currentSnapshot?.workouts.first { $0.id == id }
    }

    var currentSnapshot: HistorySnapshot? {
        switch state {
        case let .loaded(snapshot),
             let .offline(previousValue: snapshot?),
             let .failed(previousValue: snapshot?, error: _):
            snapshot
        case .idle, .loading, .empty, .offline(previousValue: nil),
             .failed(previousValue: nil, error: _), .unavailable:
            nil
        }
    }

    private var currentRevision = 0

    private func publish(_ completion: FeatureLoadCompletion<HistoryResponse>) {
        switch completion {
        case let .value(response):
            state = response.data.meals.isEmpty && response.data.workouts.isEmpty
                ? .empty
                : .loaded(response.data)
        case let .failure(error):
            state = Self.readState(for: error, previousValue: currentSnapshot)
        }
    }

    private static func readState(
        for error: any Error,
        previousValue: HistorySnapshot?
    ) -> FeatureReadState<HistorySnapshot> {
        switch error as? BodyFlowCapabilityError ?? .serviceUnavailable {
        case .operationUnavailable:
            .unavailable
        case .offline:
            .offline(previousValue: previousValue)
        default:
            .failed(
                previousValue: previousValue,
                error: error as? BodyFlowCapabilityError ?? .serviceUnavailable
            )
        }
    }
}
