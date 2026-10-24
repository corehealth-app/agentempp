import Foundation

typealias WorkoutStrengthHistoryResponse = MobileResponse<WorkoutStrengthHistorySnapshot>

/// Only the opt-in GET has this wrapper. The authority inside remains strict;
/// a malformed wrapper never falls back to a different authority shape.
struct WorkoutStrengthHistorySnapshot: Codable, Equatable, Sendable {
    let clarification: WorkoutStrengthClarification
    let feedback: RegistrationFeedbackSnapshot?

    init(clarification: WorkoutStrengthClarification, feedback: RegistrationFeedbackSnapshot? = nil) {
        self.clarification = clarification
        self.feedback = clarification.workoutID != nil && feedback?.kind == .workout ? feedback : nil
    }

    private enum CodingKeys: String, CodingKey { case clarification, feedback }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.clarification) {
            let principal = try values.decode(WorkoutStrengthClarification.self, forKey: .clarification)
            let optional = try? values.decode(RegistrationFeedbackSnapshot.self, forKey: .feedback)
            self.init(clarification: principal, feedback: optional)
        } else {
            // Compatibility with a server that does not implement the opt-in.
            self.init(clarification: try WorkoutStrengthClarification(from: decoder))
        }
    }
}

extension WorkoutStrengthClarificationProviding {
    func loadWithFeedback(workoutID: String) async throws -> WorkoutStrengthHistoryResponse {
        let previous = try await load(workoutID: workoutID)
        return MobileResponse(data: WorkoutStrengthHistorySnapshot(clarification: previous.data), meta: previous.meta)
    }
}
