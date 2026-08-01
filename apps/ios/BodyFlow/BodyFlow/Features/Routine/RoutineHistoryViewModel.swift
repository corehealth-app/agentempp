import Foundation
import Observation

@MainActor
@Observable
final class RoutineHistoryViewModel {
    let kind: RoutineItemKind
    let itemID: String
    private let provider: any RoutineProviding
    private let controller = FeatureRevisionLoadController<RoutineHistoryPage>()
    private var isLoadingMore = false

    private(set) var state: FeatureReadState<RoutineHistorySnapshot> = .idle
    private(set) var items: [RoutineHistoryItem] = []
    private(set) var nextCursor: String?

    init(kind: RoutineItemKind, itemID: String, provider: any RoutineProviding) {
        self.kind = kind
        self.itemID = itemID
        self.provider = provider
    }

    func load(revision: Int) async {
        await controller.load(
            revision: revision,
            operation: { [provider, kind, itemID] in
                try await provider.history(
                    kind: kind,
                    itemID: itemID,
                    cursor: nil,
                    limit: 20
                )
            },
            publish: publishFirstPage
        )
    }

    func retry(revision: Int) async {
        await controller.retry(
            revision: revision,
            operation: { [provider, kind, itemID] in
                try await provider.history(
                    kind: kind,
                    itemID: itemID,
                    cursor: nil,
                    limit: 20
                )
            },
            publish: publishFirstPage
        )
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, !Task.isCancelled else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await provider.history(
                kind: kind,
                itemID: itemID,
                cursor: cursor,
                limit: 20
            )
            try Task.checkCancellation()
            guard nextCursor == cursor else { return }
            items += page.items
            nextCursor = page.nextCursor
            state = .loaded(RoutineHistorySnapshot(items: items, nextCursor: nextCursor))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = Self.readState(for: error, previousValue: state.presentation.value)
        }
    }

    private func publishFirstPage(
        _ completion: FeatureLoadCompletion<RoutineHistoryPage>
    ) {
        switch completion {
        case let .value(response):
            items = response.items
            nextCursor = response.nextCursor
            state = response.items.isEmpty
                ? .empty
                : .loaded(response.data)
        case let .failure(error):
            state = Self.readState(for: error, previousValue: state.presentation.value)
        }
    }

    private static func readState(
        for error: any Error,
        previousValue: RoutineHistorySnapshot?
    ) -> FeatureReadState<RoutineHistorySnapshot> {
        let capabilityError = error as? BodyFlowCapabilityError ?? .serviceUnavailable
        switch capabilityError {
        case .operationUnavailable:
            return .unavailable
        case .offline:
            return .offline(previousValue: previousValue)
        default:
            return .failed(previousValue: previousValue, error: capabilityError)
        }
    }
}
