import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Actual linked question UI preserves original typed intent")
@MainActor struct FlowConversationMealReplyModelTests {
  @Test func actualRuntimeSourceInstallsReplyWithSameOriginalAuthPatientScopeAndSharedVault()
    async throws
  {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let body = try JSONSerialization.data(withJSONObject: [
      "data": [
        "schema": "conversation.session.v1",
        "auth_user_id": f.context.authUserID.uuidString.lowercased(),
        "owner_id": f.context.ownerID.uuidString.lowercased(),
        "epoch": f.context.epoch.uuidString.lowercased(), "observed_at": f.context.observedAt,
        "meal_command_protocol": "conversation.command.v1",
      ], "meta": ["api_version": "v1", "request_id": "synthetic-native-reply-factory"],
    ])
    await f.http.stub.respond { request, _ in
      guard request.url?.path.hasSuffix("/session") == true else { throw URLError(.badURL) }
      return .init(status: 200, body: body)
    }
    let source = FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: .init(security: f.keys),
      editing: .init(
        store: EncryptedConversationMealEditOutboxStore(directory: f.disk.directory),
        keyVault: .init(
          service: ConversationMealEditOutboxSession.keychainService, security: f.keys)))
    let session = try await source.open(expectedUserID: f.disk.lease.userID)
    #expect(session.model.mealReplies != nil && session.model.mealEditor != nil)
    #expect(session.model.acceptedIdentity?.authUserID == f.context.authUserID)
    #expect(session.model.acceptedIdentity?.ownerID == f.context.ownerID)
    #expect(session.model.acceptedIdentity?.authUserID != session.model.acceptedIdentity?.ownerID)
    #expect(await f.http.stub.requests.count == 1)
    #expect(await f.http.stub.requests.first?.httpMethod == "GET")
    await session.close()
  }
  @Test func mealTypeAnswerUsesActualProtocolAndSavedReceiptWithoutNewReport() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in .init(status: 200, body: try f.envelope("saved")) }
    let c = try await f.open()
    let probe = ReplyModelProbe()
    let m = try await FlowConversationMealReplyModel.open(
      controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { result, _ in probe.results.append(result) }
    m.accept(f.context)
    let original = try f.disk.intent()
    try m.begin(
      parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
      question: original.question, replyID: original.replyID)
    #expect(!m.canSubmit)
    m.mealType = .almoco
    #expect(m.canSubmit)
    await m.submit()
    #expect(probe.results.count == 1 && m.lastDelivered?.receipt != nil)
    #expect(await f.http.stub.requests.count == 1)
    #expect(await f.http.stub.requests.first?.httpBody == original.wireBody)
    #expect(m.pendingEntries.isEmpty)
    await m.close()
  }
  @Test func failedPersistLocksOriginalAnswerAndExplicitRetryKeepsItsIdAndBody() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(
      controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { _, _ in }
    m.accept(f.context)
    let original = try f.disk.intent()
    try m.begin(
      parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
      question: original.question, replyID: original.replyID)
    m.mealType = .almoco
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.disk.store.root.path)
    await m.submit()
    #expect(m.isLocked && m.failure == .storage && m.canDiscardUnsent)
    m.mealType = .cafe
    m.amountText = "999"
    #expect(m.mealType == .almoco && m.pendingIntent?.wireBody == original.wireBody)
    #expect(await f.http.stub.requests.isEmpty)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.disk.store.root.path)
    await f.http.stub.respond { _, _ in .init(status: 200, body: try f.envelope("saved")) }
    await m.submit()
    #expect(await f.http.stub.requests.first?.httpBody == original.wireBody)
    #expect(m.lastDelivered?.replyID == original.replyID)
    await m.close()
  }
  @Test func unknownRestartRestoresOriginalQuestionAndOnlyExplicitGetCanReconcile() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    let ca = try await f.open()
    let a = try await FlowConversationMealReplyModel.open(
      controller: ca, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { _, _ in }
    a.accept(f.context)
    let original = try f.disk.intent()
    try a.begin(
      parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
      question: original.question, replyID: original.replyID)
    a.mealType = .almoco
    await a.submit()
    #expect(a.canCheckStatus && !a.canDiscardUnsent)
    await a.close()
    let cb = try await f.open()
    let b = try await FlowConversationMealReplyModel.open(
      controller: cb, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { _, _ in }
    b.accept(f.context)
    await b.restore()
    try b.presentPending(replyID: original.replyID)
    #expect(b.pendingIntent?.wireBody == original.wireBody && b.isLocked)
    #expect(await f.http.stub.requests.count == 1)
    await f.http.stub.respond { _, _ in .init(status: 200, body: try f.envelope("saved")) }
    await b.checkStatus()
    #expect(await f.http.stub.requests.map(\.httpMethod) == ["POST", "GET"])
    #expect(b.lastDelivered?.receipt != nil)
    await b.close()
  }
  @Test func quantityAnswerPreservesAuthoredDecimalAndUnitWithoutLocalGramConversion() async throws
  {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(
      controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { _, _ in }
    m.accept(f.context)
    let original = try f.disk.firstIntent()
    try m.begin(
      parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
      question: original.question)
    m.amountText = "0,125"
    m.quantityUnit = "kg"
    await m.submit()
    let intent = try #require(m.pendingIntent)
    let raw = try #require(JSONSerialization.jsonObject(with: intent.wireBody) as? [String: Any])
    let answer = try #require((raw["input"] as? [String: Any])?["answer"] as? [String: Any])
    #expect((answer["amount"] as? NSNumber)?.doubleValue == 0.125)
    #expect(answer["unit"] as? String == "kg")
    #expect(m.amountText == "0,125" && m.quantityUnit == "kg" && m.isLocked)
    #expect(await f.http.stub.requests.count == 1)
    await m.close()
  }
  #if canImport(UIKit)
    @Test func quantityUnitChoiceRemainsAnIdentifiedNativeButton() async throws {
      let f = try ReplyControllerFixture()
      defer { f.disk.remove() }
      await f.http.lifecycle.replace(f.disk.lease)
      let c = try await f.open()
      let m = try await FlowConversationMealReplyModel.open(
        controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
      ) { _, _ in }
      m.accept(f.context)
      let original = try f.disk.firstIntent()
      try m.begin(
        parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
        question: original.question)
      m.amountText = "0,125"
      m.quantityUnit = "kg"
      let host = SignUpRenderingProbe.host(
        FlowConversationMealReplyContent(model: m).environment(
          \.locale, Locale(identifier: "pt_BR")), width: 390, height: 1200)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(
        nodes.contains {
          $0.identifier == "conversation.reply.unit" && $0.isButton && $0.label == "Unidade"
        }, Comment(rawValue: nodes.map(\.description).joined(separator: "\n")))
      #expect(m.amountText == "0,125" && m.quantityUnit == "kg" && !m.isLocked)
      #expect(await f.http.stub.requests.isEmpty)
      await m.close()
    }

    @Test func actualMealQuestionAndLockedBreakfastAreVisibleWithoutEditableRetagControls()
      async throws
    {
      let f = try ReplyControllerFixture()
      defer { f.disk.remove() }
      await f.http.lifecycle.replace(f.disk.lease)
      let c = try await f.open()
      let m = try await FlowConversationMealReplyModel.open(
        controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
      ) { _, _ in }
      m.accept(f.context)
      let original = try f.disk.intent()
      try m.begin(
        parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
        question: original.question)
      let normal = SignUpRenderingProbe.host(
        FlowConversationMealReplyContent(model: m).environment(
          \.locale, Locale(identifier: "pt_BR")), width: 390, height: 1200)
      let normalNodes = normal.nodes()
      #expect(
        normalNodes.contains { $0.identifier == "conversation.reply.meal" },
        Comment(rawValue: normalNodes.map(\.description).joined(separator: "\n")))
      normal.detach()
      m.mealType = .cafe
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o500], ofItemAtPath: f.disk.store.root.path)
      await m.submit()
      m.mealType = .almoco
      let locked = SignUpRenderingProbe.host(
        FlowConversationMealReplyContent(model: m).environment(
          \.locale, Locale(identifier: "pt_BR")), width: 390, height: 1200)
      defer { locked.detach() }
      let nodes = locked.nodes()
      #expect(
        nodes.contains {
          $0.identifier == "conversation.reply.locked-meal" && $0.label == "Café da manhã"
        })
      #expect(!nodes.contains { $0.identifier == "conversation.reply.meal" })
      #expect(await f.http.stub.requests.isEmpty)
      await m.close()
    }
  #endif
  @Test func explicitRedactedHeldActionDiscardsOnlyProvenUnsentAndNeverUnknown() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let c = try await f.open()
    let original = try await f.prepare(c)
    let id = try await c.enqueue(preparation: original, context: f.context) { _ in }
    let other = try await c.prepare(
      parentBinding: original.intent.parentBinding,
      parentDecisionHash: original.intent.parentDecisionHash, question: original.intent.question,
      answer: .mealType(.almoco), context: f.context)
    let unknown = try await c.enqueue(preparation: other, context: f.context) { _ in }
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    await #expect(throws: (any Error).self) {
      try await c.send(replyID: unknown, context: f.context) { _ in }
    }
    let m = try await FlowConversationMealReplyModel.open(
      controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { _, _ in }
    m.accept(f.context)
    let token = try f.authority.beginRefresh()
    let changed = ConversationCommandContext(
      observation: try f.authority.accept(
        refreshID: token, authUserID: f.context.authUserID, ownerID: UUID(),
        localSessionGeneration: f.context.sessionGeneration, epoch: UUID()),
      observedAt: f.context.observedAt)
    m.accept(changed)
    await m.restore()
    #expect(m.question == nil && m.pendingIntent == nil && m.pendingEntries.isEmpty)
    #expect(m.heldEntries.first(where: { $0.id == id })?.canDiscardUnsent == true)
    #expect(m.heldEntries.first(where: { $0.id == unknown })?.canDiscardUnsent == false)
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    await m.discardProtectedUnsent(replyID: unknown)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == before)
    await m.discardProtectedUnsent(replyID: id)
    #expect(m.heldEntries.map(\.id) == [unknown])
    #expect(await f.http.stub.requests.count == 1)
    await m.close()
  }
  @Test func cachedEnqueueOnlyGrantCannotRevealOrDispatchAPreservedPrivateAnswer() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(
      controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { _, _ in }
    m.accept(f.context)
    let original = try f.disk.intent()
    try m.begin(
      parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
      question: original.question, replyID: original.replyID)
    m.mealType = .almoco
    await m.submit()
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    let token = try f.authority.beginRefresh()
    let cached = ConversationCommandContext(
      observation: try f.authority.accept(
        refreshID: token, authUserID: f.context.authUserID, ownerID: f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch,
        enqueueOnly: true), observedAt: f.context.observedAt)
    m.accept(cached)
    #expect(
      m.question == nil && m.pendingIntent == nil && m.pendingEntries.isEmpty && !m.canSubmit
        && !m.canCheckStatus)
    await m.submit()
    await m.checkStatus()
    #expect(await f.http.stub.requests.count == 1)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == before)
    let freshToken = try f.authority.beginRefresh()
    let fresh = ConversationCommandContext(
      observation: try f.authority.accept(
        refreshID: freshToken, authUserID: f.context.authUserID, ownerID: f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration, epoch: f.context.epoch),
      observedAt: f.context.observedAt)
    m.accept(fresh)
    await m.restore()
    try m.presentPending(replyID: original.replyID)
    #expect(m.pendingIntent?.wireBody == original.wireBody && m.canCheckStatus)
    #expect(await f.http.stub.requests.count == 1)
    await m.close()
  }
  @Test func sameAuthRemapSynchronouslyRedactsOriginalQuestionAndAnswer() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(
      controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease
    ) { _, _ in }
    m.accept(f.context)
    let original = try f.disk.intent()
    try m.begin(
      parentBinding: original.parentBinding, parentDecisionHash: original.parentDecisionHash,
      question: original.question)
    m.mealType = .cafe
    _ = try f.authority.beginRefresh()
    #expect(m.presentation == nil && m.question == nil && m.mealType == nil && m.amountText.isEmpty)
    #expect(!m.canSubmit)
    await m.close()
  }
}
@MainActor final class ReplyModelProbe { var results: [ConversationMealReplyResultSnapshot] = [] }


@MainActor @Suite("Focused owned meal parent question reads", .serialized)
struct ConversationMealParentQuestionTests {
  @Test func actualParentProjectionOpensExistingAnswerWithoutOriginalCommand() async throws {
    let f = try ReplyControllerFixture()
    defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let payload = try parentQuestionUnit()
    let read = try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(payload))
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease) { _, _ in }
    m.accept(try parentQuestionContext(f))
    m.observeParentHead(read)
    try m.begin(parentBinding: read.parentBinding, parentDecisionHash: read.parentDecisionHash, question: #require(read.question))
    #expect(m.question?.kind == "meal_type" && !m.canSubmit)
    m.mealType = .almoco
    #expect(m.canSubmit)
    await m.close()
  }
}

/// UNIT projection of the genuine public typed reply fixture. It supplies no
/// fabricated original command/Thread/ACK and makes no connected-server claim.
func parentQuestionUnit() throws -> [String: Any] { try frozenParentQuestionUnit("meal_type") }

func frozenParentQuestionUnit(_ name: String) throws -> [String: Any] {
  #if SWIFT_PACKAGE
  let url = try #require(Bundle.module.url(forResource: "ConversationMealParentQuestionPublicUnitFixtures", withExtension: "json"))
  #else
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ConversationMealParentQuestionPublicUnitFixtures.json")
  #endif
  let bytes = try Data(contentsOf: url)
  #expect(ConversationMealCommand.digest(bytes) == "222866e3001e143a1009fb7f3a7cab6e0078e23a7cc057d12775c1703932aa08")
  let root = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
  return (root["samples"] as! [String: Any])[name] as! [String: Any]
}

/// Controlled unit grant at the real quantity observation clock, preceding the
/// later meal-type read. Raw server fixture clocks are retained byte-for-byte.
func parentQuestionContext(_ f: ReplyControllerFixture) throws -> ConversationCommandContext {
  .init(observation: f.context.observation, observedAt: try frozenParentQuestionUnit("quantity")["observed_at"] as! String)
}

extension ConversationMealParentQuestionTests {
  @Test func closedDecoderRejectsUnknownFieldsAndBrokenParentRelations() throws {
    let original = try parentQuestionUnit()
    for field in ["owner_id", "epoch", "parent_command_id", "parent_input_hash"] {
      var p = original
      p[field] = field == "parent_input_hash" ? String(repeating: "a", count: 64) : UUID().uuidString.lowercased()
      #expect(throws: (any Error).self) { try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(p)) }
    }
    for patch: [String: Any] in [
      ["unrecognized": true], ["status": "prepared"], ["head_revision": 32],
      ["head_revision": 0], ["question": NSNull()], ["reason": "no_current_question"],
      ["parent_decision_hash": "bad"], ["observed_at": "2020-01-01T00:00:00.000000Z"],
    ] {
      let p = original.merging(patch) { _, value in value }
      #expect(throws: (any Error).self) { try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(p)) }
    }
    var child = original
    var b = child["parent_binding"] as! [String: Any]
    b["kind"] = "meal.clarify"; b["command_protocol"] = "conversation.clarification.v1"
    child["parent_binding"] = b
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(child)) }
  }

  @Test func closedAndAdvancedHeadsInvalidateFormWithoutChangingPreparedIntent() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease) { _, _ in }
    m.accept(try parentQuestionContext(f))
    let p = try parentQuestionUnit()
    let read = try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(p))
    m.observeParentHead(read)
    try m.begin(parentBinding: read.parentBinding, parentDecisionHash: read.parentDecisionHash, question: #require(read.question))
    m.mealType = .almoco
    await f.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    await m.submit()
    let original = try #require(m.pendingIntent)
    #expect(m.canCheckStatus && !m.canSubmit)
    var closed = p; closed["status"] = "closed"; closed["question"] = NSNull(); closed["reason"] = "parent_fulfilled"
    m.observeParentHead(try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(closed)))
    #expect(!m.canSubmit && m.pendingIntent?.wireBody == original.wireBody && m.pendingIntent?.idempotencyKey == original.idempotencyKey)
    m.observeParentHead(read)
    #expect(!m.canSubmit && m.pendingIntent?.replyID == original.replyID)
    #expect(await f.http.stub.requests.count == 1)
    await m.close()
  }

  @Test func parentGetUsesOnlyActualSelectedChildAndRejectsWrongScopeOrReplyProtocol() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let repo = try await MobileConversationMealReplyRepository.scoped(transport: f.http.transport, lifecycle: f.http.lifecycle, lease: f.disk.lease)
    let p = try parentQuestionUnit()
    let response = try parentReadHTTP(p)
    let child = try selectedParentChildUnit(p)
    await f.http.stub.respond { _, _ in response }
    let read = try await repo.readParent(child: child, context: try parentQuestionContext(f))
    #expect(read.parentCommandID == child.commandID && read.parentDecisionHash != String(repeating: "e", count: 64))
    let request = try #require(await f.http.stub.requests.first)
    #expect(request.httpMethod == "GET" && request.httpBody == nil)
    #expect(request.url?.path.hasSuffix("/replies") == true)
    let url = try #require(request.url)
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [.init(name: "parent_input_hash", value: child.inputHash)])
    #expect(request.value(forHTTPHeaderField: "X-Conversation-Owner") == child.ownerID.uuidString.lowercased())
    #expect(request.value(forHTTPHeaderField: "X-Conversation-Epoch") == child.epoch.uuidString.lowercased())
    #expect(request.value(forHTTPHeaderField: "X-Conversation-Protocol") == "meal-question-v1")
    #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    for field in ["auth_user_id", "parent_input_hash", "parent_decision_hash", "epoch", "observed_at"] {
      var wrong = p
      if field == "auth_user_id" { wrong[field] = UUID().uuidString.lowercased() }
      else if field == "observed_at" { wrong[field] = "2026-11-04T13:57:31.600000Z" }
      else if field == "epoch" { wrong[field] = UUID().uuidString.lowercased() }
      else { wrong[field] = "invalid" }
      let response = try parentReadHTTP(wrong)
      await f.http.stub.respond { _, _ in response }
      await #expect(throws: (any Error).self) { try await repo.readParent(child: child, context: try parentQuestionContext(f)) }
    }
    for headers in [["Content-Type": "application/json"], ["X-Conversation-Protocol": "meal-command-v1", "Cache-Control": "no-store"]] {
      let body = response.body
      await f.http.stub.respond { _, _ in .init(status: 200, body: body, headers: headers) }
      await #expect(throws: (any Error).self) { try await repo.readParent(child: child, context: try parentQuestionContext(f)) }
    }
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
  }

  @Test func accountChangeDuringParentReadCannotPublishQuestion() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let repo = try await MobileConversationMealReplyRepository.scoped(transport: f.http.transport, lifecycle: f.http.lifecycle, lease: f.disk.lease)
    let p = try parentQuestionUnit(); let child = try selectedParentChildUnit(p)
    let response = try parentReadHTTP(p)
    await f.http.stub.respond { _, _ in
      await f.http.lifecycle.replace(.init(userID: UUID().uuidString.lowercased(), generation: 8, bearer: "synthetic-new-account"))
      return response
    }
    await #expect(throws: (any Error).self) { try await repo.readParent(child: child, context: try parentQuestionContext(f)) }
    #expect(await f.http.stub.requests.count == 1)
  }
}

func parentReadHTTP(_ payload: [String: Any]) throws -> ConversationHTTPReply {
  .init(status: 200, body: try neutralData(["data": payload, "meta": ["api_version": "v1", "request_id": "synthetic-parent-read-unit"]]), headers: ["Content-Type": "application/json", "X-Conversation-Protocol": "meal-question-v1", "Cache-Control": "no-store"])
}

func selectedParentChildUnit(_ parent: [String: Any]) throws -> FlowNeutralIntakeChild {
  let packet = try selectedParentPacketUnit(parent)
  return try #require(JSONDecoder().decode(FlowNeutralIntakeResponseSnapshot.self, from: neutralData(packet)).selection?.child)
}

/// UNIT neutral selection around the genuine typed parent fixture; no source,
/// meal report or receipt is reconstructed by production code.
func selectedParentPacketUnit(_ parent: [String: Any]) throws -> [String: Any] {
  var p = try neutralNotRecordedUnit(variant: "meal_not_recorded")
  let b = parent["parent_binding"] as! [String: Any]
  var intake = p["intake"] as! [String: Any]
  intake["owner_id"] = parent["owner_id"]; intake["epoch"] = parent["epoch"]
  intake["admitted_at"] = b["admitted_at"]
  p["intake"] = intake
  var selection = p["selection"] as! [String: Any]
  selection["selected_at"] = b["admitted_at"]
  selection["decision_hash"] = String(repeating: "e", count: 64)
  selection["command"] = b.filter { $0.key != "command_protocol" }
  p["selection"] = selection
  p["result"] = ["schema": "conversation.meal-command-state.v1", "status": "not_recorded", "owner_id": parent["owner_id"]!, "epoch": parent["epoch"]!, "command_id": parent["parent_command_id"]!, "input_hash": parent["parent_input_hash"]!, "reason": "missing_quantity", "food_indexes": [0]]
  return p
}

extension ConversationMealParentQuestionTests {
  @Test func genuineTerminalChildReadsQuantityThenMealTypeAndUsesExistingWriter() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let server = try NeutralParentQuestionUnitServer()
    await f.http.stub.respond { request, _ in try await server.reply(request) }
    let model = try await FlowConversationModel.open(transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store, keyVault: .init(security: f.keys), linkedReplies: true, historyVersion: .v3, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "comi arroz"
    await neutral.submit()
    let original = try #require(neutral.terminalRows.first)
    let child = try #require(neutral.mealQuestionChild(intakeID: original.id))
    #expect(neutral.pendingRows.isEmpty && neutral.savedRows.isEmpty)
    #expect(model.canReadNeutralMealQuestion(intakeID: original.id))
    #if canImport(UIKit)
    let host = SignUpRenderingProbe.host(
      FlowNeutralIntakeTranscriptContent(model: neutral, conversation: model, historicalTerminalIntakeIDs: [original.id])
        .environment(\.locale, Locale(identifier: "pt_BR")), width: 390, height: 1200)
    #expect(host.nodes().contains { $0.identifier == "conversation.neutral.answer-meal" && $0.isButton })
    host.detach()
    #endif
    await model.beginNeutralMealReply(intakeID: original.id)
    let replies = try #require(model.mealReplies)
    #expect(replies.question?.kind == "quantity" && replies.pendingIntent == nil)
    replies.amountText = "100"; replies.quantityUnit = "g"
    await replies.submit()
    #expect(replies.nextQuestion?.kind == "meal_type" && model.savedEffectRevision == 0)
    try replies.beginNextQuestion()
    replies.mealType = .almoco
    await replies.submit()
    #expect(replies.lastDelivered?.receipt != nil && model.savedEffectRevision == 1)
    #expect(neutral.terminalRows.first?.response.selection?.child.commandID == child.commandID)
    #expect(neutral.terminalRows.first?.input.wireBody == original.input.wireBody && neutral.savedRows.isEmpty)
    #expect(model.savedRows.isEmpty && model.pendingRows.isEmpty)
    let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 3 && posts.first?.url?.path == "/api/mobile/v1/conversation/intakes")
    #expect(posts.dropFirst().allSatisfy { $0.url?.path.hasSuffix("/replies") == true && $0.value(forHTTPHeaderField: ConversationFeedbackPresentationSelection.header) == "2" })
    let bodies = try posts.dropFirst().map { try JSONSerialization.jsonObject(with: #require($0.httpBody)) as! [String: Any] }
    #expect(bodies[0]["reply_id"] as? String != bodies[1]["reply_id"] as? String)
    await model.loadHistory()
    #expect(!model.hasUnpublishedLinkedDelivery && model.savedEffectRevision == 1)
    #expect(model.unifiedRows.filter { $0.kind == .fulfillment }.count == 1)
    await model.loadHistory()
    #expect(!model.hasUnpublishedLinkedDelivery && model.unifiedRows.filter { $0.kind == .fulfillment }.count == 1)
    await model.close()
  }

  @Test func refreshedGrantHidesUnpreparedQuestionAndPreservesProtectedAnswer() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease) { _, _ in }
    m.accept(try parentQuestionContext(f))
    let read = try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(parentQuestionUnit()))
    m.observeParentHead(read)
    try m.begin(parentBinding: read.parentBinding, parentDecisionHash: read.parentDecisionHash, question: #require(read.question))
    m.mealType = .almoco
    m.suspend()
    #expect(m.presentation == nil && !m.canSubmit)
    m.accept(try parentQuestionContext(f))
    #expect(m.presentation == nil && m.question == nil && !m.canSubmit)
    await m.close()
  }
}

/// Controlled UNIT HTTP boundary. Real controller/outbox/request bytes are
/// exercised; these rebinding fixtures are never connected provider/PG evidence.
actor NeutralParentQuestionUnitServer {
  let initial: Data
  let selected: Data
  var saved: Data?
  var lastReply: Data?
  var originalInput: Data?
  var loseMealTypeResponse: Bool
  init(loseMealTypeResponse: Bool = false) throws {
    self.loseMealTypeResponse = loseMealTypeResponse
    let p = try frozenParentQuestionUnit("quantity")
    initial = try neutralData(p)
    selected = try neutralData(selectedParentPacketUnit(p))
  }
  func reply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let path = request.url!.path
    let parent = try JSONSerialization.jsonObject(with: initial) as! [String: Any]
    if path.hasSuffix("/session") {
      let intake = path.contains("intakes")
      var p: [String: Any] = ["schema": intake ? "conversation.intake-session.v1" : "conversation.session.v1", "auth_user_id": parent["auth_user_id"]!, "owner_id": parent["owner_id"]!, "epoch": parent["epoch"]!, "observed_at": parent["observed_at"]!]
      p[intake ? "intake_protocol" : "meal_command_protocol"] = intake ? "conversation.intake.v1" : "conversation.command.v1"
      var r = try neutralHTTP(p)
      r.headers["X-Conversation-Protocol"] = intake ? "intake-v1" : "meal-command-v1"
      return r
    }
    if path == "/api/mobile/v1/conversation/journal" {
      return .init(status: 200, body: try journal(parent))
    }
    if path == "/api/mobile/v1/conversation/intakes" {
      let bytes = try #require(request.httpBody); originalInput = bytes
      let input = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
      var p = try JSONSerialization.jsonObject(with: selected) as! [String: Any]
      var binding = p["intake"] as! [String: Any]
      binding["intake_id"] = input["intake_id"]; binding["input_hash"] = ConversationMealCommand.digest(bytes)
      p["intake"] = binding
      return try neutralHTTP(p)
    }
    if request.httpMethod == "GET", path.hasSuffix("/replies") { return try parentReadHTTP(parent) }
    if request.httpMethod == "POST", path.hasSuffix("/replies") {
      let bytes = try #require(request.httpBody)
      let input = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
      let id = input["reply_id"] as! String
      let rawInput = try JSONDecoder().decode(ConversationMealEditJSON.self, from: neutralData(input["input"]!))
      let hash = try ConversationMealCommand.digest(Data(ConversationMealEditOperation.canonicalJSON(rawInput).utf8))
      let answer = (input["input"] as! [String: Any])["answer"] as! [String: Any]
      let isSaved = answer["kind"] as? String == "meal_type"
      var p = try ReplySessionFixture.payload(isSaved ? "saved" : "needs_reply")
      p["reply_id"] = id; p["reply_input_hash"] = hash
      var binding = p["child_binding"] as! [String: Any]
      binding["command_id"] = id; binding["input_hash"] = hash
      p["child_binding"] = binding
      if isSaved {
        var receipt = p["receipt"] as! [String: Any]
        receipt["command_id"] = id; receipt["input_hash"] = hash
        p["receipt"] = receipt; p["feedback"] = NSNull()
        saved = try neutralData(p)
      }
      lastReply = try neutralData(["data": p, "meta": ["api_version": "v1", "request_id": "synthetic-linked-answer"]])
      if isSaved && loseMealTypeResponse {
        loseMealTypeResponse = false
        throw URLError(.networkConnectionLost)
      }
      return .init(status: 200, body: lastReply!, headers: ["Content-Type": "application/json", ConversationFeedbackPresentationSelection.header: "2"])
    }
    if request.httpMethod == "GET", let lastReply { return .init(status: 200, body: lastReply) }
    throw URLError(.badURL)
  }
  private func journal(_ parent: [String: Any]) throws -> Data {
    var rows: [[String: Any]] = []
    if let saved {
      let p = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
      let r = p["receipt"] as! [String: Any]
      let id = p["reply_id"] as! String; let parentID = p["parent_command_id"] as! String
      let record = r.filter { ["registration_id", "meal_type", "local_date", "log_ids", "effect_version"].contains($0.key) }.merging(["kind": "meal"]) { _, new in new }
      rows = [["event_id": "fulfillment/\(parentID)/\(id)", "at": r["consumed_at"]!, "thread_id": parentID, "kind": "fulfillment", "lineage": ["kind": "meal.clarify", "intake_id": NSNull(), "command_id": id, "parent_command_id": parentID, "origin_epoch": parent["epoch"]!], "input": NSNull(), "outcome": ["status": "registered", "feedback": NSNull(), "record": record]]]
    }
    return try neutralData(["data": ["schema": "conversation.journal-page.v3", "mode": "historical", "auth_user_id": parent["auth_user_id"]!, "owner_id": parent["owner_id"]!, "epoch": parent["epoch"]!, "observed_at": "2026-11-04T14:00:00.000000Z", "items": rows, "has_more": false, "next_cursor": NSNull()], "meta": ["api_version": "v1", "request_id": "synthetic-linked-journal"]])
  }
}

extension ConversationMealParentQuestionTests {
  @Test func frozenActualPublicHeadsAndContractOnlyNoCurrentDecodeWithoutThreadAuthority() throws {
    for name in ["quantity", "meal_type", "fulfilled"] {
      let p = try frozenParentQuestionUnit(name)
      let read = try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(p))
      #expect(read.headRevision == (name == "quantity" ? 0 : name == "meal_type" ? 1 : 2))
      #expect(read.question?.kind == (name == "fulfilled" ? nil : name))
      #expect(read.parentBinding.commandProtocol == "conversation.command.v1")
    }
    // Contract-only state: current private reader cannot yet return this shape.
    var closed = try parentQuestionUnit()
    closed["status"] = "closed"; closed["question"] = NSNull(); closed["reason"] = "no_current_question"
    #expect(try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(closed)).question == nil)
  }

  @Test func higherGenuineHeadAndFulfillmentNeverRenewAnOlderQuestion() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let c = try await f.open()
    let m = try await FlowConversationMealReplyModel.open(controller: c, lifecycle: f.http.lifecycle, lease: f.disk.lease) { _, _ in }
    m.accept(try parentQuestionContext(f))
    func read(_ name: String) throws -> ConversationMealParentQuestionSnapshot {
      try JSONDecoder().decode(ConversationMealParentQuestionSnapshot.self, from: neutralData(frozenParentQuestionUnit(name)))
    }
    let q = try read("quantity")
    m.observeParentHead(q)
    try m.begin(parentBinding: q.parentBinding, parentDecisionHash: q.parentDecisionHash, question: #require(q.question))
    m.amountText = "100"
    #expect(m.canSubmit)
    m.observeParentHead(try read("meal_type"))
    #expect(!m.canSubmit)
    m.observeParentHead(q)
    #expect(!m.canSubmit)
    m.dismiss()
    #expect(throws: ConversationMealReplyControllerError.changed) {
      try m.begin(parentBinding: q.parentBinding, parentDecisionHash: q.parentDecisionHash, question: #require(q.question))
    }
    m.observeParentHead(try read("fulfilled"))
    #expect(throws: ConversationMealReplyControllerError.changed) {
      let next = try read("meal_type")
      try m.begin(parentBinding: next.parentBinding, parentDecisionHash: next.parentDecisionHash, question: #require(next.question))
    }
    #expect(await f.http.stub.requests.isEmpty)
    await m.close()
  }

  @Test func lostLinkedSaveColdRecoveryKeepsSameCipherKeyAndOnlyReconcilesOriginal() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let server = try NeutralParentQuestionUnitServer(loseMealTypeResponse: true)
    await f.http.stub.respond { request, _ in try await server.reply(request) }
    func open() async throws -> FlowConversationModel {
      try await FlowConversationModel.open(transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store, keyVault: .init(security: f.keys), linkedReplies: true, historyVersion: .v3, neutralIntakeEnabled: true)
    }
    let a = try await open()
    let neutral = try #require(a.neutralIntake)
    neutral.composer = "comi arroz"; await neutral.submit()
    let intakeID = try #require(neutral.terminalRows.first?.id)
    await a.beginNeutralMealReply(intakeID: intakeID)
    let replies = try #require(a.mealReplies)
    replies.amountText = "100"; await replies.submit()
    try replies.beginNextQuestion(); replies.mealType = .almoco; await replies.submit()
    let original = try #require(replies.pendingIntent)
    #expect(replies.canCheckStatus && !replies.canSubmit && a.savedEffectRevision == 0)
    let cipher = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    let postsBefore = await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count
    await a.close()
    let b = try await open()
    #expect(b.neutralIntake?.terminalRows.isEmpty == true) // Retained initial-question cold gap.
    let restored = try #require(b.mealReplies)
    try restored.presentPending(replyID: original.replyID)
    #expect(restored.pendingIntent?.wireBody == original.wireBody && restored.pendingIntent?.idempotencyKey == original.idempotencyKey)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == cipher)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == postsBefore)
    await restored.checkStatus()
    #expect(restored.lastDelivered?.receipt != nil && b.savedEffectRevision == 1)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == postsBefore)
    // Callback may independently start a journal GET; find the exact reply GET.
    let get = try #require(await f.http.stub.requests.last(where: { $0.httpMethod == "GET" && $0.url?.path.hasSuffix(original.replyID.uuidString.lowercased()) == true }))
    let url = try #require(get.url)
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "reply_input_hash", value: original.replyInputHash)) == true)
    await b.close()
  }
}

extension ConversationMealParentQuestionTests {
  @Test func routingDecisionHashCannotBecomeTypedMealDecisionAuthority() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let server = try NeutralParentQuestionUnitServer()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET", request.url?.path.hasSuffix("/replies") == true {
        var wrong = try frozenParentQuestionUnit("quantity")
        wrong["parent_decision_hash"] = String(repeating: "e", count: 64)
        return try parentReadHTTP(wrong)
      }
      return try await server.reply(request)
    }
    let model = try await FlowConversationModel.open(transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store, keyVault: .init(security: f.keys), linkedReplies: true, historyVersion: .v3, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "comi arroz"; await neutral.submit()
    let row = try #require(neutral.terminalRows.first)
    await model.beginNeutralMealReply(intakeID: row.id)
    #expect(model.mealReplies?.presentation == nil && model.mealReplies?.pendingIntent == nil)
    #expect(neutral.terminalRows.first?.input.wireBody == row.input.wireBody)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }

  @Test func selectedWorkoutNeverUsesMealParentRead() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let repo = try await MobileConversationMealReplyRepository.scoped(transport: f.http.transport, lifecycle: f.http.lifecycle, lease: f.disk.lease)
    let unit = try neutralFixture()["workout_known_unit"] as! [String: Any]
    let response = try JSONDecoder().decode(FlowNeutralIntakeResponseSnapshot.self, from: neutralData(unit["response"]!))
    let child = try #require(response.selection?.child)
    #expect(child.kind == .workout)
    await #expect(throws: (any Error).self) { try await repo.readParent(child: child, context: f.context) }
    #expect(await f.http.stub.requests.isEmpty)
  }
}

extension ConversationMealParentQuestionTests {
  @Test func leavingConversationWhileParentReadIsInFlightCannotOpenLateAnswerForm() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let server = try NeutralParentQuestionUnitServer()
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET", request.url?.path.hasSuffix("/replies") == true { await barrier.enter() }
      return try await server.reply(request)
    }
    let model = try await FlowConversationModel.open(transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store, keyVault: .init(security: f.keys), linkedReplies: true, historyVersion: .v3, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "comi arroz"; await neutral.submit()
    let intakeID = try #require(neutral.terminalRows.first?.id)
    let reading = Task {
      await model.beginNeutralMealReply(intakeID: intakeID)
      await barrier.finish()
    }
    #expect(await barrier.waitEnteredOrFinished())
    model.cancelTransientWork()
    await barrier.release()
    await reading.value
    #expect(model.mealReplies?.presentation == nil && model.neutralMealQuestion(intakeID: intakeID) == nil)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
}

extension ConversationMealParentQuestionTests {
  @Test func genuineNotConsumedTerminalDoesNotOfferMealQuestionOrReadAnotherParent() async throws {
    let f = try await neutralVisibleFixture(variant: "meal_not_recorded")
    defer { f.disk.remove() }
    let model = try await FlowConversationModel.open(transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store, keyVault: f.vault, linkedReplies: true, historyVersion: .v3, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "não comi arroz"; await neutral.submit()
    let row = try #require(neutral.terminalRows.first)
    #expect(neutral.mealQuestionChild(intakeID: row.id) == nil)
    #expect(!model.canReadNeutralMealQuestion(intakeID: row.id))
    await model.beginNeutralMealReply(intakeID: row.id)
    #expect(model.mealReplies?.presentation == nil)
    #expect(await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/replies") == true }.isEmpty)
    await model.close()
  }
}
