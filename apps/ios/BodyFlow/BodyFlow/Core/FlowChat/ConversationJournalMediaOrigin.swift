import Foundation

/// A canonical server-owned media child is historical evidence, not a public
/// command or an outbox ticket. In particular, it cannot be enqueued/replayed.
struct ConversationJournalMediaOrigin: Sendable {
  let commandID: UUID
  let inputHash: String
  let epoch: UUID
  let intakeID: UUID
  let source: ConversationMealCommand.Source
  let mealType: ConversationMealCommand.MealType?

  init(_ raw: ConversationMealEditJSON) throws {
    let o = try raw.object(
      required: ["command_protocol", "command_id", "kind", "source", "intake_origin"],
      optional: ["meal_type"])
    try editCheck(
      o.required("command_protocol").string() == "conversation.command.v1"
        && o.required("kind").string() == "meal.report")
    commandID = try o.required("command_id").uuid()
    let s = try o.required("source").object(
      required: ["channel", "media_asset_id", "user_action"], optional: ["caption"])
    try editCheck(
      s.required("channel").string() == "media"
        && s.required("user_action").string() == "report_actual_record")
    let assetID = try s.required("media_asset_id").uuid()
    let caption = try s["caption"].map { try $0.string() }
    // Reuse the closed public source's text/control/length checks, but never
    // expose or use its different wire body/hash as this internal identity.
    _ = try ConversationMealCommand(
      commandID: commandID, source: .media(assetID: assetID, caption: caption))
    source = .media(assetID: assetID, caption: caption)
    if let rawMeal = o["meal_type"] {
      guard let value = ConversationMealCommand.MealType(rawValue: try rawMeal.string()) else {
        throw ConversationMealEditInvalid.value
      }
      mealType = value
    } else {
      mealType = nil
    }
    let origin = try o.required("intake_origin").object([
      "schema", "intake_id", "input_hash", "source_hash", "epoch", "claim_id", "decision_hash",
    ])
    try editCheck(origin.required("schema").string() == "conversation.intake-media-origin.v1")
    intakeID = try origin.required("intake_id").uuid()
    epoch = try origin.required("epoch").uuid()
    _ = try origin.required("claim_id").uuid()
    for key in ["input_hash", "source_hash", "decision_hash"] {
      _ = try origin.required(key).hash()
    }
    try editCheck(intakeID != commandID)
    inputHash = try ConversationMealCommand.digest(raw.data())
  }
}
