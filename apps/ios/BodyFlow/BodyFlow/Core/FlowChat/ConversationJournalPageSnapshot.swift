import Foundation

/// Delivery of a sealed non-registration decision. This is not food, XP or a
/// grant to acknowledge/resubmit an outbox entry without its current lease.
struct ConversationMealDecisionReceiptSnapshot: Decodable, Sendable {
  let ownerID: UUID
  let commandID: UUID
  let originalInputHash: String
  let epoch: UUID
  let reason: String
  let foodIndexes: [Int]
  let decisionHash: String
  let sealedAt: String

  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      let o = try raw.object([
        "schema", "status", "owner_id", "command_id", "input_hash", "epoch", "reason",
        "food_indexes", "decision_hash", "sealed_at",
      ])
      try editCheck(
        o.required("schema").string() == "conversation.meal-decision-public.v1"
          && o.required("status").string() == "not_recorded")
      ownerID = try o.required("owner_id").uuid()
      commandID = try o.required("command_id").uuid()
      originalInputHash = try o.required("input_hash").hash()
      epoch = try o.required("epoch").uuid()
      reason = try o.required("reason").string()
      try editCheck(reason.range(of: "^[a-z_]{1,80}$", options: .regularExpression) != nil)
      let indexes = try o.required("food_indexes").array()
      try editCheck(indexes.count <= 30)
      foodIndexes = try indexes.map { value in
        let number = try value.amount(max: 29)
        try editCheck(number.rounded() == number)
        return Int(number)
      }
      try editCheck(Set(foodIndexes).count == foodIndexes.count)
      // The SQL proof is an opaque token, never a client reserialized hash.
      decisionHash = try o.required("decision_hash").hash()
      sealedAt = try o.required("sealed_at").clock()
    } catch { throw journalDecodeFailure(decoder) }
  }
  func matches(state: ConversationMealCommandStateSnapshot) -> Bool {
    state.status == .notRecorded && ownerID == state.ownerID && commandID == state.commandID
      && originalInputHash == state.inputHash && epoch == state.epoch && reason == state.reason
      && foodIndexes == state.foodIndexes
  }
}

/// Immutable public history under an intrinsic server scope. This leaf does
/// not authenticate transport, validate a revocable lease, close a delivery,
/// mutate a cache, reorder events, execute an operation or calculate nutrition.
struct ConversationJournalPageSnapshot: Decodable, Sendable {
  typealias TerminalReceipt = ConversationMealDecisionReceiptSnapshot
  struct CommandEntry: Sendable {
    let eventID: String
    let at: String
    let originalCommand: ConversationMealCommand
    let result: ConversationMealCommandReply
    let terminalReceipt: ConversationMealDecisionReceiptSnapshot?
  }
  struct EditEntry: Sendable {
    let eventID: String
    let at: String
    let result: ConversationMealEditResultSnapshot
  }
  enum Entry: Sendable {
    case command(CommandEntry)
    case edit(EditEntry)
    var eventID: String {
      switch self {
      case .command(let v): v.eventID
      case .edit(let v): v.eventID
      }
    }
    var at: String {
      switch self {
      case .command(let v): v.at
      case .edit(let v): v.at
      }
    }
  }
  struct Envelope: Decodable, Sendable {
    let data: ConversationJournalPageSnapshot
    let meta: MobileResponseMetadata
    init(data: Data) throws {
      guard data.count <= 262_144 else { throw ConversationMealEditInvalid.value }
      self = try JSONDecoder().decode(Self.self, from: data)
    }
    init(from decoder: any Decoder) throws {
      do {
        let raw = try ConversationMealEditJSON(from: decoder)
        try editCheck(raw.data().count <= 262_144)
        let o = try raw.object(["data", "meta"])
        let m = try o.required("meta").object(["api_version", "request_id"])
        try editCheck(m.required("api_version").string() == "v1")
        _ = try m.required("request_id").text(limit: 262_144)
        meta = try o.required("meta").decode(MobileResponseMetadata.self)
        data = try o.required("data").decode(ConversationJournalPageSnapshot.self)
      } catch { throw journalDecodeFailure(decoder) }
    }
  }
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let observedAt: String
  let items: [Entry]
  let hasMore: Bool
  /// Opaque bounded server value. Only the SQL reader can qualify its anchor.
  let nextCursor: String?

  init(data: Data) throws {
    guard data.count <= 240_000 else { throw ConversationMealEditInvalid.value }
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      // Apply this BEFORE optional historical enrichment may be discarded.
      try editCheck(raw.data().count <= 240_000)
      let o = try raw.object([
        "schema", "auth_user_id", "owner_id", "epoch", "observed_at", "items", "has_more",
        "next_cursor",
      ])
      try editCheck(o.required("schema").string() == "conversation.journal-page.v1")
      authUserID = try o.required("auth_user_id").uuid()
      ownerID = try o.required("owner_id").uuid()
      epoch = try o.required("epoch").uuid()
      observedAt = try o.required("observed_at").clock()
      let rows = try o.required("items").array()
      try editCheck(rows.count <= 25)
      let scopeOwner = ownerID
      let scopeEpoch = epoch
      let finalObservation = observedAt
      items = try rows.map {
        try Self.entry($0, ownerID: scopeOwner, epoch: scopeEpoch, observedAt: finalObservation, selection: .selected(from: decoder))
      }
      try editCheck(Set(items.map(\.eventID)).count == items.count)
      for (previous, next) in zip(items, items.dropFirst()) {
        let a = try editInstant(previous.at)
        let b = try editInstant(next.at)
        try editCheck(
          a > b || (a == b && next.eventID.utf8.lexicographicallyPrecedes(previous.eventID.utf8)))
      }
      hasMore = try o.required("has_more").bool()
      nextCursor = try o.required("next_cursor").optional { try $0.text(limit: 1024) }
      try editCheck(hasMore ? (!items.isEmpty && nextCursor != nil) : nextCursor == nil)
    } catch { throw journalDecodeFailure(decoder) }
  }
  func matches(authUserID: UUID, ownerID: UUID, epoch: UUID) -> Bool {
    self.authUserID == authUserID && self.ownerID == ownerID && self.epoch == epoch
  }
  private static func entry(
    _ raw: ConversationMealEditJSON, ownerID: UUID, epoch: UUID, observedAt: String,
    selection: ConversationFeedbackPresentationSelection?
  ) throws -> Entry {
    let kind = try raw.member("kind").string()
    if kind == "edit" {
      let o = try raw.object(["event_id", "at", "kind", "result"])
      let result = try o.required("result").decode(ConversationMealEditResultSnapshot.self)
      let at = try o.required("at").clock()
      let id = try o.required("event_id").string()
      try editCheck(
        result.ownerID == ownerID && result.epoch == epoch
          && id
            == "edit/\(result.commandID.uuidString.lowercased())/\(result.receipt.operationID.uuidString.lowercased())"
      )
      try editCheck(
        editInstant(at) == editInstant(result.receipt.appliedAt)
          && editInstant(at) <= editInstant(observedAt))
      return .edit(.init(eventID: id, at: at, result: result))
    }
    try editCheck(kind == "command")
    let o = try raw.object([
      "event_id", "at", "kind", "original_command", "result", "terminal_receipt",
    ])
    let sourceValue = try o.required("original_command")
    let originalFields = try sourceValue.object(
      required: ["command_protocol", "command_id", "kind", "source"], optional: ["meal_type"])
    let explicitMealType = try originalFields["meal_type"].map { try $0.string() }
    let source = try sourceValue.data()
    let command = try ConversationMealCommand(wireBody: source)
    let result = try o.required("result").decode(ConversationMealCommandReply.self, selection: selection)
    let terminal = try o.required("terminal_receipt").optional {
      try $0.decode(ConversationMealDecisionReceiptSnapshot.self)
    }
    let at = try o.required("at").clock()
    let id = try o.required("event_id").string()
    try editCheck(
      id == "command/\(command.commandID.uuidString.lowercased())"
        && editInstant(at) <= editInstant(observedAt))
    switch result {
    case .saved(let saved):
      if let explicitMealType { try editCheck(saved.receipt.mealType.rawValue == explicitMealType) }
      try editCheck(
        saved.ownerID == ownerID.uuidString.lowercased()
          && saved.commandID == command.commandID.uuidString.lowercased()
          && saved.inputHash == command.inputHash && saved.epoch == epoch.uuidString.lowercased()
          && terminal == nil)
      try editCheck(
        editInstant(at) == editInstant(saved.admittedAt)
          && editInstant(saved.receipt.consumedAt) <= editInstant(observedAt))
      if let feedback = saved.feedback {
        try editCheck(editInstant(feedback.provenance.observedAt) <= editInstant(observedAt))
      }
    case .state(let state):
      try editCheck(
        state.status != .absent && state.ownerID == ownerID && state.commandID == command.commandID
          && state.inputHash == command.inputHash && state.epoch == epoch)
      if state.status == .notRecorded {
        guard let terminal else { throw ConversationMealEditInvalid.value }
        try editCheck(
          terminal.matches(state: state) && editInstant(terminal.sealedAt) >= editInstant(at)
            && editInstant(terminal.sealedAt) <= editInstant(observedAt))
      } else {
        try editCheck(terminal == nil)
      }
    }
    return .command(
      .init(
        eventID: id, at: at, originalCommand: command, result: result, terminalReceipt: terminal))
  }
}
private func journalDecodeFailure(_ decoder: any Decoder) -> DecodingError {
  .dataCorrupted(
    .init(codingPath: decoder.codingPath, debugDescription: "Conversation history unavailable"))
}
