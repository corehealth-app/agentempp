import Foundation

/// Closed public observations. These facts deliberately have no original body,
/// hash, question lease, ACK, retry or outbox conversion.
struct ConversationJournalV3PageSnapshot: Decodable, Sendable {
  enum Kind: String, Sendable {
    case intake, workout, report, reply
    case replyResult = "reply_result"
    case fulfillment, edit
  }
  enum Status: String, Sendable {
    case pending
    case notRecorded = "not_recorded"
    case needsReply = "needs_reply"
    case clarificationRequired = "clarification_required"
    case registered
  }
  enum Input: Sendable {
    case text(String)
    case media(caption: String?)
    case quantity(foodIndex: Int, amount: Double, unit: String)
    case mealType(String)
  }
  enum Question: Sendable {
    case observed(field: String, text: String)
    case meal(
      kind: String, foodIndex: Int?, foodName: String?, units: [String],
      reference: MealQuantityDisplay?)
  }
  struct Meal: Sendable {
    let registrationID: UUID
    let mealType: String
    let localDate: String
    let logIDs: [UUID]
    let effectVersion: String
  }
  struct Workout: Sendable {
    let registrationID: UUID
    let workoutID: UUID
    let performedAt: String
    let localDate: String
    let timeZone: String
    let committedAt: String
    let workoutType: String
    let durationMin: Int
    let intensity: String?
    let estimatedKcal: Int?
  }
  struct Edit: Sendable {
    enum Change: String, Sendable {
      case saved
      case saveUndone = "save_undone"
      case registrationUndone = "registration_undone"
    }
    let operationID: UUID
    let change: Change
    let revision: Int
    let appliedAt: String
    let targetOperationID: UUID?
    let removedItemIDs: [UUID]
    let newItemIDs: [UUID]
    let nextRecordID: UUID?
  }
  enum Record: Sendable {
    case meal(Meal)
    case workout(Workout)
    case edit(Edit)
  }
  struct Entry: Identifiable, Sendable {
    let eventID: String
    let at: String
    let threadID: UUID
    let kind: Kind
    let lineageKind: String
    let intakeID: UUID?
    let commandID: UUID?
    let parentCommandID: UUID?
    let originEpoch: UUID
    let input: Input?
    let status: Status
    let reason: String?
    let question: Question?
    let record: Record?
    let feedback: ConversationFeedbackPresentationSnapshot?
    /// Optional current-policy commentary is never a factual event pin.
    let immutablePin: Data
    let outcomePin: Data
    var id: String { eventID }
  }
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let observedAt: String
  let items: [Entry]
  let hasMore: Bool
  let nextCursor: String?

  func matches(authUserID: UUID, ownerID: UUID, epoch: UUID) -> Bool {
    self.authUserID == authUserID && self.ownerID == ownerID && self.epoch == epoch
  }
  init(from decoder: any Decoder) throws {
    let raw = try ConversationMealEditJSON(from: decoder)
    try editCheck(raw.data().count <= 240_000)
    let o = try raw.object([
      "schema", "mode", "auth_user_id", "owner_id", "epoch", "observed_at", "items", "has_more",
      "next_cursor",
    ])
    try editCheck(
      o.required("schema").string() == "conversation.journal-page.v3"
        && o.required("mode").string() == "historical")
    authUserID = try o.required("auth_user_id").uuid()
    ownerID = try o.required("owner_id").uuid()
    epoch = try o.required("epoch").uuid()
    observedAt = try Self.clock(o.required("observed_at"))
    let epoch = epoch
    let observedAt = observedAt
    let values = try o.required("items").array()
    try editCheck(values.count <= 25)
    items = try values.map { try Self.entry($0, epoch: epoch, observedAt: observedAt) }
    try editCheck(Set(items.map(\.eventID)).count == items.count)
    for (newer, older) in zip(items, items.dropFirst()) {
      try editCheck(Self.precedes(newer, older))
    }
    hasMore = try o.required("has_more").bool()
    nextCursor = try o.required("next_cursor").optional { try $0.string() }
    try editCheck(hasMore == (nextCursor != nil))
    if let nextCursor {
      guard let last = items.last else { throw ConversationMealEditInvalid.value }
      try Self.validateCursor(nextCursor, ownerID: ownerID, epoch: epoch, anchor: last)
    }
  }
  static func precedes(_ newer: Entry, _ older: Entry) -> Bool {
    guard let a = ConversationProtocolInstant(newer.at),
      let b = ConversationProtocolInstant(older.at)
    else { return false }
    return a > b || (a == b && older.eventID.utf8.lexicographicallyPrecedes(newer.eventID.utf8))
  }
  static func validateCursor(_ value: String, ownerID: UUID, epoch: UUID, anchor: Entry? = nil)
    throws
  {
    try editCheck(
      !value.isEmpty && value.utf8.count <= 1024
        && value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil)
    let base = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    guard
      let data = Data(base64Encoded: base + String(repeating: "=", count: (4 - base.count % 4) % 4))
    else { throw ConversationMealEditInvalid.value }
    try editCheck(
      data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
        of: "/", with: "_"
      ).replacingOccurrences(of: "=", with: "") == value)
    let c = try JSONDecoder().decode(ConversationMealEditJSON.self, from: data).object([
      "v", "owner_id", "epoch", "at", "id",
    ])
    try editCheck(
      c.required("v").revision() == 3 && c.required("owner_id").uuid() == ownerID
        && c.required("epoch").uuid() == epoch)
    let at = try clock(c.required("at"))
    let id = try c.required("id").text(limit: 160)
    try editCheck(validEventID(id))
    if let anchor { try editCheck(at == anchor.at && id == anchor.eventID) }
  }
  private static func clock(_ value: ConversationMealEditJSON) throws -> String {
    let s = try value.string()
    try editCheck(
      s.range(
        of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$", options: .regularExpression)
        != nil && ConversationProtocolInstant(s) != nil)
    return s
  }
  private static func validEventID(_ s: String) -> Bool {
    let u = "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
    return s.range(
      of: "^(?:(?:intake|workout|command)/" + u + "|(?:reply|reply-result|fulfillment|edit)/" + u
        + "/" + u + ")$", options: .regularExpression) != nil
  }
  private static func entry(_ raw: ConversationMealEditJSON, epoch: UUID, observedAt: String) throws
    -> Entry
  {
    let o = try raw.object(["event_id", "at", "thread_id", "kind", "lineage", "input", "outcome"])
    let id = try o.required("event_id").string()
    let at = try clock(o.required("at"))
    try editCheck(
      validEventID(id)
        && ConversationProtocolInstant(at)! <= ConversationProtocolInstant(observedAt)!)
    let thread = try o.required("thread_id").uuid()
    guard let kind = Kind(rawValue: try o.required("kind").string()) else {
      throw ConversationMealEditInvalid.value
    }
    let l = try o.required("lineage").object([
      "kind", "intake_id", "command_id", "parent_command_id", "origin_epoch",
    ])
    let lineageKind = try l.required("kind").string()
    let intake = try l.required("intake_id").optional { try $0.uuid() }
    let command = try l.required("command_id").optional { try $0.uuid() }
    let parent = try l.required("parent_command_id").optional { try $0.uuid() }
    try editCheck(l.required("origin_epoch").uuid() == epoch)
    let parts = id.split(separator: "/").map(String.init)
    let c = command?.uuidString.lowercased()
    let p = parent?.uuidString.lowercased()
    switch kind {
    case .intake:
      try editCheck(
        parts[0] == "intake" && intake == thread && parts[1] == thread.uuidString.lowercased()
          && parent == nil && lineageKind == "intake" && command != intake)
    case .workout:
      try editCheck(
        parts[0] == "workout" && command == thread && parts[1] == c && intake == nil
          && parent == nil && lineageKind == "workout.report")
    case .report:
      try editCheck(
        parts[0] == "command" && parts[1] == c && parent == nil && thread == (intake ?? command)
          && lineageKind == "meal.report")
    case .reply, .replyResult, .fulfillment:
      let prefix = kind == .replyResult ? "reply-result" : kind.rawValue
      try editCheck(
        parts[0] == prefix && parts[1] == p && parts[2] == c && command != parent && parent != nil
          && thread == (intake ?? parent) && lineageKind == "meal.clarify")
    case .edit:
      try editCheck(
        parts[0] == "edit" && parts[1] == c && command != nil
          && thread == (intake ?? parent ?? command) && lineageKind == "meal.edit")
    }
    let input = try o.required("input").optional { try parseInput($0) }
    if kind == .intake || kind == .workout || kind == .report {
      guard let input else { throw ConversationMealEditInvalid.value }
      switch input {
      case .text, .media: break
      default: throw ConversationMealEditInvalid.value
      }
    } else if kind == .reply {
      guard let input else { throw ConversationMealEditInvalid.value }
      switch input {
      case .quantity, .mealType: break
      default: throw ConversationMealEditInvalid.value
      }
    } else {
      try editCheck(input == nil)
    }
    let outcome = try o.required("outcome").object(
      required: ["status", "feedback"], optional: ["reason", "observed_question", "record"])
    guard let status = Status(rawValue: try outcome.required("status").string()) else {
      throw ConversationMealEditInvalid.value
    }
    let reason = try outcome["reason"].map { try $0.text(limit: 240) }
    let question = try outcome["observed_question"]?.optional { try parseQuestion($0) }
    let record = try outcome["record"].map {
      try parseRecord($0, command: command, kind: kind, id: parts, at: at, observedAt: observedAt)
    }
    try editCheck((status == .registered) == (record != nil))
    if kind == .intake && status == .registered { try editCheck(command != nil) }
    if status != .registered {
      try editCheck((try outcome.required("feedback").optional { _ in true }) == nil)
    }
    // Wrapper2 belongs to this closed schema3 boundary. Old request/echo2
    // negotiation remains unchanged elsewhere. A malformed optional wrapper
    // withholds commentary without erasing a factual registered event.
    let feedback = try? outcome.required("feedback").optional {
      value -> ConversationFeedbackPresentationSnapshot in
      let schema = try value.member("schema").string()
      if schema == "conversation.feedback-presentation.v2" {
        return ConversationFeedbackPresentationSnapshot(
          historicalProjection: try value.decode(ConversationFeedbackPresentationV2Snapshot.self))
      }
      try editCheck(schema == "conversation.feedback-presentation.v1")
      return try value.decode(ConversationFeedbackPresentationSnapshot.self)
    }
    var immutable = o
    immutable.removeValue(forKey: "outcome")
    if kind == .intake {
      // Selection is observed later than admission. Pin the original intake,
      // then let the model bind its one actual selected child exactly once.
      var stableLineage = l
      stableLineage.removeValue(forKey: "command_id")
      immutable["lineage"] = .object(stableLineage)
    }
    var facts = outcome
    facts.removeValue(forKey: "feedback")
    if kind == .report || kind == .intake {
      // The public service projects the CURRENT continuation question here,
      // not an immutable original decision or an answer lease.
      facts.removeValue(forKey: "observed_question")
    }
    return .init(
      eventID: id, at: at, threadID: thread, kind: kind, lineageKind: lineageKind, intakeID: intake,
      commandID: command, parentCommandID: parent, originEpoch: epoch, input: input, status: status,
      reason: reason, question: question, record: record, feedback: feedback ?? nil,
      immutablePin: try ConversationMealEditJSON.object(immutable).data(),
      outcomePin: try ConversationMealEditJSON.object(facts).data())
  }
  private static func parseInput(_ raw: ConversationMealEditJSON) throws -> Input {
    switch try raw.member("channel").string() {
    case "text":
      let o = try raw.object(["channel", "text"])
      return .text(try o.required("text").text(limit: 2000))
    case "media":
      let o = try raw.object(["channel", "caption"])
      return .media(caption: try o.required("caption").optional { try $0.text(limit: 2000) })
    case "structured":
      let o = try raw.object(["channel", "answer"])
      let a = try o.required("answer")
      if try a.member("kind").string() == "quantity" {
        let q = try a.object(["kind", "food_index", "amount", "unit"])
        let index = try q.required("food_index").revision()
        try editCheck(index < 30)
        return .quantity(
          foodIndex: index, amount: try q.required("amount").amount(max: 9999, positive: true),
          unit: try unit(q.required("unit")))
      }
      let q = try a.object(["kind", "meal_type"])
      try editCheck(q.required("kind").string() == "meal_type")
      return .mealType(try mealType(q.required("meal_type")))
    default: throw ConversationMealEditInvalid.value
    }
  }
  private static func unit(_ raw: ConversationMealEditJSON) throws -> String {
    let s = try raw.text(limit: 40)
    try editCheck(["g", "kg", "mL", "L", "unit", "scoop", "caneca"].contains(s))
    return s
  }
  private static func mealType(_ raw: ConversationMealEditJSON) throws -> String {
    let s = try raw.string()
    try editCheck(ConversationMealCommand.MealType(rawValue: s) != nil)
    return s
  }
  private static func parseQuestion(_ raw: ConversationMealEditJSON) throws -> Question {
    if (try? raw.member("field")) != nil {
      let o = try raw.object(["field", "text"])
      return .observed(
        field: try o.required("field").text(limit: 80),
        text: try o.required("text").text(limit: 1000))
    }
    let o = try raw.object([
      "kind", "food_index", "food_name", "allowed_units", "quantity_reference",
    ])
    let kind = try o.required("kind").string()
    let index = try o.required("food_index").optional { try $0.revision() }
    let name = try o.required("food_name").optional { try $0.text(limit: 160) }
    let units = try o.required("allowed_units").array().map { try unit($0) }
    try editCheck(Set(units).count == units.count && (index == nil || index! < 30))
    let reference = try o.required("quantity_reference").optional { value in
      let r = try value.object(["unit", "grams_per_unit", "reference_id", "estimated"])
      _ = try r.required("unit").string()
      _ = try r.required("grams_per_unit").amount(
        max: Double.greatestFiniteMagnitude, positive: true)
      _ = try r.required("reference_id").text(limit: 240)
      try editCheck(r.required("estimated").bool())
      return try value.decode(MealQuantityDisplay.self)
    }
    if kind == "meal_type" {
      try editCheck(index == nil && name == nil && units.isEmpty && reference == nil)
    } else {
      try editCheck(kind == "quantity" && index != nil && name != nil)
      let actual = MealQuantityDisplay.reference(for: name!)
      try editCheck(reference == actual)
      var expected = ["g", "kg"]
      if let actual {
        if actual.unit == "mL" {
          expected += ["mL", "L"]
          if actual.referenceID == "fao-infoods-v2-whole-milk-tb" { expected.append("caneca") }
        } else {
          expected.append(actual.unit)
        }
      }
      try editCheck(units == expected)
    }
    return .meal(kind: kind, foodIndex: index, foodName: name, units: units, reference: reference)
  }
  private static func parseRecord(
    _ raw: ConversationMealEditJSON, command: UUID?, kind: Kind, id: [String], at: String,
    observedAt: String
  ) throws -> Record {
    switch try raw.member("kind").string() {
    case "meal":
      try editCheck([Kind.intake, .report, .fulfillment].contains(kind))
      let o = try raw.object([
        "kind", "registration_id", "meal_type", "local_date", "log_ids", "effect_version",
      ])
      let effect = try o.required("effect_version").string()
      try editCheck(effect.range(of: "^cmeal1:[a-f0-9]{64}$", options: .regularExpression) != nil)
      return .meal(
        .init(
          registrationID: try o.required("registration_id").uuid(),
          mealType: try mealType(o.required("meal_type")),
          localDate: try o.required("local_date").civilDate(),
          logIDs: try o.required("log_ids").ids(nonempty: true), effectVersion: effect))
    case "workout":
      try editCheck(kind == .intake || kind == .workout)
      let o = try raw.object(["kind", "registration", "activity"])
      let r = try o.required("registration").object([
        "provenance", "registration_id", "workout_id", "performed_at", "local_date", "time_zone",
        "committed_at", "effect_version",
      ])
      let a = try o.required("activity").object([
        "kind", "log_id", "workout_type", "duration_min", "intensity", "estimated_kcal",
      ])
      let rid = try r.required("registration_id").uuid()
      let wid = try r.required("workout_id").uuid()
      try editCheck(
        rid == command && a.required("log_id").uuid() == wid
          && r.required("provenance").string() == "conversation.workout.v1"
          && r.required("effect_version").revision() == 1
          && a.required("kind").string() == "workout")
      let performed = try r.required("performed_at").clock()
      let committed = try r.required("committed_at").clock()
      try editCheck(
        ConversationProtocolInstant(performed)! <= ConversationProtocolInstant(committed)!
          && ConversationProtocolInstant(at)! <= ConversationProtocolInstant(committed)!
          && ConversationProtocolInstant(committed)! <= ConversationProtocolInstant(observedAt)!)
      let date = try r.required("local_date").civilDate()
      let zoneName = try r.required("time_zone").string()
      guard let zone = TimeZone(identifier: zoneName) else {
        throw ConversationMealEditInvalid.value
      }
      var cal = Calendar(identifier: .iso8601)
      cal.timeZone = zone
      let day = cal.dateComponents(
        [.year, .month, .day],
        from: Date(timeIntervalSince1970: Double(ConversationProtocolInstant(performed)!.seconds)))
      try editCheck(date == String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!))
      let duration = try a.required("duration_min").revision()
      try editCheck((1...1440).contains(duration))
      let intensity = try a.required("intensity").optional { try $0.string() }
      try editCheck(intensity == nil || ["leve", "moderada", "alta"].contains(intensity!))
      let energy = try a.required("estimated_kcal").optional { try $0.revision() }
      try editCheck(energy == nil || energy! <= 10000)
      return .workout(
        .init(
          registrationID: rid, workoutID: wid, performedAt: performed, localDate: date,
          timeZone: zoneName, committedAt: committed,
          workoutType: try a.required("workout_type").text(limit: 200), durationMin: duration,
          intensity: intensity, estimatedKcal: energy))
    case "meal_edit":
      try editCheck(kind == .edit)
      let o = try raw.object([
        "kind", "operation_id", "change", "revision", "applied_at", "target_operation_id",
        "removed_item_ids", "new_item_ids", "next_record_id",
      ])
      let operation = try o.required("operation_id").uuid()
      guard let change = Edit.Change(rawValue: try o.required("change").string()) else {
        throw ConversationMealEditInvalid.value
      }
      let revision = try o.required("revision").revision()
      let applied = try o.required("applied_at").clock()
      try editCheck(
        id[2] == operation.uuidString.lowercased()
          && revision > 0 && ConversationProtocolInstant(applied) == ConversationProtocolInstant(at)
      )
      let target = try o.required("target_operation_id").optional { try $0.uuid() }
      let removed = try o.required("removed_item_ids").ids(nonempty: true)
      let added = try o.required("new_item_ids").ids()
      let next = try o.required("next_record_id").optional { try $0.uuid() }
      try editCheck(Set(removed).isDisjoint(with: Set(added)))
      // Validate only public factual relationships. No missing Undo clock,
      // operation body, expected revision, hash or lease is reconstructed.
      switch change {
      case .saved:
        try editCheck(removed.count == 1 && !added.isEmpty && next == added.first && target == nil)
      case .saveUndone:
        try editCheck(
          revision >= 2 && target != nil && target != operation && added.count == 1
            && next == added.first)
      case .registrationUndone:
        try editCheck(revision == 1 && target == nil && added.isEmpty && next == nil)
      }
      return .edit(
        .init(
          operationID: operation, change: change, revision: revision, appliedAt: applied,
          targetOperationID: target, removedItemIDs: removed, newItemIDs: added, nextRecordID: next)
      )
    default: throw ConversationMealEditInvalid.value
    }
  }
}
