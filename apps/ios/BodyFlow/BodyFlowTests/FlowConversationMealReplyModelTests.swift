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

@MainActor @Suite("Cold meal question origins remain lookup-only", .serialized)
struct ConversationMealQuestionOriginsTests {
  @Test func coldEmptyOutboxAndRAMRecoverCurrentQuantityWithoutAnotherReport() async throws {
    let f = try ReplyControllerFixture(); defer { f.disk.remove() }
    await f.http.lifecycle.replace(f.disk.lease)
    let server = try NeutralParentQuestionUnitServer()
    let origins = try coldOriginsContractUnitPage()
    let originHTTP = try coldOriginsContractUnitHTTP(origins)
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET", request.url?.path == "/api/mobile/v1/conversation/intakes" { return originHTTP }
      return try await server.reply(request)
    }
    let model = try await FlowConversationModel.open(transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store, keyVault: .init(security: f.keys), linkedReplies: true, historyVersion: .v3, neutralIntakeEnabled: true)
    await model.refreshConversation()
    let neutral = try #require(model.neutralIntake)
    #expect(neutral.pendingRows.isEmpty && neutral.terminalRows.isEmpty && neutral.savedRows.isEmpty)
    let id = try #require(UUID(uuidString: ((origins["items"] as! [[String: Any]])[0]["intake"] as! [String: Any])["intake_id"] as! String))
    #expect(model.canReadNeutralMealQuestion(intakeID: id))
    await model.beginNeutralMealReply(intakeID: id)
    #expect(model.mealReplies?.question?.kind == "quantity")
    #expect(model.mealReplies?.pendingIntent == nil && model.savedEffectRevision == 0)
    #expect(neutral.pendingRows.isEmpty && neutral.terminalRows.isEmpty)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    await model.close()
  }
}

/// Synthetic public-contract JSON only. This does not claim private-parser,
/// PostgreSQL or connected HTTP provenance. Real projected fixtures are separate.
func coldOriginsContractUnitPage() throws -> [String: Any] {
  let parent = try frozenParentQuestionUnit("quantity")
  let packet = try selectedParentPacketUnit(parent)
  return ["schema": "conversation.meal-question-origins.v1", "mode": "lookup_only", "auth_user_id": parent["auth_user_id"]!, "owner_id": parent["owner_id"]!, "epoch": parent["epoch"]!, "observed_at": parent["observed_at"]!, "items": [["intake": packet["intake"]!, "selection": packet["selection"]!, "source": ["channel": "text", "text": "comi arroz"]]], "has_more": false, "next_cursor": NSNull()]
}
func coldOriginsContractUnitHTTP(_ page: [String: Any]) throws -> ConversationHTTPReply {
  .init(status: 200, body: try neutralData(["data": page, "meta": ["api_version": "v1", "request_id": "synthetic-origins-contract"]]), headers: ["Content-Type": "application/json", "X-Conversation-Protocol": "intake-question-origins-v1", "Cache-Control": "no-store"])
}

func coldOriginsProjectedUnitRoot() throws -> [String: Any] {
  #if SWIFT_PACKAGE
  let url = try #require(Bundle.module.url(forResource: "ConversationMealQuestionOriginsPublicUnitFixtures", withExtension: "json"))
  #else
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ConversationMealQuestionOriginsPublicUnitFixtures.json")
  #endif
  let bytes = try Data(contentsOf: url)
  #expect(ConversationMealCommand.digest(bytes) == "60f980ead12835eda94f05f80c5c140fdcd86dd55264bb295299a56f3cfc3d3e")
  return try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
}
func coldOriginsProjectedUnitPage() throws -> [String: Any] { try coldOriginsProjectedUnitRoot()["data"] as! [String: Any] }

@MainActor struct ColdOriginsNativeFixture {
  let http: ConversationHTTPFixture
  let disk: OutboxDiskFixture
  let keys: OutboxKeychainFake
  let lease: SessionLease
  let server: ColdOriginsScopedUnitServer
  func open() async throws -> FlowConversationModel {
    try await FlowConversationModel.open(transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: .init(security: keys), linkedReplies: true, historyVersion: .v3, neutralIntakeEnabled: true, expectedLease: lease)
  }
}
@MainActor func coldOriginsNativeFixture() async throws -> ColdOriginsNativeFixture {
  let root = try coldOriginsProjectedUnitRoot(), page = root["data"] as! [String: Any]
  let http = try ConversationHTTPFixture(), disk = try OutboxDiskFixture()
  let lease = SessionLease(userID: page["auth_user_id"] as! String, generation: 7, bearer: "synthetic-cold-origins")
  await http.lifecycle.replace(lease)
  let server = try ColdOriginsScopedUnitServer(root: neutralData(root))
  await http.stub.respond { request, _ in try await server.reply(request) }
  return .init(http: http, disk: disk, keys: OutboxKeychainFake(), lease: lease, server: server)
}

/// UNIT HTTP boundary over the unchanged private-parser/service projection.
/// Synthetic response transitions/ACKs below are contract tests, never actual
/// PostgreSQL, connected HTTP, provider, six-section or domain-effect evidence.
actor ColdOriginsScopedUnitServer {
  let originalPage: Data
  let heads: [String: Data]
  private var pages: [String: Data]
  private var headOverrides: [String: Data] = [:]
  private var savedReplies: [String: Data] = [:]
  private var closedParents: Set<String> = []
  private var originsGate: ConversationControllerBarrier?
  private var headGate: ConversationControllerBarrier?
  private var loseReply = false
  private var includeClosedOrigins = false
  init(root: Data) throws {
    let raw = try JSONSerialization.jsonObject(with: root) as! [String: Any]
    originalPage = try neutralData(raw["data"]!)
    pages = ["first": originalPage]
    var heads: [String: Data] = [:]
    for value in (raw["parent_heads"] as! [String: [String: Any]]).values {
      heads[value["parent_command_id"] as! String] = try neutralData(value)
    }
    self.heads = heads
  }
  func setPage(_ bytes: Data, cursor: String? = nil) { pages[cursor ?? "first"] = bytes }
  func setHead(_ bytes: Data, parentID: UUID) { headOverrides[parentID.uuidString.lowercased()] = bytes }
  func holdOrigins(_ barrier: ConversationControllerBarrier) { originsGate = barrier }
  func holdHead(_ barrier: ConversationControllerBarrier) { headGate = barrier }
  func loseNextReply() { loseReply = true }
  func exposeStaleClosedOriginLabels() { includeClosedOrigins = true }
  func reply(_ request: URLRequest) async throws -> ConversationHTTPReply {
    let url = try #require(request.url), path = url.path
    let page = try JSONSerialization.jsonObject(with: originalPage) as! [String: Any]
    if path.hasSuffix("/session") {
      let intake = path.contains("intakes")
      var session: [String: Any] = ["schema": intake ? "conversation.intake-session.v1" : "conversation.session.v1", "auth_user_id": page["auth_user_id"]!, "owner_id": page["owner_id"]!, "epoch": page["epoch"]!, "observed_at": page["observed_at"]!]
      session[intake ? "intake_protocol" : "meal_command_protocol"] = intake ? "conversation.intake.v1" : "conversation.command.v1"
      var reply = try neutralHTTP(session)
      reply.headers["X-Conversation-Protocol"] = intake ? "intake-v1" : "meal-command-v1"
      return reply
    }
    if path == "/api/mobile/v1/conversation/intakes", request.httpMethod == "GET" {
      if let gate = originsGate { originsGate = nil; await gate.enter() }
      let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value
      let bytes = try #require(pages[cursor ?? "first"])
      var projected = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
      let rows = projected["items"] as! [[String: Any]]
      projected["items"] = rows.filter { includeClosedOrigins || !closedParents.contains((($0["selection"] as! [String: Any])["command"] as! [String: Any])["command_id"] as! String) }
      return try coldOriginsContractUnitHTTP(projected)
    }
    if path == "/api/mobile/v1/conversation/journal" { return .init(status: 200, body: try journal(page)) }
    let components = path.split(separator: "/").map(String.init)
    guard let commands = components.firstIndex(of: "commands"), components.count > commands + 2 else { throw URLError(.badURL) }
    let parentID = components[commands + 1]
    if request.httpMethod == "GET", path.hasSuffix("/replies") {
      if let gate = headGate { headGate = nil; await gate.enter() }
      var p = try JSONSerialization.jsonObject(with: #require(headOverrides[parentID] ?? heads[parentID])) as! [String: Any]
      if closedParents.contains(parentID) { p["status"] = "closed"; p["question"] = NSNull(); p["reason"] = "parent_fulfilled"; p["head_revision"] = (p["head_revision"] as! Int) + 1 }
      return try parentReadHTTP(p)
    }
    if request.httpMethod == "POST", path.hasSuffix("/replies") {
      let body = try #require(request.httpBody)
      let input = try JSONSerialization.jsonObject(with: body) as! [String: Any]
      let head = try JSONSerialization.jsonObject(with: #require(heads[parentID])) as! [String: Any]
      let id = input["reply_id"] as! String
      let raw = try JSONDecoder().decode(ConversationMealEditJSON.self, from: neutralData(input["input"]!))
      let hash = try ConversationMealCommand.digest(Data(ConversationMealEditOperation.canonicalJSON(raw).utf8))
      let answer = (input["input"] as! [String: Any])["answer"] as! [String: Any]
      // Only the initial meal-type example is used for this synthetic saved ACK.
      guard answer["kind"] as? String == "meal_type" else { throw URLError(.badServerResponse) }
      var receipt = try ReplySessionFixture.payload("saved")["receipt"] as! [String: Any]
      receipt["owner_id"] = page["owner_id"]; receipt["command_id"] = id; receipt["input_hash"] = hash
      receipt["epoch"] = page["epoch"]; receipt["parent_command_id"] = parentID
      receipt["parent_input_hash"] = head["parent_input_hash"]; receipt["parent_decision_hash"] = head["parent_decision_hash"]
      receipt["provider_key"] = "conversation.clarification/\(page["owner_id"] as! String)/\(parentID)"
      receipt["meal_type"] = answer["meal_type"]; receipt["consumed_at"] = page["observed_at"]
      let child: [String: Any] = ["owner_id": page["owner_id"]!, "command_id": id, "input_hash": hash, "command_protocol": "conversation.clarification.v1", "kind": "meal.clarify", "epoch": page["epoch"]!, "admitted_at": page["observed_at"]!]
      let p: [String: Any] = ["schema": "conversation.meal-reply-result.v1", "auth_user_id": page["auth_user_id"]!, "owner_id": page["owner_id"]!, "epoch": page["epoch"]!, "parent_command_id": parentID, "parent_input_hash": head["parent_input_hash"]!, "parent_decision_hash": head["parent_decision_hash"]!, "parent_binding": head["parent_binding"]!, "reply_id": id, "reply_input_hash": hash, "child_binding": child, "observed_at": page["observed_at"]!, "status": "saved", "receipt": receipt, "question": NSNull(), "reason": NSNull(), "feedback": NSNull()]
      let bytes = try neutralData(p)
      savedReplies[id] = bytes; closedParents.insert(parentID)
      if loseReply { loseReply = false; throw URLError(.networkConnectionLost) }
      return try replyHTTP(bytes)
    }
    if request.httpMethod == "GET", let id = components.last, let saved = savedReplies[id] { return try replyHTTP(saved) }
    throw URLError(.badURL)
  }
  private func replyHTTP(_ payload: Data) throws -> ConversationHTTPReply {
    .init(status: 200, body: try neutralData(["data": JSONSerialization.jsonObject(with: payload), "meta": ["api_version": "v1", "request_id": "synthetic-cold-linked-ack"]]), headers: ["Content-Type": "application/json", ConversationFeedbackPresentationSelection.header: "2"])
  }
  private func journal(_ page: [String: Any]) throws -> Data {
    var entries: [[String: Any]] = []
    for bytes in savedReplies.values {
      let saved = try JSONSerialization.jsonObject(with: bytes) as! [String: Any], receipt = saved["receipt"] as! [String: Any]
      let parent = saved["parent_command_id"] as! String, child = saved["reply_id"] as! String
      let origin = (page["items"] as! [[String: Any]]).first { ((($0["selection"] as! [String: Any])["command"] as! [String: Any])["command_id"] as! String) == parent }!
      let intakeID = (origin["intake"] as! [String: Any])["intake_id"] as! String
      let record = receipt.filter { ["registration_id", "meal_type", "local_date", "log_ids", "effect_version"].contains($0.key) }.merging(["kind": "meal"]) { _, next in next }
      entries.append(["event_id": "fulfillment/\(parent)/\(child)", "at": receipt["consumed_at"]!, "thread_id": intakeID, "kind": "fulfillment", "lineage": ["kind": "meal.clarify", "intake_id": intakeID, "command_id": child, "parent_command_id": parent, "origin_epoch": page["epoch"]!], "input": NSNull(), "outcome": ["status": "registered", "feedback": NSNull(), "record": record]])
    }
    entries.sort { ($0["event_id"] as! String) > ($1["event_id"] as! String) }
    return try neutralData(["data": ["schema": "conversation.journal-page.v3", "mode": "historical", "auth_user_id": page["auth_user_id"]!, "owner_id": page["owner_id"]!, "epoch": page["epoch"]!, "observed_at": page["observed_at"]!, "items": entries, "has_more": false, "next_cursor": NSNull()], "meta": ["api_version": "v1", "request_id": "synthetic-cold-journal"]])
  }
}

extension ConversationMealQuestionOriginsTests {
  @Test func projectedDistinctInitialOriginsOpenBothRealFormsAfterReopen() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    let first = try await f.open(); await first.refreshConversation(); await first.close()
    let model = try await f.open(); await model.refreshConversation()
    #expect(model.neutralIntake?.pendingRows.isEmpty == true && model.neutralIntake?.terminalRows.isEmpty == true)
    #expect(model.recoveredMealQuestionOrigins.count == 2)
    for row in model.recoveredMealQuestionOrigins {
      await model.beginNeutralMealReply(intakeID: row.id)
      #expect(model.mealReplies?.question?.kind == (row.id.uuidString.lowercased().hasSuffix("91") ? "meal_type" : "quantity"))
      #expect(model.mealReplies?.pendingIntent == nil)
      model.mealReplies?.dismiss()
    }
    let reads = await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/replies") == true }
    #expect(reads.count == 2 && reads.allSatisfy { $0.httpMethod == "GET" })
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    #expect(model.savedEffectRevision == 0)
    await model.close()
  }

  @Test func closedOriginsDecoderRejectsPrivateAuthorityAndBrokenLineage() throws {
    let page = try coldOriginsProjectedUnitPage()
    let good = try JSONDecoder().decode(FlowMealQuestionOriginsPageSnapshot.self, from: neutralData(page))
    #expect(good.items.count == 2 && good.authUserID != good.ownerID)
    for patch: [String: Any] in [["mode": "historical"], ["question_key": String(repeating: "a", count: 64)], ["has_more": true], ["observed_at": "2026-11-04T12:02:00Z"]] {
      let wrong = page.merging(patch) { _, next in next }
      #expect(throws: (any Error).self) { try JSONDecoder().decode(FlowMealQuestionOriginsPageSnapshot.self, from: neutralData(wrong)) }
    }
    for kind in ["duplicate", "out_of_order", "owner", "epoch", "child_id", "child_hash", "kind", "future", "false_media", "question_authority", "descendant"] {
      var wrong = page, rows = page["items"] as! [[String: Any]]
      var item = rows[0], intake = item["intake"] as! [String: Any], selection = item["selection"] as! [String: Any], child = selection["command"] as! [String: Any]
      switch kind {
      case "duplicate": rows[1] = item
      case "out_of_order": rows.reverse()
      case "owner": intake["owner_id"] = UUID().uuidString.lowercased(); item["intake"] = intake; rows[0] = item
      case "epoch": wrong["epoch"] = UUID().uuidString.lowercased()
      case "child_id": child["command_id"] = intake["intake_id"]; selection["command"] = child; item["selection"] = selection; rows[0] = item
      case "child_hash": child["input_hash"] = "not-a-hash"; selection["command"] = child; item["selection"] = selection; rows[0] = item
      case "kind": child["kind"] = "workout.report"; selection["kind"] = "workout.report"; selection["command"] = child; item["selection"] = selection; rows[0] = item
      case "future": selection["selected_at"] = "2026-11-05T12:02:00.000001Z"; item["selection"] = selection; rows[0] = item
      case "false_media": item["source"] = ["channel": "media", "caption": NSNull(), "media_asset_id": UUID().uuidString.lowercased()]; rows[0] = item
      case "question_authority": item["question"] = ["revision": 0, "question_key": String(repeating: "a", count: 64)]; rows[0] = item
      default: item["kind"] = "fulfillment"; rows[0] = item
      }
      wrong["items"] = rows
      #expect(throws: (any Error).self) { try JSONDecoder().decode(FlowMealQuestionOriginsPageSnapshot.self, from: neutralData(wrong)) }
    }
    var media = page, rows = page["items"] as! [[String: Any]]
    rows[0]["source"] = ["channel": "media", "caption": NSNull()]; media["items"] = rows
    let parsed = try JSONDecoder().decode(FlowMealQuestionOriginsPageSnapshot.self, from: neutralData(media))
    #expect(parsed.items[0].source == .media(caption: nil))
  }

  @Test func originHeaderContractRejectsDuplicateUnknownForeignAndRetryRequests() throws {
    let p = try coldOriginsProjectedUnitPage()
    let owner = UUID(uuidString: p["owner_id"] as! String)!, epoch = UUID(uuidString: p["epoch"] as! String)!
    func request(_ query: [URLQueryItem], replay: MobileAPIUnauthorizedReplay = .never) throws -> MobileAPIRequest<FlowMealQuestionOriginsPageSnapshot> {
      try .init(method: .get, path: "/api/mobile/v1/conversation/intakes", queryItems: query, conversation: .intakeQuestionOrigins(epoch: epoch, ownerID: owner), unauthorizedReplay: replay)
    }
    _ = try request([])
    for query in [[URLQueryItem(name: "limit", value: "0")], [.init(name: "limit", value: "01")], [.init(name: "limit", value: "26")], [.init(name: "limit", value: "10"), .init(name: "limit", value: "10")], [.init(name: "version", value: "3")], [.init(name: "cursor", value: "opaque")]] {
      #expect(throws: (any Error).self) { try request(query) }
    }
    #expect(throws: (any Error).self) { try request([], replay: .standard) }
    let foreign = coldOriginsUnitCursor(owner: UUID(), epoch: epoch)
    #expect(throws: (any Error).self) { try request([.init(name: "cursor", value: foreign)]) }
  }

  @Test func emptyOriginPageKeepsExplicitOlderPageActionAndNeverAutoScans() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    let page = try coldOriginsProjectedUnitPage(), owner = UUID(uuidString: page["owner_id"] as! String)!, epoch = UUID(uuidString: page["epoch"] as! String)!
    let cursor = coldOriginsUnitCursor(owner: owner, epoch: epoch)
    var empty = page; empty["items"] = [] as [Any]; empty["has_more"] = true; empty["next_cursor"] = cursor
    await f.server.setPage(try neutralData(empty)); await f.server.setPage(try neutralData(page), cursor: cursor)
    let model = try await f.open(); await model.refreshConversation()
    #expect(model.recoveredMealQuestionOrigins.isEmpty && model.mealQuestionOrigins?.hasMore == true)
    #expect(await f.http.stub.requests.filter { $0.url?.path == "/api/mobile/v1/conversation/intakes" }.count == 1)
    #if canImport(UIKit)
    let host = SignUpRenderingProbe.host(FlowConversationMealQuestionOriginsContent(model: model), width: 390, height: 600)
    #expect(host.nodes().contains { $0.identifier == "conversation.origins.more" && $0.isEnabled })
    host.detach()
    #endif
    await model.loadMealQuestionOrigins(reset: false)
    #expect(model.recoveredMealQuestionOrigins.count == 2 && model.mealQuestionOrigins?.hasMore == false)
    let request = try #require(await f.http.stub.requests.last { $0.url?.path == "/api/mobile/v1/conversation/intakes" })
    let url = try #require(request.url)
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "cursor", value: cursor)) == true)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  @Test func sameTextDistinctIntakesRemainDistinctAndClosedHeadPrunesOnlyItsOrigin() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    var page = try coldOriginsProjectedUnitPage(), rows = page["items"] as! [[String: Any]]
    // Contract-only label counterfactual; not a new private-parser/SQL fixture.
    for i in rows.indices { rows[i]["source"] = ["channel": "text", "text": "Mesmo relato"] }
    page["items"] = rows; await f.server.setPage(try neutralData(page))
    let model = try await f.open(); await model.refreshConversation()
    #expect(model.recoveredMealQuestionOrigins.count == 2)
    let first = try #require(model.recoveredMealQuestionOrigins.first)
    let root = try coldOriginsProjectedUnitRoot(), heads = root["parent_heads"] as! [String: [String: Any]]
    var closed = heads[first.id.uuidString.lowercased()]!
    closed["status"] = "closed"; closed["question"] = NSNull(); closed["reason"] = "parent_fulfilled"; closed["head_revision"] = 1
    await f.server.setHead(try neutralData(closed), parentID: first.selection.child.commandID)
    await model.beginNeutralMealReply(intakeID: first.id)
    #expect(model.mealReplies?.presentation == nil && model.recoveredMealQuestionOrigins.count == 1)
    await model.loadMealQuestionOrigins()
    #expect(model.recoveredMealQuestionOrigins.count == 1 && !model.canReadNeutralMealQuestion(intakeID: first.id))
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  @Test func freshHeadCannotSubstituteRoutingHashOrWrongChildHash() async throws {
    for kind in ["routing", "child_hash"] {
      let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
      let model = try await f.open(); await model.refreshConversation()
      let origin = try #require(model.recoveredMealQuestionOrigins.first)
      let root = try coldOriginsProjectedUnitRoot(), heads = root["parent_heads"] as! [String: [String: Any]]
      var wrong = heads[origin.id.uuidString.lowercased()]!
      if kind == "routing" { wrong["parent_decision_hash"] = origin.selection.decisionHash }
      else {
        wrong["parent_input_hash"] = String(repeating: "f", count: 64)
        var binding = wrong["parent_binding"] as! [String: Any]; binding["input_hash"] = wrong["parent_input_hash"]; wrong["parent_binding"] = binding
      }
      await f.server.setHead(try neutralData(wrong), parentID: origin.selection.child.commandID)
      await model.beginNeutralMealReply(intakeID: origin.id)
      #expect(model.mealReplies?.presentation == nil && model.mealReplies?.pendingIntent == nil)
      #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
      await model.close()
    }
  }

  @Test func canceledOriginReadAndAccountReplacementCannotPublishOldLabelsOrForms() async throws {
    for switchAccount in [false, true] {
      let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
      let model = try await f.open(), barrier = ConversationControllerBarrier()
      await f.server.holdOrigins(barrier)
      let reading = Task { await model.refreshConversation(); await barrier.finish() }
      #expect(await barrier.waitEnteredOrFinished())
      if switchAccount {
        model.invalidateSynchronously()
        await f.http.lifecycle.replace(.init(userID: UUID().uuidString.lowercased(), generation: 8, bearer: "synthetic-next"))
      } else { model.cancelTransientWork() }
      await barrier.release(); await reading.value
      #expect(model.recoveredMealQuestionOrigins.isEmpty && model.mealReplies?.presentation == nil)
      #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
      await model.close()
    }
  }

  @Test func resettingOriginPageWhileHeadWaitsCannotOpenLateForm() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    let model = try await f.open(); await model.refreshConversation()
    let origin = try #require(model.recoveredMealQuestionOrigins.first), barrier = ConversationControllerBarrier()
    await f.server.holdHead(barrier)
    let reading = Task { await model.beginNeutralMealReply(intakeID: origin.id); await barrier.finish() }
    #expect(await barrier.waitEnteredOrFinished())
    await model.loadMealQuestionOrigins()
    await barrier.release(); await reading.value
    #expect(model.mealReplies?.presentation == nil && model.neutralMealQuestion(intakeID: origin.id) == nil)
    await model.close()
  }

  @Test func coldProtectedAnswerWinsOverOriginsAndExactGetPublishesOneEffect() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    let a = try await f.open(); await a.refreshConversation()
    let origin = try #require(a.recoveredMealQuestionOrigins.first { $0.id.uuidString.lowercased().hasSuffix("91") })
    await a.beginNeutralMealReply(intakeID: origin.id)
    let replies = try #require(a.mealReplies); replies.mealType = .almoco
    await f.server.loseNextReply(); await replies.submit()
    let original = try #require(replies.pendingIntent), owner = try ConversationOutboxOwner(lease: f.lease)
    let cipher = try Data(contentsOf: f.disk.store.fileURL(owner: owner))
    #expect(replies.canCheckStatus && a.savedEffectRevision == 0)
    await a.close()
    let b = try await f.open(); await b.refreshConversation()
    let restored = try #require(b.mealReplies)
    try restored.presentPending(replyID: original.replyID)
    #expect(restored.pendingIntent?.wireBody == original.wireBody && restored.pendingIntent?.idempotencyKey == original.idempotencyKey)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: owner)) == cipher)
    let other = try #require(b.recoveredMealQuestionOrigins.first)
    #expect(!b.canReadNeutralMealQuestion(intakeID: other.id))
    await b.beginNeutralMealReply(intakeID: other.id)
    #expect(restored.pendingIntent?.wireBody == original.wireBody && restored.canCheckStatus)
    await restored.checkStatus()
    #expect(restored.lastDelivered?.receipt != nil && b.savedEffectRevision == 1)
    await b.loadHistory()
    #expect(!b.hasUnpublishedLinkedDelivery && b.unifiedRows.filter { $0.kind == .fulfillment }.count == 1)
    await b.refreshConversation()
    #expect(b.savedEffectRevision == 1)
    let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 1 && posts[0].url?.path.hasSuffix("/replies") == true && posts[0].httpBody == original.wireBody)
    #expect(posts[0].value(forHTTPHeaderField: "Idempotency-Key") == original.idempotencyKey)
    await b.close()
  }
}

/// Canonical existing journal3 cursor framing for a controlled unrelated event.
/// It is a query token in UNIT tests, not server selection/question authority.
func coldOriginsUnitCursor(owner: UUID, epoch: UUID, at: String = "2026-11-04T12:01:00.000001Z") -> String {
  let raw = "{\"v\":3,\"owner_id\":\"\(owner.uuidString.lowercased())\",\"epoch\":\"\(epoch.uuidString.lowercased())\",\"at\":\"\(at)\",\"id\":\"workout/10000000-0000-4000-8000-000000000077\"}"
  return Data(raw.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

extension ConversationMealQuestionOriginsTests {
  @Test func knownReconciledParentCannotReappearFromAnOlderOriginObservation() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    let a = try await f.open(); await a.refreshConversation()
    let first = try #require(a.recoveredMealQuestionOrigins.first)
    await a.beginNeutralMealReply(intakeID: first.id)
    let replies = try #require(a.mealReplies); replies.mealType = .almoco
    await f.server.loseNextReply(); await replies.submit()
    let original = try #require(replies.pendingIntent)
    await a.close()
    let b = try await f.open(); await b.refreshConversation()
    let restored = try #require(b.mealReplies)
    try restored.presentPending(replyID: original.replyID); await restored.checkStatus()
    #expect(restored.lastDelivered?.receipt != nil && b.recoveredMealQuestionOrigins.count == 1)
    // A controlled older lookup projection may arrive after the genuine ACK.
    // Its observed source labels must never re-open that fulfilled parent.
    await f.server.exposeStaleClosedOriginLabels(); await b.loadMealQuestionOrigins()
    #expect(b.recoveredMealQuestionOrigins.count == 1 && !b.canReadNeutralMealQuestion(intakeID: first.id))
    #expect(b.savedEffectRevision == 1)
    await b.close()
  }

  @Test func originsRepositoryRequiresCurrentScopeClockProtocolAndNoRetry() async throws {
    for kind in ["valid", "protocol", "cache", "status", "auth", "owner", "epoch", "clock", "unauthorized", "switch"] {
      let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
      let pair = try coldOriginsUnitGrant(f), repo = try await MobileConversationIntakeRepository.scoped(transport: f.http.transport, lease: f.lease)
      var page = try coldOriginsProjectedUnitPage()
      if kind == "auth" { page["auth_user_id"] = UUID().uuidString.lowercased() }
      if kind == "owner" { page["owner_id"] = UUID().uuidString.lowercased() }
      if kind == "epoch" { page["epoch"] = UUID().uuidString.lowercased() }
      if kind == "clock" { page["observed_at"] = "2026-11-04T12:02:00.000001Z" }
      var http = try coldOriginsContractUnitHTTP(page)
      if kind == "protocol" { http.headers["X-Conversation-Protocol"] = "intake-v1" }
      if kind == "cache" { http.headers.removeValue(forKey: "Cache-Control") }
      if kind == "status" { http = .init(status: 202, body: http.body, headers: http.headers) }
      if kind == "unauthorized" { http = .failure(401, "invalid_access_token") }
      let response = http
      await f.http.stub.respond { _, _ in
        if kind == "switch" { await f.http.lifecycle.replace(.init(userID: UUID().uuidString.lowercased(), generation: 8, bearer: "synthetic-next")) }
        return response
      }
      if kind == "valid" {
        let data = try await repo.questionOrigins(context: pair.context)
        #expect(data.items.count == 2 && data.authUserID != data.ownerID)
      } else {
        await #expect(throws: (any Error).self) { try await repo.questionOrigins(context: pair.context) }
      }
      let requests = await f.http.stub.requests
      #expect(requests.count == 1 && requests[0].httpMethod == "GET" && requests[0].httpBody == nil)
      #expect(requests[0].value(forHTTPHeaderField: "X-Conversation-Protocol") == "intake-question-origins-v1")
      #expect(requests[0].value(forHTTPHeaderField: "X-Conversation-Owner") == pair.context.ownerID.uuidString.lowercased())
      #expect(requests[0].value(forHTTPHeaderField: "X-Conversation-Epoch") == pair.context.epoch.uuidString.lowercased())
      #expect(requests[0].value(forHTTPHeaderField: "Idempotency-Key") == nil && requests[0].value(forHTTPHeaderField: "X-Conversation-Input-Hash") == nil)
    }
  }

  @Test func staleGrantAndInvalidPageLimitCannotReadOrPublishAnOrigin() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    let repo = try await MobileConversationIntakeRepository.scoped(transport: f.http.transport, lease: f.lease)
    let pair = try coldOriginsUnitGrant(f)
    await #expect(throws: (any Error).self) { try await repo.questionOrigins(limit: 0, context: pair.context) }
    let foreign = coldOriginsUnitCursor(owner: UUID(), epoch: pair.context.epoch)
    await #expect(throws: (any Error).self) { try await repo.questionOrigins(cursor: foreign, context: pair.context) }
    #expect(await f.http.stub.requests.isEmpty)
    let response = try coldOriginsContractUnitHTTP(coldOriginsProjectedUnitPage())
    await f.http.stub.respond { _, _ in _ = try pair.authority.beginRefresh(); return response }
    await #expect(throws: (any Error).self) { try await repo.questionOrigins(context: pair.context) }
    #expect(await f.http.stub.requests.count == 1)
  }

  @Test func replayedEmptyCursorStopsWithoutAutomaticPagination() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    var page = try coldOriginsProjectedUnitPage()
    let cursor = coldOriginsUnitCursor(owner: UUID(uuidString: page["owner_id"] as! String)!, epoch: UUID(uuidString: page["epoch"] as! String)!)
    page["items"] = [] as [Any]; page["has_more"] = true; page["next_cursor"] = cursor
    await f.server.setPage(try neutralData(page)); await f.server.setPage(try neutralData(page), cursor: cursor)
    let model = try await f.open(); await model.refreshConversation(); await model.loadMealQuestionOrigins(reset: false)
    #expect(model.recoveredMealQuestionOrigins.isEmpty && model.mealQuestionOrigins?.unavailable == true)
    #expect(await f.http.stub.requests.filter { $0.url?.path == "/api/mobile/v1/conversation/intakes" }.count == 2)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  #if canImport(UIKit)
  @Test func actualFlowRefreshTaskLoadsOriginsAndNativeRecoveryControlsUseDistinctIds() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    let model = try await f.open()
    let shell = SignUpRenderingProbe.host(FlowConversationView(model: model), width: 390, height: 1200)
    defer { shell.detach() }
    shell.settle()
    for _ in 0..<100 {
      if model.recoveredMealQuestionOrigins.count == 2 { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.recoveredMealQuestionOrigins.count == 2)
    #expect(await f.http.stub.requests.contains { $0.url?.path == "/api/mobile/v1/conversation/intakes" && $0.httpMethod == "GET" })
    // The existing AX probe cannot read a ScrollView's descendants. Inspect
    // the same real mounted component directly, retaining the shell task proof.
    let content = SignUpRenderingProbe.host(FlowConversationMealQuestionOriginsContent(model: model), width: 390, height: 1000)
    defer { content.detach() }
    let nodes = content.nodes(), buttons = nodes.filter { $0.identifier.hasPrefix("conversation.origins.answer.") }
    #expect(buttons.count == 2 && Set(buttons.map(\.identifier)).count == 2 && buttons.allSatisfy(\.isEnabled))
    #expect(nodes.contains { $0.label == "Comi 200 mL de leite" } && nodes.contains { $0.label == "Comi leite" })
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }
  #endif
}

/// Explicit controlled test grant, independent of origin-body authority.
@MainActor func coldOriginsUnitGrant(_ f: ColdOriginsNativeFixture) throws -> (context: ConversationCommandContext, authority: ConversationOutboxObservationAuthority) {
  let page = try coldOriginsProjectedUnitPage(), authority = ConversationOutboxObservationAuthority()
  let id = try authority.beginRefresh()
  let context = ConversationCommandContext(observation: try authority.accept(refreshID: id,
    authUserID: UUID(uuidString: f.lease.userID)!, ownerID: UUID(uuidString: page["owner_id"] as! String)!, localSessionGeneration: f.lease.generation, epoch: UUID(uuidString: page["epoch"] as! String)!), observedAt: page["observed_at"] as! String)
  return (context, authority)
}

extension ConversationMealQuestionOriginsTests {
  @Test func emptyCandidatePageCannotMoveCursorBackTowardNewerHistory() async throws {
    let f = try await coldOriginsNativeFixture(); defer { f.disk.remove() }
    var page = try coldOriginsProjectedUnitPage()
    let owner = UUID(uuidString: page["owner_id"] as! String)!, epoch = UUID(uuidString: page["epoch"] as! String)!
    let first = coldOriginsUnitCursor(owner: owner, epoch: epoch)
    let backwards = coldOriginsUnitCursor(owner: owner, epoch: epoch, at: "2026-11-04T12:01:30.000001Z")
    page["items"] = [] as [Any]; page["has_more"] = true; page["next_cursor"] = first
    await f.server.setPage(try neutralData(page))
    page["next_cursor"] = backwards; await f.server.setPage(try neutralData(page), cursor: first)
    let model = try await f.open(); await model.refreshConversation(); await model.loadMealQuestionOrigins(reset: false)
    #expect(model.recoveredMealQuestionOrigins.isEmpty && model.mealQuestionOrigins?.unavailable == true)
    #expect(await f.http.stub.requests.filter { $0.url?.path == "/api/mobile/v1/conversation/intakes" }.count == 2)
    await model.close()
  }
}
