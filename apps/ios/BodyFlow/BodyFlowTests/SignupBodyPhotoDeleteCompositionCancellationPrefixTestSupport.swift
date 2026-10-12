#if DEBUG
import Foundation

// Unique local names keep this additive proxy separate from prior suites.
enum SignupDeleteCompositionCancelPrefix: String, CaseIterable, Sendable { case idle, ready }

final class SignupDeleteCompositionCancelCallerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var calls = 0

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let current = task
        if current != nil { calls += 1 }
        lock.unlock()
        current?.cancel()
    }

    var cancellationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}
#endif
