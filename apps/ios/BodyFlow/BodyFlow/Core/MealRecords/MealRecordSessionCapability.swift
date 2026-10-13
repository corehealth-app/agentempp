import Foundation

/// Reuses the authenticated owner gate: no operation starts after close and
/// no response from A may publish after switch to B. Cancellation is not a
/// claim that the server rolled back; the original command remains retained.
final class MealRecordSessionCapability: MealRecordProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var provider: (any MealRecordProviding)?
    private let gate: Prompt14SessionOperationGate

    init(provider: any MealRecordProviding, gate: Prompt14SessionOperationGate) {
        self.provider = provider; self.gate = gate
    }

    var hasRetainedCapability: Bool { lock.withLock { provider != nil } }
    func release() { lock.withLock { provider = nil } }
    private func current() throws -> any MealRecordProviding {
        guard let value = lock.withLock({ provider }) else { throw CancellationError() }
        return value
    }

    func mealRecord(id: String) async throws -> MealRecordResponse {
        try await gate.perform { try await self.current().mealRecord(id: id) }
    }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        try await gate.perform { try await self.current().patch(attempt) }
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        try await gate.perform { try await self.current().delete(attempt) }
    }
}
