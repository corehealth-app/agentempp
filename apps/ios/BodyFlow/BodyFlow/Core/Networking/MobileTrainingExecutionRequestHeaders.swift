import Foundation

/// A closed capability for the three execution routes. No arbitrary headers,
/// original-login refresh, redirect, owner override or mutable retry body.
enum MobileTrainingExecutionRequestHeaders: Sendable {
  case home(ownerID: UUID, cursor: TrainingExecutionCursor?)
  case read(ownerID: UUID, sessionID: UUID)
  case mutation(TrainingExecutionOperation)

  func validate(method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?,
    key: IdempotencyKey?, replay: MobileAPIUnauthorizedReplay) throws {
    let base = "/api/mobile/v1/training/execution"
    guard replay == .never else { throw MobileAPIRequestError.invalidTrainingExecutionHeaders }
    switch self {
    case .home(let owner, let cursor):
      guard method == .get, path == base, body == nil, key == nil,
        cursor == nil || cursor?.ownerID == owner else { throw MobileAPIRequestError.invalidTrainingExecutionHeaders }
      let expected: [URLQueryItem]
      if let cursor {
        guard let value = String(data: try cursor.json.data(), encoding: .utf8), value.utf8.count <= 1024 else {
          throw MobileAPIRequestError.invalidTrainingExecutionHeaders
        }
        expected = [.init(name: "cursor", value: value)]
      } else { expected = [] }
      guard query == expected else { throw MobileAPIRequestError.invalidTrainingExecutionHeaders }
    case .read(_, let session):
      guard method == .get, path == base + "/" + session.uuidString.lowercased(), body == nil,
        query.isEmpty, key == nil else { throw MobileAPIRequestError.invalidTrainingExecutionHeaders }
    case .mutation(let operation):
      guard method == .post, path == base + "/commands", query.isEmpty, body == operation.wireBody,
        key?.value == operation.idempotencyKey else { throw MobileAPIRequestError.invalidTrainingExecutionHeaders }
    }
  }
  func apply(to request: inout URLRequest) {
    let owner: UUID
    switch self {
    case .home(let value, _), .read(let value, _): owner = value
    case .mutation(let operation):
      owner = operation.binding.ownerID
      request.setValue(operation.binding.epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Training-Epoch")
    }
    request.setValue(owner.uuidString.lowercased(), forHTTPHeaderField: "X-Training-Owner")
  }
  func validateResponseProtocol(_ response: HTTPURLResponse) throws {
    guard (200...299).contains(response.statusCode) else { return }
    guard response.statusCode == 200,
      response.value(forHTTPHeaderField: "X-Training-Execution") == "1",
      response.value(forHTTPHeaderField: "Cache-Control") == "no-store" else {
      throw MobileAPITransportError.invalidResponse
    }
  }
}
