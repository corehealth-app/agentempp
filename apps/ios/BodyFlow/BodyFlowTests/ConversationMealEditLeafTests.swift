import Foundation
import Testing

@testable import BodyFlow

@Suite("Closed public conversation meal edits")
struct ConversationMealEditLeafTests {
  @Test func exactPublicGroupsPreserveOriginalBindingAndReferences() throws {
    for key in ["group", "milk", "whey", "unavailable_group"] {
      let group = try decode(ConversationMealGroupSnapshot.self, payload(key))
      #expect(
        group.originalInputHash
          == (try root()["headers"] as? [String: String])?["X-Conversation-Input-Hash"])
      #expect(group.ownerID.uuidString.lowercased() == group.originalReceipt.ownerID)
      #expect(group.commandID.uuidString.lowercased() == group.originalReceipt.commandID)
      #expect(group.observedAt == (try payload(key)["observed_at"] as? String))
      if key == "milk" {
        #expect(group.current?.items.first?.quantityG == 206)
        #expect(group.current?.items.first?.quantityDisplay?.unit == "mL")
        #expect(group.current?.items.first?.quantityDisplay?.gramsPerUnit == Decimal(103) / 100)
      }
      if key == "whey" {
        #expect(group.current?.items.first?.quantityDisplay?.unit == "scoop")
        #expect(group.current?.items.first?.quantityDisplay?.gramsPerUnit == 30)
      }
      if key == "unavailable_group" {
        #expect(group.current == nil)
        #expect(!group.actions.save.allowed)
      }
    }
  }
  @Test func unknownNutritionAndTimezoneRemainNull() throws {
    var p = try payload("group")
    try put(&p, ["current", "timezone"], NSNull())
    for key in ["quantity_g", "kcal", "protein_g", "carbs_g", "fat_g", "source", "meal_type"] {
      try put(&p, ["current", "items", "0", key], NSNull())
    }
    let item = try #require(decode(ConversationMealGroupSnapshot.self, p).current?.items.first)
    #expect(
      item.quantityG == nil && item.kcal == nil && item.proteinG == nil && item.carbsG == nil
        && item.fatG == nil)
    #expect(item.source == nil && item.mealType == nil)
    #expect(try decode(ConversationMealGroupSnapshot.self, p).current?.timezone == nil)
  }
  @Test(
    "group rejects private, malformed and mixed identity fields",
    arguments: [
      "extra", "policy", "snapshot", "missing", "owner", "upper", "hash", "epoch", "revision",
      "revision-bool", "lineage-bool", "clock", "clock-back", "original-owner", "original-hash",
      "original-future", "last-revision", "date", "version", "item-extra", "item-duplicate",
      "items-empty", "items-many", "quantity-zero", "quantity-high", "kcal-negative", "kcal-string",
      "kcal-bool", "meal", "metadata-extra", "metadata-ref", "metadata-factor", "metadata-name",
      "action-extra", "action-reason", "action-allowed-reason", "actions-missing",
    ]) func rejectsGroup(_ attack: String) throws
  {
    var p = try payload(attack.hasPrefix("metadata") ? "milk" : "group")
    switch attack {
    case "extra": p["private_context"] = "private"
    case "policy": p["current_policy"] = [:] as [String: String]
    case "snapshot": p["snapshot"] = [:] as [String: String]
    case "missing": p.removeValue(forKey: "last_operation")
    case "owner": p["owner_id"] = UUID().uuidString.lowercased()
    case "upper": p["owner_id"] = "A0000000-0000-4000-8000-000000000001"
    case "hash": p["input_hash"] = "bad"
    case "epoch": p["epoch"] = NSNull()
    case "revision": p["revision"] = 2_147_483_648
    case "revision-bool": p["revision"] = true
    case "lineage-bool": p["lineage_compatible"] = 0
    case "clock": p["observed_at"] = "1900-02-29T12:00:00Z"
    case "clock-back": p["observed_at"] = "2026-11-04T11:00:00Z"
    case "original-owner":
      try put(&p, ["original_receipt", "owner_id"], UUID().uuidString.lowercased())
    case "original-hash":
      try put(&p, ["original_receipt", "input_hash"], String(repeating: "f", count: 64))
    case "original-future":
      try put(&p, ["original_receipt", "consumed_at"], "2026-11-04T12:10:00Z")
    case "last-revision": p["revision"] = 1
    case "date": try put(&p, ["current", "local_date"], "2026-02-30")
    case "version":
      try put(&p, ["current", "expected_version"], "cmeal1:" + String(repeating: "a", count: 64))
    case "item-extra": try put(&p, ["current", "items", "0", "nutrition_authority"], "forged")
    case "item-duplicate":
      let item = try item(p)
      try put(&p, ["current", "items"], [item, item])
    case "items-empty": try put(&p, ["current", "items"], [] as [String])
    case "items-many": try put(&p, ["current", "items"], Array(repeating: try item(p), count: 31))
    case "quantity-zero": try put(&p, ["current", "items", "0", "quantity_g"], 0)
    case "quantity-high": try put(&p, ["current", "items", "0", "quantity_g"], 10000)
    case "kcal-negative": try put(&p, ["current", "items", "0", "kcal"], -1)
    case "kcal-string": try put(&p, ["current", "items", "0", "kcal"], "55")
    case "kcal-bool": try put(&p, ["current", "items", "0", "kcal"], true)
    case "meal": try put(&p, ["current", "items", "0", "meal_type"], "breakfast")
    case "metadata-extra":
      try put(&p, ["current", "items", "0", "quantity_display", "private"], true)
    case "metadata-ref":
      try put(&p, ["current", "items", "0", "quantity_display", "reference_id"], "unknown")
    case "metadata-factor":
      try put(&p, ["current", "items", "0", "quantity_display", "grams_per_unit"], 1)
    case "metadata-name": try put(&p, ["current", "items", "0", "food_name"], "leite em po")
    case "action-extra": try put(&p, ["actions", "save", "reason"], "day_closed")
    case "action-reason": try put(&p, ["actions", "undo_save", "reason"], "private condition")
    case "action-allowed-reason": try put(&p, ["actions", "undo_save", "allowed"], true)
    case "actions-missing": p.removeValue(forKey: "actions")
    default: Issue.record("Unknown attack")
    }
    #expect(throws: (any Error).self) { try decode(ConversationMealGroupSnapshot.self, p) }
  }
  @Test func savedAndAbsentRepliesKeepTwoHashesSeparate() throws {
    let op = try operation(inputKey: "input")
    #expect(op.operationInputHash == (try root()["operation_input_hash"] as? String))
    let reply = try decode(ConversationMealEditReply.self, payload("saved"))
    #expect(reply.matches(operation: op))
    #expect(reply.acceptsHTTPStatus(200))
    #expect(!reply.acceptsHTTPStatus(202))
    #expect(!reply.acceptsHTTPStatus(401))
    let absent = try decode(ConversationMealEditReply.self, payload("absent"))
    #expect(absent.matches(operation: op))
    #expect(absent.acceptsHTTPStatus(200))
    #expect(!absent.acceptsHTTPStatus(202))
    #expect(op.originalInputHash != op.operationInputHash)
    #expect(!String(describing: op).contains("Arroz"))
    #expect(Mirror(reflecting: op).children.isEmpty)
    let restored = try ConversationMealEditOperation(
      ownerID: op.ownerID, commandID: op.commandID, originalInputHash: op.originalInputHash,
      epoch: op.epoch, operationID: op.operationID, wireBody: op.wireBody)
    #expect(
      restored.wireBody == op.wireBody && restored.operationInputHash == op.operationInputHash)
  }
  @Test func allThreeOperationKindsMatchActualFrozenACKs() throws {
    for (inputKey, replyKey) in [
      ("input", "saved"), ("undo_save_input", "undo_save"),
      ("undo_registration_input", "undo_registration"),
    ] {
      let op = try operation(inputKey: inputKey)
      #expect(try decode(ConversationMealEditReply.self, payload(replyKey)).matches(operation: op))
    }
  }
  @Test(
    "effect rejects snapshot and receipt invariant violations",
    arguments: [
      "schema", "extra", "owner", "op", "hash", "revision", "revision-bool", "kind", "expired-nano",
      "overlap", "duplicate", "removed-empty", "next", "target", "future-deadline", "undo-target",
      "undo-next", "registration-new", "registration-revision",
    ])
  func rejectsEffect(_ attack: String) throws {
    var p = try payload(
      attack.hasPrefix("undo-")
        ? "undo_save" : attack.hasPrefix("registration-") ? "undo_registration" : "saved")
    switch attack {
    case "schema": try put(&p, ["receipt", "schema"], "conversation.meal-edit-effect.v1")
    case "extra": try put(&p, ["receipt", "snapshot"], ["daily_balance": 0])
    case "owner": try put(&p, ["receipt", "owner_id"], UUID().uuidString.lowercased())
    case "op": try put(&p, ["receipt", "operation_id"], "bad")
    case "hash": try put(&p, ["receipt", "input_hash"], "bad")
    case "revision": try put(&p, ["receipt", "revision"], 0)
    case "revision-bool": try put(&p, ["receipt", "revision"], true)
    case "kind": try put(&p, ["receipt", "kind"], "pending")
    case "expired-nano":
      try put(&p, ["receipt", "undo_expires_at"], "2026-11-04T12:06:00.123456001+00:00")
    case "overlap":
      try put(&p, ["receipt", "new_item_ids"], ["10000000-0000-4000-8000-000000000005"])
    case "duplicate":
      try put(
        &p, ["receipt", "new_item_ids"],
        Array(repeating: "10000000-0000-4000-8000-000000000081", count: 2))
    case "removed-empty": try put(&p, ["receipt", "removed_item_ids"], [] as [String])
    case "next": try put(&p, ["receipt", "next_record_id"], UUID().uuidString.lowercased())
    case "target": try put(&p, ["receipt", "target_operation_id"], UUID().uuidString.lowercased())
    case "future-deadline":
      try put(&p, ["receipt", "undo_expires_at"], "2026-11-04T12:07:00.123456+00:00")
    case "undo-target": try put(&p, ["receipt", "target_operation_id"], NSNull())
    case "undo-next": try put(&p, ["receipt", "new_item_ids"], [] as [String])
    case "registration-new":
      try put(&p, ["receipt", "new_item_ids"], [UUID().uuidString.lowercased()])
    case "registration-revision": try put(&p, ["receipt", "revision"], 2)
    default: Issue.record("Unknown attack")
    }
    #expect(throws: (any Error).self) { try decode(ConversationMealEditReply.self, p) }
  }
  @Test func validButDifferentOperationIsNotAnACK() throws {
    let op = try operation(inputKey: "input")
    var p = try payload("saved")
    try put(&p, ["receipt", "input_hash"], op.originalInputHash)
    #expect(!(try decode(ConversationMealEditReply.self, p)).matches(operation: op))
    p = try payload("absent")
    p["operation_id"] = UUID().uuidString.lowercased()
    #expect(!(try decode(ConversationMealEditReply.self, p)).matches(operation: op))
  }
  @Test func canonicalExponentAndNegativeZeroMatchPostgresNotOldCommandHashing() throws {
    let exponent = try #require(root()["exponent_hash_case"] as? [String: Any])
    let op = try operation(input: try #require(exponent["input"] as? [String: Any]))
    #expect(op.operationInputHash == exponent["operation_input_hash"] as? String)
    var input = try #require(root()["input"] as? [String: Any])
    var items = try #require(input["items"] as? [[String: Any]])
    items[0]["user_kcal"] = -0.0
    input["items"] = items
    let minus = try operation(input: input)
    items[0]["user_kcal"] = 0
    input["items"] = items
    #expect(minus.operationInputHash == (try operation(input: input)).operationInputHash)
    // Restoration preserves exact bytes; only the OP hash normalizes zero.
    #expect(String(data: minus.wireBody, encoding: .utf8)?.contains("\"user_kcal\":-0") == true)
  }
  @Test func typedIntentRejectsUnrepresentableDecimalInsteadOfRounding() throws {
    let item = try ConversationMealEditOperation.Item(
      foodName: "Whey", quantityG: 35, userKcal: nil, quantityBasis: .stated)
    let op = try ConversationMealEditOperation(
      ownerID: UUID(), commandID: UUID(), originalInputHash: String(repeating: "a", count: 64),
      epoch: UUID(), expectedRevision: 0,
      expectedVersion: "v1:" + String(repeating: "b", count: 64),
      action: .save(recordID: UUID(), items: [item]))
    #expect(op.wireBody.count <= 16384)
    #expect(op.idempotencyKey == "cmedit1:" + op.operationID.uuidString.lowercased())
    #expect(throws: (any Error).self) {
      try ConversationMealEditOperation.Item(
        foodName: "Whey", quantityG: Decimal(string: "1.00000000000000000001")!)
    }
    for amount in [Decimal.zero, Decimal(-1), Decimal(10000)] {
      #expect(throws: (any Error).self) {
        try ConversationMealEditOperation.Item(foodName: "Whey", quantityG: amount)
      }
    }
  }
  @Test(
    "closed input refuses authority and malformed intent",
    arguments: [
      "extra", "schema", "revision", "version", "empty", "name", "quantity", "kcal", "candidate",
      "basis", "null-optional", "body-limit",
    ])
  func invalidInput(_ attack: String) throws {
    var input = try #require(root()["input"] as? [String: Any])
    switch attack {
    case "extra": input["owner_id"] = UUID().uuidString.lowercased()
    case "schema": input["schema"] = "conversation.meal-edit.v2"
    case "revision": input["expected_revision"] = true
    case "version": input["expected_version"] = "bad"
    case "empty": input["items"] = [] as [String]
    case "name": try put(&input, ["items", "0", "food_name"], " rice ")
    case "quantity": try put(&input, ["items", "0", "quantity_g"], 0)
    case "kcal": try put(&input, ["items", "0", "user_kcal"], 20001)
    case "candidate": try put(&input, ["items", "0", "candidate_id"], "c100-aaaaaaaa")
    case "basis": try put(&input, ["items", "0", "quantity_basis"], "unknown")
    case "null-optional": try put(&input, ["items", "0", "user_kcal"], NSNull())
    case "body-limit":
      input["items"] = Array(
        repeating: [
          "food_name": String(repeating: "食", count: 160), "quantity_g": 9999, "user_kcal": 20000,
          "quantity_basis": "portion_reference", "candidate_id": "c29-aaaaaaaa",
        ], count: 30)
      #expect(try JSONSerialization.data(withJSONObject: input).count > 16384)
    default: Issue.record("Unknown attack")
    }
    #expect(throws: (any Error).self) { try operation(input: input) }
  }
  @Test func neighboringNumericAndUnicodeHashesMatchActualTypeScriptCanonicalizer() throws {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealEditNumericFixtures", withExtension: "json")
      )
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealEditNumericFixtures.json")
    #endif
    let fixture = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for row in try #require(fixture["cases"] as? [[String: Any]]) {
      let op = try operation(input: try #require(row["input"] as? [String: Any]))
      #expect(op.operationInputHash == row["operation_input_hash"] as? String)
    }
  }
  @Test(
    "absent is closed read observation and never a saved effect",
    arguments: [
      "extra", "missing", "schema", "status", "owner", "command", "original-hash", "epoch",
      "operation", "op-hash", "numeric-hash",
    ])
  func rejectsAbsent(_ attack: String) throws {
    var p = try payload("absent")
    switch attack {
    case "extra": p["receipt"] = ["snapshot": "private"]
    case "missing": p.removeValue(forKey: "operation_input_hash")
    case "schema": p["schema"] = "conversation.meal-edit-state.v2"
    case "status": p["status"] = "saved"
    case "owner": p["owner_id"] = "bad"
    case "command": p["command_id"] = NSNull()
    case "original-hash": p["input_hash"] = String(repeating: "A", count: 64)
    case "epoch": p["epoch"] = "bad"
    case "operation": p["operation_id"] = "bad"
    case "op-hash": p["operation_input_hash"] = "bad"
    case "numeric-hash": p["operation_input_hash"] = 1
    default: Issue.record("Unknown attack")
    }
    #expect(throws: (any Error).self) { try decode(ConversationMealEditReply.self, p) }
  }
  @Test func matchingNeverConfusesRevisionTargetOrOriginalScope() throws {
    let op = try operation(inputKey: "input")
    for path in [["owner_id"], ["command_id"], ["epoch"]] {
      var p = try payload("absent")
      try put(&p, path, UUID().uuidString.lowercased())
      #expect(!(try decode(ConversationMealEditReply.self, p)).matches(operation: op))
    }
    var p = try payload("saved")
    try put(&p, ["receipt", "revision"], 2)
    #expect(!(try decode(ConversationMealEditReply.self, p)).matches(operation: op))
    p = try payload("saved")
    try put(&p, ["receipt", "removed_item_ids"], [UUID().uuidString.lowercased()])
    #expect(!(try decode(ConversationMealEditReply.self, p)).matches(operation: op))
    p = try payload("undo_save")
    try put(&p, ["receipt", "target_operation_id"], UUID().uuidString.lowercased())
    #expect(
      !(try decode(ConversationMealEditReply.self, p)).matches(
        operation: try operation(inputKey: "undo_save_input")))
  }
  @Test func rawBoundariesAndNonfiniteNumbersRefuseWithoutExposingSource() throws {
    let data = try JSONSerialization.data(withJSONObject: payload("group"))
    #expect(throws: (any Error).self) {
      try ConversationMealGroupSnapshot(data: data + Data(repeating: 32, count: 65536))
    }
    let text = try #require(String(data: data, encoding: .utf8))
    let nonfinite = text.replacingOccurrences(of: "\"kcal\":55", with: "\"kcal\":1e999")
    #expect(nonfinite != text)
    #expect(throws: (any Error).self) {
      try ConversationMealGroupSnapshot(data: Data(nonfinite.utf8))
    }
    let saved = try JSONSerialization.data(withJSONObject: payload("saved"))
    _ = try ConversationMealEditResultSnapshot(data: saved)
    _ = try ConversationMealEditReply(data: saved)
  }
  private func root() throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealEditPublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealEditPublicFixtures.json")
    #endif
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  private func payload(_ key: String) throws -> [String: Any] {
    let envelope = try #require(root()[key] as? [String: Any])
    return try #require(envelope["data"] as? [String: Any])
  }
  private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
  }
  private func operation(inputKey: String) throws -> ConversationMealEditOperation {
    try operation(input: try #require(root()[inputKey] as? [String: Any]))
  }
  private func operation(input: [String: Any]) throws -> ConversationMealEditOperation {
    let headers = try #require(root()["headers"] as? [String: String])
    return try ConversationMealEditOperation(
      ownerID: UUID(uuidString: headers["X-Conversation-Owner"]!)!,
      commandID: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
      originalInputHash: headers["X-Conversation-Input-Hash"]!,
      epoch: UUID(uuidString: headers["X-Conversation-Epoch"]!)!,
      operationID: UUID(uuidString: root()["operation_id"] as! String)!,
      wireBody: JSONSerialization.data(
        withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes]))
  }
  private func item(_ p: [String: Any]) throws -> [String: Any] {
    let current = try #require(p["current"] as? [String: Any])
    return try #require((current["items"] as? [[String: Any]])?.first)
  }
  private func put(_ p: inout [String: Any], _ path: [String], _ value: Any) throws {
    func update(_ original: Any, _ path: ArraySlice<String>) throws -> Any {
      guard let key = path.first else { return value }
      if var array = original as? [Any], let n = Int(key) {
        array[n] = try update(array[n], path.dropFirst())
        return array
      }
      var object = try #require(original as? [String: Any])
      object[key] = try update(object[key] ?? [:], path.dropFirst())
      return object
    }
    p = try #require(update(p, path[...]) as? [String: Any])
  }
}
