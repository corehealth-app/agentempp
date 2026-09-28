import Foundation

struct WeightCommand: Hashable, Sendable {
    let weightKG: Double
    let recordedAt: Date

    init(weightKG: Double, recordedAt: Date) throws {
        guard weightKG.isFinite,
              (30...300).contains(weightKG) else {
            throw RoutineCommandValidationError.invalidWeight
        }

        self.weightKG = weightKG
        self.recordedAt = recordedAt
    }
}

/// What the server did with a measurement it accepted.
enum WeightRecordOutcome: String, Sendable {
    /// It is now the current weight.
    case applied
    /// The same measurement had already been recorded.
    case sameMeasurement = "same_measurement"
    /// A more recent measurement exists; the current weight did not change.
    case olderThanCurrent = "older_than_current"
}

/// `POST /api/mobile/v1/weight`: the weight and instant in force after the
/// request, which are not the submitted ones when it was not applied.
struct WeightRecordSnapshot: Codable, Equatable, Sendable {
    let applied: Bool
    let reason: String
    let weightKG: Decimal
    let measuredAt: APITimestamp

    private enum CodingKeys: String, CodingKey {
        case applied
        case reason
        case weightKG = "weight_kg"
        case measuredAt = "measured_at"
    }
}

typealias WeightRecordResponse = MobileResponse<WeightRecordSnapshot>

/// The request body. The unit is always sent; the server converts and rounds.
struct WeightRecordRequest: Encodable, Sendable {
    let value: Double
    let unit: String
    let measuredAt: APITimestamp

    init(command: WeightCommand) {
        value = command.weightKG
        unit = "kg"
        measuredAt = APITimestamp(value: command.recordedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case unit
        case measuredAt = "measured_at"
    }
}

struct WeightDemoReceipt: Equatable, Sendable {
    let weightKG: Double
    let recordedAt: Date
    let label: String
    /// nil for the local demonstration; the server's outcome for a real
    /// record. An outcome this build does not know is kept as nil-with-reason
    /// and shown as recorded without claiming it became the current weight.
    var outcome: WeightRecordOutcome? = nil
    var isServerRecord = false
}

protocol WeightRecording: Sendable {
    func record(
        _ attempt: MutationAttempt<WeightCommand>
    ) async throws -> WeightDemoReceipt
}
