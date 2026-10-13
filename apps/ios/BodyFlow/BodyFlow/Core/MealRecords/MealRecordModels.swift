import Foundation

// CANDIDATE SOURCE ONLY. DTO response keys must match the new C11 route;
// existing HistoryProviding / RegistrationProviding are unchanged.
typealias MealRecordResponse = MobileResponse<MealRecordSnapshot>
typealias MealRecordMutationResponse = MobileResponse<MealRecordMutationSnapshot>

enum MealRecordScope: String, Codable, Hashable, Sendable {
    case group
    case item
}

struct MealRecordSnapshot: Codable, Equatable, Sendable {
    let recordID: String
    let scope: MealRecordScope
    /// Opaque server version; never regenerated from timestamps or totals.
    let expectedVersion: String
    let itemIDs: [String]
    let items: [MealRecordItemSnapshot]
    /// Server eligibility: current official local date and open snapshot.
    let editable: Bool
    let dayClosed: Bool
    let localDate: String
    let timezone: String
    let editBlockReason: String?

    private enum CodingKeys: String, CodingKey {
        case scope, items, editable, timezone
        case recordID = "record_id"
        case expectedVersion = "expected_version"
        case itemIDs = "item_ids"
        case dayClosed = "day_closed"
        case localDate = "local_date"
        case editBlockReason = "edit_block_reason"
    }
}

struct MealRecordItemSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let foodName: String
    let quantityG: Decimal?
    let kcal: Decimal?
    let proteinG: Decimal?
    let carbsG: Decimal?
    let fatG: Decimal?
    let source: String?
    let consumedAt: APITimestamp
    let mealType: String?

    private enum CodingKeys: String, CodingKey {
        case id, kcal, source
        case foodName = "food_name"
        case mealType = "meal_type"
        case quantityG = "quantity_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case consumedAt = "consumed_at"
    }
}

struct MealRecordPatchBody: Codable, Hashable, Sendable {
    let expectedVersion: String
    let itemIDs: [String]
    let items: [MealProposalItemRequest]

    private enum CodingKeys: String, CodingKey {
        case items
        case expectedVersion = "expected_version"
        case itemIDs = "item_ids"
    }
}

struct MealRecordDeleteBody: Codable, Hashable, Sendable {
    let expectedVersion: String
    let itemIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
        case itemIDs = "item_ids"
    }
}

struct MealRecordPatchCommand: Hashable, Sendable {
    let recordID: String
    let body: MealRecordPatchBody
    // Captured GET facts for receipt validation, never encoded in the API body.
    let originalGroupItemIDs: [String]
    let expectedLocalDate: String
}

struct MealRecordDeleteCommand: Hashable, Sendable {
    let recordID: String
    let body: MealRecordDeleteBody
    let originalGroupItemIDs: [String]
    let expectedLocalDate: String
}

enum MealRecordMutationAttempt: Hashable, Sendable {
    case patch(MutationAttempt<MealRecordPatchCommand>)
    case delete(MutationAttempt<MealRecordDeleteCommand>)
}

struct MealRecordMutationSnapshot: Codable, Equatable, Sendable {
    enum Operation: String, Codable, Sendable { case updated, deleted }
    let recordID: String
    let operation: Operation
    let newItemIDs: [String]
    let removedItemIDs: [String]
    let nextRecordID: String?
    let snapshot: MealRecordPersistedSnapshot

    private enum CodingKeys: String, CodingKey {
        case operation, snapshot
        case recordID = "record_id"
        case newItemIDs = "new_item_ids"
        case removedItemIDs = "removed_item_ids"
        case nextRecordID = "next_record_id"
    }
}

/// Persisted server totals only. No food/block/exercise arithmetic on-device.
struct MealRecordPersistedSnapshot: Codable, Equatable, Sendable {
    let id: String
    let date: String
    let caloriesConsumed: Decimal
    let proteinG: Decimal
    let carbsG: Decimal
    let fatG: Decimal
    let dailyBalance: Decimal?

    private enum CodingKeys: String, CodingKey {
        case id, date
        case caloriesConsumed = "calories_consumed"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case dailyBalance = "daily_balance"
    }
}

enum MealRecordFailure: Error, Equatable, Sendable {
    case versionChanged
    case notEditable
    case notFound
    case commandConflict
    case requestInProgress
    case invalidInput
    case countryRequired
    case quantityNotRepresentable
    case nutritionUnresolved
    /// HTTP422: the requested composition exceeds the group limit.
    case groupLimitExceeded
    /// HTTP409: current official group state requires GET and explicit review.
    case groupLimitChanged
    case interruptedUnknown
    case capability(BodyFlowCapabilityError)

    var mayRetrySameAttempt: Bool {
        switch self {
        case .interruptedUnknown, .requestInProgress,
             .capability(.offline), .capability(.serviceUnavailable): true
        default: false
        }
    }
}

extension MealRecordMutationSnapshot {
    func encode(to encoder: any Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(recordID, forKey: .recordID)
        try value.encode(operation, forKey: .operation)
        try value.encode(newItemIDs, forKey: .newItemIDs)
        try value.encode(removedItemIDs, forKey: .removedItemIDs)
        try value.encode(nextRecordID, forKey: .nextRecordID)
        try value.encode(snapshot, forKey: .snapshot)
    }

    init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        guard value.contains(.nextRecordID) else {
            throw DecodingError.keyNotFound(CodingKeys.nextRecordID,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing next_record_id"))
        }
        recordID = try value.decode(String.self, forKey: .recordID)
        operation = try value.decode(Operation.self, forKey: .operation)
        newItemIDs = try value.decode([String].self, forKey: .newItemIDs)
        removedItemIDs = try value.decode([String].self, forKey: .removedItemIDs)
        nextRecordID = try value.decodeIfPresent(String.self, forKey: .nextRecordID)
        snapshot = try value.decode(MealRecordPersistedSnapshot.self, forKey: .snapshot)
    }
}

extension MealRecordPersistedSnapshot {
    func encode(to encoder: any Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(id, forKey: .id)
        try value.encode(date, forKey: .date)
        try value.encode(caloriesConsumed, forKey: .caloriesConsumed)
        try value.encode(proteinG, forKey: .proteinG)
        try value.encode(carbsG, forKey: .carbsG)
        try value.encode(fatG, forKey: .fatG)
        try value.encode(dailyBalance, forKey: .dailyBalance)
    }

    init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        guard value.contains(.dailyBalance) else {
            throw DecodingError.keyNotFound(CodingKeys.dailyBalance,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing daily_balance"))
        }
        id = try value.decode(String.self, forKey: .id)
        date = try value.decode(String.self, forKey: .date)
        caloriesConsumed = try value.decode(Decimal.self, forKey: .caloriesConsumed)
        proteinG = try value.decode(Decimal.self, forKey: .proteinG)
        carbsG = try value.decode(Decimal.self, forKey: .carbsG)
        fatG = try value.decode(Decimal.self, forKey: .fatG)
        dailyBalance = try value.decodeIfPresent(Decimal.self, forKey: .dailyBalance)
    }
}

protocol MealRecordProviding: Sendable {
    func mealRecord(id: String) async throws -> MealRecordResponse
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse
}

struct UnavailableMealRecordProvider: MealRecordProviding {
    func mealRecord(id: String) async throws -> MealRecordResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
    func patch(_ attempt: MutationAttempt<MealRecordPatchCommand>) async throws -> MealRecordMutationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
    func delete(_ attempt: MutationAttempt<MealRecordDeleteCommand>) async throws -> MealRecordMutationResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}
