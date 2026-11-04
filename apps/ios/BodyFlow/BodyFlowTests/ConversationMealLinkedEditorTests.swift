import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
  import UIKit
#endif

@Suite("Genuine linked meal uses the existing immutable editor")
@MainActor
struct ConversationMealLinkedEditorTests {
  @Test func currentLinkedPrepareCreatesOnlyTheActualChildOperation() async throws {
    let f = try LinkedMealEditorFixture()
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { _, _ in .init(status: 200, body: f.groupBody) }
    let controller = try await f.base.openController()
    let prepared = try await controller.prepare(
      linked: f.identity, expectedRevision: f.group.revision,
      expectedVersion: #require(f.group.current).expectedVersion,
      action: .save(recordID: f.itemID, items: [try .init(foodName: "Iogurte", quantityG: 100)]),
      context: f.context)
    #expect(prepared.operation.commandID == f.identity.commandID)
    #expect(prepared.operation.originalInputHash == f.identity.inputHash)
    #expect(prepared.operation.ownerID == f.identity.ownerID)
    #expect(prepared.operation.commandID != f.identity.parentBinding.commandID)
    #expect(await f.base.http.stub.requests.count == 1)
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    await controller.close()
  }

  @Test(arguments: ["decision", "effect", "admission", "revision", "disabled"])
  func freshLinkedReadMustRetainLineageAndCapturedCAS(_ attack: String) async throws {
    let f = try LinkedMealEditorFixture()
    defer { f.base.disk.remove() }
    var raw = try f.leaf.groupRaw
    var revision = f.group.revision
    if attack == "revision" { revision += 1 }
    if attack == "decision" || attack == "effect" {
      var receipt = try #require(raw["original_receipt"] as? [String: Any])
      receipt[attack == "decision" ? "parent_decision_hash" : "effect_version"] =
        attack == "decision"
        ? String(repeating: "a", count: 64) : "cmeal1:" + String(repeating: "a", count: 64)
      raw["original_receipt"] = receipt
    }
    if attack == "admission" { raw["admitted_at"] = "2026-11-04T18:15:27.997474Z" }
    if attack == "disabled" {
      var actions = try #require(raw["actions"] as? [String: Any])
      actions["save"] = ["allowed": false, "reason": "day_closed"]
      raw["actions"] = actions
    }
    let body = try linkedEditorEnvelope(raw)
    await f.base.http.stub.respond { _, _ in .init(status: 200, body: body) }
    let controller = try await f.base.openController()
    await #expect(throws: (any Error).self) {
      try await controller.prepare(
        linked: f.identity, expectedRevision: revision,
        expectedVersion: #require(f.group.current).expectedVersion,
        action: .save(recordID: f.itemID, items: [try .init(foodName: "Iogurte", quantityG: 100)]),
        context: f.context)
    }
    #expect(await f.base.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    await controller.close()
  }

  @Test(arguments: [false, true])
  func editorSaveAndUndoRegistrationUseTheChildRouteAndImmutableReceipt(_ undo: Bool) async throws {
    let f = try LinkedMealEditorFixture()
    defer { f.base.disk.remove() }
    await f.base.http.stub.respond { request, _ in
      request.httpMethod == "GET"
        ? .init(status: 200, body: f.groupBody) : try f.savedReply(request)
    }
    let controller = try await f.base.openController()
    let probe = FlowEditUIProbe()
    let editor = try await FlowConversationMealEditModel.open(
      controller: controller, lifecycle: f.base.http.lifecycle,
      lease: await f.base.http.lifecycle.leaseForRequest()
    ) { result, _ in probe.saved.append(result) }
    editor.accept(f.context)
    if undo {
      await editor.undoRegistration(linked: f.identity, group: f.group)
    } else {
      try editor.beginEditing(linked: f.identity, group: f.group, itemID: f.itemID)
      editor.setQuantityText("100", language: .englishUnitedStates)
      #expect(editor.canSave(language: .englishUnitedStates))
      await editor.save(language: .englishUnitedStates)
    }
    #expect(probe.saved.count == 1 && editor.pendingOperation == nil && editor.failure == nil)
    #expect(editor.lastSaved?.commandID == f.identity.commandID)
    let requests = await f.base.http.stub.requests
    let write = try #require(requests.last)
    #expect(
      requests.count == 2 && requests.first?.httpMethod == "GET" && write.httpMethod == "POST")
    #expect(write.url?.path.contains(f.identity.commandID.uuidString.lowercased()) == true)
    #expect(
      write.url?.path.contains(f.identity.parentBinding.commandID.uuidString.lowercased()) == false)
    #expect(write.value(forHTTPHeaderField: "X-Conversation-Input-Hash") == f.identity.inputHash)
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    await editor.close()
  }

  @Test func undoSaveKeepsTheActualChildTargetRevisionAndFreshCAS() async throws {
    let f = try LinkedMealEditorFixture()
    defer { f.base.disk.remove() }
    let target = UUID(uuidString: "c3c70000-0000-4000-8000-000000000077")!
    let original = try ConversationMealEditOperation(
      ownerID: f.identity.ownerID, commandID: f.identity.commandID,
      originalInputHash: f.identity.inputHash, epoch: f.identity.epoch, operationID: target,
      expectedRevision: 0, expectedVersion: #require(f.group.current?.expectedVersion),
      action: .save(recordID: f.itemID, items: [try .init(foodName: "Iogurte", quantityG: 100)]))
    var request = URLRequest(
      url: URL(string: "https://unit.invalid/edits/\(target.uuidString.lowercased())")!)
    request.httpBody = original.wireBody
    let savedEnvelope = try #require(
      JSONSerialization.jsonObject(with: f.savedReply(request).body) as? [String: Any])
    let savedResult = try #require(savedEnvelope["data"] as? [String: Any])
    let effect = try #require(savedResult["receipt"] as? [String: Any])
    var raw = try f.leaf.groupRaw
    raw["revision"] = 1
    raw["last_operation"] = effect
    raw["observed_at"] = "2026-11-04T18:16:02.000000Z"
    var current = try #require(raw["current"] as? [String: Any])
    current["expected_version"] = "v1:" + String(repeating: "a", count: 64)
    var items = try #require(current["items"] as? [[String: Any]])
    items[0]["id"] = "c3c70000-0000-4000-8000-000000000098"
    current["items"] = items
    raw["current"] = current
    raw["actions"] = [
      "save": ["allowed": true], "undo_save": ["allowed": true],
      "undo_registration": ["allowed": false, "reason": "version_changed"],
    ]
    let group = try f.leaf.group(raw)
    let body = try linkedEditorEnvelope(raw)
    await f.base.http.stub.respond { request, _ in
      request.httpMethod == "GET" ? .init(status: 200, body: body) : try f.savedReply(request)
    }
    let controller = try await f.base.openController()
    let editor = try await FlowConversationMealEditModel.open(
      controller: controller, lifecycle: f.base.http.lifecycle,
      lease: await f.base.http.lifecycle.leaseForRequest()
    ) { _, _ in }
    editor.accept(f.context)
    await editor.undoSave(linked: f.identity, group: group)
    let posted = try #require(await f.base.http.stub.requests.last)
    let operation = try f.operation(posted)
    #expect(
      operation.expectedRevision == 1 && operation.expectedVersion == group.current?.expectedVersion
    )
    if case .undoSave(let actual) = operation.action {
      #expect(actual == target)
    } else {
      Issue.record("The explicit actual saved edit must be the Undo target")
    }
    #expect(editor.lastSaved?.receipt.kind == .saveUndone && editor.pendingOperation == nil)
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    await editor.close()
  }

  @Test func coldEncryptedChildReconcilesWithoutAnyParentHistoryOrCurrentGroup() async throws {
    let f = try LinkedMealEditorFixture()
    defer { f.base.disk.remove() }
    let operation = try ConversationMealEditOperation(
      ownerID: f.identity.ownerID, commandID: f.identity.commandID,
      originalInputHash: f.identity.inputHash, epoch: f.identity.epoch,
      operationID: UUID(), expectedRevision: f.group.revision,
      expectedVersion: #require(f.group.current?.expectedVersion),
      action: .save(recordID: f.itemID, items: [try .init(foodName: "Iogurte", quantityG: 100)]))
    let session = try await f.base.session()
    let id = try await session.enqueue(operation: operation, server: f.context.observation)
    let ticket = try await session.prepareDispatch(id: id, server: f.context.observation)
    try await session.markWaiting(ticket: ticket, hold: .unknownOutcome)
    await session.invalidate()
    await f.base.http.stub.respond { request, _ in
      guard request.url?.path.hasSuffix("/reconcile") == true else {
        throw URLError(.networkConnectionLost)
      }
      return try f.savedReply(request)
    }
    let controller = try await f.base.openController()
    let editor = try await FlowConversationMealEditModel.open(
      controller: controller, lifecycle: f.base.http.lifecycle,
      lease: await f.base.http.lifecycle.leaseForRequest()
    ) { _, _ in }
    editor.accept(f.context)
    await editor.restore()
    try editor.presentPending(id: id)
    #expect(editor.pendingOperation?.wireBody == operation.wireBody)
    await editor.reconcile()
    #expect(editor.lastSaved?.matches(operation: operation) == true)
    #expect(editor.pendingOperation == nil && editor.historicalNotice == nil)
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    let requests = await f.base.http.stub.requests
    #expect(requests.count == 1 && requests.first?.httpBody == operation.wireBody)
    #expect(requests.first?.url?.path.hasSuffix("/reconcile") == true)
    await editor.close()
  }

  @Test(arguments: ["patient", "epoch", "logout"])
  func linkedPreparationCannotReturnOldPatientPayloadAfterItsLocalStateGate(_ change: String)
    async throws
  {
    let f = try LinkedMealEditorFixture()
    defer { f.base.disk.remove() }
    await f.base.seedKey()
    await f.base.http.stub.respond { _, _ in .init(status: 200, body: f.groupBody) }
    let gate = EditMutationGate()
    let life = EditGatedLifecycle(base: f.base.http.lifecycle, gate: gate)
    let controller = try await ConversationMealEditController.open(
      transport: f.base.http.transport, lifecycle: life, store: f.base.disk.store,
      keyVault: f.base.vault)
    let barrier = ConversationControllerBarrier()
    await gate.holdNextStateReturn(barrier)
    let work = Task {
      try await controller.prepare(
        linked: f.identity, expectedRevision: f.group.revision,
        expectedVersion: #require(f.group.current?.expectedVersion),
        action: .undoRegistration, context: f.context)
    }
    #expect(await barrier.waitEnteredOrFinished())
    if change == "logout" {
      await f.base.http.lifecycle.replace(
        .init(userID: UUID().uuidString, generation: 8, bearer: "synthetic-next"))
    } else {
      let token = try f.base.authority.beginRefresh()
      _ = try f.base.authority.accept(
        refreshID: token, authUserID: f.context.authUserID,
        ownerID: change == "patient" ? UUID() : f.context.ownerID,
        localSessionGeneration: f.context.sessionGeneration,
        epoch: change == "epoch" ? UUID() : f.context.epoch)
    }
    await barrier.release()
    await #expect(throws: (any Error).self) { try await work.value }
    #expect(try f.base.disk.store.load(owner: f.base.disk.owner, key: f.base.disk.key).isEmpty)
    await controller.close()
  }

  #if canImport(UIKit)
    @Test func nativeLinkedMealCardExposesTheRealItemPencilAndUndoRegistration() throws {
      let f = try LinkedMealIdentityFixture()
      let identity = try f.identity()
      let group = try f.group()
      let row = FlowConversationLinkedMealRow(
        reference: identity.reference, identity: identity, feedback: nil)
      let scope = ConversationFeedbackPresentationSnapshot.Scope(
        ownerID: identity.ownerID.uuidString.lowercased(),
        sessionGeneration: 7, epoch: identity.epoch.uuidString.lowercased())
      let actions = FlowConversationMealEditActions(
        editItem: { _ in }, undoSave: { _ in }, undoRegistration: { _ in }, isWorking: false)
      let host = SignUpRenderingProbe.host(
        FlowConversationLinkedMealResponseView(
          row: row, group: group, scope: scope, editing: actions, refresh: {}
        )
        .environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 1600)
      defer { host.detach() }
      let nodes = host.nodes()
      let item = try #require(group.current?.items.first)
      #expect(
        nodes.contains {
          $0.identifier == "conversation.meal.edit.\(item.id.uuidString.lowercased())"
            && $0.isButton && $0.isEnabled
        })
      #expect(
        nodes.contains { $0.identifier == "conversation.meal.undo-registration" && $0.isButton })
      #expect(nodes.contains { $0.identifier == "conversation.meal.original-history" })
      #expect(!nodes.contains { $0.identifier == "conversation.thread.linked-actions-unavailable" })
    }
  #endif

  @Test func wrongLinkedOriginCannotOpenARealCurrentGroup() async throws {
    let f = try LinkedMealEditorFixture()
    defer { f.base.disk.remove() }
    let controller = try await f.base.openController()
    let editor = try await FlowConversationMealEditModel.open(
      controller: controller, lifecycle: f.base.http.lifecycle,
      lease: await f.base.http.lifecycle.leaseForRequest()
    ) { _, _ in }
    editor.accept(f.context)
    var raw = try f.leaf.groupRaw
    var receipt = try #require(raw["original_receipt"] as? [String: Any])
    receipt["parent_decision_hash"] = String(repeating: "a", count: 64)
    raw["original_receipt"] = receipt
    let other = try f.leaf.group(raw)
    #expect(throws: (any Error).self) {
      try editor.beginEditing(linked: f.identity, group: other, itemID: f.itemID)
    }
    #expect(editor.presentation == nil && editor.pendingOperation == nil)
    #expect(await f.base.http.stub.requests.isEmpty)
    await editor.close()
  }
}

/// Controlled unit transport responses. The original SDK and group projector
/// fixtures remain exact; this helper claims no actual server/SQL/HTTP fixture.
struct LinkedMealEditorFixture: Sendable {
  let base: EditControllerFixture
  let leaf: LinkedMealIdentityFixture
  let identity: ConversationMealLinkedIdentity
  let group: ConversationMealGroupSnapshot
  let groupBody: Data
  let context: ConversationCommandContext
  let itemID: UUID
  init() throws {
    base = try .init()
    leaf = try .init()
    identity = try leaf.identity()
    group = try leaf.group()
    itemID = try #require(group.current?.items.first?.id)
    groupBody = try linkedEditorEnvelope(leaf.groupRaw)
    let token = try base.authority.beginRefresh()
    context = .init(
      observation: try base.authority.accept(
        refreshID: token, authUserID: base.context.authUserID, ownerID: identity.ownerID,
        localSessionGeneration: base.context.sessionGeneration, epoch: identity.epoch),
      observedAt: identity.parentBinding.admittedAt)
  }
  func operation(_ request: URLRequest) throws -> ConversationMealEditOperation {
    var parts = try #require(request.url?.pathComponents)
    if parts.last == "reconcile" { parts.removeLast() }
    let last = try #require(parts.last)
    let operationID = try #require(UUID(uuidString: last))
    return try .init(
      ownerID: identity.ownerID, commandID: identity.commandID,
      originalInputHash: identity.inputHash, epoch: identity.epoch, operationID: operationID,
      wireBody: #require(request.httpBody))
  }
  func savedReply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let operation = try operation(request)
    let next = "c3c70000-0000-4000-8000-000000000098"
    let undo: Bool
    let kind: String
    let removed: [String]
    let target: Any
    switch operation.action {
    case .save(let record, _):
      undo = false
      kind = "saved"
      removed = [record.uuidString.lowercased()]
      target = NSNull()
    case .undoSave(let id):
      undo = true
      kind = "save_undone"
      removed = [next]
      target = id.uuidString.lowercased()
    case .undoRegistration:
      undo = true
      kind = "registration_undone"
      removed = [itemID.uuidString.lowercased()]
      target = NSNull()
    }
    let registrationUndo = kind == "registration_undone"
    let nextID = kind == "save_undone" ? "c3c70000-0000-4000-8000-000000000097" : next
    let receipt: [String: Any] = [
      "schema": "conversation.meal-edit-effect-public.v1",
      "owner_id": identity.ownerID.uuidString.lowercased(),
      "command_id": identity.commandID.uuidString.lowercased(),
      "operation_id": operation.operationID.uuidString.lowercased(),
      "input_hash": operation.operationInputHash, "kind": kind,
      "revision": operation.expectedRevision + 1, "applied_at": "2026-11-04T18:16:01.000000Z",
      "undo_expires_at": undo ? NSNull() : "2026-11-04T18:21:01.000000Z",
      "target_operation_id": target, "removed_item_ids": removed,
      "new_item_ids": registrationUndo ? [] : [nextID],
      "next_record_id": registrationUndo ? NSNull() : nextID,
    ]
    return .init(
      status: 200,
      body: try linkedEditorEnvelope([
        "schema": "conversation.meal-edit-result.v1", "status": "saved",
        "owner_id": identity.ownerID.uuidString.lowercased(),
        "command_id": identity.commandID.uuidString.lowercased(), "input_hash": identity.inputHash,
        "epoch": identity.epoch.uuidString.lowercased(), "receipt": receipt,
      ]))
  }
}
func linkedEditorEnvelope(_ raw: [String: Any]) throws -> Data {
  try JSONSerialization.data(withJSONObject: [
    "data": raw, "meta": ["api_version": "v1", "request_id": "controlled-linked-editor-unit"],
  ])
}
