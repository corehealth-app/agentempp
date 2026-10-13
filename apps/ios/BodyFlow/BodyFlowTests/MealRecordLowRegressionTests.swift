import Foundation
import Testing
@testable import BodyFlow

// Private test proposal only. Root must compile/run before calling it causal RED.
// Kept separate from the 27 byte-frozen MealRecordCandidateTests declarations.
@MainActor
@Suite("C11 low regression: remembered refusals")
struct MealRecordLowRegressionTests {
    @Test("L1: refused X, then refused Y, then X cannot obtain a third key or request")
    func refusesPreviouslyRejectedXAfterDifferentRejectedY() async throws {
        let peer = C11LowRefusalPeer(detail: C11LowFixtures.detail())
        let keys = C11LowKeys()
        let center = FeatureInvalidationCenter()
        let model = C11LowFixtures.model(peer, keys: keys, center: center)
        await model.load()
        try #require(model.canStartMutation)

        // X is the exact three-decimal quantity refused by the server.
        model.draft?.items[0].quantityText = "170.001"
        await model.save(language: .englishUnitedStates)
        let x = try #require(model.retainedAttempt)
        try #require(model.failure == .quantityNotRepresentable)
        try #require(keys.count == 1)
        model.beginCorrectingRejectedInput()
        try #require(model.canEditDraft)

        // Y changes the body and is independently refused for unresolved nutrition.
        model.draft?.items[0].foodName = "unresolvable"
        model.draft?.items[0].quantityText = "50"
        await model.save(language: .englishUnitedStates)
        let y = try #require(model.retainedAttempt)
        try #require(model.failure == .nutritionUnresolved)
        try #require(keys.count == 2)
        let firstTwo = await peer.patches
        try #require(firstTwo.count == 2)
        #expect(firstTwo[0].key != firstTwo[1].key)
        #expect(firstTwo[0].payload.body.items[0].foodName == "Synthetic item A")
        #expect(firstTwo[0].payload.body.items[0].quantityG == Decimal(string: "170.001"))
        #expect(firstTwo[1].payload.body.items[0].foodName == "unresolvable")
        #expect(firstTwo[1].payload.body.items[0].quantityG == 50)
        #expect(firstTwo[0].payload.body.expectedVersion == firstTwo[1].payload.body.expectedVersion)
        #expect(firstTwo[0].createdAt == firstTwo[1].createdAt)

        // Return to X while the same official version/group still stands.
        // An explicit Save is attempted to verify the model gate, not just a UI getter.
        model.beginCorrectingRejectedInput()
        try #require(model.canEditDraft)
        model.draft?.items[0].foodName = "Synthetic item A"
        model.draft?.items[0].quantityText = "170.001"
        #expect(!model.canSave(language: .englishUnitedStates))
        await model.save(language: .englishUnitedStates)
        #expect(keys.count == 2)
        #expect(await peer.patches == firstTwo)
        #expect(await peer.reads == [C11LowFixtures.a])
        #expect(model.retainedAttempt == y)
        #expect(model.attemptHistory == [x, y])
        #expect(model.failure == .nutritionUnresolved)
        #expect(model.confirmedReceipt == nil)
        #expect(model.draft?.items[0].foodName == "Synthetic item A")
        #expect(model.draft?.items[0].quantityText == "170.001")
        #expect(center.revision(for: .today) == 0)
        #expect(center.revision(for: .history) == 0)
    }


}

// Original C11 helpers are file-private. Preserve them and the frozen test file.
// These reduced synthetic builders retain its A/B IDs, snapshot facts, fixed date,
// real DTOs/model/key protocol and injectable typed failures. No extra app API.
private enum C11LowFixtures {
    static let a = "11111111-1111-4111-8111-111111111111"
    static let b = "22222222-2222-4222-8222-222222222222"
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static func detail(name: String = "Synthetic item A") -> MealRecordResponse {
        let rows = [
            MealRecordItemSnapshot(id: a, foodName: name, quantityG: 50, kcal: 100,
                proteinG: 1, carbsG: 2, fatG: 3, source: "canonical_exact",
                consumedAt: APITimestamp(value: date), mealType: nil),
            MealRecordItemSnapshot(id: b, foodName: "Synthetic item B", quantityG: 120, kcal: 70,
                proteinG: 4, carbsG: 5, fatG: 6, source: "user_kcal",
                consumedAt: APITimestamp(value: date), mealType: nil),
        ]
        return MealRecordResponse(data: MealRecordSnapshot(recordID: a, scope: .group,
            expectedVersion: "opaque-fixture-version", itemIDs: [a, b], items: rows,
            editable: true, dayClosed: false, localDate: "2026-10-09",
            timezone: "America/Sao_Paulo", editBlockReason: nil),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "c11-synthetic-unit"))
    }
    @MainActor
    static func model(_ provider: any MealRecordProviding, keys: C11LowKeys,
                      center: FeatureInvalidationCenter) -> MealRecordModel {
        MealRecordModel(recordID: a, provider: provider, time: C11LowTime(),
            keys: keys, invalidation: center, isSessionActive: { true })
    }
}
private struct C11LowTime: TimeProviding { var now: Date { C11LowFixtures.date } }
private final class C11LowKeys: IdempotencyKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    var count: Int { lock.withLock { issued } }
    func nextKey() throws -> IdempotencyKey {
        try lock.withLock {
            issued += 1
            return try IdempotencyKey(validating: "c11-low-key-\(issued)")
        }
    }
}
private actor C11LowRefusalPeer: MealRecordProviding {
    let detail: MealRecordResponse
    private var failures: [MealRecordFailure] = [.quantityNotRepresentable, .nutritionUnresolved]
    private(set) var reads: [String] = []
    private(set) var patches: [MutationAttempt<MealRecordPatchCommand>] = []
    init(detail: MealRecordResponse) { self.detail = detail }
    func mealRecord(id: String) async throws -> MealRecordResponse {
        reads.append(id)
        return detail
    }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        patches.append(attempt)
        throw failures.isEmpty ? MealRecordFailure.quantityNotRepresentable : failures.removeFirst()
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}
