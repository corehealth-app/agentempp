import Foundation
import Testing

@testable import BodyFlow

@Suite("Actual typed linked reply controller stays exact and read-only after uncertainty")
struct ConversationMealReplyControllerTests {
  @Test(arguments: ["patient", "epoch", "logout"])
  func oldPreparedAnswerCannotEscapeAfterItsStateOperationReturns(_ change: String) async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let gate = EditMutationGate()
    let lifecycle = EditGatedLifecycle(base: f.http.lifecycle, gate: gate)
    let controller = try await ConversationMealReplyController.open(
      transport: f.http.transport, lifecycle: lifecycle, store: f.disk.store,
      keyVault: .init(security: f.keys), expectedLease: f.disk.lease)
    let barrier = ConversationControllerBarrier()
    await gate.holdNextStateReturn(barrier)
    let pending = Task { try await f.prepare(controller) }
    #expect(await barrier.waitEnteredOrFinished())
    if change == "logout" {
      await f.http.lifecycle.replace(
        .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-replaced"))
    } else {
      let token = try f.authority.beginRefresh()
      _ = try f.authority.accept(
        refreshID: token, authUserID: f.context.authUserID,
        ownerID: change == "patient" ? UUID() : f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration,
        epoch: change == "epoch" ? UUID() : f.context.epoch)
    }
    await barrier.release()
    await #expect(throws: (any Error).self) { try await pending.value }
    #expect(await f.http.stub.requests.isEmpty)
    await controller.close()
  }
  @Test func exactSavedChildClosesReplyWithoutReportWriterFallback() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in .init(status: 200, body: try f.envelope("saved")) }
    let controller = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(controller)
    let id = try await controller.enqueue(preparation: preparation, context: f.context) {
      probe.receive($0)
    }
    try await controller.send(replyID: id, context: f.context) { probe.receive($0) }
    let requests = await f.http.stub.requests
    #expect(requests.count == 1 && requests[0].httpMethod == "POST")
    #expect(requests[0].httpBody == preparation.intent.wireBody)
    #expect(
      requests[0].value(forHTTPHeaderField: "Idempotency-Key") == preparation.intent.idempotencyKey)
    #expect(
      requests[0].value(forHTTPHeaderField: "X-Conversation-Owner")
        == f.context.ownerID.uuidString.lowercased())
    #expect(
      requests[0].value(forHTTPHeaderField: "X-Conversation-Epoch")
        == f.context.epoch.uuidString.lowercased())
    #expect(requests[0].url?.path.contains("/commands/") == true)
    #expect(await probe.delivered.count == 1)
    #expect(await probe.snapshot?.entries.isEmpty == true)
    #expect(f.context.authUserID != f.context.ownerID)
    await controller.close()
  }
  @Test(arguments: ["patient", "epoch", "logout"])
  func lateRealChildResponseCannotPublishOrDeleteOldContextWork(_ change: String) async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { _, _ in
      await barrier.enter()
      return .init(status: 200, body: try f.envelope("saved"))
    }
    let c = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(c)
    let id = try await c.enqueue(preparation: preparation, context: f.context) { probe.receive($0) }
    let sending = Task { try await c.send(replyID: id, context: f.context) { probe.receive($0) } }
    #expect(await barrier.waitEnteredOrFinished())
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    if change == "logout" {
      await f.http.lifecycle.replace(
        .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-new-account"))
    } else {
      let token = try f.authority.beginRefresh()
      _ = try f.authority.accept(
        refreshID: token, authUserID: f.context.authUserID,
        ownerID: change == "patient" ? UUID() : f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration,
        epoch: change == "epoch" ? UUID() : f.context.epoch)
    }
    await barrier.release()
    await #expect(throws: (any Error).self) { try await sending.value }
    #expect(await probe.delivered.isEmpty)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == before)
    #expect(await f.http.stub.requests.count == 1)
    await c.close()
  }
  @Test func networkLossThenColdRestartReconcilesWithGetAndSameOriginalHashesOnly() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    let a = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(a)
    let id = try await a.enqueue(preparation: preparation, context: f.context) { probe.receive($0) }
    await #expect(throws: (any Error).self) {
      try await a.send(replyID: id, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.count == 1)
    await a.close()
    let b = try await f.open()
    await f.http.stub.respond { _, _ in .init(status: 200, body: try f.envelope("saved")) }
    try await b.reconcile(replyID: id, context: f.context) { probe.receive($0) }
    let requests = await f.http.stub.requests
    #expect(requests.map(\.httpMethod) == ["POST", "GET"])
    let requestURL = try #require(requests.last?.url)
    let query = try #require(
      URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(
      query.first { $0.name == "parent_input_hash" }?.value
        == preparation.intent.parentBinding.inputHash)
    #expect(
      query.first { $0.name == "reply_input_hash" }?.value == preparation.intent.replyInputHash)
    #expect(await probe.delivered.count == 1)
    await b.close()
  }
  @Test(arguments: ["ready_for_explicit_resume", "awaiting_explicit_resume"])
  func heldGetRequiresExplicitOneUseSameBodyResume(_ reason: String) async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    let c = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(c)
    let id = try await c.enqueue(preparation: preparation, context: f.context) { probe.receive($0) }
    await #expect(throws: (any Error).self) {
      try await c.send(replyID: id, context: f.context) { probe.receive($0) }
    }
    await f.http.stub.respond { _, _ in
      .init(status: 200, body: try f.envelope("held", reason: reason))
    }
    try await c.reconcile(replyID: id, context: f.context) { probe.receive($0) }
    #expect(await probe.canResume)
    #expect(await f.http.stub.requests.map(\.httpMethod) == ["POST", "GET"])
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    await #expect(throws: (any Error).self) {
      try await c.resume(replyID: id, context: f.context) { probe.receive($0) }
    }
    await #expect(throws: ConversationMealReplyControllerError.reconciliationRequired) {
      try await c.resume(replyID: id, context: f.context) { probe.receive($0) }
    }
    let requests = await f.http.stub.requests
    #expect(requests.map(\.httpMethod) == ["POST", "GET", "POST"])
    #expect(requests.first?.httpBody == requests.last?.httpBody)
    #expect(
      requests.first?.value(forHTTPHeaderField: "Idempotency-Key")
        == requests.last?.value(forHTTPHeaderField: "Idempotency-Key"))
    #expect(await probe.delivered.isEmpty)
    await c.close()
  }
  @Test func unauthorizedPostHasOnePhysicalRequestAndNoRefreshOrAck() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in .failure(401, "unauthorized") }
    let c = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(c)
    let id = try await c.enqueue(preparation: preparation, context: f.context) { probe.receive($0) }
    await #expect(throws: (any Error).self) {
      try await c.send(replyID: id, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.count == 1)
    #expect(await f.http.lifecycle.refreshCount == 0)
    #expect(await probe.delivered.isEmpty)
    await c.close()
  }
  @Test(arguments: [
    "stale_epoch", "input_conflict", "decision_conflict", "ineligible", "event_conflict",
  ])
  func permanentServerFenceCannotBecomeAResumeAfterARead(_ suffix: String) async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in .failure(409, "conversation_meal_reply_" + suffix) }
    let c = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(c)
    let id = try await c.enqueue(preparation: preparation, context: f.context) { probe.receive($0) }
    await #expect(throws: (any Error).self) {
      try await c.send(replyID: id, context: f.context) { probe.receive($0) }
    }
    await f.http.stub.respond { _, _ in .init(status: 200, body: try f.envelope("held")) }
    try await c.reconcile(replyID: id, context: f.context) { probe.receive($0) }
    #expect(await !probe.canResume)
    await #expect(throws: ConversationMealReplyControllerError.reconciliationRequired) {
      try await c.resume(replyID: id, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.map(\.httpMethod) == ["POST", "GET"])
    #expect(await probe.delivered.isEmpty)
    await c.close()
  }
  @Test func actual202ParentOnlyFallbackNeverAcknowledgesOrAuthorizesAnotherPost() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in .init(status: 202, body: try f.envelope("not_admitted")) }
    let c = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(c)
    let id = try await c.enqueue(preparation: preparation, context: f.context) { probe.receive($0) }
    try await c.send(replyID: id, context: f.context) { probe.receive($0) }
    #expect(await probe.delivered.isEmpty)
    #expect(await !probe.canResume)
    try await c.reconcile(replyID: id, context: f.context) { probe.receive($0) }
    await #expect(throws: ConversationMealReplyControllerError.reconciliationRequired) {
      try await c.resume(replyID: id, context: f.context) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.map(\.httpMethod) == ["POST", "GET"])
    #expect(await probe.snapshot?.entries.first?.intent.wireBody == preparation.intent.wireBody)
    await c.close()
  }
  @Test func oldPatientPreparationCannotEnqueueOrPublishAfterSameAuthRemap() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let c = try await f.open()
    let probe = await MainActor.run { ReplyControllerProbe() }
    let preparation = try await f.prepare(c)
    let token = try f.authority.beginRefresh()
    let changed = ConversationCommandContext(
      observation: try f.authority.accept(
        refreshID: token, authUserID: f.context.authUserID, ownerID: UUID(),
        localSessionGeneration: 7, epoch: f.context.epoch), observedAt: f.context.observedAt)
    await #expect(throws: (any Error).self) {
      try await c.enqueue(preparation: preparation, context: changed) { probe.receive($0) }
    }
    #expect(await f.http.stub.requests.isEmpty)
    #expect(await probe.delivered.isEmpty)
    await c.close()
  }
}
@MainActor final class ReplyControllerProbe {
  var snapshot: ConversationMealReplyOutboxViewSnapshot?
  var delivered: [ConversationMealReplyResultSnapshot] = []
  var canResume = false
  func receive(_ event: ConversationMealReplyEvent) {
    switch event {
    case .snapshot(let s): snapshot = s
    case .delivered(let p): delivered.append(p.result)
    case .held(_, _, let allowed): canResume = allowed
    case .queued, .deferred: break
    }
  }
}
struct ReplyControllerFixture: Sendable {
  let disk: ReplySessionFixture
  let http: ConversationHTTPFixture
  let keys = EditKeychainFake()
  let authority = ConversationOutboxObservationAuthority()
  let context: ConversationCommandContext
  init() throws {
    disk = try .init()
    http = try .init()
    let token = try authority.beginRefresh()
    context = .init(
      observation: try authority.accept(
        refreshID: token, authUserID: disk.server.authUserID, ownerID: disk.server.ownerID,
        localSessionGeneration: disk.lease.generation, epoch: disk.server.epoch),
      observedAt: "2026-11-04T13:57:32.280465Z")
  }
  func open() async throws -> ConversationMealReplyController {
    try await .open(
      transport: http.transport, lifecycle: http.lifecycle, store: disk.store,
      keyVault: .init(security: keys), expectedLease: disk.lease)
  }
  func prepare(_ c: ConversationMealReplyController) async throws
    -> ConversationMealReplyPreparation
  {
    let intent = try disk.intent()
    return try await c.prepare(
      parentBinding: intent.parentBinding, parentDecisionHash: intent.parentDecisionHash,
      question: intent.question, answer: .mealType(.almoco), context: context,
      replyID: intent.replyID)
  }
  func envelope(_ name: String, reason: String? = nil) throws -> Data {
    var data = try ReplySessionFixture.payload(name)
    if let reason { data["reason"] = reason }
    return try JSONSerialization.data(withJSONObject: [
      "data": data,
      "meta": ["api_version": "v1", "request_id": "synthetic-native-reply-request-0001"],
    ])
  }
}
