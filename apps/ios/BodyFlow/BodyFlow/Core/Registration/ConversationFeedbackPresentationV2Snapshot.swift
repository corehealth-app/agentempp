import Foundation

/// Separate closed current-policy wrapper for an original v3 receipt. It keeps
/// server text verbatim and never exposes the unmasked canonical day or block.
struct ConversationFeedbackPresentationV2Snapshot: Decodable, Sendable {
  typealias Snapshot = ConversationFeedbackPresentationSnapshot
  let original: Snapshot.Original
  let currentPolicy: Snapshot.Policy
  let provenance: Snapshot.Provenance
  let recorded: RegistrationFeedbackV3Snapshot.Registration
  let sections: [Snapshot.Section]

  init(from decoder: any Decoder) throws {
    let raw = try PresentationValue(from: decoder)
    _ = try raw.object([
      "schema", "mode", "assistant", "original", "status", "format",
      "recorded", "sections", "current_policy", "provenance",
    ])
    try Self.require(JSONEncoder().encode(raw).count <= 200_000)
    try Self.require(raw.member("schema").string() == "conversation.feedback-presentation.v2")
    try Self.require(raw.member("mode").string() == "historical")
    try Self.require(raw.member("assistant").string() == "Flow AI")
    try Self.require(raw.member("status").string() == "available")
    try Self.require(raw.member("format").string() == "sections")
    let identity = try raw.member("original")
    _ = try identity.object(["schema", "registration_id", "kind", "local_date"])
    try Self.require(identity.member("schema").string() == "registration.feedback.v3")
    let kind = try identity.member("kind").oneOf(["meal", "workout"])
    original = .init(
      schema: "registration.feedback.v3",
      registrationID: try Self.uuid(identity.member("registration_id")),
      localDate: try identity.member("local_date").civilDate(), kind: kind)
    let facts = try raw.member("recorded").decode(RegistrationFeedbackV3Snapshot.Recorded.self)
    recorded = facts.registration
    switch recorded {
    case .meal: try Self.require(kind == "meal")
    case .workout: try Self.require(kind == "workout")
    }
    let policy = try raw.member("current_policy")
    _ = try policy.object([
      "version", "observed_at", "assessment", "recording_allowed", "pause_weight_loss_guidance",
      "professional_assessment_recommended", "phase_selection_pending", "target_source", "hide",
    ])
    let hide = try policy.member("hide")
    let fields = try hide.object(["objective", "calories", "protein", "balance", "block", "budget"])
    for field in fields.values { _ = try field.bool() }
    currentPolicy = try .init(
      policy.decode(CurrentClinicalPolicy.self), budget: hide.member("budget").bool())
    try Self.require(currentPolicy.recordingAllowed)
    let source = try raw.member("provenance")
    _ = try source.object(["epoch", "command_id", "observed_at"])
    let clock = try source.member("observed_at").string()
    try Self.require(PresentationInstant(clock) != nil)
    try Self.require(policy.member("observed_at").string().utf16.elementsEqual(clock.utf16))
    provenance = .init(
      epoch: try Self.uuid(source.member("epoch")),
      commandID: try Self.uuid(source.member("command_id")), observedAt: clock)
    let keys: [Snapshot.Section.Key] = [.saved, .items, .summary, .day, .block, .education]
    let rows = try raw.member("sections").array()
    try Self.require(rows.count == keys.count)
    sections = try zip(rows, keys).map { row, key in
      _ = try row.object(["key", "text"])
      try Self.require(row.member("key").string() == key.rawValue)
      let text = try row.member("text").string()
      try Self.require(
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 64_000)
      return .init(key: key, text: text)
    }
  }
  private static func uuid(_ value: PresentationValue) throws -> String {
    let result = try value.uuid()
    try require(
      result.range(
        of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
        options: .regularExpression) != nil)
    return result
  }
  private static func require(_ value: Bool) throws {
    if !value {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Historical feedback presentation unavailable"))
    }
  }
}
