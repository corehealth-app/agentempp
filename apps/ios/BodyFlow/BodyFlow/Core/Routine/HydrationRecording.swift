import Foundation

typealias HydrationReceipt = MobileResponse<HydrationReceiptSnapshot>

struct HydrationCommand: Codable, Hashable, Sendable {
    let amountML: Int
    let occurredAt: APITimestamp

    init(amountML: Int, occurredAt: APITimestamp) throws {
        guard (1...5_000).contains(amountML) else {
            throw RoutineCommandValidationError.invalidHydrationAmount
        }

        self.amountML = amountML
        self.occurredAt = occurredAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            amountML: container.decode(Int.self, forKey: .amountML),
            occurredAt: container.decode(APITimestamp.self, forKey: .occurredAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case amountML = "amount_ml"
        case occurredAt = "occurred_at"
    }
}

struct HydrationReceiptSnapshot: Codable, Equatable, Sendable {
    let hydrationLogID: String
    let inserted: Bool
    let waterConsumedML: Int

    private enum CodingKeys: String, CodingKey {
        case hydrationLogID = "hydration_log_id"
        case inserted
        case waterConsumedML = "water_consumed_ml"
    }
}

protocol HydrationRecording: Sendable {
    func record(
        _ attempt: MutationAttempt<HydrationCommand>
    ) async throws -> HydrationReceipt
}
