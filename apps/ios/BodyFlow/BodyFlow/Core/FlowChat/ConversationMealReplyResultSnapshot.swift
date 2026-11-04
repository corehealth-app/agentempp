import Foundation

/// Closed reply observation. Food receipts and accepted-answer delivery remain
/// different proofs; a caller must separately hold the actual current lease.
struct ConversationMealReplyResultSnapshot: Decodable, Sendable {
  enum Status: String, Sendable {
    case saved, held
    case needsReply = "needs_reply"
    case reconciliationRequired = "reconciliation_required"
  }
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let parentCommandID: UUID
  let parentInputHash: String
  let parentDecisionHash: String
  let replyID: UUID
  let replyInputHash: String
  let parentBinding: ConversationThreadPageSnapshot.Binding
  let childBinding: ConversationThreadPageSnapshot.Binding?
  let observedAt: String
  let status: Status
  let receipt: ConversationThreadPageSnapshot.LinkedReceipt?
  let question: ConversationThreadPageSnapshot.Question?
  private(set) var feedback: ConversationFeedbackPresentationSnapshot?
  let reason: String?

  init(data: Data) throws {
    try editCheck(data.count <= 240_000)
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      try editCheck(raw.data().count <= 240_000)
      let o = try raw.object([
        "schema", "auth_user_id", "owner_id", "epoch", "parent_command_id", "parent_input_hash",
        "parent_decision_hash", "reply_id", "reply_input_hash", "parent_binding", "child_binding",
        "observed_at", "status", "receipt", "question", "feedback", "reason",
      ])
      try editCheck(o.required("schema").string() == "conversation.meal-reply-result.v1")
      authUserID = try o.required("auth_user_id").uuid()
      ownerID = try o.required("owner_id").uuid()
      epoch = try o.required("epoch").uuid()
      parentCommandID = try o.required("parent_command_id").uuid()
      parentInputHash = try o.required("parent_input_hash").hash()
      parentDecisionHash = try o.required("parent_decision_hash").hash()
      replyID = try o.required("reply_id").uuid()
      replyInputHash = try o.required("reply_input_hash").hash()
      parentBinding = try o.required("parent_binding").decode(
        ConversationThreadPageSnapshot.Binding.self)
      childBinding = try o.required("child_binding").optional {
        try $0.decode(ConversationThreadPageSnapshot.Binding.self)
      }
      observedAt = try o.required("observed_at").clock()
      try editCheck(
        observedAt.range(
          of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$",
          options: .regularExpression) != nil)
      guard let parsed = Status(rawValue: try o.required("status").string()) else {
        throw ConversationMealEditInvalid.value
      }
      status = parsed
      receipt = try o.required("receipt").optional {
        try $0.decode(ConversationThreadPageSnapshot.LinkedReceipt.self)
      }
      question = try o.required("question").optional {
        try $0.decode(ConversationThreadPageSnapshot.Question.self)
      }
      reason = try o.required("reason").optional { try $0.string() }
      try editCheck(
        !parentBinding.isChild && parentBinding.ownerID == ownerID
          && parentBinding.commandID == parentCommandID
          && parentBinding.inputHash == parentInputHash
          && parentBinding.epoch == epoch && replyID != parentCommandID
          && editInstant(parentBinding.admittedAt) <= editInstant(observedAt))
      if let childBinding {
        try editCheck(
          childBinding.isChild && childBinding.ownerID == ownerID && childBinding.epoch == epoch
            && childBinding.commandID == replyID && childBinding.inputHash == replyInputHash
            && editInstant(childBinding.admittedAt) >= editInstant(parentBinding.admittedAt)
            && editInstant(childBinding.admittedAt) <= editInstant(observedAt))
      }
      switch status {
      case .saved:
        guard let childBinding, let receipt else { throw ConversationMealEditInvalid.value }
        try editCheck(
          question == nil && reason == nil
            && receipt.matches(
              child: childBinding, parent: parentBinding, decisionHash: parentDecisionHash)
            && editInstant(receipt.consumedAt) <= editInstant(observedAt))
      case .needsReply:
        try editCheck(childBinding != nil && receipt == nil && question != nil && reason == nil)
      case .held, .reconciliationRequired:
        try editCheck(
          receipt == nil && question == nil && reason.map(Self.reasons.contains) == true)
      }
      if status != .saved {
        guard case .null = try o.required("feedback") else {
          throw ConversationMealEditInvalid.value
        }
        feedback = nil
      } else {
        let candidate = try? o.required("feedback").decode(
          ConversationFeedbackPresentationSnapshot.self)
        feedback = Self.validFeedback(
          candidate, receipt: receipt!, child: childBinding!, observedAt: observedAt)
      }
    } catch { throw editDecodeFailure(decoder) }
  }

  func matches(intent: ConversationMealReplyIntent, authUserID currentAuthUserID: UUID) -> Bool {
    guard authUserID == currentAuthUserID, ownerID == intent.ownerID, epoch == intent.epoch,
      parentCommandID == intent.parentCommandID, parentInputHash == intent.parentInputHash,
      parentDecisionHash == intent.parentDecisionHash, parentBinding == intent.parentBinding,
      replyID == intent.replyID, replyInputHash == intent.replyInputHash
    else { return false }
    if case .mealType(let meal) = intent.answer, let receipt, receipt.mealType != meal {
      return false
    }
    return true
  }
  func acceptsHTTPStatus(_ code: Int) -> Bool {
    code == (status == .reconciliationRequired ? 202 : 200)
  }
  /// A genuine own child advanced this exact question once. This is a NONFOOD
  /// delivery proof, never a saved-meal receipt, history ACK or current lease.
  func isAcceptedAnswerDelivery(for intent: ConversationMealReplyIntent) -> Bool {
    guard status == .needsReply, childBinding != nil, let question,
      matches(intent: intent, authUserID: authUserID), intent.expectedRevision < 2_147_483_647
    else { return false }
    return question.revision == intent.expectedRevision + 1
      && question.questionKey != intent.questionKey
  }
  func boundFeedback(scope: ConversationFeedbackPresentationSnapshot.Scope)
    -> ConversationFeedbackPresentationSnapshot.Bound?
  {
    guard status == .saved, let receipt, let childBinding else { return nil }
    return receipt.boundFeedback(feedback, binding: childBinding, scope: scope)
  }
  func withoutFeedback() -> Self {
    var copy = self
    copy.feedback = nil
    return copy
  }

  private static let reasons: Set<String> = [
    "reply_conflict", "parent_fulfilled", "reply_superseded", "awaiting_explicit_resume",
    "ready_for_explicit_resume", "question_changed", "source_changed", "day_closed",
    "nutrition_unresolved", "clarification_unavailable", "processing_uncertain",
  ]
  private static func validFeedback(
    _ value: ConversationFeedbackPresentationSnapshot?,
    receipt: ConversationThreadPageSnapshot.LinkedReceipt,
    child: ConversationThreadPageSnapshot.Binding, observedAt: String
  ) -> ConversationFeedbackPresentationSnapshot? {
    guard let value,
      value.provenance.epoch == receipt.epoch.uuidString.lowercased(),
      value.provenance.commandID == receipt.commandID.uuidString.lowercased(),
      value.original.registrationID == receipt.registrationID.uuidString.lowercased(),
      value.original.localDate == receipt.localDate,
      let instant = ConversationProtocolInstant(value.provenance.observedAt),
      let observed = ConversationProtocolInstant(observedAt),
      let consumed = ConversationProtocolInstant(receipt.consumedAt), instant <= observed,
      instant >= consumed,
      let admitted = ConversationProtocolInstant(child.admittedAt), instant >= admitted
    else { return nil }
    if case .sections(let recorded, _) = value.content {
      guard recorded.mealKind == receipt.mealType.rawValue,
        Set(recorded.items.map(\.logID)) == Set(receipt.logIDs.map { $0.uuidString.lowercased() })
      else { return nil }
    }
    return value
  }
}
