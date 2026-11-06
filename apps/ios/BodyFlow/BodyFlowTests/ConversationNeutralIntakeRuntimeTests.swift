import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Neutral actor and controller preserve original delivery and old meal queue")
struct ConversationNeutralIntakeRuntimeTests {
  @Test func unknownIsDurableBeforeSendAndExactSavedPacketRemovesOnlyNeutralRow() async throws {
    let f = try await neutralDisk()
    defer { f.disk.remove() }
    let old = try ConversationMealCommand(source: .text("old queued meal literal"))
    try f.disk.store.update(owner: f.owner, key: f.disk.key) {
      $0.append(
        .init(
          command: old, originalServerEpoch: f.server.epoch,
          originalPatientOwnerID: f.server.ownerID))
    }
    let actor = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    let input = try neutralRuntimeTicket().input
    _ = try await actor.enqueue(input: input, server: f.server)
    let ticket = try await actor.prepareDispatch(intakeID: input.intakeID, server: f.server)
    #expect(
      try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).first?.state
        == .dispatchedUnknown)
    let reply = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(neutralMealUnit()["response"]!))
    let seen = await MainActor.run { NeutralRuntimeProbe() }
    try await actor.acknowledgeSaved(ticket: ticket, response: reply, server: f.server) {
      seen.saved += 1
    }
    #expect(await seen.saved == 1)
    #expect(try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).isEmpty)
    #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).first?.wireBody == old.wireBody)
    await actor.invalidate()
  }
  @Test func restartReconciliationUsesSameIdentityAndForeignEpochCannotConsumeIt() async throws {
    let f = try await neutralDisk()
    defer { f.disk.remove() }
    let actor = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    let input = try neutralRuntimeTicket().input
    _ = try await actor.enqueue(input: input, server: f.server)
    _ = try await actor.prepareDispatch(intakeID: input.intakeID, server: f.server)
    await actor.invalidate()
    let next = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    let ticket = try await next.reconciliationTicket(intakeID: input.intakeID)
    #expect(ticket.input.wireBody == input.wireBody && ticket.input.inputHash == input.inputHash)
    let wrong = ConversationOutboxServerObservation(
      authUserID: f.server.authUserID, ownerID: f.server.ownerID,
      localSessionGeneration: f.server.localSessionGeneration, epoch: UUID())
    let reply = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(neutralMealUnit()["response"]!))
    await #expect(throws: (any Error).self) {
      try await next.acknowledgeSaved(ticket: ticket, response: reply, server: wrong) {}
    }
    #expect(try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).count == 1)
    await next.invalidate()
  }
  @Test func controllerDoesNotRepeatLostPostAndExplicitGetAcknowledgesActualReceipt() async throws {
    let disk = try OutboxDiskFixture()
    defer { disk.remove() }
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    let reply = try neutralHTTP(neutralMealUnit()["response"]!)
    await f.stub.respond { req, _ in
      if req.url?.path.hasSuffix("/session") == true {
        return try neutralHTTP(neutralRuntimeSession(auth: lease.userID))
      }
      if req.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
      return reply
    }
    let controller = try await ConversationNeutralIntakeController.open(
      transport: f.transport, lifecycle: f.lifecycle, store: disk.store,
      keyVault: .init(service: "neutral-unit", security: OutboxKeychainFake()), expectedLease: lease
    )
    let seen = await MainActor.run { NeutralRuntimeProbe() }
    let publish: ConversationNeutralIntakeController.Publisher = { event in
      seen.events.append(event)
      if case .saved = event { seen.saved += 1 }
    }
    try await controller.publishSnapshot(publish)
    let context = try #require(
      await seen.events.compactMap { if case .scopeAccepted(let c) = $0 { c } else { nil } }.last)
    let input = try neutralRuntimeTicket().input
    _ = try await controller.enqueue(
      input: input, expectedContext: context.identity, publish: publish)
    await #expect(throws: (any Error).self) {
      try await controller.send(intakeID: input.intakeID, publish: publish)
    }
    #expect(await seen.saved == 0)
    try await controller.reconcile(intakeID: input.intakeID, publish: publish)
    #expect(await seen.saved == 1)
    #expect(await f.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await controller.close()
  }
  @Test func actorCapacityUsesTheExistingFiftyRowsAndRefusesWithoutCiphertextMutation() async throws
  {
    let f = try await neutralDisk()
    defer { f.disk.remove() }
    try f.disk.store.update(owner: f.owner, key: f.disk.key) { rows in
      for n in 0..<50 {
        rows.append(
          .init(
            command: try ConversationMealCommand(source: .text("old original \(n)")),
            originalServerEpoch: f.server.epoch, originalPatientOwnerID: f.server.ownerID))
      }
    }
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    let actor = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    await #expect(throws: ConversationOutboxError.queueFull) {
      try await actor.enqueue(input: neutralRuntimeTicket().input, server: f.server)
    }
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == before)
    #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).count == 50)
    await actor.invalidate()
  }
  @Test func onlyFreshGetAllowsOneExplicitContinuationWithTheOriginalBodyAndKey() async throws {
    let disk = try OutboxDiskFixture()
    defer { disk.remove() }
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    let saved = try neutralHTTP(neutralMealUnit()["response"]!)
    let pending = try neutralPendingReply()
    let session = try neutralHTTP(neutralRuntimeSession(auth: lease.userID))
    await f.stub.respond { request, count in
      if request.url?.path.hasSuffix("/session") == true { return session }
      if request.httpMethod == "POST" && count == 3 { throw URLError(.networkConnectionLost) }
      return request.httpMethod == "POST" ? saved : pending
    }
    let c = try await ConversationNeutralIntakeController.open(
      transport: f.transport, lifecycle: f.lifecycle, store: disk.store,
      keyVault: .init(service: "neutral-runtime", security: OutboxKeychainFake()))
    let probe = await MainActor.run { NeutralRuntimeProbe() }
    let publish: ConversationNeutralIntakeController.Publisher = {
      probe.events.append($0)
      if case .saved = $0 { probe.saved += 1 }
    }
    try await c.publishSnapshot(publish)
    let context = try #require(
      await probe.events.compactMap { if case .scopeAccepted(let v) = $0 { v } else { nil } }.last)
    let input = try neutralRuntimeTicket().input
    _ = try await c.enqueue(input: input, expectedContext: context.identity, publish: publish)
    await #expect(throws: (any Error).self) {
      try await c.send(intakeID: input.intakeID, publish: publish)
    }
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await c.continueOriginal(intakeID: input.intakeID, publish: publish)
    }
    try await c.reconcile(intakeID: input.intakeID, publish: publish)
    #expect(await probe.saved == 0)
    #expect(await f.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    try await c.continueOriginal(intakeID: input.intakeID, publish: publish)
    let posts = await f.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(
      posts.count == 2
        && posts.allSatisfy {
          $0.httpBody == input.wireBody
            && $0.value(forHTTPHeaderField: "Idempotency-Key") == input.idempotencyKey
        })
    #expect(await probe.saved == 1)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await c.continueOriginal(intakeID: input.intakeID, publish: publish)
    }
    await c.close()
  }
  @Test func latePostCannotPublishAfterANewerScopeObservationAndFreshGetRecoversOnce() async throws
  {
    let disk = try OutboxDiskFixture()
    defer { disk.remove() }
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    let saved = try neutralHTTP(neutralMealUnit()["response"]!)
    let session = try neutralHTTP(neutralRuntimeSession(auth: lease.userID))
    let barrier = ConversationControllerBarrier()
    await f.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true { return session }
      if request.httpMethod == "POST" { await barrier.enter() }
      return saved
    }
    let c = try await ConversationNeutralIntakeController.open(
      transport: f.transport, lifecycle: f.lifecycle, store: disk.store,
      keyVault: .init(service: "neutral-runtime", security: OutboxKeychainFake()))
    let probe = await MainActor.run { NeutralRuntimeProbe() }
    let publish: ConversationNeutralIntakeController.Publisher = {
      probe.events.append($0)
      if case .saved = $0 { probe.saved += 1 }
    }
    try await c.publishSnapshot(publish)
    let context = try #require(
      await probe.events.compactMap { if case .scopeAccepted(let v) = $0 { v } else { nil } }.last)
    let input = try neutralRuntimeTicket().input
    _ = try await c.enqueue(input: input, expectedContext: context.identity, publish: publish)
    let old = Task {
      do { try await c.send(intakeID: input.intakeID, publish: publish) } catch {}
      await barrier.finish()
    }
    #expect(await barrier.waitEnteredOrFinished())
    try await c.refreshSession(publish)
    await barrier.release()
    await old.value
    #expect(await probe.saved == 0)
    try await c.reconcile(intakeID: input.intakeID, publish: publish)
    #expect(await probe.saved == 1)
    #expect(await f.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await c.close()
  }
  @Test(arguments: ["owner_id", "epoch"])
  func aNewOwnerOrEpochObservationNeverSendsTheOldQueuedInput(_ field: String) async throws {
    let disk = try OutboxDiskFixture()
    defer { disk.remove() }
    let f = try ConversationHTTPFixture()
    let lease = try await f.lifecycle.leaseForRequest()
    let session = try neutralHTTP(neutralRuntimeSession(auth: lease.userID))
    await f.stub.respond { _, _ in session }
    let c = try await ConversationNeutralIntakeController.open(
      transport: f.transport, lifecycle: f.lifecycle, store: disk.store,
      keyVault: .init(service: "neutral-runtime", security: OutboxKeychainFake()))
    let probe = await MainActor.run { NeutralRuntimeProbe() }
    let publish: ConversationNeutralIntakeController.Publisher = { probe.events.append($0) }
    try await c.publishSnapshot(publish)
    let context = try #require(
      await probe.events.compactMap { if case .scopeAccepted(let v) = $0 { v } else { nil } }.last)
    let input = try neutralRuntimeTicket().input
    _ = try await c.enqueue(input: input, expectedContext: context.identity, publish: publish)
    var changed = try neutralRuntimeSession(auth: lease.userID)
    changed[field] = UUID().uuidString.lowercased()
    let fresh = try neutralHTTP(changed)
    await f.stub.respond { _, _ in fresh }
    await #expect(throws: (any Error).self) {
      try await c.send(intakeID: input.intakeID, publish: publish)
    }
    #expect(await f.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
    let snapshot = try #require(
      await probe.events.compactMap { if case .snapshot(let v) = $0 { v } else { nil } }.last)
    #expect(snapshot.entries.isEmpty && snapshot.heldIDs == [input.intakeID])
    await c.close()
  }

  @Test func terminalCASIsIdempotentAndRefusesNewerStateReservationOrResult() async throws {
    let f = try await neutralDisk()
    defer { f.disk.remove() }
    let actor = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    let input = try neutralRuntimeTicket().input
    _ = try await actor.enqueue(input: input, server: f.server)
    let ticket = try await actor.prepareDispatch(intakeID: input.intakeID, server: f.server)
    let old = try await actor.captureTerminalCAS(ticket: ticket, server: f.server)
    let response = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self,
      from: neutralData(neutralNotRecordedUnit(variant: "outer_not_recorded_unit")))
    let probe = await MainActor.run { NeutralRuntimeProbe() }
    try await actor.markWaiting(ticket: ticket, hold: .unknownOutcome, server: f.server)
    let afterNewState = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    await #expect(throws: (any Error).self) {
      try await actor.resolveTerminal(cas: old, response: response, server: f.server) {
        probe.terminalCallbacks += 1
      }
    }
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == afterNewState)
    let stale = try await actor.captureTerminalCAS(ticket: ticket, server: f.server)
    let current = try await actor.captureTerminalCAS(ticket: ticket, server: f.server)
    await #expect(throws: (any Error).self) {
      try await actor.resolveTerminal(cas: stale, response: response, server: f.server) {
        probe.terminalCallbacks += 1
      }
    }
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == afterNewState)
    try await actor.resolveTerminal(cas: current, response: response, server: f.server) {
      probe.terminalCallbacks += 1
    }
    let closed = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    try await actor.resolveTerminal(cas: current, response: response, server: f.server) {
      probe.terminalCallbacks += 1
    }
    #expect(await probe.terminalCallbacks == 1)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == closed)
    var changed = try neutralNotRecordedUnit(variant: "outer_not_recorded_unit")
    changed["reason"] = "different_result"
    let conflicting = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(changed))
    await #expect(throws: (any Error).self) {
      try await actor.resolveTerminal(cas: current, response: conflicting, server: f.server) {
        probe.terminalCallbacks += 1
      }
    }
    await #expect(throws: (any Error).self) {
      try await actor.enqueue(input: input, server: f.server)
    }
    #expect(await probe.terminalCallbacks == 1)
    #expect(try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).isEmpty)
    await actor.invalidate()
  }
  @Test(arguments: [
    "owner_id", "intake_id", "input_hash", "epoch", "auth", "generation", "body", "pending", "held",
    "clarification", "absent", "saved", "protected_hold", "revoked",
  ])
  func terminalResolutionRefusesForeignOrUncertainEvidenceWithoutChangingCiphertext(
    _ attack: String
  ) async throws {
    let f = try await neutralDisk()
    defer { f.disk.remove() }
    let actor = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    let input = try neutralRuntimeTicket().input
    _ = try await actor.enqueue(input: input, server: f.server)
    let ticket = try await actor.prepareDispatch(intakeID: input.intakeID, server: f.server)
    if attack == "protected_hold" {
      try await actor.markWaiting(ticket: ticket, hold: .serverChanged, server: f.server)
    }
    let cas = try await actor.captureTerminalCAS(ticket: ticket, server: f.server)
    var raw = try neutralNotRecordedUnit(variant: "outer_not_recorded_unit")
    var server = f.server
    if ["owner_id", "intake_id", "input_hash", "epoch"].contains(attack) {
      var b = raw["intake"] as! [String: Any]
      b[attack] =
        attack == "input_hash" ? String(repeating: "b", count: 64) : UUID().uuidString.lowercased()
      raw["intake"] = b
    }
    if attack == "auth" || attack == "generation" {
      server = .init(
        authUserID: attack == "auth" ? UUID() : f.server.authUserID, ownerID: f.server.ownerID,
        localSessionGeneration: attack == "generation"
          ? f.server.localSessionGeneration + 1 : f.server.localSessionGeneration,
        epoch: f.server.epoch)
    }
    if ["pending", "held", "clarification", "absent", "saved"].contains(attack) {
      raw = try neutralUncertainUnit(attack)
    }
    let response = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self, from: neutralData(raw))
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    let probe = await MainActor.run { NeutralRuntimeProbe() }
    if attack == "body" {
      let changed = try FlowNeutralIntakeInput(
        intakeID: input.intakeID, source: .text("different immutable original"))
      await #expect(throws: (any Error).self) {
        try await actor.enqueue(input: changed, server: f.server)
      }
    } else {
      if attack == "revoked" {
        await f.lifecycle.replace(
          lease: .init(
            userID: f.disk.lease.userID, generation: f.disk.lease.generation + 1,
            bearer: "synthetic-new"))
      }
      let observed = server
      await #expect(throws: (any Error).self) {
        try await actor.resolveTerminal(cas: cas, response: response, server: observed) {
          probe.terminalCallbacks += 1
        }
      }
    }
    #expect(await probe.terminalCallbacks == 0)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == before)
    await actor.invalidate()
  }
  @Test func fiftyFiveTerminalsDrainOnlyTheirOriginalSlotAndKeepFortyNineLegacyRows() async throws {
    let f = try await neutralDisk()
    defer { f.disk.remove() }
    var originals: [Data] = []
    try f.disk.store.update(owner: f.owner, key: f.disk.key) { rows in
      for n in 0..<48 {
        let c = try ConversationMealCommand(source: .text("legacy literal \(n)"))
        originals.append(c.wireBody)
        rows.append(
          .init(
            command: c, originalServerEpoch: f.server.epoch,
            originalPatientOwnerID: f.server.ownerID))
      }
    }
    let reply = try neutralRuntimeReply()
    try f.disk.store.updateReplies(owner: f.owner, key: f.disk.key) {
      $0.append(.init(intent: reply))
    }
    let actor = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    for _ in 0..<55 {
      let input = try FlowNeutralIntakeInput(
        intakeID: UUID(), source: .text("unit terminal original"))
      _ = try await actor.enqueue(input: input, server: f.server)
      let ticket = try await actor.prepareDispatch(intakeID: input.intakeID, server: f.server)
      let cas = try await actor.captureTerminalCAS(ticket: ticket, server: f.server)
      var raw = try neutralNotRecordedUnit(variant: "outer_not_recorded_unit")
      var binding = raw["intake"] as! [String: Any]
      binding["intake_id"] = input.intakeID.uuidString.lowercased()
      binding["input_hash"] = input.inputHash
      raw["intake"] = binding
      let response = try JSONDecoder().decode(
        FlowNeutralIntakeResponseSnapshot.self, from: neutralData(raw))
      try await actor.resolveTerminal(cas: cas, response: response, server: f.server) {}
    }
    #expect(try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).isEmpty)
    #expect(
      try f.disk.store.loadReplies(owner: f.owner, key: f.disk.key).first?.intent.wireBody
        == reply.wireBody)
    #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).map(\.wireBody) == originals)
    _ = try await actor.enqueue(
      input: FlowNeutralIntakeInput(intakeID: UUID(), source: .text("new legitimate original")),
      server: f.server)
    await #expect(throws: ConversationOutboxError.queueFull) {
      try await actor.enqueue(
        input: FlowNeutralIntakeInput(intakeID: UUID(), source: .text("fifty first")),
        server: f.server)
    }
    #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).count == 48)
    #expect(try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).count == 1)
    await actor.invalidate()
  }
  @Test func aNewGrantCannotUpgradeAnOlderTerminalCASWithTheSameOwnerTuple() async throws {
    let f = try await neutralDisk()
    defer { f.disk.remove() }
    let authority = ConversationOutboxObservationAuthority()
    let refresh = try authority.beginRefresh()
    let original = try authority.accept(
      refreshID: refresh, authUserID: f.server.authUserID, ownerID: f.server.ownerID,
      localSessionGeneration: f.server.localSessionGeneration, epoch: f.server.epoch)
    let actor = try await ConversationNeutralIntakeOutboxSession.open(
      lifecycle: f.lifecycle, store: f.disk.store, keyVault: f.vault)
    let input = try neutralRuntimeTicket().input
    _ = try await actor.enqueue(input: input, server: original)
    let ticket = try await actor.prepareDispatch(intakeID: input.intakeID, server: original)
    let cas = try await actor.captureTerminalCAS(ticket: ticket, server: original)
    let next = try authority.beginRefresh()
    let current = try authority.accept(
      refreshID: next, authUserID: f.server.authUserID, ownerID: f.server.ownerID,
      localSessionGeneration: f.server.localSessionGeneration, epoch: f.server.epoch)
    let response = try JSONDecoder().decode(
      FlowNeutralIntakeResponseSnapshot.self,
      from: neutralData(neutralNotRecordedUnit(variant: "outer_not_recorded_unit")))
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    let probe = await MainActor.run { NeutralRuntimeProbe() }
    await #expect(throws: (any Error).self) {
      try await actor.resolveTerminal(cas: cas, response: response, server: current) {
        probe.terminalCallbacks += 1
      }
    }
    #expect(await probe.terminalCallbacks == 0)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == before)
    await actor.invalidate()
  }

}
@MainActor final class NeutralRuntimeProbe {
  var events: [ConversationNeutralIntakeEvent] = []
  var saved = 0
  var terminalCallbacks = 0
}
struct NeutralDisk {
  let disk: OutboxDiskFixture
  let lifecycle: OutboxLifecycleFake
  let vault: ConversationOutboxKeyVault
  let owner: ConversationOutboxOwner
  let server: ConversationOutboxServerObservation
}
func neutralDisk() async throws -> NeutralDisk {
  let disk = try OutboxDiskFixture()
  let owner = try ConversationOutboxOwner(lease: disk.lease)
  let keychain = OutboxKeychainFake()
  let ticket = try neutralRuntimeTicket()
  await keychain.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
  return .init(
    disk: disk, lifecycle: OutboxLifecycleFake(lease: disk.lease),
    vault: .init(service: "neutral-unit", security: keychain), owner: owner,
    server: .init(
      authUserID: UUID(uuidString: disk.lease.userID)!, ownerID: ticket.ownerID,
      localSessionGeneration: disk.lease.generation, epoch: ticket.epoch))
}

func neutralPendingReply() throws -> ConversationHTTPReply {
  let unit = try neutralMealUnit()
  let packet = unit["response"] as! [String: Any]
  let t = try neutralRuntimeTicket()
  return try neutralHTTP(
    [
      "schema": "conversation.intake-result.v1", "status": "pending", "intake": packet["intake"]!,
      "lookup": [
        "ownerId": t.ownerID.uuidString.lowercased(),
        "intakeId": t.input.intakeID.uuidString.lowercased(), "inputHash": t.input.inputHash,
        "epoch": t.epoch.uuidString.lowercased(),
      ], "reason": "processing",
    ], status: 202)
}

/// Closed counterfactual UNIT statuses, using the existing exact intake binding.
func neutralUncertainUnit(_ status: String) throws -> [String: Any] {
  let packet = try neutralMealUnit()["response"] as! [String: Any]
  let t = try neutralRuntimeTicket()
  if status == "saved" { return packet }
  if status == "clarification" {
    var value = try neutralNotRecordedUnit(variant: "outer_not_recorded_unit")
    value["status"] = "clarification_required"
    value["question"] = ["field": "description", "text": "O que você já consumiu ou realizou?"]
    return value
  }
  var value: [String: Any] = [
    "schema": "conversation.intake-result.v1", "status": status,
    "lookup": [
      "ownerId": t.ownerID.uuidString.lowercased(),
      "intakeId": t.input.intakeID.uuidString.lowercased(), "inputHash": t.input.inputHash,
      "epoch": t.epoch.uuidString.lowercased(),
    ],
  ]
  if status != "absent" {
    value["intake"] = packet["intake"]
    value["reason"] = "processing"
  }
  return value
}

private func neutralRuntimeReply() throws -> ConversationMealReplyIntent {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "Fixtures/ConversationMealReplyPublicFixtures.json")
  let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  let saved = (root["saved"] as! [String: Any])["data"] as! [String: Any]
  let needs = (root["needs_reply"] as! [String: Any])["data"] as! [String: Any]
  let binding = try JSONDecoder().decode(
    ConversationThreadPageSnapshot.Binding.self, from: neutralData(saved["parent_binding"]!))
  let question = try JSONDecoder().decode(
    ConversationThreadPageSnapshot.Question.self, from: neutralData(needs["question"]!))
  return try .init(
    parentBinding: binding, parentDecisionHash: saved["parent_decision_hash"] as! String,
    question: question, replyID: UUID(), answer: .mealType(.almoco))
}
