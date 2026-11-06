import Foundation
import Testing

@testable import BodyFlow

@Suite("Neutral intake uses the original authenticated HTTP family")
struct ConversationNeutralIntakeTransportTests {
  @Test func sessionPostAndReadCarryOnlyTheirExactOriginalProtocol() async throws {
    let f = try ConversationHTTPFixture()
    let reply = try neutralHTTP(neutralMealUnit()["response"]!)
    let ticket = try neutralRuntimeTicket()
    let lease = try await f.lifecycle.leaseForRequest()
    await f.stub.respond { req, _ in
      if req.url?.path.hasSuffix("/session") == true {
        return try neutralHTTP(neutralRuntimeSession(auth: lease.userID))
      }
      return reply
    }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    let session = try await api.session()
    #expect(session.ownerID == ticket.ownerID)
    _ = try await api.submit(ticket)
    _ = try await api.read(ticket)
    let requests = await f.stub.requests
    #expect(requests.count == 3)
    #expect(
      requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Conversation-Protocol") == "intake-v1" }
    )
    #expect(requests[1].httpBody == ticket.input.wireBody)
    #expect(requests[1].value(forHTTPHeaderField: "Idempotency-Key") == ticket.input.idempotencyKey)
    #expect(
      requests[2].value(forHTTPHeaderField: "X-Conversation-Input-Hash") == ticket.input.inputHash)
    #expect(requests[2].value(forHTTPHeaderField: "Idempotency-Key") == nil)
    #expect(
      requests[1].value(forHTTPHeaderField: "X-Conversation-Owner")
        == ticket.ownerID.uuidString.lowercased())
    #expect(
      requests[1].value(forHTTPHeaderField: "X-Conversation-Epoch")
        == ticket.epoch.uuidString.lowercased())
  }
  @Test(arguments: [401, 503]) func postNeverRefreshesOrAutomaticallyRepeats(_ status: Int)
    async throws
  {
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    await f.stub.respond { _, _ in .failure(status, "synthetic_failure") }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    await #expect(throws: (any Error).self) { try await api.submit(neutralRuntimeTicket()) }
    #expect(await f.stub.requests.count == 1)
    #expect(await f.lifecycle.refreshCount == 0)
  }
  @Test func successfulResponseRequiresExactIntakeProtocolEcho() async throws {
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    var wrong = try neutralHTTP(neutralMealUnit()["response"]!)
    wrong.headers["X-Conversation-Protocol"] = "meal-command-v1"
    let reply = wrong
    await f.stub.respond { _, _ in reply }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    await #expect(throws: (any Error).self) { try await api.submit(neutralRuntimeTicket()) }
  }
  @Test func lateResponseCannotCrossAnAuthenticationGeneration() async throws {
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    let reply = try neutralHTTP(neutralMealUnit()["response"]!)
    await f.stub.respond { _, _ in
      await f.lifecycle.replace(
        .init(userID: lease.userID, generation: lease.generation + 1, bearer: "synthetic-new"))
      return reply
    }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    await #expect(throws: (any Error).self) { try await api.submit(neutralRuntimeTicket()) }
    #expect(await f.stub.requests.count == 1)
  }
  @Test func headersRefuseBodyKeyMethodAndPathSubstitution() throws {
    let t = try neutralRuntimeTicket()
    let header = MobileConversationRequestHeaders.intakeSubmit(t)
    #expect(throws: (any Error).self) {
      try header.validate(
        method: .post, path: "/api/mobile/v1/conversation/meal-commands", query: [],
        body: t.input.wireBody, key: IdempotencyKey(validating: t.input.idempotencyKey),
        replay: .never)
    }
    #expect(throws: (any Error).self) {
      try header.validate(
        method: .post, path: "/api/mobile/v1/conversation/intakes", query: [],
        body: Data("{}".utf8), key: IdempotencyKey(validating: t.input.idempotencyKey),
        replay: .never)
    }
    #expect(throws: (any Error).self) {
      try header.validate(
        method: .post, path: "/api/mobile/v1/conversation/intakes", query: [],
        body: t.input.wireBody, key: IdempotencyKey(validating: t.input.idempotencyKey),
        replay: .standard)
    }
    var old = URLRequest(url: URL(string: "https://unit.invalid")!)
    MobileConversationRequestHeaders.session.apply(to: &old)
    #expect(old.value(forHTTPHeaderField: "X-Conversation-Protocol") == "meal-command-v1")
  }
  @Test(arguments: [200, 202]) func selectedSavedRequiresExactHTTPStatus(_ status: Int) async throws
  {
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    let reply = try neutralHTTP(neutralMealUnit()["response"]!, status: status)
    await f.stub.respond { _, _ in reply }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    if status == 200 {
      _ = try await api.submit(neutralRuntimeTicket())
    } else {
      await #expect(throws: (any Error).self) { try await api.submit(neutralRuntimeTicket()) }
    }
  }
}
func neutralRuntimeTicket(generation: UInt64 = 7) throws -> FlowNeutralIntakeTicket {
  let u = try neutralMealUnit()
  let b = u["binding"] as! [String: Any]
  return .init(
    input: try FlowNeutralIntakeInput(wireBody: neutralData(u["input"]!)),
    ownerID: UUID(uuidString: b["owner_id"] as! String)!,
    epoch: UUID(uuidString: b["epoch"] as! String)!, ownerHash: "synthetic",
    sessionGeneration: generation)
}
func neutralRuntimeSession(auth: String) throws -> [String: Any] {
  let t = try neutralRuntimeTicket()
  return [
    "schema": "conversation.intake-session.v1", "auth_user_id": auth,
    "owner_id": t.ownerID.uuidString.lowercased(), "epoch": t.epoch.uuidString.lowercased(),
    "observed_at": "2026-11-03T12:00:00Z", "intake_protocol": "conversation.intake.v1",
  ]
}
func neutralHTTP(_ payload: Any, status: Int = 200) throws -> ConversationHTTPReply {
  .init(
    status: status,
    body: try neutralData([
      "data": payload, "meta": ["api_version": "v1", "request_id": "neutral-runtime-unit-0001"],
    ]), headers: ["Content-Type": "application/json", "X-Conversation-Protocol": "intake-v1"])
}
