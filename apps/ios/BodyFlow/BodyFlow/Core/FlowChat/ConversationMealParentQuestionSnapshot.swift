import Foundation

/// Pure current-parent observation. No original command, ACK or Thread is
/// reconstructed. Only the scoped adapter and a current grant can offer it.
struct ConversationMealParentQuestionSnapshot: Decodable, Sendable {
  enum Status: String, Sendable { case needsReply = "needs_reply", closed }
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let parentCommandID: UUID
  let parentInputHash: String
  let parentDecisionHash: String
  let parentBinding: ConversationThreadPageSnapshot.Binding
  let headRevision: Int
  let observedAt: String
  let status: Status
  let question: ConversationThreadPageSnapshot.Question?
  let reason: String?

  init(from decoder: any Decoder) throws {
    let raw = try ConversationMealEditJSON(from: decoder)
    try editCheck(raw.data().count <= 16_384)
    let o = try raw.object([
      "schema", "auth_user_id", "owner_id", "epoch", "parent_command_id", "parent_input_hash",
      "parent_decision_hash", "parent_binding", "head_revision", "observed_at", "status", "question", "reason",
    ])
    try editCheck(o.required("schema").string() == "conversation.meal-question-read.v1")
    authUserID = try o.required("auth_user_id").uuid()
    ownerID = try o.required("owner_id").uuid()
    epoch = try o.required("epoch").uuid()
    parentCommandID = try o.required("parent_command_id").uuid()
    parentInputHash = try o.required("parent_input_hash").hash()
    parentDecisionHash = try o.required("parent_decision_hash").hash()
    parentBinding = try o.required("parent_binding").decode(ConversationThreadPageSnapshot.Binding.self)
    headRevision = try o.required("head_revision").revision()
    observedAt = try o.required("observed_at").clock()
    try editCheck(observedAt.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$", options: .regularExpression) != nil)
    guard let status = Status(rawValue: try o.required("status").string()) else {
      throw ConversationMealEditInvalid.value
    }
    self.status = status
    question = try o.required("question").optional { try $0.decode(ConversationThreadPageSnapshot.Question.self) }
    reason = try o.required("reason").optional { try $0.string() }
    try editCheck(!parentBinding.isChild && parentBinding.ownerID == ownerID
      && parentBinding.epoch == epoch && parentBinding.commandID == parentCommandID
      && parentBinding.inputHash == parentInputHash && headRevision <= 31
      && editInstant(parentBinding.admittedAt) <= editInstant(observedAt))
    if status == .needsReply {
      try editCheck(question?.revision == headRevision && reason == nil)
    } else {
      try editCheck(question == nil && ["parent_fulfilled", "no_current_question"].contains(reason))
    }
  }

  func matches(child: FlowNeutralIntakeChild, context: ConversationCommandContext) -> Bool {
    child.kind == .meal && authUserID == context.authUserID && ownerID == context.ownerID
      && epoch == context.epoch && child.ownerID == ownerID && child.epoch == epoch
      && child.commandID == parentCommandID && child.inputHash == parentInputHash
      && child.admittedAt == parentBinding.admittedAt
  }
}
