import Foundation

/// Read-only public v2 history. Child hashes are opaque SQL tokens: historical
/// JSONB is never turned into an original outbox body or a v1 meal command.
struct ConversationThreadPageSnapshot: Decodable, Sendable {
  struct Binding: Decodable, Equatable, Sendable {
    let ownerID: UUID
    let commandID: UUID
    let inputHash: String
    let commandProtocol: String
    let epoch: UUID
    let admittedAt: String
    var isChild: Bool { commandProtocol == "conversation.clarification.v1" }
    init(from decoder: any Decoder) throws {
      try self.init(ConversationMealEditJSON(from: decoder))
    }
    fileprivate init(_ raw: ConversationMealEditJSON, child: Bool? = nil) throws {
      let o = try raw.object([
        "owner_id", "command_id", "input_hash", "command_protocol", "kind", "epoch", "admitted_at",
      ])
      ownerID = try o.required("owner_id").uuid()
      commandID = try o.required("command_id").uuid()
      inputHash = try o.required("input_hash").hash()
      commandProtocol = try o.required("command_protocol").string()
      let kind = try o.required("kind").string()
      try editCheck(
        (commandProtocol == "conversation.command.v1" && kind == "meal.report")
          || (commandProtocol == "conversation.clarification.v1" && kind == "meal.clarify"))
      if let child { try editCheck((commandProtocol == "conversation.clarification.v1") == child) }
      epoch = try o.required("epoch").uuid()
      admittedAt = try threadClock(o.required("admitted_at"))
    }
  }
  struct Question: Sendable {
    let questionKey: String
    let revision: Int
    let kind: String
    let foodIndex: Int?
    let foodName: String?
    let allowedUnits: [String]
    let quantityReference: MealQuantityDisplay?
    fileprivate let originalJSON: Data
    func hasSameContent(as other: Self) -> Bool { originalJSON == other.originalJSON }
    fileprivate init(_ raw: ConversationMealEditJSON) throws {
      let o = try raw.object([
        "schema", "question_key", "revision", "kind", "food_index", "food_name", "allowed_units",
        "quantity_reference",
      ])
      try editCheck(o.required("schema").string() == "conversation.meal-question.v1")
      questionKey = try o.required("question_key").hash()
      revision = try o.required("revision").revision()
      kind = try o.required("kind").string()
      foodIndex = try o.required("food_index").optional { try threadFoodIndex($0) }
      foodName = try o.required("food_name").optional { value in
        let name = try value.text(limit: 160)
        try editCheck(
          !name.unicodeScalars.contains {
            ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
          })
        return name
      }
      allowedUnits = try o.required("allowed_units").array().map { try threadUnit($0) }
      try editCheck(Set(allowedUnits).count == allowedUnits.count)
      let originalFoodName = foodName
      quantityReference = try o.required("quantity_reference").optional { value in
        let r = try value.object(["unit", "grams_per_unit", "reference_id", "estimated"])
        _ = try r.required("unit").string()
        _ = try r.required("grams_per_unit").amount(
          max: Double.greatestFiniteMagnitude, positive: true)
        _ = try r.required("reference_id").text(limit: 240)
        try editCheck(r.required("estimated").bool())
        let reference = try value.decode(MealQuantityDisplay.self)
        guard let originalFoodName, reference.validated(for: originalFoodName) != nil else {
          throw ConversationMealEditInvalid.value
        }
        return reference
      }
      if kind == "meal_type" {
        try editCheck(
          foodIndex == nil && foodName == nil && allowedUnits.isEmpty && quantityReference == nil)
      } else {
        try editCheck(kind == "quantity" && foodIndex != nil && foodName != nil)
        let actualReference = foodName.flatMap { MealQuantityDisplay.reference(for: $0) }
        try editCheck(quantityReference == actualReference)
        var expected = ["g", "kg"]
        if let reference = actualReference {
          if reference.unit == "mL" {
            expected += ["mL", "L"]
            if reference.referenceID == "fao-infoods-v2-whole-milk-tb" { expected.append("caneca") }
          } else {
            expected.append(reference.unit)
          }
        }
        try editCheck(allowedUnits == expected)
      }
      originalJSON = try raw.data()
    }
  }
  struct ReplyBody: Sendable {
    enum Answer: Sendable {
      case quantity(foodIndex: Int, amount: Double, unit: String)
      case mealType(ConversationMealCommand.MealType)
    }
    let expectedRevision: Int
    let questionKey: String
    let answer: Answer
    fileprivate init(_ raw: ConversationMealEditJSON, question: Question) throws {
      try editCheck(raw.data().count <= 16_384)
      let o = try raw.object(["schema", "expected_revision", "question_key", "answer"])
      try editCheck(o.required("schema").string() == "conversation.meal-clarification.v1")
      expectedRevision = try o.required("expected_revision").revision()
      questionKey = try o.required("question_key").hash()
      try editCheck(expectedRevision == question.revision && questionKey == question.questionKey)
      let value = try o.required("answer")
      let kind = try value.member("kind").string()
      if kind == "quantity" {
        let a = try value.object(["kind", "food_index", "amount", "unit"])
        let index = try threadFoodIndex(a.required("food_index"))
        let unit = try threadUnit(a.required("unit"))
        try editCheck(
          question.kind == kind && index == question.foodIndex
            && question.allowedUnits.contains(unit))
        answer = try .quantity(
          foodIndex: index, amount: a.required("amount").amount(max: 9999, positive: true),
          unit: unit)
      } else {
        let a = try value.object(["kind", "meal_type"])
        guard kind == "meal_type", question.kind == kind,
          let meal = ConversationMealCommand.MealType(
            rawValue: try a.required("meal_type").string())
        else { throw ConversationMealEditInvalid.value }
        answer = .mealType(meal)
      }
    }
  }
  struct Continuation: Sendable {
    let revision: Int
    let question: Question?
    let fulfilledBy: UUID?
  }
  struct Thread: Sendable {
    let threadID: UUID
    let parentBinding: Binding
    let originalCommand: ConversationMealCommand
    let terminalReceipt: ConversationMealDecisionReceiptSnapshot?
    let continuation: Continuation?
  }
  /// Genuine continuation receipt; it cannot be passed to the v1 editor or ACK.
  struct LinkedReceipt: Decodable, Sendable {
    let ownerID: UUID
    let commandID: UUID
    let inputHash: String
    let registrationID: UUID
    let providerKey: String
    let mealType: ConversationMealCommand.MealType
    let localDate: String
    let timezone: String
    let consumedAt: String
    let logIDs: [UUID]
    let effectVersion: String
    let parentCommandID: UUID
    let parentInputHash: String
    let parentDecisionHash: String
    let epoch: UUID
    init(from decoder: any Decoder) throws {
      try self.init(ConversationMealEditJSON(from: decoder))
    }
    func matches(child: Binding, parent: Binding, decisionHash: String) -> Bool {
      child.isChild && !parent.isChild && child.ownerID == parent.ownerID
        && child.epoch == parent.epoch && ownerID == child.ownerID && epoch == child.epoch
        && commandID == child.commandID && commandID != parent.commandID
        && inputHash == child.inputHash && parentCommandID == parent.commandID
        && parentInputHash == parent.inputHash && parentDecisionHash == decisionHash
        && providerKey
          == "conversation.clarification/\(ownerID.uuidString.lowercased())/\(parent.commandID.uuidString.lowercased())"
        && ConversationProtocolInstant(consumedAt).map { consumed in
          guard let admitted = ConversationProtocolInstant(child.admittedAt),
            let original = ConversationProtocolInstant(parent.admittedAt)
          else { return false }
          return consumed >= admitted && admitted >= original
        } == true
    }
    func boundFeedback(
      _ value: ConversationFeedbackPresentationSnapshot?, binding: Binding,
      scope: ConversationFeedbackPresentationSnapshot.Scope
    ) -> ConversationFeedbackPresentationSnapshot.Bound? {
      guard binding.isChild, binding.ownerID == ownerID, binding.commandID == commandID,
        binding.inputHash == inputHash, binding.epoch == epoch,
        scope.ownerID == ownerID.uuidString.lowercased(),
        scope.epoch == epoch.uuidString.lowercased()
      else { return nil }
      return value?.bound(
        to: .init(
          scope: scope, commandID: commandID.uuidString.lowercased(),
          registrationID: registrationID.uuidString.lowercased(), localDate: localDate,
          mealKind: mealType.rawValue, logIDs: logIDs.map { $0.uuidString.lowercased() },
          admittedAt: binding.admittedAt), current: scope)
    }
    fileprivate init(_ raw: ConversationMealEditJSON) throws {
      let o = try raw.object([
        "schema", "owner_id", "command_id", "input_hash", "registration_id", "provider_key",
        "meal_type", "local_date", "timezone", "consumed_at", "log_ids", "effect_version",
        "parent_command_id", "parent_input_hash", "parent_decision_hash", "epoch",
      ])
      try editCheck(o.required("schema").string() == "conversation.meal-continuation-effect.v1")
      ownerID = try o.required("owner_id").uuid()
      commandID = try o.required("command_id").uuid()
      inputHash = try o.required("input_hash").hash()
      registrationID = try o.required("registration_id").uuid()
      providerKey = try o.required("provider_key").string()
      guard
        let meal = ConversationMealCommand.MealType(rawValue: try o.required("meal_type").string())
      else { throw ConversationMealEditInvalid.value }
      mealType = meal
      localDate = try o.required("local_date").civilDate()
      timezone = try o.required("timezone").text(limit: 240)
      consumedAt = try threadClock(o.required("consumed_at"))
      try threadLocalDate(localDate, timezone: timezone, clock: consumedAt)
      logIDs = try o.required("log_ids").ids(nonempty: true)
      effectVersion = try o.required("effect_version").string()
      try editCheck(effectVersion.hasPrefix("cmeal1:") && effectVersion.count == 71)
      _ = try ConversationMealEditJSON.string(String(effectVersion.dropFirst(7))).hash()
      parentCommandID = try o.required("parent_command_id").uuid()
      parentInputHash = try o.required("parent_input_hash").hash()
      parentDecisionHash = try o.required("parent_decision_hash").hash()
      epoch = try o.required("epoch").uuid()
    }
  }
  enum ReportStatus: String, Sendable {
    case pending, registered
    case notRecorded = "not_recorded"
  }
  struct Report: Sendable {
    let status: ReportStatus
    let receipt: SavedConversationMealCommandResultSnapshot.Receipt?
    let feedback: ConversationFeedbackPresentationSnapshot?
  }
  struct Reply: Sendable {
    let binding: Binding
    let body: ReplyBody
    let question: Question
  }
  struct ReplyResult: Sendable {
    let binding: Binding
    let preparedHash: String
    let status: String
    let nextQuestion: Question?
  }
  struct Fulfillment: Sendable {
    let binding: Binding
    let receipt: LinkedReceipt
    let feedback: ConversationFeedbackPresentationSnapshot?
  }
  struct Edit: Sendable {
    let binding: Binding
    let receipt: ConversationMealEditEffectSnapshot
  }
  struct Entry: Sendable {
    enum Detail: Sendable {
      case report(Report)
      case reply(Reply)
      case replyResult(ReplyResult)
      case fulfillment(Fulfillment)
      case edit(Edit)
    }
    let eventID: String
    let at: String
    let threadID: UUID
    let detail: Detail
    /// RAM cache consistency only, not an input/source/prepared/SQL proof hash.
    /// Current clinical feedback is deliberately excluded from this pin.
    let readConsistencyDigest: String
    var reportStatus: ReportStatus? {
      if case .report(let value) = detail { return value.status }
      return nil
    }
    var childBinding: Binding? {
      switch detail {
      case .reply(let v): v.binding
      case .replyResult(let v): v.binding
      case .fulfillment(let v): v.binding
      case .edit(let v): v.binding.isChild ? v.binding : nil
      case .report: nil
      }
    }
  }
  struct Envelope: Decodable, Sendable {
    let data: ConversationThreadPageSnapshot
    let meta: MobileResponseMetadata
    init(data: Data) throws {
      try editCheck(data.count <= 262_144)
      self = try JSONDecoder().decode(Self.self, from: data)
    }
    init(from decoder: any Decoder) throws {
      let raw = try ConversationMealEditJSON(from: decoder)
      try editCheck(raw.data().count <= 262_144)
      let o = try raw.object(["data", "meta"])
      let m = try o.required("meta").object(["api_version", "request_id"])
      try editCheck(m.required("api_version").string() == "v1")
      _ = try m.required("request_id").text(limit: 262_144)
      meta = try o.required("meta").decode(MobileResponseMetadata.self)
      data = try o.required("data").decode(ConversationThreadPageSnapshot.self)
    }
  }
  let authUserID: UUID
  let ownerID: UUID
  let epoch: UUID
  let observedAt: String
  let threads: [Thread]
  let items: [Entry]
  let hasMore: Bool
  let nextCursor: String?
  init(data: Data) throws {
    try editCheck(data.count <= 240_000)
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      try editCheck(raw.data().count <= 240_000)
      let o = try raw.object([
        "schema", "auth_user_id", "owner_id", "epoch", "observed_at", "threads", "items",
        "has_more", "next_cursor",
      ])
      try editCheck(o.required("schema").string() == "conversation.journal-page.v2")
      authUserID = try o.required("auth_user_id").uuid()
      ownerID = try o.required("owner_id").uuid()
      epoch = try o.required("epoch").uuid()
      observedAt = try threadClock(o.required("observed_at"))
      let rawThreads = try o.required("threads").array()
      let rawItems = try o.required("items").array()
      try editCheck(rawThreads.count <= 25 && rawItems.count <= 25)
      let owner = ownerID
      let epoch = epoch
      let observed = observedAt
      threads = try rawThreads.map {
        try Self.thread($0, owner: owner, epoch: epoch, observed: observed)
      }
      try editCheck(Set(threads.map(\.threadID)).count == threads.count)
      for (a, b) in zip(threads, threads.dropFirst()) {
        try editCheck(a.threadID.uuidString.lowercased() < b.threadID.uuidString.lowercased())
      }
      let byID = Dictionary(uniqueKeysWithValues: threads.map { ($0.threadID, $0) })
      items = try rawItems.map { raw in
        let id = try raw.member("thread_id").uuid()
        guard let parent = byID[id] else { throw ConversationMealEditInvalid.value }
        return try Self.entry(raw, parent: parent, owner: owner, epoch: epoch, observed: observed)
      }
      try editCheck(
        Set(items.map(\.eventID)).count == items.count
          && Set(items.map(\.threadID)) == Set(byID.keys))
      var children: [UUID: (UUID, Binding)] = [:]
      for item in items {
        if let child = item.childBinding {
          try editCheck(byID[child.commandID] == nil)
          if let previous = children[child.commandID] {
            try editCheck(previous.0 == item.threadID && previous.1 == child)
          }
          children[child.commandID] = (item.threadID, child)
        }
      }
      for (previous, next) in zip(items, items.dropFirst()) {
        let a = try editInstant(previous.at)
        let b = try editInstant(next.at)
        try editCheck(
          a > b || (a == b && next.eventID.utf8.lexicographicallyPrecedes(previous.eventID.utf8)))
      }
      for item in items {
        if case .fulfillment(let fulfillment) = item.detail {
          for related in items
          where related.childBinding?.commandID == fulfillment.binding.commandID {
            if case .replyResult(let prepared) = related.detail {
              try editCheck(
                prepared.status == "prepared" && editInstant(related.at) <= editInstant(item.at))
            }
          }
        }
        if case .replyResult(let result) = item.detail, let question = result.nextQuestion {
          for related in items where related.childBinding?.commandID == result.binding.commandID {
            if case .reply(let reply) = related.detail {
              try editCheck(question.revision == reply.body.expectedRevision + 1)
            }
          }
        }
      }
      hasMore = try o.required("has_more").bool()
      nextCursor = try o.required("next_cursor").optional { value in
        let s = try value.text(limit: 1024)
        try editCheck(s.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil)
        return s
      }
      try editCheck(hasMore ? (!items.isEmpty && nextCursor != nil) : nextCursor == nil)
      if let nextCursor, let last = items.last {
        // Verify only the closed public anchor framing; retain the opaque bytes.
        // This neither grants a read/write capability nor creates a new cursor.
        let canonical =
          "{\"v\":2,\"owner_id\":\"\(ownerID.uuidString.lowercased())\",\"epoch\":\"\(epoch.uuidString.lowercased())\",\"at\":\"\(last.at)\",\"id\":\"\(last.eventID)\"}"
        let expected = Data(canonical.utf8).base64EncodedString()
          .replacingOccurrences(of: "+", with: "-")
          .replacingOccurrences(of: "/", with: "_")
          .replacingOccurrences(of: "=", with: "")
        try editCheck(nextCursor == expected)
      }
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Linked conversation history unavailable"))
    }
  }
  func matches(authUserID: UUID, ownerID: UUID, epoch: UUID) -> Bool {
    self.authUserID == authUserID && self.ownerID == ownerID && self.epoch == epoch
  }
  func thread(_ id: UUID) -> Thread? { threads.first { $0.threadID == id } }

  private static func thread(
    _ raw: ConversationMealEditJSON, owner: UUID, epoch: UUID, observed: String
  ) throws -> Thread {
    let o = try raw.object([
      "schema", "thread_id", "parent_binding", "original_command", "terminal_receipt",
      "continuation",
    ])
    try editCheck(o.required("schema").string() == "conversation.meal-thread.v1")
    let id = try o.required("thread_id").uuid()
    let binding = try Binding(o.required("parent_binding"), child: false)
    let command = try ConversationMealCommand(wireBody: o.required("original_command").data())
    try editCheck(
      id == binding.commandID && binding.ownerID == owner && binding.epoch == epoch
        && command.commandID == id && command.inputHash == binding.inputHash)
    try threadBetween(binding.admittedAt, binding.admittedAt, observed)
    let terminal = try o.required("terminal_receipt").optional { value in
      let d = try value.decode(ConversationMealDecisionReceiptSnapshot.self)
      _ = try threadClock(value.member("sealed_at"))
      try editCheck(
        d.ownerID == owner && d.commandID == id && d.originalInputHash == binding.inputHash
          && d.epoch == epoch)
      try threadBetween(d.sealedAt, binding.admittedAt, observed)
      return d
    }
    let continuation = try o.required("continuation").optional { value in
      let h = try value.object(["revision", "question", "fulfilled_by"])
      let revision = try h.required("revision").revision()
      let question = try h.required("question").optional { try Question($0) }
      let fulfilled = try h.required("fulfilled_by").optional { try $0.uuid() }
      try editCheck(
        revision <= 31 && terminal != nil && fulfilled != id
          && ((fulfilled == nil) == (question != nil))
          && (question == nil || question?.revision == revision))
      return Continuation(revision: revision, question: question, fulfilledBy: fulfilled)
    }
    return .init(
      threadID: id, parentBinding: binding, originalCommand: command, terminalReceipt: terminal,
      continuation: continuation)
  }
  private static func entry(
    _ raw: ConversationMealEditJSON, parent: Thread, owner: UUID, epoch: UUID, observed: String
  ) throws -> Entry {
    let kind = try raw.member("kind").string()
    let base: Set<String> = ["event_id", "at", "kind", "thread_id"]
    let fields: Set<String>
    switch kind {
    case "report": fields = ["status", "receipt", "feedback"]
    case "reply": fields = ["child_binding", "body", "question"]
    case "reply_result": fields = ["child_binding", "prepared_hash", "status", "next_question"]
    case "fulfillment": fields = ["child_binding", "receipt", "feedback"]
    case "edit": fields = ["effect_binding", "receipt"]
    default: throw ConversationMealEditInvalid.value
    }
    let o = try raw.object(base.union(fields))
    let id = try o.required("event_id").string()
    let at = try threadClock(o.required("at"))
    try threadBetween(at, parent.parentBinding.admittedAt, observed)
    let prefix = parent.threadID.uuidString.lowercased()
    func child(_ value: ConversationMealEditJSON) throws -> Binding {
      let b = try Binding(value, child: true)
      guard let terminal = parent.terminalReceipt, parent.continuation != nil else {
        throw ConversationMealEditInvalid.value
      }
      try editCheck(b.ownerID == owner && b.epoch == epoch && b.commandID != parent.threadID)
      try threadBetween(b.admittedAt, terminal.sealedAt, observed)
      return b
    }
    let detail: Entry.Detail
    switch kind {
    case "report":
      guard let status = ReportStatus(rawValue: try o.required("status").string()) else {
        throw ConversationMealEditInvalid.value
      }
      let receipt = try o.required("receipt").optional {
        try $0.decode(SavedConversationMealCommandResultSnapshot.Receipt.self)
      }
      try editCheck(
        id == "command/\(prefix)" && at == parent.parentBinding.admittedAt
          && (status == .registered) == (receipt != nil)
          && (status == .notRecorded) == (parent.terminalReceipt != nil))
      var feedback: ConversationFeedbackPresentationSnapshot?
      if let r = receipt {
        try editCheck(
          r.ownerID == owner.uuidString.lowercased() && r.commandID == prefix
            && r.inputHash == parent.parentBinding.inputHash)
        if let meal = parent.originalCommand.mealType { try editCheck(r.mealType == meal) }
        _ = try threadClock(.string(r.consumedAt))
        try threadBetween(r.consumedAt, at, observed)
        feedback = try optionalFeedback(
          o.required("feedback"), owner: owner, epoch: epoch, binding: parent.parentBinding,
          registrationID: r.registrationID, date: r.localDate, meal: r.mealType, logs: r.logIDs,
          observed: observed)
      } else {
        if case .null = try o.required("feedback") {
        } else {
          throw ConversationMealEditInvalid.value
        }
      }
      detail = .report(.init(status: status, receipt: receipt, feedback: feedback))
    case "reply":
      let b = try child(o.required("child_binding"))
      let q = try Question(o.required("question"))
      let body = try ReplyBody(o.required("body"), question: q)
      guard let head = parent.continuation else { throw ConversationMealEditInvalid.value }
      try editCheck(
        id == "reply/\(prefix)/\(b.commandID.uuidString.lowercased())" && at == b.admittedAt
          && body.expectedRevision <= head.revision)
      if body.expectedRevision == head.revision {
        try editCheck(head.question?.originalJSON == q.originalJSON)
      }
      detail = .reply(.init(binding: b, body: body, question: q))
    case "reply_result":
      let b = try child(o.required("child_binding"))
      let hash = try o.required("prepared_hash").hash()
      let status = try o.required("status").string()
      let next = try o.required("next_question").optional { try Question($0) }
      try editCheck(
        id == "reply-result/\(prefix)/\(b.commandID.uuidString.lowercased())"
          && ["prepared", "needs_reply"].contains(status)
          && (status == "needs_reply") == (next != nil))
      if let next { try editCheck(next.revision <= (parent.continuation?.revision ?? -1)) }
      try threadBetween(at, b.admittedAt, observed)
      detail = .replyResult(
        .init(binding: b, preparedHash: hash, status: status, nextQuestion: next))
    case "fulfillment":
      let b = try child(o.required("child_binding"))
      let r = try LinkedReceipt(o.required("receipt"))
      guard let terminal = parent.terminalReceipt else { throw ConversationMealEditInvalid.value }
      try editCheck(
        id == "fulfillment/\(prefix)/\(b.commandID.uuidString.lowercased())"
          && parent.continuation?.fulfilledBy == b.commandID
          && r.matches(child: b, parent: parent.parentBinding, decisionHash: terminal.decisionHash)
          && at == r.consumedAt)
      if let meal = parent.originalCommand.mealType { try editCheck(r.mealType == meal) }
      try threadBetween(at, b.admittedAt, observed)
      let feedback = try optionalFeedback(
        o.required("feedback"), owner: owner, epoch: epoch, binding: b,
        registrationID: r.registrationID.uuidString.lowercased(), date: r.localDate,
        meal: r.mealType, logs: r.logIDs.map { $0.uuidString.lowercased() }, observed: observed)
      detail = .fulfillment(.init(binding: b, receipt: r, feedback: feedback))
    default:
      let b = try Binding(o.required("effect_binding"))
      let r = try o.required("receipt").decode(ConversationMealEditEffectSnapshot.self)
      if b.isChild {
        _ = try child(o.required("effect_binding"))
        try editCheck(parent.continuation?.fulfilledBy == b.commandID)
      } else {
        try editCheck(b == parent.parentBinding && parent.terminalReceipt == nil)
      }
      try editCheck(
        id == "edit/\(b.commandID.uuidString.lowercased())/\(r.operationID.uuidString.lowercased())"
          && r.ownerID == owner && r.commandID == b.commandID
          && editInstant(at) == editInstant(r.appliedAt))
      try threadBetween(at, b.admittedAt, observed)
      detail = .edit(.init(binding: b, receipt: r))
    }
    var immutable = o
    immutable.removeValue(forKey: "feedback")
    let pin = try ConversationMealCommand.digest(ConversationMealEditJSON.object(immutable).data())
    return .init(
      eventID: id, at: at, threadID: parent.threadID, detail: detail, readConsistencyDigest: pin)
  }
  private static func optionalFeedback(
    _ raw: ConversationMealEditJSON, owner: UUID, epoch: UUID, binding: Binding,
    registrationID: String, date: String, meal: ConversationMealCommand.MealType, logs: [String],
    observed: String
  ) throws -> ConversationFeedbackPresentationSnapshot? {
    guard let bytes = try? raw.data(), bytes.count <= 200_000,
      let value = try? JSONDecoder().decode(
        ConversationFeedbackPresentationSnapshot.self, from: bytes),
      let instant = ConversationProtocolInstant(value.provenance.observedAt),
      instant <= (try editInstant(observed))
    else { return nil }
    guard binding.ownerID == owner, value.provenance.epoch == epoch.uuidString.lowercased(),
      value.provenance.commandID == binding.commandID.uuidString.lowercased(),
      value.original.registrationID == registrationID, value.original.localDate == date,
      instant >= (try editInstant(binding.admittedAt))
    else { return nil }
    if case .sections(let recorded, _) = value.content {
      guard recorded.mealKind == meal.rawValue, Set(recorded.items.map(\.logID)) == Set(logs) else {
        return nil
      }
    }
    return value
  }
}

private func threadClock(_ raw: ConversationMealEditJSON) throws -> String {
  let value = try raw.clock()
  try editCheck(
    value.range(
      of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$",
      options: .regularExpression) != nil)
  return value
}
private func threadFoodIndex(_ raw: ConversationMealEditJSON) throws -> Int {
  let n = try raw.amount(max: 29)
  try editCheck(n.rounded() == n)
  return Int(n)
}
private func threadUnit(_ raw: ConversationMealEditJSON) throws -> String {
  let s = try raw.string()
  try editCheck(["g", "kg", "mL", "L", "unit", "scoop", "caneca"].contains(s))
  return s
}
private func threadBetween(_ value: String, _ low: String, _ high: String) throws {
  try editCheck(editInstant(value) >= editInstant(low) && editInstant(value) <= editInstant(high))
}
private func threadLocalDate(_ date: String, timezone: String, clock: String) throws {
  guard let zone = TimeZone(identifier: timezone) else { throw ConversationMealEditInvalid.value }
  var calendar = Calendar(identifier: .iso8601)
  calendar.timeZone = zone
  let instant = try editInstant(clock)
  let components = calendar.dateComponents(
    [.year, .month, .day], from: Date(timeIntervalSince1970: Double(instant.seconds)))
  guard let y = components.year, let m = components.month, let d = components.day else {
    throw ConversationMealEditInvalid.value
  }
  try editCheck(date == String(format: "%04d-%02d-%02d", y, m, d))
}
