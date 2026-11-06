import Foundation

enum MobileAPIUnauthorizedReplay: Sendable, Equatable { case standard, never }

/// Closed new-protocol headers, never arbitrary header overrides. They are
/// preconditions, not part of the immutable command body or source authority.
enum MobileConversationRequestHeaders: Sendable {
  case session
  case intakeQuestionOrigins(epoch: UUID, ownerID: UUID)
  case intakeSession
  case intakeSubmit(FlowNeutralIntakeTicket)
  case intakeReconciliation(FlowNeutralIntakeTicket)
  case mealParentQuestion(FlowNeutralIntakeChild)
  case mealReplySubmit(ConversationMealReplyIntent)
  case mealReplyReconciliation(ConversationMealReplyIntent)
  case submit(epoch: UUID, ownerID: UUID)
  case reconciliation(epoch: UUID, ownerID: UUID, inputHash: String)
  case mealGroup(epoch: UUID, ownerID: UUID, inputHash: String)
  case journal(epoch: UUID, ownerID: UUID)
  case threadJournal(epoch: UUID, ownerID: UUID)
  case unifiedJournal(epoch: UUID, ownerID: UUID)
  case mealEdit(epoch: UUID, ownerID: UUID, inputHash: String)
  case mealEditReconciliation(epoch: UUID, ownerID: UUID, inputHash: String)

  func validate(
    method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?, key: IdempotencyKey?,
    replay: MobileAPIUnauthorizedReplay
  ) throws {
    let base = "/api/mobile/v1/conversation/meal-commands"
    if case .journal = self {
    } else if case .threadJournal = self {
    } else if case .unifiedJournal = self {
    } else if case .intakeQuestionOrigins = self {
    } else if case .mealParentQuestion = self {
    } else if case .mealReplyReconciliation = self {
    } else {
      guard query.isEmpty else { throw MobileAPIRequestError.invalidConversationHeaders }
    }
    switch self {
    case .intakeQuestionOrigins(let epoch, let owner):
      let names = query.map(\.name)
      let rawLimit = query.first(where: { $0.name == "limit" })?.value ?? "10"
      guard method == .get, path == "/api/mobile/v1/conversation/intakes", body == nil, key == nil, replay == .never,
        names.count == Set(names).count, Set(names).isSubset(of: ["limit", "cursor"]),
        let limit = Int(rawLimit), String(limit) == rawLimit, (1...25).contains(limit)
      else { throw MobileAPIRequestError.invalidConversationHeaders }
      if let cursor = query.first(where: { $0.name == "cursor" }) {
        guard let value = cursor.value, (try? FlowMealQuestionOriginsPageSnapshot.cursorAnchor(value, owner: owner, epoch: epoch)) != nil
        else { throw MobileAPIRequestError.invalidConversationHeaders }
      }
    case .intakeSession:
      guard method == .get, path == "/api/mobile/v1/conversation/intakes/session", body == nil, key == nil else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .intakeSubmit(let ticket):
      guard method == .post, path == "/api/mobile/v1/conversation/intakes", body == ticket.input.wireBody,
        key?.value == ticket.input.idempotencyKey, replay == .never else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .intakeReconciliation(let ticket):
      guard method == .get, path == "/api/mobile/v1/conversation/intakes/" + ticket.input.intakeID.uuidString.lowercased(), body == nil, key == nil else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .mealParentQuestion(let child):
      guard child.kind == .meal, method == .get,
        path == "/api/mobile/v1/conversation/commands/" + child.commandID.uuidString.lowercased() + "/replies",
        body == nil, key == nil, query.count == 1,
        query.first?.name == "parent_input_hash", query.first?.value == child.inputHash
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    case .mealReplySubmit(let intent), .mealReplyReconciliation(let intent):
      let prefix =
        "/api/mobile/v1/conversation/commands/"
        + intent.parentBinding.commandID.uuidString.lowercased() + "/replies"
      switch self {
      case .mealReplySubmit:
        guard method == .post, path == prefix, replay == .never,
          body == intent.wireBody, key?.value == intent.idempotencyKey
        else { throw MobileAPIRequestError.invalidConversationHeaders }
      case .mealReplyReconciliation:
        guard method == .get, path == prefix + "/" + intent.replyID.uuidString.lowercased(),
          body == nil, key == nil, query.count == 2,
          Set(query.map(\.name)) == ["parent_input_hash", "reply_input_hash"],
          query.first(where: { $0.name == "parent_input_hash" })?.value
            == intent.parentBinding.inputHash,
          query.first(where: { $0.name == "reply_input_hash" })?.value == intent.replyInputHash
        else { throw MobileAPIRequestError.invalidConversationHeaders }
      default: throw MobileAPIRequestError.invalidConversationHeaders
      }
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
    case .journal, .threadJournal, .unifiedJournal:
      let version: String?
      switch self { case .threadJournal: version = "2"; case .unifiedJournal: version = "3"; default: version = nil }
      let names = query.map(\.name)
      guard method == .get, path == "/api/mobile/v1/conversation/journal", body == nil, key == nil,
        Set(names).count == names.count,
        Set(names).isSubset(of: version != nil ? ["version", "limit", "cursor"] : ["limit", "cursor"]),
        version == nil || query.first(where: { $0.name == "version" })?.value == version,
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
  var supportsFeedbackPresentation: Bool {
    switch self {
    case .submit, .reconciliation, .mealReplySubmit, .mealReplyReconciliation, .journal, .threadJournal, .intakeSubmit, .intakeReconciliation: true
    case .intakeQuestionOrigins, .mealParentQuestion, .session, .mealGroup, .mealEdit, .mealEditReconciliation, .intakeSession, .unifiedJournal: false
    }
  }
  /// Only the new family requires its own exact successful protocol echo.
  /// Error envelopes retain their existing Auth/transport handling.
  func validateResponseProtocol(_ response: HTTPURLResponse) throws {
    guard (200...299).contains(response.statusCode) else { return }
    switch self {
    case .intakeQuestionOrigins:
      guard response.statusCode == 200,
        response.value(forHTTPHeaderField: "X-Conversation-Protocol") == "intake-question-origins-v1",
        response.value(forHTTPHeaderField: "Cache-Control") == "no-store"
      else { throw MobileAPITransportError.invalidResponse }
    case .mealParentQuestion:
      guard response.value(forHTTPHeaderField: "X-Conversation-Protocol") == "meal-question-v1",
        response.value(forHTTPHeaderField: "Cache-Control") == "no-store"
      else { throw MobileAPITransportError.invalidResponse }
    case .intakeSession, .intakeSubmit, .intakeReconciliation:
      guard response.value(forHTTPHeaderField: "X-Conversation-Protocol") == "intake-v1" else { throw MobileAPITransportError.invalidResponse }
    default: break
    }
  }
  func apply(to request: inout URLRequest) {
    switch self {
    case .intakeQuestionOrigins: request.setValue("intake-question-origins-v1", forHTTPHeaderField: "X-Conversation-Protocol")
    case .mealParentQuestion: request.setValue("meal-question-v1", forHTTPHeaderField: "X-Conversation-Protocol")
    case .intakeSession, .intakeSubmit, .intakeReconciliation: request.setValue("intake-v1", forHTTPHeaderField: "X-Conversation-Protocol")
    default: request.setValue("meal-command-v1", forHTTPHeaderField: "X-Conversation-Protocol")
    }
    switch self {
    case .intakeSession: break
    case .intakeSubmit(let ticket), .intakeReconciliation(let ticket):
      request.setValue(ticket.ownerID.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Owner")
      request.setValue(ticket.epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Epoch")
      if case .intakeReconciliation = self { request.setValue(ticket.input.inputHash, forHTTPHeaderField: "X-Conversation-Input-Hash") }
    case .session: break
    case .mealParentQuestion(let child):
      request.setValue(child.epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Epoch")
      request.setValue(child.ownerID.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Owner")
    case .mealReplySubmit(let intent), .mealReplyReconciliation(let intent):
      request.setValue(
        intent.parentBinding.epoch.uuidString.lowercased(),
        forHTTPHeaderField: "X-Conversation-Epoch")
      request.setValue(
        intent.parentBinding.ownerID.uuidString.lowercased(),
        forHTTPHeaderField: "X-Conversation-Owner")
    case .intakeQuestionOrigins(let epoch, let owner), .submit(let epoch, let owner), .journal(let epoch, let owner),
      .threadJournal(let epoch, let owner), .unifiedJournal(let epoch, let owner):
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
