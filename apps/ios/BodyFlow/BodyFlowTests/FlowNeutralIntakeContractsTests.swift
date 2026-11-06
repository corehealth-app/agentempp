import Foundation
import Testing

@testable import BodyFlow

@Suite("Literal neutral intake and sealed child factual binding")
struct FlowNeutralIntakeContractsTests {
  @Test func actualSQLInputHashesPreserveWhitespaceMediaAndHintWithoutDomainRetag() throws {
    for f in try neutralFixture()["inputs"] as! [[String: Any]] {
      let input = try FlowNeutralIntakeInput(wireBody: neutralData(f["input"]!))
      let binding = f["binding"] as! [String: Any]
      #expect(input.inputHash == binding["input_hash"] as? String)
      #expect(input.idempotencyKey == "cintake1:" + (binding["intake_id"] as! String))
      #expect(try FlowNeutralIntakeInput(wireBody: input.wireBody).wireBody == input.wireBody)
      #expect(throws: (any Error).self) { try ConversationMealCommand(wireBody: input.wireBody) }
    }
  }
  @Test func sameLiteralTextWithDistinctIntakeIDsIsIndependentAndNeverTrimmed() throws {
    let a = try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("  Caminhei 😀 e\u{301}  "))
    let b = try FlowNeutralIntakeInput(intakeID: UUID(), source: .text("  Caminhei 😀 e\u{301}  "))
    #expect(a.inputHash != b.inputHash && a.wireBody != b.wireBody)
    #expect(String(data: a.wireBody, encoding: .utf8)!.contains("  Caminhei 😀 e\u{301}  "))
    #expect(!String(describing: a).contains("Caminhei"))
  }
  @Test(arguments: [
    "blank", "blankBOM", "tooLong", "control", "private", "mealTag", "badID", "mediaAction",
    "captionNull",
  ])
  func rejectsUnownedOrAmbiguousInput(_ attack: String) throws {
    var input = try neutralMealUnit()["input"] as! [String: Any]
    switch attack {
    case "blank": input["source"] = ["channel": "text", "text": " \t\r\n"]
    case "blankBOM": input["source"] = ["channel": "text", "text": "\u{FEFF}"]
    case "tooLong":
      input["source"] = ["channel": "text", "text": String(repeating: "😀", count: 1001)]
    case "control": input["source"] = ["channel": "text", "text": "a\u{0001}b"]
    case "private": input["owner_id"] = UUID().uuidString.lowercased()
    case "mealTag": input["kind"] = "meal.report"
    case "badID": input["intake_id"] = "BAD"
    case "mediaAction":
      input["source"] = [
        "channel": "media", "media_asset_id": "70000000-0000-4000-8000-000000000001",
        "user_action": "register_consumed_meal",
      ]
    default:
      input["source"] = [
        "channel": "media", "media_asset_id": "70000000-0000-4000-8000-000000000001",
        "user_action": "report_actual_record", "caption": NSNull(),
      ]
    }
    #expect(throws: (any Error).self) { try FlowNeutralIntakeInput(wireBody: neutralData(input)) }
  }
  @Test func sessionIsClosedAndMealProtocolDoesNotGrantNeutralProtocol() throws {
    let p: [String: Any] = [
      "schema": "conversation.intake-session.v1",
      "auth_user_id": "10000000-0000-4000-8000-000000000001",
      "owner_id": "10000000-0000-4000-8000-000000000002",
      "epoch": "50000000-0000-4000-8000-000000000001", "observed_at": "2026-11-03T10:00:00.000001Z",
      "intake_protocol": "conversation.intake.v1",
    ]
    let session = try JSONDecoder().decode(
      FlowNeutralIntakeSessionSnapshot.self, from: neutralData(p))
    #expect(session.authUserID != session.ownerID)
    for key in ["intake_protocol", "schema", "observed_at", "epoch"] {
      var bad = p
      bad[key] = "invalid"
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(FlowNeutralIntakeSessionSnapshot.self, from: neutralData(bad))
      }
    }
    var extra = p
    extra["meal_command_protocol"] = "conversation.command.v1"
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(FlowNeutralIntakeSessionSnapshot.self, from: neutralData(extra))
    }
  }
  @Test func sealedMealOnlyAcknowledgesTheActualIndependentRegistrationReceipt() throws {
    let u = try neutralMealUnit()
    let input = try FlowNeutralIntakeInput(wireBody: neutralData(u["input"]!))
    let reply = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(u["response"]!))
    let b = u["binding"] as! [String: Any]
    let ticket = FlowNeutralIntakeTicket(
      input: input, ownerID: UUID(uuidString: b["owner_id"] as! String)!,
      epoch: UUID(uuidString: b["epoch"] as! String)!, ownerHash: "owner", sessionGeneration: 7)
    guard case .meal(let saved)? = reply.factualAcknowledgement(for: ticket) else {
      Issue.record("Actual typed saved meal required")
      return
    }
    #expect(saved.receipt.registrationID != saved.commandID)
    let foreign = FlowNeutralIntakeTicket(
      input: input, ownerID: UUID(), epoch: ticket.epoch, ownerHash: "other", sessionGeneration: 7)
    #expect(reply.factualAcknowledgement(for: foreign) == nil)
  }
  @Test func mealClockBindingUsesExactInstantRatherThanFormatting() throws {
    let u = try neutralMealUnit()
    var p = u["response"] as! [String: Any]
    var selection = p["selection"] as! [String: Any]
    var child = selection["command"] as! [String: Any]
    child["admitted_at"] = "2026-11-03T07:00:00.000000000-03:00"
    selection["command"] = child
    p["selection"] = selection
    let reply = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(p))
    #expect(reply.status == .selected)
  }
  @Test(arguments: ["2026-11-05T00:35:36.966051999Z", "2026-11-05T00:35:36.966051Z"])
  func workoutPerformedClockMustEqualRealSelectedChildAdmission(_ wrongClock: String) throws {
    let u = try neutralFixture()["workout_known_unit"] as! [String: Any]
    var p = u["response"] as! [String: Any]
    var selection = p["selection"] as! [String: Any]
    var child = selection["command"] as! [String: Any]
    child["admitted_at"] = wrongClock
    selection["command"] = child
    p["selection"] = selection
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(FlowNeutralIntakeResponseSnapshot.self, from: neutralData(p))
    }
  }
  @Test func workoutClockBindingAcceptsEquivalentOffsetAndFractionSpelling() throws {
    let u = try neutralFixture()["workout_known_unit"] as! [String: Any]
    var p = u["response"] as! [String: Any]
    var selection = p["selection"] as! [String: Any]
    var child = selection["command"] as! [String: Any]
    child["admitted_at"] = "2026-11-04T21:35:36.966052000-03:00"
    selection["command"] = child
    p["selection"] = selection
    #expect(
      try JSONDecoder().decode(FlowNeutralIntakeResponseSnapshot.self, from: neutralData(p)).status
        == .selected)
  }
  @Test(arguments: ["known", "unknown"])
  func selectedWorkoutBindsItsGenuineTypedReceiptWithoutInventingMealOrCalories(_ kind: String)
    throws
  {
    let unit = try neutralFixture()["workout_" + kind + "_unit"] as! [String: Any]
    let input = try FlowNeutralIntakeInput(wireBody: neutralData(unit["input"]!))
    let b = unit["binding"] as! [String: Any]
    let ticket = FlowNeutralIntakeTicket(
      input: input, ownerID: UUID(uuidString: b["owner_id"] as! String)!,
      epoch: UUID(uuidString: b["epoch"] as! String)!, ownerHash: "owner", sessionGeneration: 7)
    let reply = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(unit["response"]!))
    guard case .workout(let saved)? = reply.factualAcknowledgement(for: ticket) else {
      Issue.record("Actual typed workout receipt required")
      return
    }
    #expect(saved.registration.registrationID == saved.commandID)
    #expect(saved.registration.workoutID != saved.commandID)
    #expect(saved.activity.estimatedKcal == (kind == "known" ? 154 : nil))
  }
  @Test(arguments: [
    "pending", "held", "absent", "not_recorded", "clarification_required", "selected_pending",
  ])
  func routingStateAndTerminalDecisionNeverBecomeFactualAcknowledgement(_ status: String) throws {
    let unit = try neutralMealUnit()
    let input = try FlowNeutralIntakeInput(wireBody: neutralData(unit["input"]!))
    let binding = unit["binding"] as! [String: Any]
    let ticket = FlowNeutralIntakeTicket(
      input: input, ownerID: UUID(uuidString: binding["owner_id"] as! String)!,
      epoch: UUID(uuidString: binding["epoch"] as! String)!, ownerHash: "owner",
      sessionGeneration: 7)
    let lookup: [String: Any] = [
      "ownerId": binding["owner_id"]!, "intakeId": binding["intake_id"]!,
      "inputHash": binding["input_hash"]!, "epoch": binding["epoch"]!,
    ]
    var p: [String: Any] = ["schema": "conversation.intake-result.v1", "status": status]
    switch status {
    case "pending", "held":
      p["lookup"] = lookup
      p["intake"] = binding
      p["reason"] = "routing_reconciliation_required"
    case "absent": p["lookup"] = lookup
    case "selected_pending":
      p = unit["response"] as! [String: Any]
      let selection = p["selection"] as! [String: Any]
      let child = selection["command"] as! [String: Any]
      var result = child.filter {
        ["owner_id", "command_id", "input_hash", "epoch"].contains($0.key)
      }
      result["schema"] = "conversation.meal-command-state.v1"
      result["status"] = "pending"
      p["result"] = result
    default:
      p["intake"] = binding
      p["source_hash"] = String(repeating: "a", count: 64)
      p["decision_hash"] = String(repeating: "b", count: 64)
      p["reason"] = "record_kind"
      if status == "clarification_required" {
        p["question"] = ["field": "record_kind", "text": "Qual registro?"]
      }
    }
    let reply = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(p))
    #expect(reply.matches(ticket))
    #expect(reply.factualAcknowledgement(for: ticket) == nil)
    p["private_context"] = "private"
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(FlowNeutralIntakeResponseSnapshot.self, from: neutralData(p))
    }
  }
  @Test(arguments: [
    "childKind", "childOwner", "childHash", "childEpoch", "childClock", "selectionClock", "sameID",
    "private", "savedHash", "savedClock", "savedMicroClock",
  ])
  func changedSelectionOrResultCannotDecodeAsFactualDelivery(_ attack: String) throws {
    var response = try neutralMealUnit()["response"] as! [String: Any]
    var selection = response["selection"] as! [String: Any]
    var child = selection["command"] as! [String: Any]
    switch attack {
    case "childKind": child["kind"] = "workout.report"
    case "childOwner": child["owner_id"] = UUID().uuidString.lowercased()
    case "childHash": child["input_hash"] = String(repeating: "f", count: 64)
    case "childEpoch": child["epoch"] = UUID().uuidString.lowercased()
    case "childClock": child["admitted_at"] = "2026-11-03T09:00:00Z"
    case "selectionClock": selection["selected_at"] = "2026-11-03T09:00:00Z"
    case "sameID": child["command_id"] = "60000000-0000-4000-8000-000000000001"
    case "private": child["input"] = ["secret": "private"]
    case "savedHash":
      var result = response["result"] as! [String: Any]
      result["input_hash"] = String(repeating: "f", count: 64)
      response["result"] = result
    case "savedMicroClock": child["admitted_at"] = "2026-11-03T10:00:00.000001Z"
    default: child["admitted_at"] = "2026-11-03T10:00:00.000000001Z"
    }
    selection["command"] = child
    response["selection"] = selection
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(FlowNeutralIntakeResponseSnapshot.self, from: neutralData(response))
    }
  }
}
func neutralFixture() throws -> [String: Any] {
  let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "Fixtures/ConversationNeutralIntakeFixtures.json")
  return try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
}
func neutralMealUnit() throws -> [String: Any] {
  try neutralFixture()["meal_unit"] as! [String: Any]
}
func neutralData(_ raw: Any) throws -> Data {
  try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
}
