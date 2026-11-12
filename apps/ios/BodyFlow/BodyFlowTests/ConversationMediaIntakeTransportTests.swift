import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Neutral media negotiation stays on the original authenticated intake")
struct ConversationMediaIntakeTransportTests {
  @Test func onlyTheOriginalMediaPostAndReadSelectProvenance() throws {
    let ticket = try mediaIntakeTicket(mediaIntakeUnit("meal_photo"))
    for header in [
      MobileConversationRequestHeaders.intakeSubmit(ticket), .intakeReconciliation(ticket),
    ] {
      var request = URLRequest(url: URL(string: "https://unit.invalid")!)
      header.apply(to: &request)
      #expect(request.value(forHTTPHeaderField: "X-Conversation-Media-Provenance") == "1")
      #expect(request.value(forHTTPHeaderField: "X-Conversation-Protocol") == "intake-v1")
    }
    for header in [
      MobileConversationRequestHeaders.intakeSession, .intakeSubmit(try neutralRuntimeTicket()),
      .session,
    ] {
      var request = URLRequest(url: URL(string: "https://unit.invalid")!)
      header.apply(to: &request)
      #expect(request.value(forHTTPHeaderField: "X-Conversation-Media-Provenance") == nil)
    }
  }
  @Test(arguments: ["meal_photo", "audio_workout"])
  func savedMediaPostAndReadCarryTheSameOriginalBodyAndFactualProjection(_ label: String)
    async throws
  {
    let f = try ConversationHTTPFixture()
    let lease = await f.lifecycle.leaseForRequest()
    let unit = try mediaIntakeUnit(label)
    let ticket = try mediaIntakeTicket(unit, generation: lease.generation)
    let reply = try mediaIntakeHTTP(unit["response"]!)
    await f.stub.respond { _, _ in reply }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    #expect(try await api.submit(ticket).factualAcknowledgement(for: ticket) != nil)
    #expect(try await api.read(ticket).factualAcknowledgement(for: ticket) != nil)
    let requests = await f.stub.requests
    #expect(requests.count == 2)
    #expect(
      requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Conversation-Media-Provenance") == "1" }
    )
    #expect(requests[0].httpBody == ticket.input.wireBody)
    #expect(requests[0].value(forHTTPHeaderField: "Idempotency-Key") == ticket.input.idempotencyKey)
    #expect(requests[1].httpBody == nil && requests[1].httpMethod == "GET")
    #expect(
      requests[1].value(forHTTPHeaderField: "X-Conversation-Input-Hash") == ticket.input.inputHash)
  }
  @Test(arguments: [nil, "2", "1, 1"] as [String?])
  func successfulMediaResponseRequiresExactEchoEvenWhenHeld(_ echo: String?) async throws {
    let f = try ConversationHTTPFixture()
    let lease = await f.lifecycle.leaseForRequest()
    let ticket = try mediaIntakeTicket(mediaIntakeUnit("meal_photo"), generation: lease.generation)
    let b = try mediaIntakeUnit("meal_photo")["binding"]!
    let held: [String: Any] = [
      "schema": "conversation.intake-result.v1", "status": "held", "intake": b,
      "lookup": [
        "ownerId": ticket.ownerID.uuidString.lowercased(),
        "intakeId": ticket.input.intakeID.uuidString.lowercased(),
        "inputHash": ticket.input.inputHash, "epoch": ticket.epoch.uuidString.lowercased(),
      ], "reason": "media_projection_required",
    ]
    var reply = try mediaIntakeHTTP(held, status: 202)
    reply.headers["X-Conversation-Media-Provenance"] = echo
    let result = reply
    await f.stub.respond { _, _ in result }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    await #expect(throws: MobileAPITransportError.invalidResponse) { try await api.submit(ticket) }
    #expect(await f.stub.requests.count == 1)
  }
  @Test func unsolicitedMediaEchoCannotSelectTheDecoderForAnOrdinaryIntakeRequest() async throws {
    let f = try ConversationHTTPFixture()
    let lease = await f.lifecycle.leaseForRequest()
    let reply = try mediaIntakeHTTP(mediaIntakeUnit("meal_photo")["response"]!)
    await f.stub.respond { _, _ in reply }
    let request = try MobileAPIRequest<FlowNeutralIntakeResponseSnapshot>(
      method: .get,
      path: "/api/mobile/v1/conversation/intakes/session", conversation: .intakeSession)
    await #expect(throws: MobileAPITransportError.decodingFailure) {
      try await f.transport.executeHTTP(request)
    }
    #expect(await f.lifecycle.leaseForRequest().generation == lease.generation)
  }
  @Test func savedMediaCannotCrossALateAuthenticationGeneration() async throws {
    let f = try ConversationHTTPFixture()
    let lease = await f.lifecycle.leaseForRequest()
    let unit = try mediaIntakeUnit("meal_photo")
    let ticket = try mediaIntakeTicket(unit, generation: lease.generation)
    let reply = try mediaIntakeHTTP(unit["response"]!)
    await f.stub.respond { _, _ in
      await f.lifecycle.replace(
        .init(userID: lease.userID, generation: lease.generation + 1, bearer: "synthetic-new"))
      return reply
    }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    await #expect(throws: (any Error).self) { try await api.submit(ticket) }
    #expect(await f.stub.requests.count == 1)
  }
  @Test func encryptedMediaSurvivesLostResponseAndRestartWithoutRepeatingThePost() async throws {
    let disk = try OutboxDiskFixture()
    defer { disk.remove() }
    let f = try ConversationHTTPFixture()
    let lease = await f.lifecycle.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let security = OutboxKeychainFake()
    await security.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    let vault = ConversationOutboxKeyVault(service: "neutral-media-unit", security: security)
    let unit = try mediaIntakeUnit("meal_photo")
    let sample = try mediaIntakeTicket(unit, generation: lease.generation)
    let session: [String: Any] = [
      "schema": "conversation.intake-session.v1", "auth_user_id": lease.userID,
      "owner_id": sample.ownerID.uuidString.lowercased(),
      "epoch": sample.epoch.uuidString.lowercased(),
      "observed_at": "2026-11-06T04:00:00.000001Z", "intake_protocol": "conversation.intake.v1",
    ]
    let opening = try neutralHTTP(session)
    let saved = try mediaIntakeHTTP(unit["response"]!)
    await f.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true { return opening }
      if request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
      return saved
    }
    let controller = try await ConversationNeutralIntakeController.open(
      transport: f.transport, lifecycle: f.lifecycle, store: disk.store, keyVault: vault,
      expectedLease: lease)
    let probe = await MainActor.run { NeutralRuntimeProbe() }
    let publish: ConversationNeutralIntakeController.Publisher = { event in
      probe.events.append(event)
      if case .saved = event { probe.saved += 1 }
    }
    try await controller.publishSnapshot(publish)
    let context = try #require(
      await probe.events.compactMap {
        if case .scopeAccepted(let value) = $0 { value } else { nil }
      }.last)
    let legacy = try ConversationMealCommand(source: .text("unrelated old meal queue"))
    try disk.store.update(owner: owner, key: disk.key) { rows in
      rows.append(
        .init(
          command: legacy, originalServerEpoch: context.epoch,
          originalPatientOwnerID: context.ownerID))
    }
    _ = try await controller.enqueue(
      input: sample.input, expectedContext: context.identity, publish: publish)
    await #expect(throws: (any Error).self) {
      try await controller.send(intakeID: sample.input.intakeID, publish: publish)
    }
    #expect(await probe.saved == 0)
    #expect(
      try disk.store.loadIntakes(owner: owner, key: disk.key).first?.input.wireBody
        == sample.input.wireBody)
    await controller.close()
    let restored = try await ConversationNeutralIntakeController.open(
      transport: f.transport, lifecycle: f.lifecycle, store: disk.store, keyVault: vault,
      expectedLease: lease)
    try await restored.publishSnapshot(publish)
    try await restored.reconcile(intakeID: sample.input.intakeID, publish: publish)
    #expect(await probe.saved == 1)
    #expect(try disk.store.loadIntakes(owner: owner, key: disk.key).isEmpty)
    #expect(try disk.store.load(owner: owner, key: disk.key).first?.wireBody == legacy.wireBody)
    let requests = await f.stub.requests
    #expect(requests.filter { $0.httpMethod == "POST" }.count == 1)
    let reads = requests.filter {
      $0.url?.path.hasSuffix(sample.input.intakeID.uuidString.lowercased()) == true
    }
    #expect(
      reads.count == 1
        && reads[0].value(forHTTPHeaderField: "X-Conversation-Media-Provenance") == "1")
    #expect(requests.first { $0.httpMethod == "POST" }?.httpBody == sample.input.wireBody)
    await restored.close()
  }

  @Test(arguments: [401, 503]) func mediaPostNeverRefreshesOrRepeats(_ status: Int) async throws {
    let f = try ConversationHTTPFixture()
    let lease = await f.lifecycle.leaseForRequest()
    let ticket = try mediaIntakeTicket(mediaIntakeUnit("meal_photo"), generation: lease.generation)
    await f.stub.respond { _, _ in .failure(status, "synthetic_failure") }
    let api = try await MobileConversationIntakeRepository.scoped(
      transport: f.transport, lease: lease)
    await #expect(throws: (any Error).self) { try await api.submit(ticket) }
    #expect(await f.stub.requests.count == 1)
    #expect(await f.lifecycle.refreshCount == 0)
  }
}
func mediaIntakeHTTP(_ payload: Any, status: Int = 200) throws -> ConversationHTTPReply {
  var response = try neutralHTTP(payload, status: status)
  response.headers["X-Conversation-Media-Provenance"] = "1"
  response.headers["Cache-Control"] = "no-store"
  return response
}
