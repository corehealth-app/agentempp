import Foundation
import Testing

@testable import BodyFlow

@Suite("Read-only media intake children in canonical history")
struct ConversationJournalMediaOriginTests {
  @Test func internalMediaChildDoesNotInvalidateItsCanonicalPage() throws {
    let page = try journalMediaChildPage()
    let data = try JSONSerialization.data(withJSONObject: page)
    let decoded = try ConversationJournalPageSnapshot(data: data)
    #expect(decoded.items.count == 1)
    let row = (page["items"] as! [[String: Any]])[0]
    let command = row["original_command"] as! [String: Any]
    // Reading an internal child must never admit it as an outbound v1 command.
    #expect(throws: (any Error).self) {
      try ConversationMealCommand(wireBody: JSONSerialization.data(withJSONObject: command))
    }
  }

  @Test(arguments: [
    "extra", "origin-extra", "schema", "action", "epoch", "hash", "asset", "caption", "meal",
  ])
  func malformedInternalSourceStillFailsClosed(_ attack: String) throws {
    var page = try journalMediaChildPage()
    var row = (page["items"] as! [[String: Any]])[0]
    var command = row["original_command"] as! [String: Any]
    var source = command["source"] as! [String: Any]
    var origin = command["intake_origin"] as! [String: Any]
    switch attack {
    case "extra": command["execute"] = true
    case "origin-extra": origin["url"] = "https://private.invalid"
    case "schema": origin["schema"] = "conversation.intake-media-origin.v2"
    case "action": source["user_action"] = "register_consumed_meal"
    case "epoch": origin["epoch"] = UUID().uuidString.lowercased()
    case "hash": origin["input_hash"] = "wrong"
    case "asset": source["media_asset_id"] = "invalid"
    case "caption": source["caption"] = " "
    default: command["meal_type"] = "jantar"
    }
    command["source"] = source
    command["intake_origin"] = origin
    row["original_command"] = command
    page["items"] = [row]
    #expect(throws: (any Error).self) {
      try ConversationJournalPageSnapshot(data: JSONSerialization.data(withJSONObject: page))
    }
  }
}

func journalMediaChildPage() throws -> [String: Any] {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/ConversationJournalPublicFixtures.json")
  let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  var page = root["data"] as! [String: Any]
  var row = (page["items"] as! [[String: Any]]).first {
    $0["event_id"] as? String == "command/10000000-0000-4000-8000-000000000002"
  }!
  var command = row["original_command"] as! [String: Any]
  command["source"] = [
    "channel": "media", "media_asset_id": "30000000-0000-4000-8000-000000000001",
    "user_action": "report_actual_record",
  ]
  command["intake_origin"] = [
    "schema": "conversation.intake-media-origin.v1",
    "intake_id": "40000000-0000-4000-8000-000000000001",
    "input_hash": String(repeating: "a", count: 64),
    "source_hash": String(repeating: "b", count: 64),
    "epoch": page["epoch"]!,
    "claim_id": "50000000-0000-4000-8000-000000000001",
    "decision_hash": String(repeating: "c", count: 64),
  ]
  let hash = ConversationMealCommand.digest(
    try JSONSerialization.data(
      withJSONObject: command, options: [.sortedKeys, .withoutEscapingSlashes]))
  var result = row["result"] as! [String: Any]
  var receipt = result["receipt"] as! [String: Any]
  result["input_hash"] = hash
  receipt["input_hash"] = hash
  result["receipt"] = receipt
  row["original_command"] = command
  row["result"] = result
  page["items"] = [row]
  page["has_more"] = false
  page["next_cursor"] = NSNull()
  return page
}
