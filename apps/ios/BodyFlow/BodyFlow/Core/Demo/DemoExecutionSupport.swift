#if DEBUG
import Foundation

struct FixedTimeProvider: TimeProviding {
    let value: Date

    var now: Date {
        value
    }
}

final class DeterministicIdempotencyKeyProvider: @unchecked Sendable, IdempotencyKeyProviding {
    private let prefix: String
    private let lock = NSLock()
    private var nextSequence = 1

    init(prefix: String = "demo-key") {
        self.prefix = prefix
    }

    func nextKey() throws -> IdempotencyKey {
        let sequence = lock.withLock {
            defer { nextSequence += 1 }
            return nextSequence
        }

        return try IdempotencyKey(
            validating: "\(prefix)-\(String(format: "%04d", sequence))"
        )
    }
}
#endif
