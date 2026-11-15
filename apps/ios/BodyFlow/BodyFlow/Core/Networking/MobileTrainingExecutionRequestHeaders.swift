import Foundation

/// Closed route capabilities. Original-login refresh and redirects remain
/// forbidden; the v1 protocol is never silently upgraded or retried as v2.
enum MobileTrainingExecutionRequestHeaders: Sendable {
  case home(ownerID: UUID, cursor: TrainingExecutionCursor?)
  case read(ownerID: UUID, sessionID: UUID)
  case mutation(TrainingExecutionOperation)
  case history(ownerID: UUID, cursor: TrainingExecutionCursor?)
  case state(TrainingExecutionBinding, sessionID: UUID)
  case progressV2(TrainingExecutionOperation)
  case finish(TrainingExecutionOperation)
  case completionRead(TrainingExecutionCompletionIdentity)
  case completionCancel(TrainingExecutionCompletionIdentity)

  private var v2: Bool {
    switch self {
    case .home, .read, .mutation: return false
    default: return true
    }
  }
  func validate(
    method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?,
    key: IdempotencyKey?, replay: MobileAPIUnauthorizedReplay
  ) throws {
    let base = "/api/mobile/v1/training/" + (v2 ? "execution-v2" : "execution")
    func require(_ ok: Bool) throws {
      guard ok else { throw MobileAPIRequestError.invalidTrainingExecutionHeaders }
    }
    try require(replay == .never)
    switch self {
    case .home(let owner, let cursor), .history(let owner, let cursor):
      try require(
        method == .get && path == base && body == nil && key == nil
          && (cursor == nil || cursor?.ownerID == owner))
      let expected: [URLQueryItem]
      if let cursor {
        guard let value = String(data: try cursor.json.data(), encoding: .utf8),
          value.utf8.count <= 1024
        else { throw MobileAPIRequestError.invalidTrainingExecutionHeaders }
        expected = [.init(name: "cursor", value: value)]
      } else {
        expected = []
      }
      try require(query == expected)
    case .read(_, let session), .state(_, let session):
      try require(
        method == .get && path == base + "/" + session.uuidString.lowercased() && body == nil
          && query.isEmpty && key == nil)
    case .mutation(let operation), .progressV2(let operation), .finish(let operation):
      let expected: String
      switch self {
      case .mutation: expected = base + "/commands"
      case .progressV2: expected = base + "/" + operation.sessionID.uuidString.lowercased()
      default: expected = base + "/completions"
      }
      let finishing: Bool
      if case .finish = self { finishing = true } else { finishing = false }
      try require(
        (operation.kind == "finish") == finishing && method == .post && path == expected
          && query.isEmpty && body == operation.wireBody && key?.value == operation.idempotencyKey)
    case .completionRead(let identity), .completionCancel(let identity):
      let root =
        base + "/" + identity.sessionID.uuidString.lowercased() + "/completions/"
        + identity.completionID.uuidString.lowercased()
      if case .completionRead = self {
        try require(method == .get && path == root && query.isEmpty && body == nil && key == nil)
      } else {
        try require(
          method == .post && path == root + "/cancel" && query.isEmpty
            && body == identity.cancelBody
            && key?.value == "tcancel1:" + identity.completionID.uuidString.lowercased())
      }
    }
  }
  func apply(to request: inout URLRequest) {
    let owner: UUID
    let binding: TrainingExecutionBinding?
    switch self {
    case .home(let value, _), .history(let value, _), .read(let value, _):
      owner = value
      binding = nil
    case .state(let value, _):
      owner = value.ownerID
      binding = value
    case .mutation(let operation), .progressV2(let operation), .finish(let operation):
      owner = operation.binding.ownerID
      binding = operation.binding
    case .completionRead(let identity), .completionCancel(let identity):
      owner = identity.binding.ownerID
      binding = identity.binding
      if case .completionRead = self {
        request.setValue(identity.inputHash, forHTTPHeaderField: "X-Training-Completion-Hash")
      }
    }
    request.setValue(owner.uuidString.lowercased(), forHTTPHeaderField: "X-Training-Owner")
    if let binding {
      request.setValue(
        binding.epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Training-Epoch")
    }
  }
  func validateResponseProtocol(_ response: HTTPURLResponse) throws {
    guard (200...299).contains(response.statusCode) else { return }
    let accepted: Bool
    switch self {
    case .finish, .completionRead: accepted = [200, 202].contains(response.statusCode)
    default: accepted = response.statusCode == 200
    }
    guard accepted, response.value(forHTTPHeaderField: "X-Training-Execution") == (v2 ? "2" : "1"),
      !v2 || response.value(forHTTPHeaderField: "X-Training-Completion") == "1",
      response.value(forHTTPHeaderField: "Cache-Control") == "no-store"
    else { throw MobileAPITransportError.invalidResponse }
  }
}
