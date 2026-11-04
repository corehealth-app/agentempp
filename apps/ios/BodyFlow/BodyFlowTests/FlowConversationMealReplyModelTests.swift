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
