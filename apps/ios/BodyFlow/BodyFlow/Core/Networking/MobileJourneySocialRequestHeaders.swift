import Foundation

/// Social privacy operations are closed capabilities, never arbitrary headers
/// or patient-accessible moderation. Every request retains its original login.
enum MobileJourneySocialRequestHeaders: Sendable {
  case profile(JourneySocialBinding)
  case ranking(JourneySocialBinding, cursor: JourneySocialRankingCursor?, limit: Int)
  case blocks(JourneySocialBinding, cursor: JourneySocialBlocksCursor?, limit: Int)
  case mutation(JourneySocialOperation)
  case recovery(JourneySocialBinding, JourneySocialPendingOperation)
  var binding: JourneySocialBinding {
    switch self {
    case .profile(let b), .ranking(let b, _, _), .blocks(let b, _, _), .recovery(let b, _): b
    case .mutation(let o): o.binding
    }
  }
  static func required(for path: String) -> Bool {
    let p = path.removingPercentEncoding ?? path
    return p == "/api/mobile/v1/profile/journey-social"
      || p.hasPrefix("/api/mobile/v1/profile/journey-social/")
      || p == "/api/mobile/v1/journey/ranking" || p.hasPrefix("/api/mobile/v1/journey/ranking/")
  }
  func validate(
    method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?, key: IdempotencyKey?,
    replay: MobileAPIUnauthorizedReplay
  ) throws {
    func require(_ value: Bool) throws {
      guard value else { throw MobileAPIRequestError.invalidJourneySocialHeaders }
    }
    try require(replay == .never)
    switch self {
    case .profile:
      try require(
        method == .get && path == "/api/mobile/v1/profile/journey-social" && query.isEmpty
          && body == nil && key == nil)
    case .ranking(_, let cursor, let limit):
      if let cursor { try binding.publicID(cursor.viewerMemberID) }
      try require(
        method == .get && path == "/api/mobile/v1/journey/ranking" && body == nil && key == nil
          && query == (try Self.pageQuery(cursor: cursor?.json, limit: limit)))
    case .blocks(_, let cursor, let limit):
      if let cursor { try binding.publicID(cursor.afterMemberID) }
      try require(
        method == .get && path == "/api/mobile/v1/profile/journey-social/blocks" && body == nil
          && key == nil && query == (try Self.pageQuery(cursor: cursor?.json, limit: limit)))
    case .mutation(let operation):
      try require(
        method == operation.method && path == operation.path && body == operation.wireBody
          && query.isEmpty && key?.value == operation.idempotencyKey)
    case .recovery(let current, let pending):
      try require(
        pending.matches(current) && method == .post
          && path == "/api/mobile/v1/profile/journey-social/operations/resolve"
          && query.isEmpty && body == (try pending.recoveryBody())
          && key?.value == pending.recoveryKey)
    }
  }
  static func pageQuery(cursor: ConversationMealEditJSON?, limit: Int) throws -> [URLQueryItem] {
    guard (1...100).contains(limit) else { throw MobileAPIRequestError.invalidJourneySocialHeaders }
    var query: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
    if let cursor {
      let data = try cursor.data()
      guard data.count <= 2048, let value = String(data: data, encoding: .utf8) else {
        throw MobileAPIRequestError.invalidJourneySocialHeaders
      }
      query.append(.init(name: "cursor", value: value))
    }
    return query
  }
  func validate(lease: SessionLease) throws { try binding.validate(lease: lease) }
  func validate(origin: URL) throws {
    if case .recovery(_, let pending) = self {
      guard try journeySocialOrigin(origin) == pending.origin else {
        throw MobileAPIRequestError.invalidJourneySocialHeaders
      }
    }
  }
  func apply(to request: inout URLRequest) {
    request.setValue(binding.ownerID.uuidString.lowercased(), forHTTPHeaderField: "X-Journey-Owner")
    request.setValue(
      binding.loginID.uuidString.lowercased(), forHTTPHeaderField: "X-Journey-Session")
  }
  func validateResponseProtocol(_ response: HTTPURLResponse) throws {
    guard (200...299).contains(response.statusCode) else { return }
    guard response.statusCode == 200, response.value(forHTTPHeaderField: "X-Journey-Social") == "1",
      response.value(forHTTPHeaderField: "Cache-Control") == "no-store"
    else { throw MobileAPITransportError.invalidResponse }
  }
}
