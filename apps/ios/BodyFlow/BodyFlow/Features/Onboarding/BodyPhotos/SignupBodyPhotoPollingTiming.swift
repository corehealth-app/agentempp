import Foundation

/// Monotonic reading time, independent from MutationAttempt.createdAt.
struct SignupBodyPhotoPollingTiming: Sendable {
    let elapsed: @Sendable () async -> Duration
    let sleep: @Sendable (Duration) async throws -> Void

    static func live() -> Self {
        let clock = ContinuousClock()
        let origin = clock.now
        return Self(
            elapsed: { origin.duration(to: clock.now) },
            sleep: { try await clock.sleep(for: $0) }
        )
    }
}
