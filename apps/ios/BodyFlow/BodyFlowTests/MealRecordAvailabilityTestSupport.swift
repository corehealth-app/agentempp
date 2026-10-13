import Foundation
@testable import BodyFlow

// Reuses the original C11 fake server below the real repository. All inputs,
// IDs and persisted totals are synthetic canned facts, never patient data.
enum C11L24Fixtures {
    static let a = "11111111-1111-4111-8111-111111111111"
    static let b = "22222222-2222-4222-8222-222222222222"
    static let new1 = "33333333-3333-4333-8333-333333333333"
    static let new2 = "44444444-4444-4444-8444-444444444444"
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let localDate = "2026-10-09"
    static let meta = MobileResponseMetadata(apiVersion: "v1", requestID: "c11-l24-synthetic")
    static func item(_ id: String, _ name: String, _ quantity: Decimal, _ kcal: Decimal) -> MealRecordItemSnapshot {
        MealRecordItemSnapshot(id: id, foodName: name, quantityG: quantity, kcal: kcal,
            proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
            consumedAt: APITimestamp(value: date), mealType: nil)
    }
    static let group = MealRecordSnapshot(recordID: a, scope: .group, expectedVersion: "V1",
        itemIDs: [a, b], items: [item(a, "Synthetic item A", 50, 100), item(b, "Synthetic item B", 120, 70)],
        editable: true, dayClosed: false, localDate: localDate, timezone: "America/Sao_Paulo", editBlockReason: nil)
    static let totals = MealRecordPersistedSnapshot(id: "fixture-snapshot", date: localDate,
        caloriesConsumed: 170, proteinG: 3, carbsG: 4, fatG: 5, dailyBalance: -100)
    static let localRow = HistoryMealLogRow(id: a, mealType: nil, foodName: "Synthetic item A",
        quantityG: 50, kcal: 100, proteinG: 1, carbsG: 2, fatG: 3, consumedAt: APITimestamp(value: date))
    static func server() -> C11FakeMealServer {
        C11FakeMealServer(group: group, freshIDs: [new1, new2], totals: totals, meta: meta)
    }
    @MainActor
    static func model(_ id: String, provider: any MealRecordProviding,
                      keys: C11L24Keys = C11L24Keys(prefix: "external-a"),
                      center: FeatureInvalidationCenter? = nil) -> MealRecordModel {
        MealRecordModel(recordID: id, provider: provider, time: C11L24Time(), keys: keys,
                        invalidation: center ?? FeatureInvalidationCenter(), isSessionActive: { true })
    }
}
struct C11L24Time: TimeProviding { var now: Date { C11L24Fixtures.date } }
final class C11L24Keys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    private let prefix: String
    init(prefix: String = "target") { self.prefix = prefix }
    var count: Int { lock.withLock { issued } }
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock {
            issued += 1
            return try IdempotencyKey(validating: "c11-l24-\(prefix)-key-\(issued)")
        }
    }
}
actor C11L24ReadControl: MealRecordProviding {
    let base: any MealRecordProviding
    private var failure: MealRecordFailure?
    init(base: any MealRecordProviding) { self.base = base }
    func failNextRead(_ reason: MealRecordFailure) { failure = reason }
    func mealRecord(id: String) async throws -> MealRecordResponse {
        if let failure { self.failure = nil; throw failure }
        return try await base.mealRecord(id: id)
    }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        try await base.patch(attempt)
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        try await base.delete(attempt)
    }
}
actor C11L24LostReply: MealRecordProviding {
    let base: any MealRecordProviding
    private var losesNextPatch = true
    init(base: any MealRecordProviding) { self.base = base }
    func mealRecord(id: String) async throws -> MealRecordResponse { try await base.mealRecord(id: id) }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        let receipt = try await base.patch(attempt)
        if losesNextPatch { losesNextPatch = false; throw MealRecordFailure.interruptedUnknown }
        return receipt
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        try await base.delete(attempt)
    }
}
