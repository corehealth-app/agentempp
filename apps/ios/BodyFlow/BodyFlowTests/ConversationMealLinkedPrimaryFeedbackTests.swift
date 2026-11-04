import Foundation
import Testing

@testable import BodyFlow

@Suite("Linked primary six sections require every unchanged original fact")
struct ConversationMealLinkedPrimaryFeedbackTests {
  @Test func actualLinkedPiecesShowTheOriginalSixLiteralSectionsWhenCurrentFactsMatch() throws {
    let f = try Fixture()
    #expect(
      ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.receipt, feedback: f.feedback, group: try f.group(), scope: f.scope))
    #expect(f.receipt.registrationID != f.receipt.commandID)
    guard case .sections(let recorded, let sections) = f.feedback.presentation.content else {
      Issue.record("Actual six literal sections required")
      return
    }
    #expect(sections.map(\.key) == [.saved, .items, .summary, .day, .block, .education])
    #expect(recorded.items.first?.quantityG == 100 && recorded.items.first?.nutrients.kcal == 128.3)
    var equivalent = f.unchanged
    var current = equivalent["current"] as! [String: Any]
    var rows = current["items"] as! [[String: Any]]
    rows.reverse()
    for i in rows.indices {
      rows[i]["consumed_at"] = f.receipt.consumedAt.replacingOccurrences(of: "Z", with: "+00:00")
    }
    current["items"] = rows
    equivalent["current"] = current
    #expect(
      ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.receipt, feedback: f.feedback, group: try f.group(equivalent), scope: f.scope))
    #expect(sections.map(\.text) == f.sections)
  }

  @Test(arguments: [
    "owner_id", "command_id", "input_hash", "registration_id", "provider_key",
    "meal_type", "local_date", "timezone", "consumed_at", "log_ids", "effect_version",
    "parent_command_id", "parent_input_hash", "parent_decision_hash", "epoch",
  ])
  func everyGenuineLinkedReceiptFieldMustRemainIdentical(_ field: String) throws {
    let f = try Fixture()
    var receipt = f.receiptRaw
    switch field {
    case "owner_id", "command_id", "registration_id", "parent_command_id", "epoch":
      receipt[field] = UUID().uuidString.lowercased()
    case "input_hash", "parent_input_hash", "parent_decision_hash":
      receipt[field] = String(repeating: "a", count: 64)
    case "provider_key": receipt[field] = "conversation.clarification/other/parent"
    case "meal_type": receipt[field] = "jantar"
    case "local_date":
      // Keep the strict receipt civil date valid.
      receipt[field] = "2026-11-05"
      receipt["consumed_at"] = "2026-11-05T18:15:29.256011Z"
    case "timezone": receipt[field] = "Etc/UTC"
    case "consumed_at": receipt[field] = "2026-11-04T18:15:29.256012Z"
    case "log_ids": receipt[field] = [UUID().uuidString.lowercased()]
    default: receipt[field] = "cmeal1:" + String(repeating: "a", count: 64)
    }
    let changed = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.LinkedReceipt.self, from: bytes(receipt))
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: changed, feedback: f.feedback, group: try f.group(), scope: f.scope))
  }

  @Test(arguments: [
    "lineage", "current-null", "name", "quantity", "kcal", "protein", "carbs", "fat",
    "quantity-null", "kcal-null", "protein-null", "source", "source-null", "item-id",
    "missing-item",
    "meal", "clock", "zone", "clock-before-policy", "group-hash", "group-epoch", "group-owner",
    "scope-owner", "scope-epoch", "scope-generation", "edited",
  ])
  func changedUnknownOrUnownedCurrentFactsStayHistorical(_ attack: String) throws {
    let f = try Fixture()
    var raw = f.unchanged
    var scope = f.scope
    var current = raw["current"] as! [String: Any]
    var rows = current["items"] as! [[String: Any]]
    switch attack {
    case "lineage": raw["lineage_compatible"] = false
    case "current-null": raw["current"] = NSNull()
    case "name": rows[0]["food_name"] = "arroz com outra receita"
    case "quantity": rows[0]["quantity_g"] = 101
    case "kcal": rows[0]["kcal"] = 130
    case "protein": rows[0]["protein_g"] = 3
    case "carbs": rows[0]["carbs_g"] = 29
    case "fat": rows[0]["fat_g"] = 1
    case "quantity-null": rows[0]["quantity_g"] = NSNull()
    case "kcal-null": rows[0]["kcal"] = NSNull()
    case "protein-null": rows[0]["protein_g"] = NSNull()
    case "source": rows[0]["source"] = "history"
    case "source-null": rows[0]["source"] = NSNull()
    case "item-id": rows[0]["id"] = UUID().uuidString.lowercased()
    case "missing-item": rows.removeLast()
    case "meal": rows[0]["meal_type"] = "jantar"
    case "clock": rows[0]["consumed_at"] = "2026-11-04T18:15:29.256011001Z"
    case "zone": current["timezone"] = "America/Sao_Paulo"
    case "clock-before-policy": raw["observed_at"] = "2026-11-04T18:15:30.000000Z"
    case "group-hash", "group-epoch", "group-owner":
      var receipt = raw["original_receipt"] as! [String: Any]
      let key =
        attack == "group-hash" ? "input_hash" : attack == "group-epoch" ? "epoch" : "owner_id"
      let value =
        key == "input_hash" ? String(repeating: "a", count: 64) : UUID().uuidString.lowercased()
      raw[key] = value
      receipt[key] = value
      if key == "owner_id" {
        receipt["provider_key"] =
          "conversation.clarification/\(value)/\(f.receipt.parentCommandID.uuidString.lowercased())"
      }
      raw["original_receipt"] = receipt
    case "scope-owner":
      scope = .init(
        ownerID: UUID().uuidString.lowercased(), sessionGeneration: 7, epoch: scope.epoch)
    case "scope-epoch":
      scope = .init(
        ownerID: scope.ownerID, sessionGeneration: 7, epoch: UUID().uuidString.lowercased())
    case "scope-generation":
      scope = .init(ownerID: scope.ownerID, sessionGeneration: 8, epoch: scope.epoch)
    default:
      raw["revision"] = 1
      raw["last_operation"] = [
        "schema": "conversation.meal-edit-effect-public.v1",
        "owner_id": f.receipt.ownerID.uuidString.lowercased(),
        "command_id": f.receipt.commandID.uuidString.lowercased(),
        "operation_id": "c3c70000-0000-4000-8000-000000000099",
        "input_hash": String(repeating: "b", count: 64),
        "kind": "saved", "revision": 1, "applied_at": "2026-11-04T18:15:31.000000Z",
        "undo_expires_at": "2026-11-04T18:20:31.000000Z", "target_operation_id": NSNull(),
        "removed_item_ids": [f.receipt.logIDs[0].uuidString.lowercased()],
        "new_item_ids": ["c3c70000-0000-4000-8000-000000000098"],
        "next_record_id": "c3c70000-0000-4000-8000-000000000098",
      ]
    }
    if attack != "current-null" {
      current["items"] = rows
      raw["current"] = current
    }
    let group: ConversationMealGroupSnapshot?
    if attack == "missing-item" {
      // An empty group is unavailable rather than a reason to invent missing facts.
      #expect(throws: (any Error).self) { try f.group(raw) }
      group = nil
    } else {
      // These are valid observations with different facts, not parser failures.
      group = try f.group(raw)
    }
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.receipt, feedback: f.feedback, group: group, scope: scope))
  }

  @Test func missingFeedbackOrGroupNeverPromotesTheOriginal() throws {
    let f = try Fixture()
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.receipt, feedback: nil, group: try f.group(), scope: f.scope))
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.receipt, feedback: f.feedback, group: nil, scope: f.scope))
  }

  @Test func feedbackObservedBeforeTheActualSavedFoodCannotBecomePrimary() throws {
    let f = try Fixture()
    let sdk = try object(load("ConversationLinkedFeedbackSDKFixtures"))
    let child = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self, from: bytes(sdk["childBinding"]!))
    var raw = sdk["presentation"] as! [String: Any]
    var policy = raw["current_policy"] as! [String: Any]
    var provenance = raw["provenance"] as! [String: Any]
    // A syntactically valid presentation after admission, but before the food
    // actually existed, is not a current presentation of that saved original.
    policy["observed_at"] = "2026-11-04T18:15:28.000000Z"
    provenance["observed_at"] = policy["observed_at"]
    raw["current_policy"] = policy
    raw["provenance"] = provenance
    let presentation = try JSONDecoder().decode(
      ConversationFeedbackPresentationSnapshot.self, from: bytes(raw))
    let bound = try #require(f.receipt.boundFeedback(presentation, binding: child, scope: f.scope))
    #expect(
      !ConversationMealPrimaryFeedbackPolicy.showsPrimary(
        receipt: f.receipt, feedback: bound, group: try f.group(), scope: f.scope))
  }

  private struct Fixture {
    let receipt: ConversationThreadPageSnapshot.LinkedReceipt
    let receiptRaw: [String: Any]
    let feedback: ConversationFeedbackPresentationSnapshot.Bound
    let scope: ConversationFeedbackPresentationSnapshot.Scope
    let unchanged: [String: Any]
    let sections: [String]
    init() throws {
      let sdk = try object(load("ConversationLinkedFeedbackSDKFixtures"))
      receiptRaw = sdk["receipt"] as! [String: Any]
      receipt = try JSONDecoder().decode(
        ConversationThreadPageSnapshot.LinkedReceipt.self, from: bytes(receiptRaw))
      let originalReceipt = receipt
      let child = try JSONDecoder().decode(
        ConversationThreadPageSnapshot.Binding.self, from: bytes(sdk["childBinding"]!))
      let presentation = try JSONDecoder().decode(
        ConversationFeedbackPresentationSnapshot.self, from: bytes(sdk["presentation"]!))
      scope = .init(
        ownerID: receipt.ownerID.uuidString.lowercased(), sessionGeneration: 7,
        epoch: receipt.epoch.uuidString.lowercased())
      feedback = try #require(receipt.boundFeedback(presentation, binding: child, scope: scope))
      guard case .sections(_, let original) = presentation.content else {
        throw FixtureError.invalid
      }
      sections = original.map(\.text)
      var raw =
        try object(load("ConversationMealLinkedGroupPublicFixture"))["group"] as! [String: Any]
      #expect(raw["original_receipt"] as! NSDictionary == receiptRaw as NSDictionary)
      let facts = (sdk["presentation"] as! [String: Any])["recorded"] as! [String: Any]
      let foods = facts["items"] as! [[String: Any]]
      var current = raw["current"] as! [String: Any]
      current["items"] = foods.map { food in
        [
          "id": food["log_id"]!, "food_name": food["food_name"]!, "quantity_g": food["quantity_g"]!,
          "quantity_display": NSNull(), "kcal": food["kcal"]!, "protein_g": food["protein_g"]!,
          "carbs_g": food["carbs_g"]!, "fat_g": food["fat_g"]!, "source": food["nutrition_source"]!,
          "consumed_at": originalReceipt.consumedAt, "meal_type": originalReceipt.mealType.rawValue,
        ] as [String: Any]
      }
      current["local_date"] = receipt.localDate
      current["timezone"] = receipt.timezone
      raw["current"] = current
      // Synthetic unchanged current read derived ONLY from genuine SDK facts/IDs.
      // No actual C11 version/group/SQL/HTTP or clinical authority is fabricated.
      unchanged = raw
    }
    func group(_ raw: [String: Any]? = nil) throws -> ConversationMealGroupSnapshot {
      try .init(data: bytes(raw ?? unchanged))
    }
    enum FixtureError: Error { case invalid }
  }
}

private func load(_ name: String) throws -> Data {
  #if SWIFT_PACKAGE
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
  #else
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
      "Fixtures/\(name).json")
  #endif
  return try Data(contentsOf: url)
}
private func object(_ data: Data) throws -> [String: Any] {
  try JSONSerialization.jsonObject(with: data) as! [String: Any]
}
private func bytes(_ value: Any) throws -> Data {
  try JSONSerialization.data(
    withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
}
