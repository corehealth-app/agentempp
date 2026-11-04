import Foundation
import Testing

@testable import BodyFlow

@Suite("Current linked meals retain their genuine continuation receipt")
struct ConversationMealLinkedGroupTests {
  @Test func linkedGroupDecodesActualChildAndDistinctRegistrationWithoutRelabelling() throws {
    let group = try decode(payload())
    #expect(group.commandID.uuidString.lowercased() == "c3c70000-0000-4000-8000-000000000005")
    #expect(
      group.originalInputHash == "9b8c2629a7d48b8fe8317e9f024aac6ee45b1f64aedcb58fe8fb854a9436902a")
    #expect(group.originalReceipt.registrationID == "11c34c7b-6487-4437-b8dd-3b738445cba5")
    #expect(group.originalReceipt.registrationID != group.originalReceipt.commandID)
    #expect(
      group.originalReceipt.providerKey
        == "conversation.clarification/c3c70000-0000-4000-8000-000000000001/c3c70000-0000-4000-8000-000000000003"
    )
    #expect(group.originalReceipt.ownerID == group.ownerID.uuidString.lowercased())
    #expect(group.originalReceipt.commandID == group.commandID.uuidString.lowercased())
    #expect(
      group.current?.items.first?.id.uuidString.lowercased()
        == "85f03b88-7ece-4006-9c8e-82d0f3726585")
    #expect(group.actions.save.allowed && group.actions.undoRegistration.allowed)
    #expect(!group.actions.undoSave.allowed && group.actions.undoSave.reason == .noSaveToUndo)
  }

  @Test(
    "mixed child groups fail closed",
    arguments: [
      "schema", "report-schema", "owner", "command", "hash", "epoch", "parent-self",
      "parent-provider",
      "provider-child", "provider-report", "parent-hash", "decision-hash", "receipt-extra",
      "receipt-before-admit",
      "receipt-after-observe", "deadline-short", "deadline-nano", "current-date", "private",
    ])
  func rejectsMixedLinkedGroups(_ attack: String) throws {
    var p = try payload()
    var receipt = try #require(p["original_receipt"] as? [String: Any])
    switch attack {
    case "schema": p["schema"] = "conversation.meal-group.v1"
    case "report-schema": receipt["schema"] = "conversation.meal-effect.v1"
    case "owner": receipt["owner_id"] = UUID().uuidString.lowercased()
    case "command": receipt["command_id"] = UUID().uuidString.lowercased()
    case "hash": receipt["input_hash"] = String(repeating: "a", count: 64)
    case "epoch": receipt["epoch"] = UUID().uuidString.lowercased()
    case "parent-self": receipt["parent_command_id"] = receipt["command_id"]
    case "parent-provider": receipt["parent_command_id"] = UUID().uuidString.lowercased()
    case "provider-child":
      receipt["provider_key"] =
        "conversation.clarification/c3c70000-0000-4000-8000-000000000001/c3c70000-0000-4000-8000-000000000005"
    case "provider-report":
      receipt["provider_key"] =
        "conversation.meal/c3c70000-0000-4000-8000-000000000001/c3c70000-0000-4000-8000-000000000005"
    case "parent-hash": receipt["parent_input_hash"] = true
    case "decision-hash": receipt["parent_decision_hash"] = "bad"
    case "receipt-extra": receipt["snapshot"] = ["daily_balance": 0]
    case "receipt-before-admit": receipt["consumed_at"] = "2026-11-04T18:15:27.997472Z"
    case "receipt-after-observe": receipt["consumed_at"] = "2026-11-04T18:16:00.000001Z"
    case "deadline-short": p["registration_undo_expires_at"] = "2026-11-04T18:20:28.256011Z"
    case "deadline-nano": p["registration_undo_expires_at"] = "2026-11-04T18:20:29.256011001Z"
    case "current-date":
      var current = try #require(p["current"] as? [String: Any])
      current["local_date"] = "2026-11-03"
      p["current"] = current
    case "private": p["current_policy"] = ["calories_target": 2000]
    default: Issue.record("Unknown mutation")
    }
    p["original_receipt"] = receipt
    #expect(throws: (any Error).self) { try decode(p) }
  }

  private func decode(_ value: [String: Any]) throws -> ConversationMealGroupSnapshot {
    try .init(data: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
  }
  private func payload() throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationMealLinkedGroupPublicFixture", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealLinkedGroupPublicFixture.json")
    #endif
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return try #require(object["group"] as? [String: Any])
  }
}
