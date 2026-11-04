import Foundation
import Testing
@testable import BodyFlow

@Suite("Closed conversation session and read-only command states")
struct ConversationCommandReadSnapshotsTests {
    @Test func sessionKeepsDistinctIdentityAndStateNeverClaimsSaved() throws {
        let s = try decode(ConversationSessionSnapshot.self, session())
        #expect(s.authUserID != s.ownerID)
        #expect(s.observedAt == "2026-11-04T12:00:00.000000001Z")
        for status in ["absent", "pending", "not_recorded"] {
            let result = try decode(ConversationMealCommandStateSnapshot.self, state(status))
            #expect(result.status.rawValue == status)
            #expect(result.reason == (status == "not_recorded" ? "missing_quantity" : nil))
        }
    }
    @Test("session payload is closed and has no mobile-selected owner/authority", arguments: ["schema", "auth", "owner", "upper", "epoch", "protocol", "clock", "zero-year", "leap", "fraction", "extra", "missing-auth"])
    func invalidSession(_ attack: String) throws {
        var p = session()
        switch attack {
        case "schema": p["schema"] = "conversation.session.v2"
        case "auth": p["auth_user_id"] = "unknown"
        case "owner": p["owner_id"] = "unknown"
        case "upper": p["owner_id"] = "A0000000-0000-4000-8000-000000000001"
        case "epoch": p["epoch"] = NSNull()
        case "protocol": p["meal_command_protocol"] = "legacy.agent"
        case "clock": p["observed_at"] = "2026-11-04T25:00:00Z"
        case "zero-year": p["observed_at"] = "0000-11-04T12:00:00Z"
        case "leap": p["observed_at"] = "1900-02-29T12:00:00Z"
        case "fraction": p["observed_at"] = "2026-11-04T12:00:00.0000000001Z"
        case "extra": p["health"] = "private"
        case "missing-auth": p.removeValue(forKey: "auth_user_id")
        default: Issue.record("Unknown attack")
        }
        #expect(throws: (any Error).self) { try decode(ConversationSessionSnapshot.self, p) }
    }
    @Test("nonterminal/negative state is closed and bounded", arguments: ["schema", "status", "owner", "command", "hash", "epoch", "extra", "pending-reason", "absent-indexes", "missing-reason", "missing-indexes", "reason-private", "reason-long", "negative", "too-high", "fractional", "bool", "duplicate", "too-many"])
    func invalidState(_ attack: String) throws {
        var p = state("not_recorded")
        switch attack {
        case "schema": p["schema"] = "conversation.meal-command-state.v2"
        case "status": p["status"] = "saved"
        case "owner": p["owner_id"] = "bad"
        case "command": p["command_id"] = "bad"
        case "hash": p["input_hash"] = String(repeating: "A", count: 64)
        case "epoch": p["epoch"] = "bad"
        case "extra": p["source"] = "private"
        case "pending-reason": p["status"] = "pending"
        case "absent-indexes": p["status"] = "absent"
        case "missing-reason": p.removeValue(forKey: "reason")
        case "missing-indexes": p.removeValue(forKey: "food_indexes")
        case "reason-private": p["reason"] = "private text / secret"
        case "reason-long": p["reason"] = String(repeating: "a", count: 81)
        case "negative": p["food_indexes"] = [-1]
        case "too-high": p["food_indexes"] = [30]
        case "fractional": p["food_indexes"] = [1.5]
        case "bool": p["food_indexes"] = [true]
        case "duplicate": p["food_indexes"] = [0, 0]
        case "too-many": p["food_indexes"] = Array(0...30)
        default: Issue.record("Unknown attack")
        }
        #expect(throws: (any Error).self) { try decode(ConversationMealCommandStateSnapshot.self, p) }
    }
    private func session() -> [String: Any] {
        ["schema": "conversation.session.v1", "auth_user_id": "90000000-0000-4000-8000-000000000001", "owner_id": "10000000-0000-4000-8000-000000000001", "epoch": "50000000-0000-4000-8000-000000000001", "observed_at": "2026-11-04T12:00:00.000000001Z", "meal_command_protocol": "conversation.command.v1"]
    }
    private func state(_ status: String) -> [String: Any] {
        var p: [String: Any] = ["schema": "conversation.meal-command-state.v1", "status": status, "owner_id": "10000000-0000-4000-8000-000000000001", "command_id": "20000000-0000-4000-8000-000000000001", "input_hash": String(repeating: "a", count: 64), "epoch": "50000000-0000-4000-8000-000000000001"]
        if status == "not_recorded" { p["reason"] = "missing_quantity"; p["food_indexes"] = [0, 29] }
        return p
    }
    private func decode<T: Decodable>(_ type: T.Type, _ p: [String: Any]) throws -> T { try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: p)) }
}
