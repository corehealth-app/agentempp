import Foundation
import Testing

@testable import BodyFlow

@Suite("Owned genuine linked current group transport")
struct ConversationMealLinkedGroupTransportTests {
  @Test func realGroupEndpointUsesChildIdentityAndFullReceiptBinding() async throws {
    let f = try LinkedMealIdentityFixture()
    let identity = try f.identity()
    let http = try ConversationHTTPFixture()
    let lease = await http.lifecycle.leaseForRequest()
    let authority = ConversationOutboxObservationAuthority()
    let token = try authority.beginRefresh()
    let context = ConversationCommandContext(
      observation: try authority.accept(
        refreshID: token, authUserID: #require(UUID(uuidString: lease.userID)),
        ownerID: identity.ownerID, localSessionGeneration: lease.generation, epoch: identity.epoch),
      observedAt: f.parent.admittedAt)
    let body = try linkedGroupEnvelope(f.groupRaw)
    await http.stub.respond { _, _ in .init(status: 200, body: body) }
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: http.transport, lifecycle: http.lifecycle, lease: lease)
    let group = try await repo.group(linked: identity, context: context)
    #expect(identity.matches(group: group))
    let request = try #require(await http.stub.requests.first)
    #expect(request.httpMethod == "GET" && request.httpBody == nil && request.url?.query == nil)
    #expect(
      request.url?.path
        == "/api/mobile/v1/conversation/meal-commands/\(identity.commandID.uuidString.lowercased())/meal"
    )
    #expect(request.value(forHTTPHeaderField: "X-Conversation-Input-Hash") == identity.inputHash)
    #expect(
      request.value(forHTTPHeaderField: "X-Conversation-Owner")
        == identity.ownerID.uuidString.lowercased())
    #expect(
      request.value(forHTTPHeaderField: "X-Conversation-Epoch")
        == identity.epoch.uuidString.lowercased())
    #expect(context.authUserID != context.ownerID)
    #expect(await http.stub.requests.count == 1)
  }
  @Test(arguments: ["parent_input_hash", "parent_decision_hash", "effect_version"])
  func structurallyValidGroupCannotChangeTheActualOriginalReceipt(_ field: String) async throws {
    let f = try LinkedMealIdentityFixture()
    let identity = try f.identity()
    let http = try ConversationHTTPFixture()
    let lease = await http.lifecycle.leaseForRequest()
    let context = ConversationCommandContext(
      observation: .init(
        authUserID: try #require(UUID(uuidString: lease.userID)), ownerID: identity.ownerID,
        localSessionGeneration: lease.generation, epoch: identity.epoch),
      observedAt: f.parent.admittedAt)
    var raw = try f.groupRaw
    var receipt = try #require(raw["original_receipt"] as? [String: Any])
    receipt[field] =
      field == "effect_version"
      ? "cmeal1:" + String(repeating: "a", count: 64) : String(repeating: "a", count: 64)
    raw["original_receipt"] = receipt
    _ = try f.group(raw)
    let body = try linkedGroupEnvelope(raw)
    await http.stub.respond { _, _ in .init(status: 200, body: body) }
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: http.transport, lifecycle: http.lifecycle, lease: lease)
    await #expect(throws: MobileAPITransportError.invalidResponse) {
      try await repo.group(linked: identity, context: context)
    }
    #expect(await http.stub.requests.count == 1)
  }
  @Test(arguments: ["patient", "epoch", "logout"])
  func lateGroupCannotReturnAnOldPatientPayload(_ change: String) async throws {
    let f = try LinkedMealIdentityFixture()
    let identity = try f.identity()
    let http = try ConversationHTTPFixture()
    let lease = await http.lifecycle.leaseForRequest()
    let authority = ConversationOutboxObservationAuthority()
    let token = try authority.beginRefresh()
    let context = ConversationCommandContext(
      observation: try authority.accept(
        refreshID: token, authUserID: #require(UUID(uuidString: lease.userID)),
        ownerID: identity.ownerID, localSessionGeneration: lease.generation, epoch: identity.epoch),
      observedAt: f.parent.admittedAt)
    let body = try linkedGroupEnvelope(f.groupRaw)
    let barrier = ConversationControllerBarrier()
    await http.stub.respond { _, _ in
      await barrier.enter()
      return .init(status: 200, body: body)
    }
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: http.transport, lifecycle: http.lifecycle, lease: lease)
    let read = Task { try await repo.group(linked: identity, context: context) }
    #expect(await barrier.waitEnteredOrFinished())
    if change == "logout" {
      await http.lifecycle.replace(
        .init(
          userID: UUID().uuidString, generation: lease.generation + 1, bearer: "synthetic-replaced")
      )
    } else {
      let next = try authority.beginRefresh()
      _ = try authority.accept(
        refreshID: next, authUserID: context.authUserID,
        ownerID: change == "patient" ? UUID() : context.ownerID,
        localSessionGeneration: lease.generation, epoch: change == "epoch" ? UUID() : context.epoch)
    }
    await barrier.release()
    await #expect(throws: (any Error).self) { try await read.value }
    #expect(await http.stub.requests.count == 1)
  }
}
private func linkedGroupEnvelope(_ raw: [String: Any]) throws -> Data {
  try JSONSerialization.data(withJSONObject: [
    "data": raw, "meta": ["api_version": "v1", "request_id": "synthetic-linked-group-read"],
  ])
}
