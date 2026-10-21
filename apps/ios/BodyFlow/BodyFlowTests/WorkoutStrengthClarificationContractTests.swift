import Foundation
import Testing

@testable import BodyFlow

@Suite("Workout strength clarification strict contract")
struct WorkoutStrengthClarificationContractTests {
    private let workout = "b2800000-0000-4000-8000-000000000001"
    private let lifecycle = "c3900000-0000-4000-8000-000000000001"
    private let question = "d4a00000-0000-4000-8000-000000000001"
    private let at = "2026-10-21T01:02:03.123456Z"

    @Test("all four exact public states round trip without exposing internal fields", arguments: [
        "unanswered", "answered", "not_applicable", "unavailable",
    ])
    func exactStates(_ status: String) throws {
        let object = wire(status)
        let value = try decode(object)
        #expect(try JSONDecoder().decode(WorkoutStrengthClarification.self, from: JSONEncoder().encode(value)) == value)
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary == object as NSDictionary)
        if case let .answered(receipt) = value {
            #expect(receipt.acceptedAt == at)
            #expect(receipt.answer == .yes)
        }
    }

    @Test("both official answers round trip literally", arguments: [WorkoutStrengthAnswer.yes, .no])
    func bothAnswerValues(_ answer: WorkoutStrengthAnswer) throws {
        var object = wire("answered")
        object["receipt"] = ["answer": answer.rawValue, "accepted_at": at]
        let value = try decode(object)
        guard case let .answered(receipt) = value else { Issue.record("Expected answered"); return }
        #expect(receipt.answer == answer)
        #expect(receipt.acceptedAt == at)
        #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary == object as NSDictionary)
    }

    @Test("every state rejects extra fields, including backend authority", arguments: [
        "unanswered", "answered", "not_applicable", "unavailable",
    ])
    func rejectsExtraAuthority(_ status: String) {
        for key in ["owner_id", "operation_key", "raw_fact", "classification", "capture", "unexpected"] {
            var object = wire(status); object[key] = "synthetic"
            #expect(throws: DecodingError.self) { try decode(object) }
        }
    }

    @Test("conditional keys and revision are strict, never a default unanswered state", arguments: [
        "missing_workout", "missing_lifecycle", "missing_question", "missing_revision",
        "revision_string", "revision_negative", "revision_one_unanswered", "revision_zero_answered",
        "revision_one_known", "question_on_known", "question_on_answered_receipt",
        "tuple_on_unavailable", "unknown_status", "unknown_reason", "null_status",
    ])
    func invalidConditionalStates(_ variant: String) {
        var object = wire("unanswered")
        switch variant {
        case "missing_workout": object.removeValue(forKey: "workout_id")
        case "missing_lifecycle": object.removeValue(forKey: "lifecycle_key")
        case "missing_question": object.removeValue(forKey: "question_key")
        case "missing_revision": object.removeValue(forKey: "fact_revision")
        case "revision_string": object["fact_revision"] = "0"
        case "revision_negative": object["fact_revision"] = -1
        case "revision_one_unanswered": object["fact_revision"] = 1
        case "revision_zero_answered": object = wire("answered"); object["fact_revision"] = 0
        case "revision_one_known": object = wire("not_applicable"); object["fact_revision"] = 1
        case "question_on_known": object = wire("not_applicable"); object["question_key"] = question
        case "question_on_answered_receipt": object = wire("answered"); object["receipt"] = ["answer": "yes", "accepted_at": at, "question_key": question]
        case "tuple_on_unavailable": object = wire("unavailable"); object["workout_id"] = workout
        case "unknown_status": object["status"] = "future"
        case "unknown_reason": object = ["status": "unavailable", "reason": "future"]
        default: object["status"] = NSNull()
        }
        #expect(throws: DecodingError.self) { try decode(object) }
    }

    @Test("strict UUIDs reject non-UUID identifiers", arguments: [
        "", "pending-id", "../workout", "b2800000000040008000000000000001",
        "{b2800000-0000-4000-8000-000000000001}", "b2800000-0000-4000-8000-000000000001 ",
    ])
    func invalidUUIDs(_ id: String) {
        for key in ["workout_id", "lifecycle_key", "question_key"] {
            var object = wire("unanswered"); object[key] = id
            #expect(throws: DecodingError.self) { try decode(object) }
        }
        #expect(WorkoutStrengthScope(workoutID: id, lifecycleKey: lifecycle) == nil)
        #expect(WorkoutStrengthQuestion(workoutID: workout, lifecycleKey: lifecycle, factRevision: 0, questionKey: id) == nil)
    }

    @Test("UUID case canonicalizes once while accepted timestamp remains literal")
    func normalizationIsLimitedToIdentity() throws {
        var object = wire("answered")
        object["workout_id"] = workout.uppercased(); object["lifecycle_key"] = lifecycle.uppercased(); object["question_key"] = question.uppercased()
        guard case let .answered(receipt) = try decode(object) else { Issue.record("Expected answered"); return }
        #expect(receipt.scope.workoutID == workout)
        #expect(receipt.scope.lifecycleKey == lifecycle)
        #expect(receipt.questionKey == question)
        #expect(receipt.acceptedAt == at)
        #expect(WorkoutStrengthQuestion(workoutID: workout, lifecycleKey: lifecycle, factRevision: 1, questionKey: question) == nil)
    }

    @Test("receipt must contain exactly yes/no and a Gregorian UTC6 timestamp", arguments: [
        "2026-10-21T01:02:03.123Z", "2026-10-21T01:02:03.123456+00:00",
        "2026-02-29T01:02:03.123456Z", "0000-10-21T01:02:03.123456Z",
        "2026-10-21T24:02:03.123456Z", "2026-10-21T01:60:03.123456Z",
        "2026-10-21T01:02:60.123456Z", "2026-04-31T01:02:03.123456Z",
    ])
    func invalidReceiptInstant(_ value: String) {
        var object = wire("answered"); object["receipt"] = ["answer": "yes", "accepted_at": value]
        #expect(throws: DecodingError.self) { try decode(object) }
    }

    @Test("receipt wrong types, null, missing and extra keys are rejected", arguments: [
        "null", "{}", "{\"answer\":\"YES\",\"accepted_at\":\"2026-10-21T01:02:03.123456Z\"}",
        "{\"answer\":true,\"accepted_at\":\"2026-10-21T01:02:03.123456Z\"}",
        "{\"answer\":\"no\",\"accepted_at\":null}",
        "{\"answer\":\"yes\",\"accepted_at\":\"2026-10-21T01:02:03.123456Z\",\"operation_key\":\"private\"}",
    ])
    func invalidReceipt(_ json: String) throws {
        var object = wire("answered"); object["receipt"] = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
        #expect(throws: DecodingError.self) { try decode(object) }
    }

    private func decode(_ value: [String: Any]) throws -> WorkoutStrengthClarification {
        try JSONDecoder().decode(WorkoutStrengthClarification.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func wire(_ status: String) -> [String: Any] {
        if status == "unavailable" { return ["status": status, "reason": "provenance_gap"] }
        var object: [String: Any] = ["status": status, "workout_id": workout, "lifecycle_key": lifecycle, "fact_revision": status == "answered" ? 1 : 0]
        if status != "not_applicable" { object["question_key"] = question }
        if status == "answered" { object["receipt"] = ["answer": "yes", "accepted_at": at] }
        return object
    }
}
