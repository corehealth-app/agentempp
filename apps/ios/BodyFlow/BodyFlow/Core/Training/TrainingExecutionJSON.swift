import CryptoKit
import Foundation

enum TrainingExecutionError: Error, Equatable, Sendable {
  case invalidResponse, unavailable, pendingOperation, storageUnavailable, scopeChanged
}

func trainingRequire(_ value: Bool) throws {
  guard value else { throw TrainingExecutionError.invalidResponse }
}

/// Closed protocol JSON, also used to restore an immutable pending command.
/// It never accepts a calculation, owner override or writer chosen by the UI.
indirect enum TrainingExecutionJSON: Codable, Sendable, Equatable {
  case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null
  private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  init(from decoder: any Decoder) throws {
    try trainingRequire(decoder.codingPath.count <= 32)
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) {
      try trainingRequire(n.isFinite); self = .number(n)
    } else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let a = try? c.decode([Self].self) { self = .array(a) }
    else {
      let o = try decoder.container(keyedBy: Key.self)
      self = .object(try Dictionary(uniqueKeysWithValues: o.allKeys.map {
        ($0.stringValue, try o.decode(Self.self, forKey: $0))
      }))
    }
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .object(let x): try c.encode(x)
    case .array(let x): try c.encode(x)
    case .string(let x): try c.encode(x)
    case .number(let x): try c.encode(x)
    case .bool(let x): try c.encode(x)
    case .null: try c.encodeNil()
    }
  }
  init(data: Data, limit: Int = 1_048_576) throws {
    try trainingRequire(data.count <= limit)
    self = try JSONDecoder().decode(Self.self, from: data)
  }
  func object(_ keys: Set<String>) throws -> [String: Self] {
    guard case .object(let x) = self, Set(x.keys) == keys else {
      throw TrainingExecutionError.invalidResponse
    }
    return x
  }
  func array(max: Int, min: Int = 0) throws -> [Self] {
    guard case .array(let x) = self, (min...max).contains(x.count) else {
      throw TrainingExecutionError.invalidResponse
    }
    return x
  }
  func text(max: Int, empty: Bool = false) throws -> String {
    guard case .string(let s) = self, s.utf16.count <= max, empty || !s.isEmpty else {
      throw TrainingExecutionError.invalidResponse
    }
    return s
  }
  func uuid() throws -> UUID {
    let s = try text(max: 36)
    guard let id = UUID(uuidString: s), id.uuidString.lowercased() == s else {
      throw TrainingExecutionError.invalidResponse
    }
    return id
  }
  func hash() throws -> String {
    let s = try text(max: 64)
    try trainingRequire(s.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
    return s
  }
  func number(max: Double) throws -> Double {
    guard case .number(let n) = self, n.isFinite, n >= 0, n <= max else {
      throw TrainingExecutionError.invalidResponse
    }
    return n
  }
  func integer(max: Int, min: Int = 0) throws -> Int {
    let n = try number(max: Double(max))
    try trainingRequire(n.rounded() == n && n >= Double(min))
    return Int(n)
  }
  func boolean() throws -> Bool {
    guard case .bool(let b) = self else { throw TrainingExecutionError.invalidResponse }
    return b
  }
  func clock() throws -> String {
    let s = try text(max: 64)
    try trainingRequire(ConversationProtocolInstant(s) != nil)
    return s
  }
  func date() throws -> String {
    let s = try text(max: 10)
    try trainingRequire(NutritionCivilDate.date(s) != nil && !s.hasPrefix("0000"))
    return s
  }
  var isNull: Bool { self == .null }
  func data() throws -> Data { Data(try canonical().utf8) }
  /// Matches the server's recursive JSON.stringify canonicalization for these
  /// ASCII-keyed commands. In particular, tiny IEEE754 values keep exponent
  /// spelling, while values from 1e-6 upward use decimal spelling.
  func canonical() throws -> String {
    switch self {
    case .object(let v):
      return try "{" + v.keys.sorted().map {
        try Self.quote($0) + ":" + v[$0]!.canonical()
      }.joined(separator: ",") + "}"
    case .array(let v): return try "[" + v.map { try $0.canonical() }.joined(separator: ",") + "]"
    case .string(let v): return try Self.quote(v)
    case .number(let n):
      try trainingRequire(n.isFinite)
      if n == 0 { return "0" }
      let raw = String(n).lowercased()
      let parts = raw.split(separator: "e", omittingEmptySubsequences: false)
      guard parts.count == 2, let exponent = Int(parts[1]) else {
        return raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
      }
      var coefficient = String(parts[0])
      if coefficient.hasSuffix(".0") { coefficient.removeLast(2) }
      if abs(n) < 0.000001 || abs(n) >= 1e21 {
        return coefficient + "e" + (exponent >= 0 ? "+" : "") + String(exponent)
      }
      let negative = coefficient.hasPrefix("-")
      if negative { coefficient.removeFirst() }
      let digits = coefficient.split(separator: ".", omittingEmptySubsequences: false)
      var joined = digits.joined()
      let position = digits[0].count + exponent
      if position <= 0 { joined = "0." + String(repeating: "0", count: -position) + joined }
      else if position >= joined.count { joined += String(repeating: "0", count: position - joined.count) }
      else { joined.insert(".", at: joined.index(joined.startIndex, offsetBy: position)) }
      return (negative ? "-" : "") + joined
    case .bool(let b): return b ? "true" : "false"
    case .null: return "null"
    }
  }
  private static func quote(_ value: String) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let s = String(data: try encoder.encode(value), encoding: .utf8) else {
      throw TrainingExecutionError.invalidResponse
    }
    return s
  }
  var digest: String { get throws { SHA256.hash(data: try data()).map { String(format: "%02x", $0) }.joined() } }
}

extension Dictionary where Key == String, Value == TrainingExecutionJSON {
  func field(_ key: String) throws -> Value {
    guard let v = self[key] else { throw TrainingExecutionError.invalidResponse }; return v
  }
  func nullableText(_ key: String, max: Int) throws -> String? {
    let v = try field(key); return v.isNull ? nil : try v.text(max: max, empty: true)
  }
  func nullableInt(_ key: String, max: Int, min: Int = 0) throws -> Int? {
    let v = try field(key); return v.isNull ? nil : try v.integer(max: max, min: min)
  }
}
