import Foundation
import Testing

@testable import BodyFlow

@Suite("Immutable linked reply intent and closed delivery")
struct ConversationMealReplyLeafTests {
  @Test func actualMealTypeSubmitHasTheQualifiedHashAndSurvivesExactStorage() throws {
    let intent = try mealIntent()
    let source = try root()["submit"] as! [String: Any]
    #expect(try object(intent.wireBody) as NSDictionary == source as NSDictionary)
    #expect(intent.replyInputHash == (try payload("saved")["reply_input_hash"] as? String))
    #expect(intent.idempotencyKey == "cmreply1:c3cc0000-0000-4000-8000-000000000005")
    let restored = try JSONDecoder().decode(
      ConversationMealReplyIntent.self, from: JSONEncoder().encode(intent))
    #expect(restored.wireBody == intent.wireBody && restored.replyID == intent.replyID)
    #expect(restored.replyInputHash == intent.replyInputHash)
    #expect(restored.question.encodedData == intent.question.encodedData)
    let exact = try bytes(source)
    let replay = try ConversationMealReplyIntent(
      parentBinding: intent.parentBinding, parentDecisionHash: intent.parentDecisionHash,
      question: intent.question, replyID: intent.replyID, wireBody: exact)
    #expect(replay.wireBody == exact && replay.replyInputHash == intent.replyInputHash)
    #expect(!String(describing: replay).contains(intent.parentInputHash))
  }

  @Test func actualFirstQuantityDeliveryIsNotFoodAcknowledgment() throws {
    let intent = try quantityIntent(amount: 100)
    let reply = try result("needs_reply")
    #expect(intent.replyInputHash == reply.replyInputHash)
    #expect(reply.matches(intent: intent, authUserID: reply.authUserID))
    #expect(reply.isAcceptedAnswerDelivery(for: intent))
    #expect(reply.status == .needsReply && reply.receipt == nil)
    #expect(reply.acceptsHTTPStatus(200) && !reply.acceptsHTTPStatus(202))
    #expect(!reply.matches(intent: intent, authUserID: UUID()))
  }

  @Test func actualSavedReceiptKeepsDistinctRegistrationAndOriginalParent() throws {
    let saved = try result("saved")
    let intent = try mealIntent()
    #expect(saved.matches(intent: intent, authUserID: saved.authUserID))
    #expect(saved.receipt?.registrationID != saved.replyID)
    #expect(saved.receipt?.parentCommandID == intent.parentCommandID)
    #expect(!saved.isAcceptedAnswerDelivery(for: intent))
    #expect(saved.acceptsHTTPStatus(200) && !saved.acceptsHTTPStatus(202))
  }

  @Test func heldAndUnprovenConflictNeverAcknowledgeDelivery() throws {
    let intent = try mealIntent()
    let held = try result("held")
    let absent = try result("not_admitted")
    #expect(held.status == .held && held.reason == "ready_for_explicit_resume")
    #expect(held.matches(intent: intent, authUserID: held.authUserID))
    #expect(!held.isAcceptedAnswerDelivery(for: intent))
    #expect(held.acceptsHTTPStatus(200) && !held.acceptsHTTPStatus(202))
    #expect(absent.status == .reconciliationRequired && absent.childBinding == nil)
    #expect(absent.matches(intent: intent, authUserID: absent.authUserID))
    #expect(absent.acceptsHTTPStatus(202) && !absent.acceptsHTTPStatus(200))
    #expect(!absent.isAcceptedAnswerDelivery(for: intent))
  }

  @Test func higherStaleOrRepeatedQuestionCannotCloseAnOriginalAnswer() throws {
    let intent = try quantityIntent(amount: 100)
    for change in ["higher", "stale", "same-key"] {
      var p = try payload("needs_reply")
      var q = p["question"] as! [String: Any]
      if change == "higher" { q["revision"] = 2 }
      if change == "stale" { q["revision"] = 0 }
      if change == "same-key" { q["question_key"] = intent.questionKey }
      p["question"] = q
      let response = try decode(p)
      #expect(response.matches(intent: intent, authUserID: response.authUserID))
      #expect(!response.isAcceptedAnswerDelivery(for: intent))
    }
  }

  @Test func quantityCanonicalizationPreservesExponentAndRejectsSilentRounding() throws {
    let intent = try quantityIntent(amount: Decimal(string: "0.0000001")!)
    let submit = try object(intent.wireBody)
    let input = submit["input"] as! [String: Any]
    let canonical = try ConversationMealEditOperation.canonicalJSON(
      JSONDecoder().decode(ConversationMealEditJSON.self, from: bytes(input)))
    #expect(canonical.contains("\"amount\":0.0000001"))
    #expect(!canonical.contains("e-"))
    #expect(intent.replyInputHash == (try ConversationMealCommand.digest(Data(canonical.utf8))))
    for invalid in [
      Decimal.zero, Decimal(-1), Decimal(10000), Decimal.nan,
      Decimal(string: "0.10000000000000001")!,
    ] {
      #expect(throws: (any Error).self) { try quantityIntent(amount: invalid) }
    }
    for meal in ConversationMealCommand.MealType.allCases {
      let original = try mealIntent()
      let value = try ConversationMealReplyIntent(
        parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
        question: original.question, answer: .mealType(meal))
      #expect(try object(value.wireBody)["input"] != nil)
    }
  }

  @Test func restorationNeverRebasesIdentityQuestionOrWire() throws {
    let intent = try mealIntent()
    for attack in ["extra", "reply", "parent", "decision", "revision", "key", "calories", "kind"] {
      var wire = try object(intent.wireBody)
      var input = wire["input"] as! [String: Any]
      switch attack {
      case "extra": wire["owner_id"] = UUID().uuidString.lowercased()
      case "reply": wire["reply_id"] = UUID().uuidString.lowercased()
      case "parent": wire["parent_input_hash"] = String(repeating: "a", count: 64)
      case "decision": wire["parent_decision_hash"] = String(repeating: "a", count: 64)
      case "revision": input["expected_revision"] = 2
      case "key": input["question_key"] = String(repeating: "a", count: 64)
      case "calories": input["calories"] = 100
      default: input["answer"] = ["kind": "quantity", "food_index": 0, "amount": 100, "unit": "g"]
      }
      wire["input"] = input
      #expect(throws: (any Error).self) {
        try ConversationMealReplyIntent(
          parentBinding: intent.parentBinding, parentDecisionHash: intent.parentDecisionHash,
          question: intent.question, replyID: intent.replyID, wireBody: bytes(wire))
      }
    }
    #expect(throws: (any Error).self) {
      try ConversationMealReplyIntent(
        parentBinding: intent.parentBinding, parentDecisionHash: intent.parentDecisionHash,
        question: intent.question, replyID: intent.parentCommandID, answer: .mealType(.almoco))
    }
    var record = try object(JSONEncoder().encode(intent))
    record["authority"] = true
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(ConversationMealReplyIntent.self, from: bytes(record))
    }
  }

  @Test(arguments: [
    "extra", "auth", "owner", "epoch", "parent", "parent-hash", "decision",
    "child", "child-hash", "child-protocol", "child-owner", "clock", "status", "reason",
    "receipt-null", "receipt-parent", "receipt-provider", "question", "feedback-held",
  ]) func rejectsInvalidResult(_ attack: String) throws {
    var p = try payload(attack == "feedback-held" ? "held" : "saved")
    switch attack {
    case "extra": p["snapshot"] = [:]
    case "auth": p["auth_user_id"] = "UPPER-INVALID"
    case "owner": p["owner_id"] = UUID().uuidString.lowercased()
    case "epoch": p["epoch"] = UUID().uuidString.lowercased()
    case "parent": p["parent_command_id"] = UUID().uuidString.lowercased()
    case "parent-hash": p["parent_input_hash"] = String(repeating: "a", count: 64)
    case "decision":
      var r = p["receipt"] as! [String: Any]
      r["parent_decision_hash"] = String(repeating: "a", count: 64)
      p["receipt"] = r
    case "child": p["reply_id"] = UUID().uuidString.lowercased()
    case "child-hash": p["reply_input_hash"] = String(repeating: "a", count: 64)
    case "child-protocol", "child-owner":
      var b = p["child_binding"] as! [String: Any]
      b[attack == "child-protocol" ? "command_protocol" : "owner_id"] =
        attack == "child-protocol" ? "conversation.command.v1" : UUID().uuidString.lowercased()
      p["child_binding"] = b
    case "clock": p["observed_at"] = "2026-11-04T13:57:31.000000Z"
    case "status": p["status"] = "prepared"
    case "reason": p["reason"] = "ready_for_explicit_resume"
    case "receipt-null": p["receipt"] = NSNull()
    case "receipt-parent", "receipt-provider":
      var r = p["receipt"] as! [String: Any]
      r[attack == "receipt-parent" ? "parent_command_id" : "provider_key"] =
        attack == "receipt-parent" ? p["reply_id"] : "conversation.meal/fake"
      p["receipt"] = r
    case "question": p["question"] = try payload("needs_reply")["question"]
    default: p["feedback"] = [:]
    }
    #expect(throws: (any Error).self) { try decode(p) }
  }

  @Test func completeByteBudgetPrecedesOptionalFeedbackOmission() throws {
    var p = try payload("saved")
    p["feedback"] = ["invalid": true]
    #expect(try decode(p).feedback == nil)
    p["feedback"] = ["invalid": String(repeating: "é", count: 130000)]
    #expect(throws: (any Error).self) { try decode(p) }
  }

  @Test func exactWireAndResultBoundsNeverTruncateTheOriginal() throws {
    let intent = try mealIntent()
    let exact = Data(repeating: 32, count: 16384 - intent.wireBody.count) + intent.wireBody
    let restored = try ConversationMealReplyIntent(
      parentBinding: intent.parentBinding, parentDecisionHash: intent.parentDecisionHash,
      question: intent.question, replyID: intent.replyID, wireBody: exact)
    #expect(restored.wireBody == exact && restored.replyInputHash == intent.replyInputHash)
    #expect(throws: (any Error).self) {
      try ConversationMealReplyIntent(
        parentBinding: intent.parentBinding, parentDecisionHash: intent.parentDecisionHash,
        question: intent.question, replyID: intent.replyID, wireBody: Data([32]) + exact)
    }
    var p = try payload("saved")
    p["feedback"] = ["invalid": ""]
    let remaining = 240000 - (try bytes(p).count)
    p["feedback"] = ["invalid": String(repeating: "x", count: remaining)]
    #expect(try bytes(p).count == 240000)
    #expect(try decode(p).feedback == nil)
    p["feedback"] = ["invalid": String(repeating: "x", count: remaining + 1)]
    #expect(throws: (any Error).self) { try decode(p) }
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(ConversationMealReplyResultSnapshot.self, from: bytes(p))
    }
  }

  @Test func quantityUnitsUseTheExistingWholeNameReferenceWithoutConvertingTheAnswer() throws {
    let original = try quantityIntent(amount: 100)
    for (name, units) in [
      ("leite", ["g", "kg", "mL", "L", "caneca"]),
      ("whey", ["g", "kg", "scoop"]), ("leite em pó", ["g", "kg"]),
    ] {
      let reference = MealQuantityDisplay.reference(for: name)
      let metadata: Any = try reference.map { try object(JSONEncoder().encode($0)) } ?? NSNull()
      let raw: [String: Any] = [
        "schema": "conversation.meal-question.v1", "revision": 0,
        "question_key": original.questionKey, "kind": "quantity", "food_index": 0,
        "food_name": name, "allowed_units": units, "quantity_reference": metadata,
      ]
      let q = try JSONDecoder().decode(
        ConversationThreadPageSnapshot.Question.self, from: bytes(raw))
      for unit in units {
        let intent = try ConversationMealReplyIntent(
          parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
          question: q, answer: .quantity(amount: Decimal(string: "1.5")!, unit: unit))
        let input = try object(intent.wireBody)["input"] as! [String: Any]
        let answer = input["answer"] as! [String: Any]
        #expect(answer["amount"] as? Double == 1.5 && answer["unit"] as? String == unit)
        #expect(answer["quantity_g"] == nil)
      }
      #expect(throws: (any Error).self) {
        try ConversationMealReplyIntent(
          parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
          question: q, answer: .quantity(amount: 1, unit: "bottle"))
      }
      #expect(throws: (any Error).self) {
        try ConversationMealReplyIntent(
          parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
          question: q, answer: .mealType(.almoco))
      }
    }
  }

  @Test func onlyOptionalClinicalPresentationIsDroppedOnScopeRefresh() throws {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationLinkedFeedbackSDKFixtures", withExtension: "json"))
    #else
      let url = try #require(
        Bundle(for: Marker.self).url(
          forResource: "ConversationLinkedFeedbackSDKFixtures", withExtension: "json"))
    #endif
    let actual = try object(Data(contentsOf: url))
    let parent = actual["parentBinding"] as! [String: Any]
    let child = actual["childBinding"] as! [String: Any]
    let presentation = actual["presentation"] as! [String: Any]
    let provenance = presentation["provenance"] as! [String: Any]
    // Controlled public wrapper around actual coherent SDK pieces, not an HTTP capture.
    var packet = try payload("saved")
    packet["owner_id"] = parent["owner_id"]
    packet["epoch"] = parent["epoch"]
    packet["parent_command_id"] = parent["command_id"]
    packet["parent_input_hash"] = parent["input_hash"]
    packet["parent_decision_hash"] = actual["parentDecisionHash"]
    packet["reply_id"] = child["command_id"]
    packet["reply_input_hash"] = child["input_hash"]
    packet["parent_binding"] = parent
    packet["child_binding"] = child
    packet["receipt"] = actual["receipt"]
    packet["feedback"] = presentation
    packet["observed_at"] = provenance["observed_at"]
    let result = try decode(packet)
    #expect(result.feedback != nil)
    let scope = ConversationFeedbackPresentationSnapshot.Scope(
      ownerID: result.ownerID.uuidString.lowercased(), sessionGeneration: 9,
      epoch: result.epoch.uuidString.lowercased())
    #expect(result.boundFeedback(scope: scope) != nil)
    let stripped = result.withoutFeedback()
    #expect(stripped.feedback == nil && result.feedback != nil)
    #expect(
      stripped.parentBinding == result.parentBinding && stripped.childBinding == result.childBinding
    )
    #expect(stripped.replyID == result.replyID && stripped.replyInputHash == result.replyInputHash)
    #expect(
      stripped.observedAt == result.observedAt
        && stripped.receipt?.registrationID == result.receipt?.registrationID)
    let wrong = ConversationFeedbackPresentationSnapshot.Scope(
      ownerID: UUID().uuidString.lowercased(), sessionGeneration: 9, epoch: scope.epoch)
    #expect(result.boundFeedback(scope: wrong) == nil)
  }

  private func mealIntent() throws -> ConversationMealReplyIntent {
    let saved = try payload("saved")
    let submit = try root()["submit"] as! [String: Any]
    return try .init(
      parentBinding: JSONDecoder().decode(
        ConversationThreadPageSnapshot.Binding.self, from: bytes(saved["parent_binding"]!)),
      parentDecisionHash: saved["parent_decision_hash"] as! String,
      question: JSONDecoder().decode(
        ConversationThreadPageSnapshot.Question.self,
        from: bytes(payload("needs_reply")["question"]!)),
      replyID: UUID(uuidString: submit["reply_id"] as! String)!, answer: .mealType(.almoco))
  }
  private func quantityIntent(amount: Decimal) throws -> ConversationMealReplyIntent {
    let original = try mealIntent()
    // Exact original quantity question from the owned SQL reader golden's parent_head.
    let q: [String: Any] = [
      "schema": "conversation.meal-question.v1", "revision": 0,
      "question_key": "d65e541612ab9ab7cd36f100fafa0e2ae26b106f15fed31e422fa73bb5405129",
      "kind": "quantity", "food_index": 0, "food_name": "arroz", "allowed_units": ["g", "kg"],
      "quantity_reference": NSNull(),
    ]
    return try .init(
      parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
      question: JSONDecoder().decode(ConversationThreadPageSnapshot.Question.self, from: bytes(q)),
      replyID: UUID(uuidString: "c3cc0000-0000-4000-8000-000000000004")!,
      answer: .quantity(amount: amount, unit: "g"))
  }
  private func root() throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealReplyPublicFixtures", withExtension: "json")
      )
    #else
      let url = try #require(
        Bundle(for: Marker.self).url(
          forResource: "ConversationMealReplyPublicFixtures", withExtension: "json"))
    #endif
    return try object(Data(contentsOf: url))
  }
  private func payload(_ key: String) throws -> [String: Any] {
    try (root()[key] as! [String: Any])["data"] as! [String: Any]
  }
  private func result(_ key: String) throws -> ConversationMealReplyResultSnapshot {
    try decode(payload(key))
  }
  private func decode(_ p: [String: Any]) throws -> ConversationMealReplyResultSnapshot {
    try .init(data: bytes(p))
  }
  private func object(_ data: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
  private func bytes(_ value: Any) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
  }
  private class Marker {}
}
