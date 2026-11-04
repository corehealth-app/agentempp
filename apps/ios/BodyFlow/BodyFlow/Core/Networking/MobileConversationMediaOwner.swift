import Foundation

/// A patient precondition for new Flow media only. The server still derives
/// the owner from Auth. Legacy media requests omit it and keep their behavior.
enum MobileConversationMediaOwner {
  static func validate(
    method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?, key: IdempotencyKey?,
    conversation: MobileConversationRequestHeaders?, replay: MobileAPIUnauthorizedReplay
  ) throws {
    guard conversation == nil, query.isEmpty else {
      throw MobileAPIRequestError.invalidConversationHeaders
    }
    let base = "/api/mobile/v1/media"
    if path == base {
      guard method == .post, body != nil, key != nil, replay == .never else {
        throw MobileAPIRequestError.invalidConversationHeaders
      }
      return
    }
    guard path.hasPrefix(base + "/") else { throw MobileAPIRequestError.invalidConversationHeaders }
    let tail = path.dropFirst(base.count + 1).split(
      separator: "/", omittingEmptySubsequences: false)
    guard let raw = tail.first, let id = UUID(uuidString: String(raw)),
      id.uuidString.lowercased() == raw,
      body == nil
    else { throw MobileAPIRequestError.invalidConversationHeaders }
    if tail.count == 1 {
      guard (method == .get && key == nil) || (method == .delete && key != nil && replay == .never)
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    } else {
      guard tail.count == 2, ["complete", "process"].contains(String(tail[1])), method == .post,
        key != nil, replay == .never
      else { throw MobileAPIRequestError.invalidConversationHeaders }
    }
  }
}

extension MobileAPIRequest {
  /// Copy body/key verbatim; never replace a previously bound patient.
  func withConversationMediaOwner(_ ownerID: UUID) throws -> Self {
    guard conversationMediaOwnerID == nil || conversationMediaOwnerID == ownerID else {
      throw MobileAPIRequestError.invalidConversationHeaders
    }
    let key: IdempotencyKey?
    if case .required(let value) = idempotency { key = value } else { key = nil }
    return try .init(
      method: method, path: path, queryItems: queryItems, body: body, idempotencyKey: key,
      timeout: timeout, conversation: conversation,
      unauthorizedReplay: method == .get ? unauthorizedReplay : .never,
      conversationMediaOwnerID: ownerID)
  }
}
