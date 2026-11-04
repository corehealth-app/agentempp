import Foundation

enum MobileAPIUnauthorizedReplay: Sendable, Equatable { case standard, never }

/// Closed new-protocol headers, never arbitrary header overrides. They are
/// preconditions, not part of the immutable command body or source authority.
enum MobileConversationRequestHeaders: Sendable {
  case session
  case submit(epoch: UUID, ownerID: UUID)
  case reconciliation(epoch: UUID, ownerID: UUID, inputHash: String)
  case mealGroup(epoch: UUID, ownerID: UUID, inputHash: String)
  case journal(epoch: UUID, ownerID: UUID)
  case threadJournal(epoch: UUID, ownerID: UUID)
  case mealEdit(epoch: UUID, ownerID: UUID, inputHash: String)
  case mealEditReconciliation(epoch: UUID, ownerID: UUID, inputHash: String)

  func validate(
    method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?, key: IdempotencyKey?,
    replay: MobileAPIUnauthorizedReplay
  ) throws {
    let base = "/api/mobile/v1/conversation/meal-commands"
    if case .journal = self {
    } else if case .threadJournal = self {
    } else {
      guard query.isEmpty else { throw MobileAPIRequestError.invalidConversationHeaders }
    }
    switch self {
    case .mealEdit(let epoch, let owner, let hash),
      .mealEditReconciliation(let epoch, let owner, let hash):
      let reconciliation: Bool
      if case .mealEditReconciliation = self {
        reconciliation = true
      } else {
        reconciliation = false
      }
      let prefix = base + "/"
      let components =
        path.hasPrefix(prefix)
        ? String(path.dropFirst(prefix.count)).split(
          separator: "/", omittingEmptySubsequences: false
        ).map(String.init) : []
      guard method == .post, replay == .never, let body, let key,
        components.count == (reconciliation ? 4 : 3), components[1] == "edits",
        !reconciliation || components[3] == "reconcile",
        let commandID = UUID(uuidString: components[0]),
        commandID.uuidString.lowercased() == components[0],
        let operationID = UUID(uuidString: components[2]),
        operationID.uuidString.lowercased() == components[2],
        let operation = try? ConversationMealEditOperation(
          ownerID: owner, commandID: commandID,
          originalInputHash: hash, epoch: epoch, operationID: operationID, wireBody: body),
        operation.wireBody == body, key.value == operation.idempotencyKey
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .journal, .threadJournal:
      let isV2: Bool
      if case .threadJournal = self { isV2 = true } else { isV2 = false }
      let names = query.map(\.name)
      guard method == .get, path == "/api/mobile/v1/conversation/journal", body == nil, key == nil,
        Set(names).count == names.count,
        Set(names).isSubset(of: isV2 ? ["version", "limit", "cursor"] : ["limit", "cursor"]),
        !isV2 || query.first(where: { $0.name == "version" })?.value == "2",
        let rawLimit = query.first(where: { $0.name == "limit" })?.value, let limit = Int(rawLimit),
        String(limit) == rawLimit, (1...25).contains(limit)
      else { throw MobileAPIRequestError.invalidConversationHeaders }
      if let cursor = query.first(where: { $0.name == "cursor" }) {
        guard let value = cursor.value, value.utf8.count <= 1024,
          value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
        else { throw MobileAPIRequestError.invalidConversationHeaders }
      }
    case .session:
      guard method == .get, path == "/api/mobile/v1/conversation/session", body == nil, key == nil
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .submit:
      guard method == .post, path == base, let body, let key, replay == .never,
        let command = try? ConversationMealCommand(wireBody: body), command.wireBody == body,
        key.value == command.idempotencyKey
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .mealGroup(_, _, let hash):
      let prefix = base + "/"
      let tail =
        path.hasPrefix(prefix) && path.hasSuffix("/meal")
        ? String(path.dropFirst(prefix.count).dropLast(5)) : ""
      guard method == .get, body == nil, key == nil, let id = UUID(uuidString: tail),
        id.uuidString.lowercased() == tail,
        hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .reconciliation(_, _, let hash):
      let tail = String(path.dropFirst((base + "/").count))
      guard method == .get, body == nil, key == nil, path.hasPrefix(base + "/"),
        let id = UUID(uuidString: tail), id.uuidString.lowercased() == tail,
        hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    }
  }
  func apply(to request: inout URLRequest) {
    request.setValue("meal-command-v1", forHTTPHeaderField: "X-Conversation-Protocol")
    switch self {
    case .session: break
    case .submit(let epoch, let owner), .journal(let epoch, let owner),
      .threadJournal(let epoch, let owner):
      request.setValue(epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Epoch")
      request.setValue(owner.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Owner")
    case .reconciliation(let epoch, let owner, let hash),
      .mealGroup(let epoch, let owner, let hash),
      .mealEdit(let epoch, let owner, let hash),
      .mealEditReconciliation(let epoch, let owner, let hash):
      request.setValue(epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Epoch")
      request.setValue(hash, forHTTPHeaderField: "X-Conversation-Input-Hash")
      request.setValue(owner.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Owner")
    }
  }
}

struct MobileAPIHTTPResponse<Payload: Decodable & Sendable>: Sendable {
  let statusCode: Int
  let data: Payload
  let meta: MobileResponseMetadata
}

/// Opt-in envelope check only. Existing mobile consumers retain their additive
/// metadata compatibility; the new command protocol rejects private additions.
struct MobileConversationEnvelopeShape: Decodable {
  init(from decoder: any Decoder) throws {
    let root = try decoder.container(keyedBy: ConversationEnvelopeKey.self)
    guard Set(root.allKeys.map(\.stringValue)) == ["data", "meta"],
      let meta = ConversationEnvelopeKey(stringValue: "meta")
    else { throw MobileAPITransportError.invalidResponse }
    let child = try root.superDecoder(forKey: meta).container(keyedBy: ConversationEnvelopeKey.self)
    guard Set(child.allKeys.map(\.stringValue)) == ["api_version", "request_id"] else {
      throw MobileAPITransportError.invalidResponse
    }
  }
}
private struct ConversationEnvelopeKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
