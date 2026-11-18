import CryptoKit
import Foundation

enum JourneySocialPendingError: Error, Equatable, Sendable {
  case pendingOperation, storageUnavailable, scopeChanged
}

/// A new feature namespace only; existing transport normalization is unchanged.
func journeySocialOrigin(_ value: URL) throws -> URL {
  let validated = try MobileAPIConfiguration(originString: value.absoluteString).origin
  guard var parts = URLComponents(url: validated, resolvingAgainstBaseURL: false) else {
    throw JourneySocialPendingError.scopeChanged
  }
  parts.host = parts.host?.lowercased()
  if parts.port == 443 { parts.port = nil }
  guard let url = parts.url else { throw JourneySocialPendingError.scopeChanged }
  return url
}

/// Protected at rest by device-only Keychain. The checksum covers the entire
/// immutable account/origin/intent payload; no credential is persisted.
struct JourneySocialPendingOperation: Codable, Equatable, Sendable {
  let origin: URL
  let operation: JourneySocialOperation
  static let storageLimit = 32_768

  init(origin: URL, operation: JourneySocialOperation) throws {
    self.origin = try journeySocialOrigin(origin)
    self.operation = operation
  }
  func matches(_ current: JourneySocialBinding) -> Bool {
    operation.binding.ownerID == current.ownerID
      && operation.binding.authUserID == current.authUserID
  }
  var recoveryKey: String { "jsocial-resolve1:" + operation.id.uuidString.lowercased() }
  func recoveryBody() throws -> Data {
    try ConversationMealEditJSON.object([
      "kind": .string(operation.kind),
      "command": JSONDecoder().decode(ConversationMealEditJSON.self, from: operation.wireBody),
    ]).data()
  }
  private func payload() throws -> [String: ConversationMealEditJSON] {
    [
      "schema": .string("journey.social.pending.v1"), "origin": .string(origin.absoluteString),
      "owner_id": .string(operation.binding.ownerID.uuidString.lowercased()),
      "auth_user_id": .string(operation.binding.authUserID.uuidString.lowercased()),
      "login_id": .string(operation.binding.loginID.uuidString.lowercased()),
      "kind": .string(operation.kind),
      "command": try JSONDecoder().decode(ConversationMealEditJSON.self, from: operation.wireBody),
    ]
  }
  func storageData() throws -> Data {
    var fields = try payload()
    fields["checksum"] = .string(Self.digest(try ConversationMealEditJSON.object(fields).data()))
    let data = try ConversationMealEditJSON.object(fields).data()
    guard data.count <= Self.storageLimit else {
      throw JourneySocialPendingError.storageUnavailable
    }
    return data
  }
  init(from decoder: any Decoder) throws {
    let raw = try ConversationMealEditJSON(from: decoder)
    try raw.boundPublicPacket()
    var fields = try raw.object([
      "schema", "origin", "owner_id", "auth_user_id", "login_id", "kind", "command", "checksum",
    ])
    let checksum = try fields.required("checksum").hash()
    fields.removeValue(forKey: "checksum")
    try socialRequire(Self.digest(try ConversationMealEditJSON.object(fields).data()) == checksum)
    try socialRequire(fields.required("schema").string() == "journey.social.pending.v1")
    let text = try fields.required("origin").string()
    guard let origin = URL(string: text) else { throw JourneySocialPendingError.scopeChanged }
    let binding = try JourneySocialBinding(
      ownerID: fields.required("owner_id").uuid(),
      authUserID: fields.required("auth_user_id").uuid(),
      loginID: fields.required("login_id").uuid())
    try self.init(
      origin: origin,
      operation: JourneySocialOperation(
        binding: binding, kind: fields.required("kind").string(),
        command: fields.required("command")))
    try socialRequire(self.origin.absoluteString == text)
  }
  func encode(to encoder: any Encoder) throws {
    try JSONDecoder().decode(ConversationMealEditJSON.self, from: storageData()).encode(to: encoder)
  }
  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
