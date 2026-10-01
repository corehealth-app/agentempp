import Observation

@MainActor
@Observable
final class TodayRefreshCoordinator {
    private(set) var isRunning = false

    func run(isExternallyRefreshing: Bool = false, _ operation: @MainActor () async throws -> Void) async rethrows {
        // A confirmation can own a Today read outside this manual operation.
        // Repeated gestures must not restart the independent reads while it waits.
        guard !isRunning, !isExternallyRefreshing, !Task.isCancelled else { return }
        isRunning = true
        defer { isRunning = false }
        try await operation()
    }
}
