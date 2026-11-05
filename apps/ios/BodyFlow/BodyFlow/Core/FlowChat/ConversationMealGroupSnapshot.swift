import Foundation

/// Factual server observation only. Actions remain server-owned; decoding does
/// not grant a session lease, determine eligibility from device time or write.
struct ConversationMealGroupSnapshot: Decodable, Sendable {
  /// The group keeps the genuine original receipt. A clarification effect is
  /// never converted to a report effect or used as a report outbox ACK.
  enum OriginalReceipt: Sendable {
    case report(SavedConversationMealCommandResultSnapshot.Receipt)
    case linked(ConversationThreadPageSnapshot.LinkedReceipt)
    var report: SavedConversationMealCommandResultSnapshot.Receipt? {
      if case .report(let value) = self { return value }
      return nil
    }
    var linked: ConversationThreadPageSnapshot.LinkedReceipt? {
      if case .linked(let value) = self { return value }
      return nil
    }
    var ownerID: String {
      switch self {
      case .report(let value): value.ownerID
      case .linked(let value): value.ownerID.uuidString.lowercased()
      }
    }
    var commandID: String {
      switch self {
      case .report(let value): value.commandID
      case .linked(let value): value.commandID.uuidString.lowercased()
      }
    }
    var inputHash: String {
      switch self {
      case .report(let value): value.inputHash
      case .linked(let value): value.inputHash
      }
    }
    var registrationID: String {
      switch self {
      case .report(let value): value.registrationID
      case .linked(let value): value.registrationID.uuidString.lowercased()
      }
    }
    var providerKey: String {
      switch self {
      case .report(let value): value.providerKey
      case .linked(let value): value.providerKey
      }
    }
    var consumedAt: String {
      switch self {
      case .report(let value): value.consumedAt
      case .linked(let value): value.consumedAt
      }
    }
    var localDate: String {
      switch self {
      case .report(let value): value.localDate
      case .linked(let value): value.localDate
      }
    }
  }
  struct Item: Sendable {
    let id: UUID
    let foodName: String
    let quantityG: Double?
    let quantityDisplay: MealQuantityDisplay?
    let kcal: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let source: String?
    let consumedAt: String
    let mealType: ConversationMealCommand.MealType?
  }
  struct Current: Sendable {
    let expectedVersion: String
    let localDate: String
    let timezone: String?
    let dayClosed: Bool
    let items: [Item]
  }
  struct Availability: Sendable {
    enum Reason: String, Sendable {
      case currentGroupUnavailable = "current_group_unavailable"
      case dayClosed = "day_closed"
      case notCurrentDay = "not_current_day"
      case invalidTimezone = "invalid_timezone"
      case revisionExhausted = "revision_exhausted"
      case versionChanged = "version_changed"
      case undoExpired = "undo_expired"
      case noSaveToUndo = "no_save_to_undo"
    }
    let allowed: Bool
    let reason: Reason?
    fileprivate init(_ raw: ConversationMealEditJSON) throws {
      let allowed = try raw.member("allowed").bool()
      let o = try raw.object(allowed ? ["allowed"] : ["allowed", "reason"])
      self.allowed = allowed
      if allowed {
        reason = nil
      } else {
        guard let reason = Reason(rawValue: try o.required("reason").string()) else {
          throw ConversationMealEditInvalid.value
        }
        self.reason = reason
      }
    }
  }
  struct Actions: Sendable {
    let save: Availability
    let undoRegistration: Availability
    let undoSave: Availability
  }
  let ownerID: UUID
  let commandID: UUID
  let originalInputHash: String
  let epoch: UUID
  let admittedAt: String
  let observedAt: String
  let originalReceipt: OriginalReceipt
  let revision: Int
  let lineageCompatible: Bool
  let current: Current?
  let lastOperation: ConversationMealEditEffectSnapshot?
  let registrationUndoExpiresAt: String
  let actions: Actions

  init(data: Data) throws {
    guard data.count <= 65_536 else { throw ConversationMealEditInvalid.value }
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  init(from decoder: any Decoder) throws {
    do {
      let raw = try ConversationMealEditJSON(from: decoder)
      try raw.boundPublicPacket()
      let o = try raw.object([
        "schema", "owner_id", "command_id", "input_hash", "epoch", "admitted_at", "observed_at",
        "original_receipt", "revision", "lineage_compatible", "current", "last_operation",
        "registration_undo_expires_at", "actions",
      ])
      let schema = try o.required("schema").string()
      try editCheck(["conversation.meal-group.v1", "conversation.meal-group.v2"].contains(schema))
      ownerID = try o.required("owner_id").uuid()
      commandID = try o.required("command_id").uuid()
      originalInputHash = try o.required("input_hash").hash()
      epoch = try o.required("epoch").uuid()
      admittedAt = try o.required("admitted_at").clock()
      observedAt = try o.required("observed_at").clock()
      if schema == "conversation.meal-group.v1" {
        originalReceipt = try .report(
          o.required("original_receipt").decode(
            SavedConversationMealCommandResultSnapshot.Receipt.self))
      } else {
        originalReceipt = try .linked(
          o.required("original_receipt").decode(
            ConversationThreadPageSnapshot.LinkedReceipt.self))
      }
      try editCheck(
        originalReceipt.ownerID == ownerID.uuidString.lowercased()
          && originalReceipt.commandID == commandID.uuidString.lowercased()
          && originalReceipt.inputHash == originalInputHash)
      try editCheck(
        editInstant(admittedAt) <= editInstant(originalReceipt.consumedAt)
          && editInstant(originalReceipt.consumedAt) <= editInstant(observedAt))
      revision = try o.required("revision").revision()
      lineageCompatible = try o.required("lineage_compatible").bool()
      current = try o.required("current").optional(Self.parseCurrent)
      if let current { try editCheck(current.localDate == originalReceipt.localDate) }
      lastOperation = try o.required("last_operation").optional {
        try $0.decode(ConversationMealEditEffectSnapshot.self)
      }
      try editCheck((revision == 0) == (lastOperation == nil))
      if let last = lastOperation {
        try editCheck(
          last.ownerID == ownerID && last.commandID == commandID && last.revision == revision
            && editInstant(last.appliedAt) <= editInstant(observedAt)
            && editInstant(last.appliedAt) >= editInstant(admittedAt))
      }
      registrationUndoExpiresAt = try o.required("registration_undo_expires_at").clock()
      if let receipt = originalReceipt.linked {
        try editCheck(
          receipt.epoch == epoch && receipt.parentCommandID != commandID
            && receipt.providerKey
              == "conversation.clarification/\(ownerID.uuidString.lowercased())/\(receipt.parentCommandID.uuidString.lowercased())"
        )
        let consumed = try editInstant(receipt.consumedAt)
        let deadline = try editInstant(registrationUndoExpiresAt)
        try editCheck(
          deadline.seconds - consumed.seconds == 300 && deadline.nanos == consumed.nanos)
      }
      let a = try o.required("actions").object(["save", "undo_registration", "undo_save"])
      actions = try Actions(
        save: Availability(a.required("save")),
        undoRegistration: Availability(a.required("undo_registration")),
        undoSave: Availability(a.required("undo_save")))
    } catch { throw editDecodeFailure(decoder) }
  }
  private static func parseCurrent(_ raw: ConversationMealEditJSON) throws -> Current {
    let o = try raw.object(["expected_version", "local_date", "timezone", "day_closed", "items"])
    let rows = try o.required("items").array()
    try editCheck((1...30).contains(rows.count))
    let items = try rows.map(parseItem)
    try editCheck(Set(items.map(\.id)).count == items.count)
    return try Current(
      expectedVersion: o.required("expected_version").version(),
      localDate: o.required("local_date").civilDate(),
      timezone: o.required("timezone").optional { try $0.string() },
      dayClosed: o.required("day_closed").bool(), items: items)
  }
  private static func parseItem(_ raw: ConversationMealEditJSON) throws -> Item {
    let o = try raw.object([
      "id", "food_name", "quantity_g", "quantity_display", "kcal", "protein_g", "carbs_g", "fat_g",
      "source", "consumed_at", "meal_type",
    ])
    let name = try o.required("food_name").text(limit: 240)
    let metadata: MealQuantityDisplay? = try o.required("quantity_display").optional { value in
      let m = try value.object(["unit", "grams_per_unit", "reference_id", "estimated"])
      let unit = try m.required("unit").string()
      try editCheck(["mL", "unit", "scoop"].contains(unit) && m.required("estimated").bool())
      let factor = try m.required("grams_per_unit").amount(
        min: 0, max: 9_007_199_254_740_991, positive: true)
      let reference = try m.required("reference_id").text(limit: 240)
      let candidate = MealQuantityDisplay(
        unit: unit, gramsPerUnit: try editDecimal(factor), referenceID: reference, estimated: true)
      guard let valid = candidate.validated(for: name) else {
        throw ConversationMealEditInvalid.value
      }
      return valid
    }
    let meal: ConversationMealCommand.MealType? = try o.required("meal_type").optional { value in
      guard let meal = ConversationMealCommand.MealType(rawValue: try value.string()) else {
        throw ConversationMealEditInvalid.value
      }
      return meal
    }
    return try Item(
      id: o.required("id").uuid(), foodName: name,
      quantityG: o.required("quantity_g").optional {
        try $0.amount(min: 0, max: 9999, positive: true)
      }, quantityDisplay: metadata,
      kcal: o.required("kcal").optional { try $0.amount() },
      proteinG: o.required("protein_g").optional { try $0.amount() },
      carbsG: o.required("carbs_g").optional { try $0.amount() },
      fatG: o.required("fat_g").optional { try $0.amount() },
      source: o.required("source").optional { try $0.text(limit: 80) },
      consumedAt: o.required("consumed_at").clock(), mealType: meal)
  }
}

// Shared closed raw reader for these three Foundation leaves. It rejects unknown
// fields, JSON booleans masquerading as numbers and non-finite numeric values.
enum ConversationMealEditInvalid: Error { case value }
func editCheck(_ value: Bool) throws { if !value { throw ConversationMealEditInvalid.value } }
func editDecodeFailure(_ decoder: any Decoder) -> DecodingError {
  .dataCorrupted(
    .init(codingPath: decoder.codingPath, debugDescription: "Conversation meal edit unavailable"))
}
func editInstant(_ raw: String) throws -> ConversationProtocolInstant {
  guard let result = ConversationProtocolInstant(raw) else {
    throw ConversationMealEditInvalid.value
  }
  return result
}
func editDecimal(_ number: Double) throws -> Decimal {
  guard number.isFinite,
    let decimal = Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")),
    !decimal.isNaN
  else { throw ConversationMealEditInvalid.value }
  return decimal
}
func editECMATrim(_ s: String) -> String {
  let values = s.unicodeScalars
  func blank(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 9...13, 32, 160, 5760, 8192...8202, 8232, 8233, 8239, 8287, 12288, 65279: true
    default: false
    }
  }
  return String(
    String.UnicodeScalarView(values.drop(while: blank).reversed().drop(while: blank).reversed()))
}
indirect enum ConversationMealEditJSON: Codable {
  case object([String: Self])
  case array([Self])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  init(from decoder: any Decoder) throws {
    guard decoder.codingPath.count <= 64 else { throw ConversationMealEditInvalid.value }
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let n = try? c.decode(Double.self) {
      try editCheck(n.isFinite)
      // JSON numbers at the server boundary are IEEE754. Equivalent
      // lexical exponent spellings retain the same numeric intent.
      self = .number(n)
    } else if let s = try? c.decode(String.self) {
      try editCheck(!s.unicodeScalars.contains { $0.value == 0 })
      self = .string(s)
    } else if let a = try? c.decode([Self].self) {
      self = .array(a)
    } else {
      let o = try decoder.container(keyedBy: Key.self)
      self = .object(
        try Dictionary(
          uniqueKeysWithValues: o.allKeys.map {
            ($0.stringValue, try o.decode(Self.self, forKey: $0))
          }))
    }
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  func data() throws -> Data {
    let e = JSONEncoder()
    e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return try e.encode(self)
  }
  func decode<T: Decodable>(
    _ type: T.Type, selection: ConversationFeedbackPresentationSelection? = nil
  ) throws -> T {
    try ConversationFeedbackPresentationSelection.decoder(selection: selection).decode(type, from: data())
  }
  func boundPublicPacket() throws { try editCheck(data().count <= 65_536) }
  func object(_ keys: Set<String>) throws -> [String: Self] {
    guard case .object(let v) = self, Set(v.keys) == keys else {
      throw ConversationMealEditInvalid.value
    }
    return v
  }
  func object(required: Set<String>, optional: Set<String>) throws -> [String: Self] {
    guard case .object(let v) = self, required.isSubset(of: Set(v.keys)),
      Set(v.keys).isSubset(of: required.union(optional))
    else { throw ConversationMealEditInvalid.value }
    return v
  }
  func member(_ key: String) throws -> Self {
    guard case .object(let o) = self else { throw ConversationMealEditInvalid.value }
    return try o.required(key)
  }
  func array() throws -> [Self] {
    guard case .array(let v) = self else { throw ConversationMealEditInvalid.value }
    return v
  }
  func string() throws -> String {
    guard case .string(let v) = self else { throw ConversationMealEditInvalid.value }
    return v
  }
  func bool() throws -> Bool {
    guard case .bool(let v) = self else { throw ConversationMealEditInvalid.value }
    return v
  }
  func uuid() throws -> UUID {
    let s = try string()
    guard
      s.range(
        of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        options: .regularExpression) != nil, let id = UUID(uuidString: s)
    else { throw ConversationMealEditInvalid.value }
    return id
  }
  func hash() throws -> String {
    let s = try string()
    try editCheck(s.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
    return s
  }
  func version() throws -> String {
    let s = try string()
    try editCheck(s.range(of: "^v1:[0-9a-f]{64}$", options: .regularExpression) != nil)
    return s
  }
  func clock() throws -> String {
    let s = try string()
    _ = try editInstant(s)
    return s
  }
  func civilDate() throws -> String {
    let s = try string()
    try editCheck(s.utf8.count == 10)
    _ = try editInstant(s + "T00:00:00Z")
    return s
  }
  func text(limit: Int) throws -> String {
    let s = try string()
    try editCheck(!s.isEmpty && s.utf16.count <= limit && !editECMATrim(s).isEmpty)
    return s
  }
  func amount(min: Double = 0, max: Double = 9_007_199_254_740_991, positive: Bool = false) throws
    -> Double
  {
    guard case .number(let n) = self, n.isFinite, n >= min, n <= max, !positive || n > 0 else {
      throw ConversationMealEditInvalid.value
    }
    return n
  }
  func revision() throws -> Int {
    let n = try amount(max: 2_147_483_647)
    try editCheck(n.rounded() == n)
    return Int(n)
  }
  func optional<T>(_ parse: (Self) throws -> T) throws -> T? {
    if case .null = self { return nil }
    return try parse(self)
  }
  func ids(nonempty: Bool = false) throws -> [UUID] {
    let rows = try array()
    try editCheck(rows.count <= 30 && (!nonempty || !rows.isEmpty))
    let ids = try rows.map { try $0.uuid() }
    try editCheck(Set(ids).count == ids.count)
    return ids
  }
}
extension Dictionary where Key == String, Value == ConversationMealEditJSON {
  func required(_ key: String) throws -> Value {
    guard let v = self[key] else { throw ConversationMealEditInvalid.value }
    return v
  }
}
