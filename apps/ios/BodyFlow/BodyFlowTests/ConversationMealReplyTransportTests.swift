import Foundation
import Testing

@testable import BodyFlow

@Suite("Typed linked reply transport never creates a new report or retries a mutation")
struct ConversationMealReplyTransportTests {
  @Test func originalReplyHeadersRequireExactPathBodyKeyAndHashQuery() throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let intent = try f.intent()
    let path =
      "/api/mobile/v1/conversation/commands/\(intent.parentBinding.commandID.uuidString.lowercased())/replies"
    let key = try IdempotencyKey(validating: intent.idempotencyKey)
    _ = try MobileAPIRequest<ConversationMealReplyResultSnapshot>(
      method: .post, path: path, body: intent.wireBody, idempotencyKey: key,
      conversation: .mealReplySubmit(intent), unauthorizedReplay: .never)
    #expect(throws: MobileAPIRequestError.invalidConversationHeaders) {
      try MobileAPIRequest<ConversationMealReplyResultSnapshot>(
        method: .post, path: path, body: intent.wireBody, idempotencyKey: key,
        conversation: .mealReplySubmit(intent))
    }
    #expect(throws: MobileAPIRequestError.invalidConversationHeaders) {
      try MobileAPIRequest<ConversationMealReplyResultSnapshot>(
        method: .post, path: path, body: intent.wireBody + Data(" ".utf8), idempotencyKey: key,
        conversation: .mealReplySubmit(intent), unauthorizedReplay: .never)
    }
    #expect(throws: MobileAPIRequestError.invalidConversationHeaders) {
      try MobileAPIRequest<ConversationMealReplyResultSnapshot>(
        method: .post, path: path.replacingOccurrences(of: "commands", with: "meal-commands"),
        body: intent.wireBody, idempotencyKey: key, conversation: .mealReplySubmit(intent),
        unauthorizedReplay: .never)
    }
    let query = [
      URLQueryItem(name: "parent_input_hash", value: intent.parentBinding.inputHash),
      URLQueryItem(name: "reply_input_hash", value: intent.replyInputHash),
    ]
    _ = try MobileAPIRequest<ConversationMealReplyResultSnapshot>(
      method: .get, path: path + "/" + intent.replyID.uuidString.lowercased(), queryItems: query,
      conversation: .mealReplyReconciliation(intent))
    #expect(throws: MobileAPIRequestError.invalidConversationHeaders) {
      try MobileAPIRequest<ConversationMealReplyResultSnapshot>(
        method: .get, path: path + "/" + intent.replyID.uuidString.lowercased(),
        queryItems: query + [query[0]], conversation: .mealReplyReconciliation(intent))
    }
  }
}
