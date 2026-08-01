import Foundation
import Observation

@MainActor
@Observable
final class RoutineListViewModel {
    let kind: RoutineItemKind
    private let provider: any RoutineProviding
    private let controller = FeatureRevisionLoadController<RoutineListResponse>()

    private(set) var state: FeatureReadState<RoutineListSnapshot> = .idle

    var snapshot: RoutineListSnapshot? { state.presentation.value }

    init(kind: RoutineItemKind, provider: any RoutineProviding) {
        self.kind = kind
        self.provider = provider
    }

    func load(revision: Int) async {
        await controller.load(
            revision: revision,
            operation: { [provider, kind] in
                try await provider.list(kind: kind, includeArchived: false)
            },
            publish: publish
        )
    }

    func retry(revision: Int) async {
        await controller.retry(
            revision: revision,
            operation: { [provider, kind] in
                try await provider.list(kind: kind, includeArchived: false)
            },
            publish: publish
        )
    }

    private func publish(_ completion: FeatureLoadCompletion<RoutineListResponse>) {
        switch completion {
        case let .value(response):
            state = response.data.items.isEmpty ? .empty : .loaded(response.data)
        case let .failure(error):
            state = Self.readState(for: error, previousValue: snapshot)
        }
    }

    private static func readState(
        for error: any Error,
        previousValue: RoutineListSnapshot?
    ) -> FeatureReadState<RoutineListSnapshot> {
        switch error as? BodyFlowCapabilityError ?? .serviceUnavailable {
        case .operationUnavailable:
            .unavailable
        case .offline:
            .offline(previousValue: previousValue)
        default:
            .failed(previousValue: previousValue, error: error as? BodyFlowCapabilityError ?? .serviceUnavailable)
        }
    }
}
