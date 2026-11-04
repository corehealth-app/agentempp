import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Durable linked answers share original Auth scope and exact server intent")
struct ConversationMealReplyOutboxSessionTests {
  @Test func persistedBeforeFlightAndColdRestartKeepOriginalReplyBytes() async throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let keys = EditKeychainFake()
    let vault = ConversationOutboxKeyVault(security: keys)
    let a = try await ConversationMealReplyOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: vault)
    let intent = try f.intent()
    let id = try await a.enqueue(intent: intent, server: f.server)
    let ticket = try await a.prepareDispatch(replyID: id, server: f.server)
    #expect(ticket.wireBody == intent.wireBody && ticket.idempotencyKey == intent.idempotencyKey)
    await a.invalidate()
    let b = try await ConversationMealReplyOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: vault)
    let restored = try await b.reconciliationTicket(replyID: id)
    #expect(
      restored.wireBody == intent.wireBody && restored.replyInputHash == intent.replyInputHash)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await b.prepareDispatch(replyID: id, server: f.server)
    }
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await b.discardUnsent(replyID: id, server: f.server)
    }
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await b.markWaiting(ticket: ticket, hold: .unknownOutcome, server: f.server)
    }
    await b.invalidate()
  }
  @Test func savedRealChildEffectClosesOnlyOwnReplyAndDoesNotTurnParentIntoSavedReport()
    async throws
  {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let keys = EditKeychainFake()
    let vault = ConversationOutboxKeyVault(security: keys)
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: vault)
    let intent = try f.intent()
    let other = try f.intent(replyID: UUID())
    let id = try await s.enqueue(intent: intent, server: f.server)
    _ = try await s.enqueue(intent: other, server: f.server)
    let key = try await vault.key(owner: f.owner, mayCreate: false)
    let report = try ConversationMealCommand(source: .text("preserved original negative report"))
    try f.store.update(owner: f.owner, key: key) {
      $0.append(
        .init(
          command: report, originalServerEpoch: f.server.epoch,
          originalPatientOwnerID: f.server.ownerID))
    }
    let ticket = try await s.prepareDispatch(replyID: id, server: f.server)
    let probe = await MainActor.run { ReplySessionProbe() }
    try await s.acknowledgeDelivery(ticket: ticket, result: f.result("saved"), server: f.server) {
      probe.results.append($0.result)
    }
    #expect(await probe.results.count == 1)
    #expect(
      try f.store.loadReplies(owner: f.owner, key: key).map { $0.intent.replyID } == [other.replyID]
    )
    #expect(try f.store.load(owner: f.owner, key: key).first?.wireBody == report.wireBody)
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await s.enqueue(intent: intent, server: f.server)
    }
    await s.invalidate()
  }
  @Test func actualFirstAnswerDeliveryClosesOnlyItsCiphertextWithoutFoodOrReward() async throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let keys = EditKeychainFake()
    let vault = ConversationOutboxKeyVault(security: keys)
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store, keyVault: vault)
    let first = try f.firstIntent()
    let id = try await s.enqueue(intent: first, server: f.server)
    let ticket = try await s.prepareDispatch(replyID: id, server: f.server)
    let result = try f.result("needs_reply")
    #expect(result.isAcceptedAnswerDelivery(for: first))
    #expect(result.receipt == nil && result.question?.revision == first.question.revision + 1)
    let probe = await MainActor.run { ReplySessionProbe() }
    try await s.acknowledgeDelivery(ticket: ticket, result: result, server: f.server) {
      probe.results.append($0.result)
    }
    let delivered = await probe.results
    #expect(delivered.count == 1 && delivered.first?.receipt == nil)
    let key = try await vault.key(owner: f.owner, mayCreate: false)
    #expect(try f.store.loadReplies(owner: f.owner, key: key).isEmpty)
    #expect(try f.store.load(owner: f.owner, key: key).isEmpty)
    await s.invalidate()
  }
  @Test func higherQuestionRevisionIsNotDeliveryAndKeepsUnknownCiphertext() async throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: .init(security: EditKeychainFake()))
    let first = try f.firstIntent()
    let id = try await s.enqueue(intent: f.firstIntent(), server: f.server)
    let ticket = try await s.prepareDispatch(replyID: id, server: f.server)
    var raw = try ReplySessionFixture.payload("needs_reply")
    var q = try #require(raw["question"] as? [String: Any])
    q["revision"] = first.question.revision + 2
    raw["question"] = q
    let higher = try JSONDecoder().decode(
      ConversationMealReplyResultSnapshot.self, from: JSONSerialization.data(withJSONObject: raw))
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    let probe = await MainActor.run { ReplySessionProbe() }
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await s.acknowledgeDelivery(ticket: ticket, result: higher, server: f.server) {
        probe.results.append($0.result)
      }
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    #expect(await probe.results.isEmpty)
    await s.invalidate()
  }
  @Test func heldResumeRequiresOwnExactReadAndCriticalHoldNeverWeakens() async throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: .init(security: EditKeychainFake()))
    let id = try await s.enqueue(intent: f.intent(), server: f.server)
    let ticket = try await s.prepareDispatch(replyID: id, server: f.server)
    try await s.markWaiting(ticket: ticket, hold: .unknownOutcome, server: f.server)
    try await s.authorizeResubmission(ticket: ticket, result: f.result("held"), server: f.server)
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await s.authorizeResubmission(
        ticket: ticket, result: f.result("not_admitted"), server: f.server)
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    try await s.markWaiting(ticket: ticket, hold: .reset, server: f.server)
    try await s.markWaiting(ticket: ticket, hold: .unknownOutcome, server: f.server)
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await s.authorizeResubmission(ticket: ticket, result: f.result("held"), server: f.server)
    }
    let probe = await MainActor.run { ReplySessionProbe() }
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await s.acknowledgeDelivery(ticket: ticket, result: f.result("saved"), server: f.server) {
        probe.results.append($0.result)
      }
    }
    #expect(await probe.results.isEmpty)
    await s.invalidate()
  }
  @Test func explicitForeignUnsentDiscardNeverDeletesUnknownWorkOrPublishesItsBody() async throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let keys = EditKeychainFake()
    let vault = ConversationOutboxKeyVault(security: keys)
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store, keyVault: vault)
    let queued = try f.intent()
    let unknown = try f.intent(replyID: UUID())
    _ = try await s.enqueue(intent: queued, server: f.server)
    _ = try await s.enqueue(intent: unknown, server: f.server)
    _ = try await s.prepareDispatch(replyID: unknown.replyID, server: f.server)
    let changed = ConversationOutboxServerObservation(
      authUserID: f.server.authUserID, ownerID: UUID(), localSessionGeneration: f.lease.generation,
      epoch: UUID())
    let probe = await MainActor.run { ReplySessionProbe() }
    try await s.publishSnapshot(server: changed) { probe.snapshot = $0 }
    #expect(await probe.snapshot?.entries.isEmpty == true)
    let metadata = try #require(await probe.snapshot?.held)
    #expect(metadata.first { $0.id == queued.replyID }?.canDiscardUnsent == true)
    #expect(metadata.first { $0.id == unknown.replyID }?.canDiscardUnsent == false)
    try await s.discardUnsent(replyID: queued.replyID, server: changed)
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await s.discardUnsent(replyID: unknown.replyID, server: changed)
    }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    let key = try await vault.key(owner: f.owner, mayCreate: false)
    #expect(
      try f.store.loadReplies(owner: f.owner, key: key).map { $0.intent.replyID } == [
        unknown.replyID
      ])
    await s.invalidate()
  }
  @Test(arguments: ["remap", "logout"])
  func explicitHeldDiscardRechecksCurrentAuthorityInsideTheAtomicOperation(_ change: String)
    async throws
  {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let base = ConversationHTTPTestLifecycle()
    await base.replace(f.lease)
    let gate = EditMutationGate()
    let life = EditGatedLifecycle(base: base, gate: gate)
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: .init(security: EditKeychainFake()))
    let authority = ConversationOutboxObservationAuthority()
    let a = try authority.beginRefresh()
    let original = try authority.accept(
      refreshID: a, authUserID: f.server.authUserID, ownerID: f.server.ownerID,
      localSessionGeneration: f.lease.generation, epoch: f.server.epoch)
    let id = try await s.enqueue(intent: f.intent(), server: original)
    let b = try authority.beginRefresh()
    let current = try authority.accept(
      refreshID: b, authUserID: f.server.authUserID, ownerID: UUID(),
      localSessionGeneration: f.lease.generation, epoch: UUID())
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    let barrier = ConversationControllerBarrier()
    await gate.holdNextState(barrier)
    let discard = Task { try await s.discardUnsent(replyID: id, server: current) }
    #expect(await barrier.waitEnteredOrFinished())
    if change == "logout" {
      await base.replace(.init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-B"))
    } else {
      _ = try authority.beginRefresh()
    }
    await barrier.release()
    await #expect(throws: (any Error).self) { try await discard.value }
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    await s.invalidate()
  }
  @Test func failedRenameKeepsOriginalCiphertextAndReturnsNoDispatchTicket() async throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: EditLifecycleFake(lease: f.lease), store: f.store,
      keyVault: .init(security: EditKeychainFake()))
    let id = try await s.enqueue(intent: f.intent(), server: f.server)
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.store.root.path)
    await #expect(throws: ConversationOutboxError.storageUnavailable) {
      try await s.prepareDispatch(replyID: id, server: f.server)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.store.root.path)
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) == before)
    try await s.discardUnsent(replyID: id, server: f.server)
    await s.invalidate()
  }
  @Test func remappedPatientHidesPlaintextAndLateAckCannotRemoveOrPublish() async throws {
    let f = try ReplySessionFixture()
    defer { f.remove() }
    let life = EditLifecycleFake(lease: f.lease)
    let s = try await ConversationMealReplyOutboxSession.open(
      lifecycle: life, store: f.store, keyVault: .init(security: EditKeychainFake()))
    let id = try await s.enqueue(intent: f.intent(), server: f.server)
    let ticket = try await s.prepareDispatch(replyID: id, server: f.server)
    let before = try Data(contentsOf: f.store.fileURL(owner: f.owner))
    let changed = ConversationOutboxServerObservation(
      authUserID: f.server.authUserID, ownerID: UUID(), localSessionGeneration: f.lease.generation,
      epoch: f.server.epoch)
    let probe = await MainActor.run { ReplySessionProbe() }
    try await s.publishSnapshot(server: changed) { probe.snapshot = $0 }
    #expect(await probe.snapshot?.entries.isEmpty == true)
    #expect(await probe.snapshot?.held.count == 1)
    await #expect(throws: ConversationOutboxError.invalidServerObservation) {
      try await s.acknowledgeDelivery(ticket: ticket, result: f.result("saved"), server: changed) {
        probe.results.append($0.result)
      }
    }
    await life.replaceBeforeNextVisible(
      lease: .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-B"))
    await #expect(throws: (any Error).self) {
      try await s.acknowledgeDelivery(ticket: ticket, result: f.result("saved"), server: f.server) {
        probe.results.append($0.result)
      }
    }
    #expect(await probe.results.isEmpty)
    // Factual deletion preceded account change; never re-enqueue.
    #expect(try Data(contentsOf: f.store.fileURL(owner: f.owner)) != before)
    await s.invalidate()
  }
}

@MainActor final class ReplySessionProbe {
  var results: [ConversationMealReplyResultSnapshot] = []
  var snapshot: ConversationMealReplyOutboxViewSnapshot?
}
struct ReplySessionFixture: Sendable {
  let directory: URL
  let store: EncryptedConversationOutboxStore
  let lease: SessionLease
  let server: ConversationOutboxServerObservation
  let owner: ConversationOutboxOwner
  init() throws {
    let raw = try Self.payload("saved")
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "performe-reply-session-\(UUID().uuidString)")
    store = EncryptedConversationOutboxStore(directory: directory)
    lease = .init(
      userID: try #require(raw["auth_user_id"] as? String), generation: 7, bearer: "synthetic-reply"
    )
    server = .init(
      authUserID: try #require(UUID(uuidString: lease.userID)),
      ownerID: try #require(UUID(uuidString: raw["owner_id"] as? String ?? "")),
      localSessionGeneration: lease.generation,
      epoch: try #require(UUID(uuidString: raw["epoch"] as? String ?? "")))
    owner = try .init(lease: lease)
  }
  func remove() {
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: store.root.path)
    try? FileManager.default.removeItem(at: directory)
  }
  func intent(replyID: UUID? = nil) throws -> ConversationMealReplyIntent {
    let raw = try Self.payload("saved")
    let next = try Self.payload("needs_reply")
    let binding = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self,
      from: JSONSerialization.data(withJSONObject: try #require(raw["parent_binding"])))
    let q = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Question.self,
      from: JSONSerialization.data(withJSONObject: try #require(next["question"])))
    return try .init(
      parentBinding: binding,
      parentDecisionHash: try #require(raw["parent_decision_hash"] as? String), question: q,
      replyID: replyID ?? #require(UUID(uuidString: raw["reply_id"] as? String ?? "")),
      answer: .mealType(.almoco))
  }
  func firstIntent() throws -> ConversationMealReplyIntent {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationMealReplyFirstAnswerFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealReplyFirstAnswerFixtures.json")
    #endif
    let bytes = try Data(contentsOf: url)
    #expect(
      ConversationMealCommand.digest(bytes)
        == "7a4cd020f6252d59be49a5e20dde22283222d4c49e013ff83439183e49bb14a2")
    let raw = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let parent = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self,
      from: JSONSerialization.data(withJSONObject: #require(raw["parent_binding"])))
    let question = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Question.self,
      from: JSONSerialization.data(withJSONObject: #require(raw["question"])))
    let result = try ConversationMealReplyIntent(
      parentBinding: parent, parentDecisionHash: #require(raw["parent_decision_hash"] as? String),
      question: question, replyID: #require(UUID(uuidString: raw["reply_id"] as? String ?? "")),
      answer: .quantity(amount: 100, unit: "g"))
    #expect(result.replyInputHash == raw["reply_input_hash"] as? String)
    return result
  }
  func result(_ key: String) throws -> ConversationMealReplyResultSnapshot {
    try JSONDecoder().decode(
      ConversationMealReplyResultSnapshot.self,
      from: JSONSerialization.data(withJSONObject: Self.payload(key)))
  }
  static func payload(_ key: String) throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(forResource: "ConversationMealReplyPublicFixtures", withExtension: "json")
      )
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationMealReplyPublicFixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return try #require((root[key] as? [String: Any])?["data"] as? [String: Any])
  }
}
