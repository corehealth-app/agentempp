import Foundation
import Testing

@testable import BodyFlow

@Suite("Current conversation meal facts use owned read-only transport")
struct ConversationMealGroupTransportTests {
  @Test func actualGroupGETUsesOriginalPatientEpochHashAndDoesNotAcknowledgeOrWrite() async throws {
    let f = try ConversationHTTPFixture()
    let raw = try groupEnvelope()
    let responseBody = try JSONSerialization.data(withJSONObject: raw)
    let payload = try #require(raw["data"] as? [String: Any])
    let group = try ConversationMealGroupSnapshot(
      data: JSONSerialization.data(withJSONObject: payload))
    let lease = await f.lifecycle.leaseForRequest()
    let context = try ConversationCommandContext(
      observation: .init(
        authUserID: #require(UUID(uuidString: lease.userID)), ownerID: group.ownerID,
        localSessionGeneration: lease.generation, epoch: group.epoch), observedAt: group.admittedAt)
    await f.stub.respond { _, _ in .init(status: 200, body: responseBody) }
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: f.transport, lifecycle: f.lifecycle, lease: lease)
    let read = try await repo.group(
      commandID: group.commandID, originalInputHash: group.originalInputHash, context: context)
    #expect(
      read.current?.items.first?.quantityG == 85
        && read.originalInputHash == group.originalInputHash)
    let request = try #require(await f.stub.requests.first)
    #expect(request.httpMethod == "GET" && request.httpBody == nil)
    #expect(
      request.url?.path
        == "/api/mobile/v1/conversation/meal-commands/\(group.commandID.uuidString.lowercased())/meal"
    )
    #expect(
      request.value(forHTTPHeaderField: "X-Conversation-Owner")
        == group.ownerID.uuidString.lowercased())
    #expect(
      request.value(forHTTPHeaderField: "X-Conversation-Epoch")
        == group.epoch.uuidString.lowercased())
    #expect(
      request.value(forHTTPHeaderField: "X-Conversation-Input-Hash") == group.originalInputHash)
    #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
  }
  @Test func foreignGroupAndRevokedContextCannotBecomeCurrentFacts() async throws {
    let f = try ConversationHTTPFixture()
    let raw = try groupEnvelope()
    let responseBody = try JSONSerialization.data(withJSONObject: raw)
    let group = try ConversationMealGroupSnapshot(
      data: JSONSerialization.data(withJSONObject: #require(raw["data"])))
    let lease = await f.lifecycle.leaseForRequest()
    let authority = ConversationOutboxObservationAuthority()
    let token = try authority.beginRefresh()
    let observation = try authority.accept(
      refreshID: token, authUserID: #require(UUID(uuidString: lease.userID)),
      ownerID: group.ownerID, localSessionGeneration: lease.generation, epoch: group.epoch)
    let context = ConversationCommandContext(observation: observation, observedAt: group.admittedAt)
    await f.stub.respond { _, _ in .init(status: 200, body: responseBody) }
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: f.transport, lifecycle: f.lifecycle, lease: lease)
    await #expect(throws: (any Error).self) {
      try await repo.group(
        commandID: UUID(), originalInputHash: group.originalInputHash, context: context)
    }
    let before = await f.stub.requests.count
    _ = try authority.beginRefresh()
    await #expect(throws: (any Error).self) {
      try await repo.group(
        commandID: group.commandID, originalInputHash: group.originalInputHash, context: context)
    }
    #expect(await f.stub.requests.count == before)
  }
  private func groupEnvelope() throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealEditPublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealEditPublicFixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return try #require(root["group"] as? [String: Any])
  }
}
