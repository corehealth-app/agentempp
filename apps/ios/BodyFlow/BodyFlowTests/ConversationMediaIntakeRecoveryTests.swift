import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Media interruptions resume only the original fenced intake")
struct ConversationMediaIntakeRecoveryTests {
  @Test func anOlderReplayProbeCannotOverwriteTheNewerContinuationGrant() async throws {
    let gate = MediaRecoveryReturnGate()
    let f = try await mediaRecoveryFixture(
      initialReason: "media_temporarily_unavailable", loseFirstPost: true, returnGate: gate)
    defer { f.disk.remove() }
    await #expect(throws: (any Error).self) {
      try await f.controller.send(intakeID: f.input.intakeID, publish: f.publish)
    }
    await f.scenario.enable()
    let barrier = ConversationControllerBarrier()
    // In receive(), markWaiting and then the readonly replay probe return Void.
    // Pause the latter after its real encrypted transaction already ran.
    await gate.holdSecondVoidReturn(barrier)
    let older = Task {
      do { try await f.controller.reconcile(intakeID: f.input.intakeID, publish: f.publish) } catch
      {}
      await barrier.finish()
    }
    #expect(await barrier.waitEnteredOrFinished())
    try await f.controller.reconcile(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await mediaCanContinue(f.probe) == true)
    await barrier.release()
    await older.value
    try await f.controller.continueOriginal(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await f.scenario.posts == 2)
    #expect(await f.probe.saved == 1)
    #expect(try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).isEmpty)
    await f.controller.close()
  }
  @Test func temporarilyDisabledMediaWaitsForFreshReadAndExplicitContinuation() async throws {
    let f = try await mediaRecoveryFixture(initialReason: "media_temporarily_unavailable")
    defer { f.disk.remove() }
    try await f.controller.send(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await f.probe.saved == 0)
    try await f.controller.reconcile(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await mediaCanContinue(f.probe) == false)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await f.controller.continueOriginal(intakeID: f.input.intakeID, publish: f.publish)
    }
    #expect(await f.scenario.posts == 1)
    await f.scenario.enable()
    try await f.controller.reconcile(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await mediaCanContinue(f.probe) == true)
    #expect(await f.scenario.posts == 1)
    try await f.controller.continueOriginal(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await f.probe.saved == 1)
    let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 2 && posts.allSatisfy { $0.httpBody == f.input.wireBody })
    #expect(
      posts.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == f.input.idempotencyKey }
    )
    #expect(try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).isEmpty)
    await f.controller.close()
  }
  @Test func responseLostBeforeClaimResumesOnceOnlyAfterAnExplicitPendingRead() async throws {
    let f = try await mediaRecoveryFixture(
      initialReason: "media_temporarily_unavailable", loseFirstPost: true)
    defer { f.disk.remove() }
    await #expect(throws: (any Error).self) {
      try await f.controller.send(intakeID: f.input.intakeID, publish: f.publish)
    }
    #expect(await f.scenario.posts == 1)
    #expect(await f.probe.saved == 0)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await f.controller.continueOriginal(intakeID: f.input.intakeID, publish: f.publish)
    }
    await f.scenario.enable()
    try await f.controller.reconcile(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await mediaCanContinue(f.probe) == true)
    #expect(await f.scenario.posts == 1)
    try await f.controller.continueOriginal(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await f.scenario.posts == 2)
    #expect(await f.probe.saved == 1)
    let bodies = await f.http.stub.requests.filter { $0.httpMethod == "POST" }.map(\.httpBody)
    #expect(bodies.count == 2 && bodies.allSatisfy { $0 == f.input.wireBody })
    await f.controller.close()
  }
  @Test(arguments: ["day_closed", "input_conflict", "media_projection_required"])
  func aPermanentHoldCannotBeDowngradedByAContradictoryPendingRead(_ reason: String) async throws {
    let f = try await mediaRecoveryFixture(initialReason: reason)
    defer { f.disk.remove() }
    try await f.controller.send(intakeID: f.input.intakeID, publish: f.publish)
    await f.scenario.enable()
    try await f.controller.reconcile(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await mediaCanContinue(f.probe) == false)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await f.controller.continueOriginal(intakeID: f.input.intakeID, publish: f.publish)
    }
    #expect(await f.scenario.posts == 1)
    #expect(await f.probe.saved == 0)
    #expect(
      try f.disk.store.loadIntakes(owner: f.owner, key: f.disk.key).first?.hold == .serverChanged)
    await f.controller.close()
  }
  @Test func anotherGrantInvalidatesAnOlderPendingReadPermissionEvenForTheSameIdentity()
    async throws
  {
    let f = try await mediaRecoveryFixture(
      initialReason: "media_temporarily_unavailable", loseFirstPost: true)
    defer { f.disk.remove() }
    await #expect(throws: (any Error).self) {
      try await f.controller.send(intakeID: f.input.intakeID, publish: f.publish)
    }
    await f.scenario.enable()
    try await f.controller.reconcile(intakeID: f.input.intakeID, publish: f.publish)
    #expect(await mediaCanContinue(f.probe) == true)
    try await f.controller.refreshSession(f.publish)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await f.controller.continueOriginal(intakeID: f.input.intakeID, publish: f.publish)
    }
    #expect(await f.scenario.posts == 1)
    #expect(await f.probe.saved == 0)
    await f.controller.close()
  }
}
private func mediaCanContinue(_ probe: NeutralRuntimeProbe) async -> Bool? {
  await probe.events.compactMap { if case .state(_, _, let value, _) = $0 { value } else { nil } }
    .last
}
private actor MediaRecoveryScenario {
  let opening: ConversationHTTPReply
  let held: ConversationHTTPReply
  let pending: ConversationHTTPReply
  let saved: ConversationHTTPReply
  let loseFirstPost: Bool
  var enabled = false
  private(set) var posts = 0
  init(
    opening: ConversationHTTPReply, held: ConversationHTTPReply, pending: ConversationHTTPReply,
    saved: ConversationHTTPReply, loseFirstPost: Bool
  ) {
    self.opening = opening
    self.held = held
    self.pending = pending
    self.saved = saved
    self.loseFirstPost = loseFirstPost
  }
  func enable() { enabled = true }
  func respond(_ request: URLRequest) throws -> ConversationHTTPReply {
    if request.url?.path.hasSuffix("/session") == true { return opening }
    if request.httpMethod == "POST" {
      posts += 1
      if posts == 1 && loseFirstPost { throw URLError(.networkConnectionLost) }
      return enabled ? saved : held
    }
    return enabled ? pending : held
  }
}
private struct MediaRecoveryFixture {
  let disk: OutboxDiskFixture
  let http: ConversationHTTPFixture
  let owner: ConversationOutboxOwner
  let input: FlowNeutralIntakeInput
  let scenario: MediaRecoveryScenario
  let controller: ConversationNeutralIntakeController
  let probe: NeutralRuntimeProbe
  let publish: ConversationNeutralIntakeController.Publisher
}
private func mediaRecoveryFixture(
  initialReason: String, loseFirstPost: Bool = false,
  returnGate: MediaRecoveryReturnGate? = nil
) async throws
  -> MediaRecoveryFixture
{
  let disk = try OutboxDiskFixture()
  let http = try ConversationHTTPFixture()
  let lease = await http.lifecycle.leaseForRequest()
  let owner = try ConversationOutboxOwner(lease: lease)
  let security = OutboxKeychainFake()
  await security.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
  let vault = ConversationOutboxKeyVault(service: "media-recovery-unit", security: security)
  let unit = try mediaIntakeUnit("meal_photo")
  let sample = try mediaIntakeTicket(unit, generation: lease.generation)
  let opening = try neutralHTTP([
    "schema": "conversation.intake-session.v1", "auth_user_id": lease.userID,
    "owner_id": sample.ownerID.uuidString.lowercased(),
    "epoch": sample.epoch.uuidString.lowercased(),
    "observed_at": "2026-11-06T04:00:00.000001Z", "intake_protocol": "conversation.intake.v1",
  ])
  let lookup: [String: Any] = [
    "ownerId": sample.ownerID.uuidString.lowercased(),
    "intakeId": sample.input.intakeID.uuidString.lowercased(), "inputHash": sample.input.inputHash,
    "epoch": sample.epoch.uuidString.lowercased(),
  ]
  let held = try mediaIntakeHTTP(
    [
      "schema": "conversation.intake-result.v1", "status": "held", "intake": unit["binding"]!,
      "lookup": lookup, "reason": initialReason,
    ], status: 202)
  let pending = try mediaIntakeHTTP(
    [
      "schema": "conversation.intake-result.v1", "status": "pending", "intake": unit["binding"]!,
      "lookup": lookup, "reason": "intake_pending",
    ], status: 202)
  let saved = try mediaIntakeHTTP(unit["response"]!)
  let scenario = MediaRecoveryScenario(
    opening: opening, held: held, pending: pending, saved: saved, loseFirstPost: loseFirstPost)
  await http.stub.respond { request, _ in try await scenario.respond(request) }
  let lifecycle: any SessionLifecycleProviding
  if let returnGate {
    lifecycle = MediaRecoveryGatedLifecycle(base: http.lifecycle, gate: returnGate)
  } else {
    lifecycle = http.lifecycle
  }
  let controller = try await ConversationNeutralIntakeController.open(
    transport: http.transport, lifecycle: lifecycle, store: disk.store, keyVault: vault,
    expectedLease: lease)
  let probe = await MainActor.run { NeutralRuntimeProbe() }
  let publish: ConversationNeutralIntakeController.Publisher = { event in
    probe.events.append(event)
    if case .saved = event { probe.saved += 1 }
  }
  try await controller.publishSnapshot(publish)
  let context = try #require(
    await probe.events.compactMap {
      if case .scopeAccepted(let context) = $0 { context } else { nil }
    }.last)
  _ = try await controller.enqueue(
    input: sample.input, expectedContext: context.identity, publish: publish)
  return .init(
    disk: disk, http: http, owner: owner, input: sample.input, scenario: scenario,
    controller: controller, probe: probe, publish: publish)
}

private actor MediaRecoveryReturnGate {
  private var remaining = 0
  private var barrier: ConversationControllerBarrier?
  func holdSecondVoidReturn(_ value: ConversationControllerBarrier) {
    remaining = 2
    barrier = value
  }
  func afterVoidReturn() async {
    guard remaining > 0 else { return }
    remaining -= 1
    if remaining == 0, let value = barrier {
      barrier = nil
      await value.enter()
    }
  }
}

private struct MediaRecoveryGatedLifecycle: SessionLifecycleProviding {
  let base: ConversationHTTPTestLifecycle
  let gate: MediaRecoveryReturnGate
  func currentBearerToken() async -> String? { await base.currentBearerToken() }
  func leaseForRequest() async throws -> SessionLease { await base.leaseForRequest() }
  func validate(_ lease: SessionLease) async throws { try await base.validate(lease) }
  func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease {
    try await base.refreshAfterUnauthorized(lease: lease)
  }
  func signOut() async -> RemoteRevocationOutcome { await base.signOut() }
  func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws
    -> UUID
  { try await base.beginPatientWork(lease: lease, cancel: cancel) }
  func finishPatientWork(_ id: UUID) async { await base.finishPatientWork(id) }
  func performPatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @Sendable () throws -> Value
  ) async throws -> Value {
    let result = try await base.performPatientStateOperation(lease: lease, operation: operation)
    if Value.self == Void.self { await gate.afterVoidReturn() }
    return result
  }
  func performVisiblePatientStateOperation<Value: Sendable>(
    lease: SessionLease, operation: @MainActor @Sendable () throws -> Value
  ) async throws -> Value {
    try await base.performVisiblePatientStateOperation(lease: lease, operation: operation)
  }
}
