import Foundation

/// Immutable edit intent. Patient/command/hash/epoch are original transport
/// preconditions only; none is injected into the closed calculation body.
struct ConversationMealEditOperation: Sendable, CustomStringConvertible, CustomReflectable {
  struct Item: Sendable {
    enum QuantityBasis: String, Sendable {
      case stated
      case visualEstimate = "visual_estimate"
      case portionReference = "portion_reference"
    }
    let foodName: String
    let quantityG: Decimal
    let userKcal: Decimal?
    let quantityBasis: QuantityBasis?
    let candidateID: String?
    init(
      foodName: String, quantityG: Decimal, userKcal: Decimal? = nil,
      quantityBasis: QuantityBasis? = nil, candidateID: String? = nil
    ) throws {
      try Self.validateName(foodName)
      let grams = try Self.number(quantityG)
      try editCheck(grams > 0 && grams <= 9999)
      if let userKcal {
        let kcal = try Self.number(userKcal)
        try editCheck(kcal >= 0 && kcal <= 20000)
      }
      if let candidateID {
        try editCheck(
          candidateID.range(of: "^c[0-9]{1,2}-[0-9a-f]{8}$", options: .regularExpression) != nil)
      }
      self.foodName = foodName
      self.quantityG = quantityG
      self.userKcal = userKcal
      self.quantityBasis = quantityBasis
      self.candidateID = candidateID
    }
    private static func validateName(_ s: String) throws {
      try editCheck(
        !s.isEmpty && s.utf16.count <= 160 && !editECMATrim(s).isEmpty && !s.hasPrefix(" ")
          && !s.hasSuffix(" ")
          && !s.unicodeScalars.contains {
            ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
          })
    }
    fileprivate static func number(_ decimal: Decimal) throws -> Double {
      guard let n = Double(NSDecimalNumber(decimal: decimal).stringValue) else {
        throw ConversationMealEditInvalid.value
      }
      try editCheck(!decimal.isNaN && n.isFinite && decimal == editDecimal(n))
      return n
    }
    fileprivate func json() throws -> ConversationMealEditJSON {
      var value: [String: ConversationMealEditJSON] = [
        "food_name": .string(foodName), "quantity_g": .number(try Self.number(quantityG)),
      ]
      if let userKcal { value["user_kcal"] = .number(try Self.number(userKcal)) }
      if let quantityBasis { value["quantity_basis"] = .string(quantityBasis.rawValue) }
      if let candidateID { value["candidate_id"] = .string(candidateID) }
      return .object(value)
    }
    fileprivate init(_ raw: ConversationMealEditJSON) throws {
      let o = try raw.object(
        required: ["food_name", "quantity_g"],
        optional: ["user_kcal", "quantity_basis", "candidate_id"])
      let basis: QuantityBasis?
      if let value = o["quantity_basis"] {
        guard let parsed = QuantityBasis(rawValue: try value.string()) else {
          throw ConversationMealEditInvalid.value
        }
        basis = parsed
      } else {
        basis = nil
      }
      try self.init(
        foodName: o.required("food_name").string(),
        quantityG: editDecimal(o.required("quantity_g").amount(min: 0, max: 9999, positive: true)),
        userKcal: o["user_kcal"].map { try editDecimal($0.amount(max: 20000)) },
        quantityBasis: basis, candidateID: o["candidate_id"].map { try $0.string() })
    }
  }
  enum Action: Sendable {
    case save(recordID: UUID, items: [Item])
    case undoSave(targetOperationID: UUID)
    case undoRegistration
  }
  let ownerID: UUID
  let commandID: UUID
  let originalInputHash: String
  let epoch: UUID
  let operationID: UUID
  let expectedRevision: Int
  let expectedVersion: String
  let action: Action
  let wireBody: Data
  let operationInputHash: String
  var idempotencyKey: String { "cmedit1:\(operationID.uuidString.lowercased())" }

  init(
    ownerID: UUID, commandID: UUID, originalInputHash: String, epoch: UUID,
    operationID: UUID = UUID(), expectedRevision: Int, expectedVersion: String, action: Action
  ) throws {
    var object: [String: ConversationMealEditJSON] = [
      "schema": .string("conversation.meal-edit.v1"),
      "expected_revision": .number(Double(expectedRevision)),
      "expected_version": .string(expectedVersion),
    ]
    switch action {
    case .save(let recordID, let items):
      try editCheck((1...30).contains(items.count))
      object["kind"] = .string("save")
      object["record_id"] = .string(recordID.uuidString.lowercased())
      object["items"] = .array(try items.map { try $0.json() })
    case .undoSave(let target):
      object["kind"] = .string("undo_save")
      object["target_operation_id"] = .string(target.uuidString.lowercased())
    case .undoRegistration: object["kind"] = .string("undo_registration")
    }
    let bytes = try Self.canonical(.object(object))
    try self.init(
      ownerID: ownerID, commandID: commandID, originalInputHash: originalInputHash, epoch: epoch,
      operationID: operationID, wireBody: Data(bytes.utf8))
  }
  /// Restore the exact original body and operation UUID after uncertainty.
  /// This never rebases the revision, version, patient or idempotency key.
  init(
    ownerID: UUID, commandID: UUID, originalInputHash: String, epoch: UUID, operationID: UUID,
    wireBody: Data
  ) throws {
    guard wireBody.count <= 16_384 else { throw ConversationMealEditInvalid.value }
    let raw = try JSONDecoder().decode(ConversationMealEditJSON.self, from: wireBody)
    let kind = try raw.member("kind").string()
    let base: Set<String> = ["schema", "expected_revision", "expected_version", "kind"]
    let keys: Set<String>
    switch kind {
    case "save": keys = base.union(["record_id", "items"])
    case "undo_save": keys = base.union(["target_operation_id"])
    case "undo_registration": keys = base
    default: throw ConversationMealEditInvalid.value
    }
    let o = try raw.object(keys)
    try editCheck(o.required("schema").string() == "conversation.meal-edit.v1")
    expectedRevision = try o.required("expected_revision").revision()
    expectedVersion = try o.required("expected_version").version()
    _ = try ConversationMealEditJSON.string(originalInputHash).hash()
    switch kind {
    case "save":
      let items = try o.required("items").array()
      try editCheck((1...30).contains(items.count))
      action = try .save(
        recordID: o.required("record_id").uuid(), items: items.map { try Item($0) })
    case "undo_save":
      action = try .undoSave(targetOperationID: o.required("target_operation_id").uuid())
    default: action = .undoRegistration
    }
    self.ownerID = ownerID
    self.commandID = commandID
    self.originalInputHash = originalInputHash
    self.epoch = epoch
    self.operationID = operationID
    self.wireBody = wireBody
    operationInputHash = try ConversationMealCommand.digest(Data(Self.canonical(raw).utf8))
  }
  /// PostgreSQL JSONB scalar spelling differs from the old meal command hash:
  /// exponent numbers are expanded, negative zero is zero, and ASCII keys sort.
  private static func canonical(_ value: ConversationMealEditJSON) throws -> String {
    switch value {
    case .object(let v):
      return try "{"
        + v.keys.sorted().map { try quote($0) + ":" + canonical(v[$0]!) }.joined(separator: ",")
        + "}"
    case .array(let v): return try "[" + v.map(canonical).joined(separator: ",") + "]"
    case .string(let v): return try quote(v)
    case .number(let v): return try numberText(v)
    case .bool(let v): return v ? "true" : "false"
    case .null: return "null"
    }
  }
  private static func quote(_ s: String) throws -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.withoutEscapingSlashes]
    guard let value = String(data: try e.encode(s), encoding: .utf8) else {
      throw ConversationMealEditInvalid.value
    }
    return value
  }
  private static func numberText(_ n: Double) throws -> String {
    try editCheck(n.isFinite)
    if n == 0 { return "0" }
    if n.rounded() == n && abs(n) <= 9_007_199_254_740_991 { return String(Int64(n)) }
    let raw = String(n).lowercased()
    let parts = raw.split(separator: "e", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw }
    guard let exponent = Int(parts[1]) else { throw ConversationMealEditInvalid.value }
    let negative = parts[0].hasPrefix("-")
    let coefficient = negative ? String(parts[0].dropFirst()) : String(parts[0])
    let mantissa = coefficient.split(separator: ".", omittingEmptySubsequences: false)
    var digits = mantissa.joined()
    let position = mantissa[0].count + exponent
    // Swift spells 1e-7 as 1e-07; SQL hashes decimal 0.0000001.
    if position <= 0 {
      digits = "0." + String(repeating: "0", count: -position) + digits
    } else if position >= digits.count {
      digits += String(repeating: "0", count: position - digits.count)
    } else {
      digits.insert(".", at: digits.index(digits.startIndex, offsetBy: position))
    }
    return (negative ? "-" : "") + digits
  }
  var description: String { "ConversationMealEditOperation(redacted)" }
  var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
