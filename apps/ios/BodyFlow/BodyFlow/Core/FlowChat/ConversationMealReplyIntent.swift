import Foundation

/// Original linked answer bytes and identity. Neither decoding nor hashing this
/// record establishes a current question, Auth lease or registration permission.
struct ConversationMealReplyIntent: Codable, Sendable, CustomStringConvertible, CustomReflectable {
  enum Answer: Sendable {
    case quantity(amount: Decimal, unit: String)
    case mealType(ConversationMealCommand.MealType)
  }
  let parentBinding: ConversationThreadPageSnapshot.Binding
  let parentDecisionHash: String
  let question: ConversationThreadPageSnapshot.Question
  let replyID: UUID
  let answer: Answer
  let wireBody: Data
  let replyInputHash: String
  var ownerID: UUID { parentBinding.ownerID }
  var epoch: UUID { parentBinding.epoch }
  var parentCommandID: UUID { parentBinding.commandID }
  var parentInputHash: String { parentBinding.inputHash }
  var expectedRevision: Int { question.revision }
  var questionKey: String { question.questionKey }
  var idempotencyKey: String { "cmreply1:\(replyID.uuidString.lowercased())" }

  init(
    parentBinding: ConversationThreadPageSnapshot.Binding, parentDecisionHash: String,
    question: ConversationThreadPageSnapshot.Question, replyID: UUID = UUID(), answer: Answer
  ) throws {
    let value: ConversationMealEditJSON
    switch answer {
    case .quantity(let amount, let unit):
      guard let index = question.foodIndex else { throw ConversationMealEditInvalid.value }
      value = .object([
        "kind": .string("quantity"), "food_index": .number(Double(index)),
        "amount": .number(try ConversationMealEditOperation.validatedNumber(amount)),
        "unit": .string(unit),
      ])
    case .mealType(let meal):
      value = .object(["kind": .string("meal_type"), "meal_type": .string(meal.rawValue)])
    }
    let raw: ConversationMealEditJSON = .object([
      "schema": .string("conversation.meal-reply-submit.v1"),
      "reply_id": .string(replyID.uuidString.lowercased()),
      "parent_input_hash": .string(parentBinding.inputHash),
      "parent_decision_hash": .string(parentDecisionHash),
      "input": .object([
        "schema": .string("conversation.meal-clarification.v1"),
        "expected_revision": .number(Double(question.revision)),
        "question_key": .string(question.questionKey), "answer": value,
      ]),
    ])
    try self.init(
      parentBinding: parentBinding, parentDecisionHash: parentDecisionHash, question: question,
      replyID: replyID,
      wireBody: Data(ConversationMealEditOperation.canonicalJSON(raw).utf8))
  }

  /// Same original request after disk uncertainty. Never reconstruct this from a
  /// historical child JSONB body or refresh the revision, UUID or question key.
  init(
    parentBinding: ConversationThreadPageSnapshot.Binding, parentDecisionHash: String,
    question: ConversationThreadPageSnapshot.Question, replyID: UUID, wireBody: Data
  ) throws {
    try editCheck(!parentBinding.isChild && replyID != parentBinding.commandID)
    _ = try ConversationMealEditJSON.string(parentDecisionHash).hash()
    try editCheck(wireBody.count <= 16_384)
    let raw = try JSONDecoder().decode(ConversationMealEditJSON.self, from: wireBody)
    let o = try raw.object([
      "schema", "reply_id", "parent_input_hash", "parent_decision_hash", "input",
    ])
    try editCheck(
      o.required("schema").string() == "conversation.meal-reply-submit.v1"
        && o.required("reply_id").uuid() == replyID
        && o.required("parent_input_hash").hash() == parentBinding.inputHash
        && o.required("parent_decision_hash").hash() == parentDecisionHash)
    let input = try o.required("input")
    let i = try input.object(["schema", "expected_revision", "question_key", "answer"])
    try editCheck(
      i.required("schema").string() == "conversation.meal-clarification.v1"
        && i.required("expected_revision").revision() == question.revision
        && i.required("question_key").hash() == question.questionKey)
    let a = try i.required("answer")
    if try a.member("kind").string() == "quantity" {
      let value = try a.object(["kind", "food_index", "amount", "unit"])
      let index = try value.required("food_index").amount(max: 29)
      let unit = try value.required("unit").string()
      try editCheck(
        question.kind == "quantity" && index.rounded() == index
          && question.foodIndex == Int(index) && question.allowedUnits.contains(unit))
      answer = try .quantity(
        amount: editDecimal(value.required("amount").amount(max: 9999, positive: true)), unit: unit)
    } else {
      let value = try a.object(["kind", "meal_type"])
      guard try value.required("kind").string() == "meal_type", question.kind == "meal_type",
        let meal = ConversationMealCommand.MealType(
          rawValue: try value.required("meal_type").string())
      else { throw ConversationMealEditInvalid.value }
      answer = .mealType(meal)
    }
    self.parentBinding = parentBinding
    self.parentDecisionHash = parentDecisionHash
    self.question = question
    self.replyID = replyID
    self.wireBody = wireBody
    replyInputHash = try ConversationMealCommand.digest(
      Data(ConversationMealEditOperation.canonicalJSON(input).utf8))
  }

  init(from decoder: any Decoder) throws {
    let raw = try ConversationMealEditJSON(from: decoder)
    try editCheck(raw.data().count <= 65_536)
    let o = try raw.object([
      "parent_binding", "parent_decision_hash", "question", "reply_id", "wire_body",
    ])
    guard let bytes = Data(base64Encoded: try o.required("wire_body").string()) else {
      throw ConversationMealEditInvalid.value
    }
    try self.init(
      parentBinding: o.required("parent_binding").decode(
        ConversationThreadPageSnapshot.Binding.self),
      parentDecisionHash: o.required("parent_decision_hash").hash(),
      question: o.required("question").decode(ConversationThreadPageSnapshot.Question.self),
      replyID: o.required("reply_id").uuid(), wireBody: bytes)
  }
  func encode(to encoder: any Encoder) throws {
    // Closed local encrypted record, not an alternative submit wire protocol.
    let p = parentBinding
    let raw: ConversationMealEditJSON = .object([
      "parent_binding": .object([
        "owner_id": .string(p.ownerID.uuidString.lowercased()),
        "command_id": .string(p.commandID.uuidString.lowercased()),
        "input_hash": .string(p.inputHash), "command_protocol": .string(p.commandProtocol),
        "kind": .string("meal.report"), "epoch": .string(p.epoch.uuidString.lowercased()),
        "admitted_at": .string(p.admittedAt),
      ]),
      "parent_decision_hash": .string(parentDecisionHash),
      "question": try JSONDecoder().decode(
        ConversationMealEditJSON.self, from: question.encodedData),
      "reply_id": .string(replyID.uuidString.lowercased()),
      "wire_body": .string(wireBody.base64EncodedString()),
    ])
    try raw.encode(to: encoder)
  }
  var description: String { "ConversationMealReplyIntent(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
