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

struct WeightDemoReceipt: Equatable, Sendable {
    let weightKG: Double
    let recordedAt: Date
    let label: String
}

protocol WeightRecording: Sendable {
    func record(
        _ attempt: MutationAttempt<WeightCommand>
    ) async throws -> WeightDemoReceipt
}
