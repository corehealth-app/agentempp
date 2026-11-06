import Foundation

/// Literal intent only. Choosing a domain and admitting its child are server work.
/// No timestamp, patient identity or clinical fact is generated here.
struct FlowNeutralIntakeInput: Sendable, CustomStringConvertible, CustomReflectable {
  enum Source: Sendable {
    case text(String)
    case media(assetID: UUID, caption: String?)
  }
  let intakeID: UUID
  let source: Source
  let mealTypeHint: ConversationMealCommand.MealType?
  let wireBody: Data
  let inputHash: String
  var idempotencyKey: String { "cintake1:\(intakeID.uuidString.lowercased())" }
  init(intakeID: UUID, source: Source, mealTypeHint: ConversationMealCommand.MealType? = nil) throws
  {
    var o: [String: Any] = [
      "intake_protocol": "conversation.intake.v1", "intake_id": intakeID.uuidString.lowercased(),
    ]
    switch source {
    case .text(let text):
      try neutralRequire(neutralText(text, limit: 2000))
      o["source"] = ["channel": "text", "text": text]
    case .media(let id, let caption):
      var m = [
        "channel": "media", "media_asset_id": id.uuidString.lowercased(),
        "user_action": "report_actual_record",
      ]
      if let caption {
        try neutralRequire(neutralText(caption, limit: 1000))
        m["caption"] = caption
      }
      o["source"] = m
    }
    if let mealTypeHint { o["meal_type_hint"] = mealTypeHint.rawValue }
    self.intakeID = intakeID
    self.source = source
    self.mealTypeHint = mealTypeHint
    wireBody = try JSONSerialization.data(
      withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])
    inputHash = ConversationMealCommand.digest(wireBody)
  }
  init(wireBody: Data) throws {
    try neutralRequire(wireBody.count <= 16_384)
    let raw = try JSONDecoder().decode(ConversationMealEditJSON.self, from: wireBody)
    let o = try neutralObject(
      raw, required: ["intake_protocol", "intake_id", "source"], optional: ["meal_type_hint"])
    try neutralRequire(o.required("intake_protocol").string() == "conversation.intake.v1")
    let id = try o.required("intake_id").uuid()
    let source = try o.required("source")
    let s = try neutralObject(
      source, required: ["channel"], optional: ["text", "media_asset_id", "user_action", "caption"])
    let parsed: Source
    switch try s.required("channel").string() {
    case "text":
      _ = try source.object(["channel", "text"])
      parsed = .text(try s.required("text").string())
    case "media":
      _ = try neutralObject(
        source, required: ["channel", "media_asset_id", "user_action"], optional: ["caption"])
      try neutralRequire(s.required("user_action").string() == "report_actual_record")
      parsed = .media(
        assetID: try s.required("media_asset_id").uuid(),
        caption: try s["caption"].map { try $0.string() })
    default: throw FlowNeutralIntakeInvalid.value
    }
    let hint: ConversationMealCommand.MealType?
    if let value = o["meal_type_hint"] {
      guard let parsed = ConversationMealCommand.MealType(rawValue: try value.string()) else {
        throw FlowNeutralIntakeInvalid.value
      }
      hint = parsed
    } else {
      hint = nil
    }
    try self.init(intakeID: id, source: parsed, mealTypeHint: hint)
  }
  var description: String { "FlowNeutralIntakeInput(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

/// An original submission ticket, not a session grant or a factual receipt.
struct FlowNeutralIntakeTicket: Sendable, CustomStringConvertible, CustomReflectable {
  let input: FlowNeutralIntakeInput
  let ownerID: UUID
  let epoch: UUID
  let ownerHash: String
  let sessionGeneration: UInt64
  var description: String { "FlowNeutralIntakeTicket(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}

struct FlowNeutralIntakeSessionSnapshot: Decodable, Sendable {
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let observedAt: String
  init(from decoder: any Decoder) throws {
    let o = try ConversationMealEditJSON(from: decoder).object([
      "schema", "auth_user_id", "owner_id", "epoch", "observed_at", "intake_protocol",
    ])
    try neutralRequire(
      o.required("schema").string() == "conversation.intake-session.v1"
        && o.required("intake_protocol").string() == "conversation.intake.v1")
    authUserID = try o.required("auth_user_id").uuid()
    ownerID = try o.required("owner_id").uuid()
    epoch = try o.required("epoch").uuid()
    observedAt = try o.required("observed_at").string()
    _ = try neutralInstant(observedAt)
  }
}

struct FlowNeutralIntakeBinding: Sendable, Equatable {
  let ownerID: UUID
  let intakeID: UUID
  let inputHash: String
  let epoch: UUID
  let admittedAt: String
  fileprivate init(_ raw: ConversationMealEditJSON) throws {
    let o = try raw.object(["owner_id", "intake_id", "input_hash", "epoch", "admitted_at"])
    ownerID = try o.required("owner_id").uuid()
    intakeID = try o.required("intake_id").uuid()
    inputHash = try o.required("input_hash").hash()
    epoch = try o.required("epoch").uuid()
    admittedAt = try o.required("admitted_at").string()
    _ = try neutralInstant(admittedAt)
  }
  func matches(_ ticket: FlowNeutralIntakeTicket) -> Bool {
    ownerID == ticket.ownerID && epoch == ticket.epoch && intakeID == ticket.input.intakeID
      && inputHash == ticket.input.inputHash
  }
}
struct FlowNeutralIntakeChild: Sendable {
  enum Kind: String, Sendable {
    case meal = "meal.report"
    case workout = "workout.report"
  }
  let kind: Kind
  let ownerID: UUID
  let commandID: UUID
  let inputHash: String
  let epoch: UUID
  let admittedAt: String
  fileprivate init(
    _ raw: ConversationMealEditJSON, binding: FlowNeutralIntakeBinding, selectedAt: String
  ) throws {
    let o = try raw.object(["kind", "owner_id", "command_id", "input_hash", "epoch", "admitted_at"])
    guard let kind = Kind(rawValue: try o.required("kind").string()) else {
      throw FlowNeutralIntakeInvalid.value
    }
    self.kind = kind
    ownerID = try o.required("owner_id").uuid()
    commandID = try o.required("command_id").uuid()
    inputHash = try o.required("input_hash").hash()
    epoch = try o.required("epoch").uuid()
    admittedAt = try o.required("admitted_at").string()
    try neutralRequire(
      ownerID == binding.ownerID && epoch == binding.epoch && commandID != binding.intakeID)
    try neutralRequire(
      neutralInstant(binding.admittedAt) <= neutralInstant(admittedAt)
        && neutralInstant(admittedAt) <= neutralInstant(selectedAt))
  }
}
struct FlowNeutralIntakeSelection: Sendable {
  let child: FlowNeutralIntakeChild
  let sourceHash: String
  let decisionHash: String
  let selectedAt: String
  fileprivate init(_ raw: ConversationMealEditJSON, binding: FlowNeutralIntakeBinding) throws {
    let o = try raw.object(["kind", "source_hash", "decision_hash", "selected_at", "command"])
    sourceHash = try o.required("source_hash").hash()
    decisionHash = try o.required("decision_hash").hash()
    selectedAt = try o.required("selected_at").string()
    _ = try neutralInstant(selectedAt)
    child = try .init(o.required("command"), binding: binding, selectedAt: selectedAt)
    try neutralRequire(o.required("kind").string() == child.kind.rawValue)
  }
}

/// A matched factual projection. The caller still needs trusted HTTP status,
/// original lease/current grant and local CAS before removing or publishing work.
enum FlowNeutralIntakeFactualAcknowledgement: Sendable {
  case meal(SavedConversationMealCommandResultSnapshot)
  case workout(SavedConversationWorkoutCommandResultSnapshot)
}
struct FlowNeutralIntakeResponseSnapshot: Decodable, Sendable {
  enum Status: String, Sendable {
    case selected, pending, held, absent
    case notRecorded = "not_recorded"
    case clarificationRequired = "clarification_required"
  }
  enum ChildReply: Sendable {
    case meal(ConversationMealCommandReply)
    case workout(ConversationWorkoutCommandReplySnapshot)
  }
  struct Lookup: Sendable {
    let ownerID: UUID
    let intakeID: UUID
    let inputHash: String
    let epoch: UUID
    fileprivate init(_ raw: ConversationMealEditJSON) throws {
      // The driver intentionally projects its public lookup in camelCase.
      let o = try raw.object(["ownerId", "intakeId", "inputHash", "epoch"])
      ownerID = try o.required("ownerId").uuid()
      intakeID = try o.required("intakeId").uuid()
      inputHash = try o.required("inputHash").hash()
      epoch = try o.required("epoch").uuid()
    }
    func matches(_ ticket: FlowNeutralIntakeTicket) -> Bool {
      ownerID == ticket.ownerID && epoch == ticket.epoch && intakeID == ticket.input.intakeID
        && inputHash == ticket.input.inputHash
    }
  }
  struct Question: Sendable {
    let field: String
    let text: String
  }
  let status: Status
  let intake: FlowNeutralIntakeBinding?
  let lookup: Lookup?
  let selection: FlowNeutralIntakeSelection?
  let result: ChildReply?
  let reason: String?
  let question: Question?
  let sourceHash: String?
  let decisionHash: String?
  init(from decoder: any Decoder) throws {
    let raw = try ConversationMealEditJSON(from: decoder)
    let root = try neutralObject(
      raw, required: ["schema", "status"],
      optional: [
        "intake", "lookup", "selection", "result", "reason", "question", "source_hash",
        "decision_hash",
      ])
    try neutralRequire(root.required("schema").string() == "conversation.intake-result.v1")
    guard let status = Status(rawValue: try root.required("status").string()) else {
      throw FlowNeutralIntakeInvalid.value
    }
    self.status = status
    switch status {
    case .selected:
      _ = try raw.object(["schema", "status", "intake", "selection", "result"])
      let binding = try FlowNeutralIntakeBinding(root.required("intake"))
      let selected = try FlowNeutralIntakeSelection(root.required("selection"), binding: binding)
      let payload = try root.required("result")
      let child = selected.child
      switch child.kind {
      case .meal:
        let reply = try payload.decode(
          ConversationMealCommandReply.self, selection: .selected(from: decoder))
        switch reply {
        case .saved(let saved):
          try neutralRequire(
            UUID(uuidString: saved.ownerID) == child.ownerID
              && UUID(uuidString: saved.commandID) == child.commandID
              && saved.inputHash == child.inputHash && UUID(uuidString: saved.epoch) == child.epoch
              && neutralInstant(saved.admittedAt) == neutralInstant(child.admittedAt))
        case .state(let state):
          try neutralRequire(
            state.ownerID == child.ownerID && state.commandID == child.commandID
              && state.inputHash == child.inputHash && state.epoch == child.epoch)
        }
        result = .meal(reply)
      case .workout:
        let reply = try payload.decode(
          ConversationWorkoutCommandReplySnapshot.self, selection: .selected(from: decoder))
        try neutralRequire(
          reply.matches(
            ownerID: child.ownerID, commandID: child.commandID, inputHash: child.inputHash,
            epoch: child.epoch, admittedAt: child.admittedAt))
        result = .workout(reply)
      }
      intake = binding
      selection = selected
      lookup = nil
      reason = nil
      question = nil
      sourceHash = nil
      decisionHash = nil
    case .pending, .held:
      _ = try raw.object(["schema", "status", "lookup", "intake", "reason"])
      let id = try Lookup(root.required("lookup"))
      if case .null = try root.required("intake") {
        intake = nil
      } else {
        let b = try FlowNeutralIntakeBinding(root.required("intake"))
        try neutralRequire(
          b.ownerID == id.ownerID && b.intakeID == id.intakeID && b.inputHash == id.inputHash
            && b.epoch == id.epoch)
        intake = b
      }
      lookup = id
      reason = try neutralReason(root.required("reason"))
      selection = nil
      result = nil
      question = nil
      sourceHash = nil
      decisionHash = nil
    case .absent:
      _ = try raw.object(["schema", "status", "lookup"])
      lookup = try Lookup(root.required("lookup"))
      intake = nil
      reason = nil
      selection = nil
      result = nil
      question = nil
      sourceHash = nil
      decisionHash = nil
    case .notRecorded, .clarificationRequired:
      _ = try raw.object(
        status == .notRecorded
          ? ["schema", "status", "intake", "source_hash", "decision_hash", "reason"]
          : ["schema", "status", "intake", "source_hash", "decision_hash", "reason", "question"])
      intake = try FlowNeutralIntakeBinding(root.required("intake"))
      lookup = nil
      sourceHash = try root.required("source_hash").hash()
      decisionHash = try root.required("decision_hash").hash()
      reason = try neutralReason(root.required("reason"))
      if status == .clarificationRequired {
        let q = try root.required("question").object(["field", "text"])
        let field = try q.required("field").string()
        let text = try q.required("text").string()
        try neutralRequire(
          ["record_kind", "description"].contains(field) && neutralText(text, limit: 300))
        question = .init(field: field, text: text)
      } else {
        question = nil
      }
      selection = nil
      result = nil
    }
  }
  func matches(_ ticket: FlowNeutralIntakeTicket) -> Bool {
    intake?.matches(ticket) ?? lookup?.matches(ticket) ?? false
  }
  func factualAcknowledgement(for ticket: FlowNeutralIntakeTicket)
    -> FlowNeutralIntakeFactualAcknowledgement?
  {
    guard status == .selected, matches(ticket), selection != nil, case .text = ticket.input.source
    else { return nil }
    // Media stays recoverable, but this text-only slice cannot prove a genuine
    // domain media projection. A later negotiated contract must establish it.
    switch result {
    case .meal(.saved(let saved)): return .meal(saved)
    case .workout(.saved(let saved)): return .workout(saved)
    default: return nil
    }
  }
}

private func neutralReason(_ raw: ConversationMealEditJSON) throws -> String {
  let reason = try raw.string()
  try neutralRequire(reason.range(of: "^[a-z_]{1,80}$", options: .regularExpression) != nil)
  return reason
}

enum FlowNeutralIntakeInvalid: Error { case value }
func neutralRequire(_ value: Bool) throws { if !value { throw FlowNeutralIntakeInvalid.value } }
func neutralText(_ value: String, limit: Int) -> Bool {
  guard value.utf16.count <= limit,
    !value.unicodeScalars.contains(where: {
      ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
    })
  else { return false }
  // ECMAScript String.trim whitespace, including BOM. Never trim stored bytes.
  return value.unicodeScalars.contains {
    switch $0.value {
    case 9...13, 32, 160, 5760, 8192...8202, 8232, 8233, 8239, 8287, 12288, 65279: false
    default: true
    }
  }
}
func neutralInstant(_ value: String) throws -> ConversationProtocolInstant {
  guard let instant = ConversationProtocolInstant(value) else {
    throw FlowNeutralIntakeInvalid.value
  }
  return instant
}
func neutralObject(
  _ value: ConversationMealEditJSON, required: Set<String>, optional: Set<String> = []
) throws -> [String: ConversationMealEditJSON] {
  guard case .object(let o) = value, required.isSubset(of: Set(o.keys)),
    Set(o.keys).isSubset(of: required.union(optional))
  else { throw FlowNeutralIntakeInvalid.value }
  return o
}
