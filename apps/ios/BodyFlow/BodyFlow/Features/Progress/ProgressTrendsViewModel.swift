import Foundation
import Observation

/// The chart series beside the progress snapshot. Loaded with Progress and
/// on every retry; a failure shows the unavailable line, never a stale or
/// invented chart.
@MainActor
@Observable
final class ProgressTrendsViewModel {
    enum State: Equatable {
        case idle, loading, loaded(TrendsSnapshot), unavailable
    }

    nonisolated static let window = 14

    private let provider: any ProgressProviding
    private var sequence = 0
    private(set) var state: State = .idle

    init(provider: any ProgressProviding) {
        self.provider = provider
    }

    func load() async {
        sequence += 1
        let current = sequence
        if case .loaded = state {} else { state = .loading }
        do {
            let response = try await provider.trends(days: Self.window)
            guard current == sequence, !Task.isCancelled else { return }
            state = .loaded(response.data)
        } catch is CancellationError {
            return
        } catch {
            guard current == sequence else { return }
            state = .unavailable
        }
    }
}
