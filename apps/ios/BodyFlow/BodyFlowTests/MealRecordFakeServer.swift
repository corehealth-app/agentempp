import Foundation
@testable import BodyFlow

/// Stand-in for `/api/mobile/v1/meal-records/:id`, placed where the phone's
/// transport sits, so the real `MobileMealRecordRepository` runs in front of
/// it. It answers the way the server does wherever the phone depends on it:
///
/// - a corrected food item comes back under a NEW id; the old id is gone;
/// - an id that no longer exists answers 404 `MEAL_RECORD_NOT_FOUND`;
/// - `next_record_id` is the replacement after a PATCH and, after a DELETE,
///   the first survivor of the group ordered by id, or null when none is left;
/// - a command already finished is answered again from its key, unchanged;
/// - another `expected_version` answers 409 `MEAL_VERSION_CONFLICT`;
/// - a name the server refuses (empty or over 160 after trimming) answers 422.
///
/// Totals are canned and energy is copied from the old row: the phone never
/// computes either. Synthetic; no network, no SQL, no patient data.
actor C11FakeMealServer: MobileAPIEnvelopeExecuting {
    private var rows: [MealRecordItemSnapshot]
    private var revision = 0
    private var freshIDs: [String]
    private let firstVersion: String
    private let localDate: String
    private let timezone: String
    private let totals: MealRecordPersistedSnapshot
    private let meta: MobileResponseMetadata
    private var ledger: [IdempotencyKey: MealRecordMutationResponse] = [:]
    private var holdsNextAnswer = false
    private var heldAnswer: CheckedContinuation<Void, Never>?
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Ids asked by GET, in order.
    private(set) var reads: [String] = []
    /// PATCH and DELETE requests received, replays and refusals included.
    private(set) var mutationCount = 0

    /// - Parameters:
    ///   - group: the meal as it stands before the test starts.
    ///   - freshIDs: the ids the server hands out to corrected items, in order.
    ///   - totals: the persisted day totals every receipt carries.
    init(group: MealRecordSnapshot, freshIDs: [String],
         totals: MealRecordPersistedSnapshot, meta: MobileResponseMetadata) {
        rows = group.items
        firstVersion = group.expectedVersion
        localDate = group.localDate
        timezone = group.timezone
        self.freshIDs = freshIDs
        self.totals = totals
        self.meta = meta
    }

    var itemIDs: [String] { rows.map(\.id) }
    var version: String { revision == 0 ? firstVersion : "\(firstVersion)+\(revision)" }

    /// The next PATCH or DELETE is committed at once, as on the server, but
    /// its answer only leaves when `releaseHeldAnswer()` is called.
    func holdNextMutationAnswer() { holdsNextAnswer = true }

    func releaseHeldAnswer() {
        heldAnswer?.resume()
        heldAnswer = nil
    }

    func waitUntilMutationCount(_ count: Int) async {
        if mutationCount >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        let id = request.path.split(separator: "/").last.map(String.init) ?? ""
        let answer: Data
        switch request.method {
        case .get:
            reads.append(id)
            answer = try JSONEncoder().encode(try read(id))
        case .patch, .delete:
            mutationCount += 1
            wake()
            guard case let .required(key) = request.idempotency, let body = request.body else {
                throw MobileAPITransportError.invalidResponse
            }
            let receipt = try commit(request.method, id: id, key: key, body: body)
            if holdsNextAnswer {
                holdsNextAnswer = false
                await withCheckedContinuation { heldAnswer = $0 }
            }
            answer = try JSONEncoder().encode(receipt)
        case .post:
            throw MobileAPITransportError.invalidResponse
        }
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: answer)
    }

    private func read(_ id: String) throws -> MealRecordResponse {
        guard rows.contains(where: { $0.id == id }) else { throw Self.notFound }
        return MealRecordResponse(data: MealRecordSnapshot(recordID: id, scope: .group,
            expectedVersion: version, itemIDs: rows.map(\.id), items: rows,
            editable: true, dayClosed: false, localDate: localDate, timezone: timezone,
            editBlockReason: nil), meta: meta)
    }

    private func commit(_ method: HTTPMethod, id: String, key: IdempotencyKey,
                        body: Data) throws -> MealRecordMutationResponse {
        // A finished command is answered from its key before anything else.
        if let finished = ledger[key] { return finished }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { throw Self.notFound }
        let receipt: MealRecordMutationSnapshot
        if method == .patch {
            let command = try JSONDecoder().decode(MealRecordPatchBody.self, from: body)
            guard command.expectedVersion == version else { throw Self.versionConflict }
            guard command.itemIDs == [id], command.items.count == 1,
                  Self.accepts(name: command.items[0].foodName), !freshIDs.isEmpty
            else { throw Self.refused }
            let old = rows[index]
            let newID = freshIDs.removeFirst()
            rows[index] = MealRecordItemSnapshot(id: newID, foodName: command.items[0].foodName,
                quantityG: command.items[0].quantityG, kcal: old.kcal, proteinG: old.proteinG,
                carbsG: old.carbsG, fatG: old.fatG, source: old.source,
                consumedAt: old.consumedAt, mealType: old.mealType)
            receipt = MealRecordMutationSnapshot(recordID: id, operation: .updated,
                newItemIDs: [newID], removedItemIDs: [id], nextRecordID: newID, snapshot: totals)
        } else {
            let command = try JSONDecoder().decode(MealRecordDeleteBody.self, from: body)
            guard command.expectedVersion == version else { throw Self.versionConflict }
            guard !command.itemIDs.isEmpty, Set(command.itemIDs).count == command.itemIDs.count,
                  Set(command.itemIDs).isSubset(of: Set(rows.map(\.id)))
            else { throw Self.refused }
            rows.removeAll { command.itemIDs.contains($0.id) }
            receipt = MealRecordMutationSnapshot(recordID: id, operation: .deleted,
                newItemIDs: [], removedItemIDs: command.itemIDs,
                nextRecordID: rows.map(\.id).sorted().first, snapshot: totals)
        }
        revision += 1
        let response = MealRecordMutationResponse(data: receipt, meta: meta)
        ledger[key] = response
        return response
    }

    private func wake() {
        let ready = waiters.filter { $0.count <= mutationCount }
        waiters.removeAll { $0.count <= mutationCount }
        for waiter in ready { waiter.continuation.resume() }
    }

    /// The server trims the name and accepts 1 to 160 UTF-16 units.
    private static func accepts(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf16.count <= 160
    }

    private static let notFound = MobileAPITransportError.http(
        status: 404, code: "MEAL_RECORD_NOT_FOUND", requestID: "c11-fake-server")
    private static let versionConflict = MobileAPITransportError.conflict(
        code: "MEAL_VERSION_CONFLICT", requestID: "c11-fake-server")
    private static let refused = MobileAPITransportError.validation(
        code: "validation_failed", requestID: "c11-fake-server")
}
