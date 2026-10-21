import Foundation
import Testing

@testable import BodyFlow

@Suite("Confirmed workout optional identity")
struct WorkoutConfirmedIdentityTests {
    private let pendingID = "a1700000-0000-4000-8000-000000000001"
    private let workoutID = "b2800000-0000-4000-8000-000000000001"

    @Test("a confirmed real workout UUID survives flattened response round trip", arguments: [false, true])
    func confirmedIDSurvivesRoundTrip(uppercase: Bool) throws {
        let identity = uppercase ? workoutID.uppercased() : workoutID
        let response = try decode(extra: ",\"confirmed_workout_id\":\"\(identity)\"")
        #expect(response.registration.status == "confirmed")
        #expect(response.registration.id == pendingID)
        let encoded = try object(JSONEncoder().encode(response))
        #expect(encoded["confirmed_workout_id"] as? String == workoutID)
        #expect(encoded["id"] as? String != workoutID)
    }

    @Test("missing or invalid optional identity does not invalidate the confirmed snapshot", arguments: [
        "", ",\"confirmed_workout_id\":null", ",\"confirmed_workout_id\":1",
        ",\"confirmed_workout_id\":true", ",\"confirmed_workout_id\":{}",
        ",\"confirmed_workout_id\":[]", ",\"confirmed_workout_id\":\"../pending\"",
        ",\"confirmed_workout_id\":\"b2800000000040008000000000000001\"",
    ])
    func optionalIdentityCannotTurnConfirmationIntoFailure(_ extra: String) throws {
        let response = try decode(extra: extra)
        #expect(response.registration.status == "confirmed")
        #expect(!response.alreadyConfirmed)
        #expect(response.registration.workoutVersion?.contentRevision == 0)
        #expect(try object(JSONEncoder().encode(response))["confirmed_workout_id"] == nil)
    }

    @Test("valid optional UUID cannot authorize a different kind or unconfirmed status", arguments: [
        "meal", "unknown", "pending", "cancelled", "expired",
    ])
    func optionalIdentityRequiresConfirmedWorkout(_ variant: String) throws {
        let kind = variant == "meal" || variant == "unknown" ? variant : "workout"
        let status = kind == "workout" ? variant : "confirmed"
        let response = try decode(extra: ",\"confirmed_workout_id\":\"\(workoutID)\"", kind: kind, status: status)
        #expect(try object(JSONEncoder().encode(response))["confirmed_workout_id"] == nil)
    }

    @Test("new optional identity cannot weaken principal version or receipt validation", arguments: [
        "\"workout_protocol\":\"ui-v1\"",
        "\"workout_protocol\":\"ui-v2\",\"content_revision\":0",
        "\"workout_protocol\":\"ui-v1\",\"content_revision\":-1",
        "\"workout_protocol\":\"ui-v1\",\"content_revision\":0,\"receipt\":null",
        "\"workout_protocol\":\"ui-v1\",\"content_revision\":0,\"receipt\":{\"requestKey\":\"wue1:a1700000-0000-4000-8000-000000000001\",\"expectedRevision\":0,\"resultRevision\":1}",
    ])
    func principalValidationRemainsStrict(_ metadata: String) {
        #expect(throws: DecodingError.self) {
            try decode(extra: ",\"confirmed_workout_id\":\"\(workoutID)\"", metadata: metadata)
        }
    }

    @Test("programmatic snapshots apply the same optional identity normalization")
    func initializerCannotBypassIdentityScope() throws {
        let base = try decode(extra: "").registration
        for identity in [workoutID.uppercased(), "not-a-uuid"] {
            let value = RegistrationSnapshot(id: base.id, status: base.status, createdAt: base.createdAt,
                expiresAt: base.expiresAt, resolvedAt: base.resolvedAt, proposal: base.proposal,
                workoutVersion: base.workoutVersion, confirmedWorkoutID: identity)
            #expect(value.confirmedWorkoutID == (identity == "not-a-uuid" ? nil : workoutID))
        }
        let pending = RegistrationSnapshot(id: base.id, status: "pending", createdAt: base.createdAt,
            expiresAt: base.expiresAt, resolvedAt: nil, proposal: base.proposal,
            workoutVersion: base.workoutVersion, confirmedWorkoutID: workoutID)
        #expect(pending.confirmedWorkoutID == nil)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(extra: String, kind: String = "workout", status: String = "confirmed",
                        metadata: String? = nil) throws -> RegistrationConfirmationSnapshot {
        let proposal: String
        switch kind {
        case "workout": proposal = "{\"kind\":\"workout\",\"workout_type\":\"Natação\",\"duration_min\":40,\"estimated_kcal\":400,\"intensity\":\"moderada\"}"
        case "meal": proposal = "{\"kind\":\"meal\",\"meal_type\":\"almoco\",\"items\":[],\"warnings\":[]}"
        default: proposal = "{\"kind\":\"unknown\"}"
        }
        let version = metadata.map { ",\($0)" } ?? (kind == "workout" ? ",\"workout_protocol\":\"ui-v1\",\"content_revision\":0" : "")
        let json = """
        {"id":"\(pendingID)","status":"\(status)","created_at":"2026-10-21T12:00:00Z",
         "expires_at":"2026-10-22T12:00:00Z","resolved_at":"2026-10-21T12:30:00Z",
         "proposal":\(proposal),"already_confirmed":false,"deduped":false\(version)\(extra)}
        """
        return try JSONDecoder().decode(RegistrationConfirmationSnapshot.self, from: Data(json.utf8))
    }
}
