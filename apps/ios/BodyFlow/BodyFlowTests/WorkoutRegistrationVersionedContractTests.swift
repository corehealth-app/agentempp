import Foundation
import Testing

@testable import BodyFlow

@Suite("Versioned workout registration contract")
struct WorkoutRegistrationVersionedContractTests {
    @Test("only the server's known capability selects ui-v1", arguments: [
        "", ", \"workout_registration_protocol\": null",
        ", \"workout_registration_protocol\": \"ui-v2\"",
        ", \"workout_registration_protocol\": \"ui-v1\"",
    ])
    func capabilityIsExplicit(_ extra: String) throws {
        let me = try JSONDecoder().decode(MeSnapshot.self, from: Data("{\"id\":\"test-user\"\(extra)}".utf8))
        #expect(me.supportsVersionedWorkoutRegistration == extra.contains("ui-v1"))
    }

    @Test("legacy snapshots never acquire a default revision")
    func legacySnapshotRemainsLegacy() throws {
        let snapshot = try decode("")
        #expect(snapshot.workoutVersion == nil)
        #expect(snapshot.editReceipt == nil)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        #expect(object["workout_protocol"] == nil)
        #expect(object["content_revision"] == nil)
        #expect(object["receipt"] == nil)
    }

    @Test("ui-v1 accepts the full nonnegative int32 revision range", arguments: [0, 2, 2147483647])
    func validSnapshotMetadata(_ revision: Int) throws {
        let snapshot = try decode(", \"workout_protocol\": \"ui-v1\", \"content_revision\": \(revision)")
        #expect(snapshot.workoutVersion?.contentRevision == revision)
        #expect(try JSONDecoder().decode(RegistrationSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test("partial null unknown or invalid metadata never becomes legacy", arguments: [
        ", \"workout_protocol\": \"ui-v1\"",
        ", \"content_revision\": 0",
        ", \"workout_protocol\": null, \"content_revision\": null",
        ", \"workout_protocol\": \"ui-v1\", \"content_revision\": null",
        ", \"workout_protocol\": \"ui-v2\", \"content_revision\": 0",
        ", \"workout_protocol\": \"ui-v1\", \"content_revision\": -1",
        ", \"workout_protocol\": \"ui-v1\", \"content_revision\": 1.5",
        ", \"workout_protocol\": \"ui-v1\", \"content_revision\": 2147483648",
        ", \"workout_protocol\": \"ui-v1\", \"content_revision\": \"0\"",
    ])
    func invalidSnapshotMetadata(_ extra: String) {
        #expect(throws: DecodingError.self) { try decode(extra) }
    }

    @Test("workout metadata cannot authorize another proposal kind", arguments: ["meal", "unknown"])
    func otherKindsRejectWorkoutMetadata(_ kind: String) {
        #expect(throws: DecodingError.self) {
            try decode(", \"workout_protocol\": \"ui-v1\", \"content_revision\": 0", kind: kind)
        }
    }

    @Test("an old edit receipt and the current confirmed projection remain distinct")
    func oldReceiptDoesNotReplaceTheCurrentRevision() throws {
        let snapshot = try decode(
            ", \"workout_protocol\": \"ui-v1\", \"content_revision\": 2, \"receipt\": \(receipt(expected: 0, result: 1))",
            status: "confirmed"
        )
        #expect(snapshot.status == "confirmed")
        #expect(snapshot.workoutVersion?.contentRevision == 2)
        #expect(snapshot.editReceipt?.expectedRevision == 0)
        #expect(snapshot.editReceipt?.resultRevision == 1)
        #expect(snapshot.editReceipt?.requestKey == "wue1:7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C")
        #expect(try JSONDecoder().decode(RegistrationSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test("invalid receipt or receipt without version never authorizes an edit", arguments: [
        ", \"receipt\": null",
        ", \"receipt\": {\"requestKey\":\"wue1:7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C\",\"expectedRevision\":0,\"resultRevision\":1}",
        ", \"workout_protocol\":\"ui-v1\", \"content_revision\":0, \"receipt\":{\"requestKey\":\"wue1:7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C\",\"expectedRevision\":0,\"resultRevision\":1}",
        ", \"workout_protocol\":\"ui-v1\", \"content_revision\":2, \"receipt\":{\"requestKey\":\"not-a-sql-key\",\"expectedRevision\":0,\"resultRevision\":1}",
        ", \"workout_protocol\":\"ui-v1\", \"content_revision\":2, \"receipt\":{\"requestKey\":\"wue1:7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C\",\"expectedRevision\":0,\"resultRevision\":2}",
        ", \"workout_protocol\":\"ui-v1\", \"content_revision\":2, \"receipt\":{\"requestKey\":\"wue1:7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C\",\"expectedRevision\":-1,\"resultRevision\":0}",
    ])
    func invalidReceipt(_ extra: String) {
        #expect(throws: DecodingError.self) { try decode(extra) }
    }

    @Test("version construction rejects values outside the server domain")
    func versionConstructionHasNoFallback() {
        #expect(WorkoutRegistrationVersion(contentRevision: -1) == nil)
        #expect(WorkoutRegistrationVersion(contentRevision: 2147483648) == nil)
        #expect(WorkoutRegistrationVersion(contentRevision: 0)?.contentRevision == 0)
    }

    @Test("request decoding rejects unknown or null explicit protocol", arguments: ["null", "\"ui-v2\""])
    func invalidRequestProtocol(_ value: String) {
        let data = Data("{\"kind\":\"workout\",\"workout_type\":\"Natação\",\"duration_min\":40,\"workout_protocol\":\(value)}".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegistrationProposalRequest.self, from: data) }
    }

    @Test("a standalone workout request also rejects explicit invalid protocol", arguments: ["null", "\"ui-v2\""])
    func standaloneRequestRejectsInvalidProtocol(_ value: String) {
        let data = Data("{\"workout_type\":\"Natação\",\"duration_min\":40,\"workout_protocol\":\(value)}".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WorkoutProposalRequest.self, from: data) }
    }

    @Test("a meal request cannot discard explicit workout metadata", arguments: ["null", "\"ui-v1\""])
    func mealRequestRejectsWorkoutProtocol(_ value: String) {
        let data = Data("{\"kind\":\"meal\",\"meal_type\":\"almoco\",\"items\":[],\"workout_protocol\":\(value)}".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RegistrationProposalRequest.self, from: data) }
    }

    private func decode(_ extra: String, kind: String = "workout", status: String = "pending") throws -> RegistrationSnapshot {
        let proposal: String
        switch kind {
        case "workout":
            proposal = "{\"kind\":\"workout\",\"workout_type\":\"Natação\",\"duration_min\":40,\"estimated_kcal\":400,\"intensity\":\"moderada\"}"
        case "meal":
            proposal = "{\"kind\":\"meal\",\"meal_type\":\"almoco\",\"items\":[],\"warnings\":[]}"
        default:
            proposal = "{\"kind\":\"unknown\"}"
        }
        let resolvedAt = status == "pending" ? "null" : "\"2026-07-20T12:30:00Z\""
        let json = """
        {"id":"7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c","status":"\(status)",
         "created_at":"2026-07-20T12:00:00Z","expires_at":"2026-07-21T12:00:00Z",
         "resolved_at":\(resolvedAt),"proposal":\(proposal)\(extra)}
        """
        return try JSONDecoder().decode(RegistrationSnapshot.self, from: Data(json.utf8))
    }

    private func receipt(expected: Int, result: Int) -> String {
        "{\"requestKey\":\"wue1:7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C\",\"expectedRevision\":\(expected),\"resultRevision\":\(result)}"
    }
}
