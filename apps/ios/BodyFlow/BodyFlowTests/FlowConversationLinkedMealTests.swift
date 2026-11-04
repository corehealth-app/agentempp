import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Flow keeps linked child groups separate from original reports")
@MainActor
struct FlowConversationLinkedMealTests {
  @Test func coldEditOnlyPageCanOnlyReadUntilTheActualGroupCompletesItsOrigin() async throws {
    let f = try await LinkedFlowUnitFixture.make()
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    let row = try #require(model.linkedMealRow(eventID: f.editEventID))
    #expect(row.identity == nil && row.reference.commandID == f.childID)
    #expect(model.savedRows.isEmpty && model.pendingRows.isEmpty)
    #expect(model.mealEditActions(commandID: f.childID) == nil)
    #expect(model.knownEditRevision(commandID: f.childID) == 1)
    await model.loadCurrentGroup(commandID: f.childID)
    let complete = try #require(model.linkedMealRow(eventID: f.editEventID)?.identity)
    let current = try #require(model.currentGroup(commandID: f.childID))
    #expect(complete.matches(group: current))
    #expect(model.mealEditActions(commandID: f.childID) != nil)
    #expect(model.savedRows.isEmpty && model.savedEffectRevision == 0)
    let requests = await f.http.stub.requests
    #expect(requests.allSatisfy { $0.httpMethod == "GET" })
    #expect(requests.last?.url?.path.contains(f.childID.uuidString.lowercased()) == true)
    #expect(
      requests.last?.value(forHTTPHeaderField: "X-Conversation-Input-Hash")
        == row.reference.inputHash)
    await model.close()
  }
  @Test func knownChildEditRejectsALateUneditedGroupAndKeepsItsRevisionFence() async throws {
    let f = try await LinkedFlowUnitFixture.make(staleGroup: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    await model.loadCurrentGroup(commandID: f.childID)
    #expect(
      model.currentGroup(commandID: f.childID) == nil
        && model.groupUnavailable(commandID: f.childID))
    #expect(model.knownEditRevision(commandID: f.childID) == 1)
    #expect(model.linkedMealRow(eventID: f.editEventID)?.identity == nil)
    await model.close()
  }
  @Test func sameChildIDCannotChangeItsOriginalHashOnAResetPage() async throws {
    let f = try await LinkedFlowUnitFixture.make()
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    await model.loadCurrentGroup(commandID: f.childID)
    let before = model.linkedMealRow(eventID: f.editEventID)?.identity
    let malicious = try f.pageBody(changedHash: true)
    await f.http.stub.respond { _, _ in .init(status: 200, body: malicious) }
    await model.loadHistory()
    #expect(model.historyUnavailable)
    #expect(model.linkedMealRow(eventID: f.editEventID)?.identity == before)
    #expect(model.knownEditRevision(commandID: f.childID) == 1)
    await model.close()
  }
  @Test(arguments: [true, false])
  func historyOnlyClosesTheUIWhenTheExactCiphertextIsAlreadyAbsent(_ closed: Bool) async throws {
    let f = try await LinkedFlowUnitFixture.make(staleGroup: true)
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let authority = ConversationOutboxObservationAuthority()
    let token = try authority.beginRefresh()
    let context = ConversationCommandContext(
      observation: try authority.accept(
        refreshID: token, authUserID: #require(UUID(uuidString: lease.userID)),
        ownerID: f.identity.ownerID, localSessionGeneration: lease.generation,
        epoch: f.identity.epoch),
      observedAt: f.identity.parentBinding.admittedAt)
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle, lease: lease)
    let originalGroup = try await repo.group(linked: f.identity, context: context)
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      if !closed { throw URLError(.networkConnectionLost) }
      await f.http.lifecycle.holdNextVisible(barrier)
      return try f.savedReply(request)
    }
    let controller = try await ConversationMealEditController.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      store: f.editing.store, keyVault: f.editing.keyVault)
    let probe = LinkedHistoricalNoticeProbe()
    let editor = try await FlowConversationMealEditModel.open(
      controller: controller, lifecycle: f.http.lifecycle, lease: lease,
      onHistorical: { value, _ in probe.notices.append(value) },
      onSaved: { value, _ in probe.saved.append(value) })
    editor.accept(context)
    try editor.beginEditing(
      linked: f.identity, group: originalGroup,
      itemID: #require(originalGroup.current?.items.first?.id))
    editor.setQuantityText("250", language: .englishUnitedStates)
    let work = Task { await editor.save(language: .englishUnitedStates) }
    if closed {
      #expect(await barrier.waitEnteredOrFinished())
      #expect(try f.editing.store.load(owner: f.owner, key: f.disk.key).isEmpty)
      work.cancel()
      await barrier.release()
    }
    await work.value
    let original = try #require(editor.pendingOperation)
    await editor.restore()
    let before = try Data(contentsOf: f.editing.store.fileURL(owner: f.owner))
    let bodies = try f.historyAndGroup(operation: original)
    await f.http.stub.respond { request, _ in
      .init(
        status: 200,
        body: request.url?.path.hasSuffix("/journal") == true ? bodies.page : bodies.group)
    }
    let read = try await repo.threadJournal(context: context)
    let group = try await repo.group(linked: f.identity, context: context)
    editor.observeThreadJournal(read, linked: f.identity, group: group)
    #expect((editor.pendingOperation == nil) == closed)
    #expect((editor.historicalNotice != nil) == closed)
    #expect(editor.lastSaved == nil && probe.saved.isEmpty)
    #expect(probe.notices.count == (closed ? 1 : 0))
    #expect(try Data(contentsOf: f.editing.store.fileURL(owner: f.owner)) == before)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await editor.close()
  }

  @Test func laterPaginationDoesNotHideTheActualEditReadNeededForHistoricalRecovery() async throws {
    let f = try await LinkedFlowUnitFixture.make(staleGroup: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    let editor = try #require(model.mealEditor)
    let lease = await f.http.lifecycle.leaseForRequest()
    let context = ConversationCommandContext(
      observation: .init(
        authUserID: try #require(UUID(uuidString: lease.userID)), ownerID: f.identity.ownerID,
        localSessionGeneration: lease.generation, epoch: f.identity.epoch),
      observedAt: f.identity.parentBinding.admittedAt)
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle, lease: lease)
    let initial = try await repo.group(linked: f.identity, context: context)
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "GET" { return .init(status: 200, body: f.groupBody) }
      await f.http.lifecycle.holdNextVisible(barrier)
      return try f.savedReply(request)
    }
    try editor.beginEditing(
      linked: f.identity, group: initial, itemID: #require(initial.current?.items.first?.id))
    editor.setQuantityText("250", language: .englishUnitedStates)
    let work = Task { await editor.save(language: .englishUnitedStates) }
    #expect(await barrier.waitEnteredOrFinished())
    work.cancel()
    await barrier.release()
    await work.value
    let original = try #require(editor.pendingOperation)
    await editor.restore()
    let bodies = try f.historyAndGroup(operation: original)
    var root = try #require(JSONSerialization.jsonObject(with: bodies.page) as? [String: Any])
    var first = try #require(root["data"] as? [String: Any])
    let events = try #require(first["items"] as? [[String: Any]])
    let last = try #require(events.last)
    let at = try #require(last["at"] as? String)
    let id = try #require(last["event_id"] as? String)
    let cursor =
      "{\"v\":2,\"owner_id\":\"\(f.identity.ownerID.uuidString.lowercased())\",\"epoch\":\"\(f.identity.epoch.uuidString.lowercased())\",\"at\":\"\(at)\",\"id\":\"\(id)\"}"
    first["has_more"] = true
    first["next_cursor"] = Data(cursor.utf8).base64EncodedString().replacingOccurrences(
      of: "+", with: "-"
    )
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    root["data"] = first
    let firstBody = try JSONSerialization.data(withJSONObject: root)
    var second = try #require(root["data"] as? [String: Any])
    second["items"] = [try JSONSerialization.jsonObject(with: f.reportEvent)]
    second["has_more"] = false
    second["next_cursor"] = NSNull()
    let secondBody = try linkedEditorEnvelope(second)
    let groupCounter = ConversationControllerCounter()
    await f.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/journal") == true {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        return .init(
          status: 200,
          body: query?.contains { $0.name == "cursor" } == true ? secondBody : firstBody)
      }
      if await groupCounter.next() == 1 { throw URLError(.networkConnectionLost) }
      return .init(status: 200, body: bodies.group)
    }
    await model.loadHistory()
    #expect(editor.pendingOperation != nil)
    await model.loadHistory(reset: false)
    #expect(model.threadRows.count == 2 && !model.historyUnavailable)
    #expect(editor.pendingOperation == nil && editor.historicalNotice != nil)
    #expect(editor.lastSaved == nil && model.savedRows.isEmpty && model.savedEffectRevision == 1)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }

  @Test(arguments: ["uuid", "action", "hash", "owner", "epoch", "revision", "stale-group"])
  func historicalNoticeRequiresTheExactOriginalIntentAndFreshBoundGroup(_ attack: String)
    async throws
  {
    let f = try await LinkedFlowUnitFixture.make(staleGroup: true)
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let context = ConversationCommandContext(
      observation: .init(
        authUserID: try #require(UUID(uuidString: lease.userID)), ownerID: f.identity.ownerID,
        localSessionGeneration: lease.generation, epoch: f.identity.epoch),
      observedAt: f.identity.parentBinding.admittedAt)
    let operationID = UUID()
    let action = ConversationMealEditOperation.Action.save(
      recordID: try #require(f.identity.receipt.logIDs.first),
      items: [try .init(foodName: "Leite", quantityG: 250)])
    let original = try ConversationMealEditOperation(
      ownerID: f.identity.ownerID,
      commandID: f.childID, originalInputHash: f.identity.inputHash, epoch: f.identity.epoch,
      operationID: operationID, expectedRevision: 0,
      expectedVersion: "v1:" + String(repeating: "a", count: 64), action: action)
    let changed = try ConversationMealEditOperation(
      ownerID: attack == "owner" ? UUID() : original.ownerID,
      commandID: original.commandID,
      originalInputHash: attack == "hash"
        ? String(repeating: "a", count: 64) : original.originalInputHash,
      epoch: attack == "epoch" ? UUID() : original.epoch,
      operationID: attack == "uuid" ? UUID() : original.operationID,
      expectedRevision: attack == "revision" ? 1 : original.expectedRevision,
      expectedVersion: original.expectedVersion,
      action: attack == "action" ? .undoRegistration : action)
    let bodies = try f.historyAndGroup(operation: original)
    var groupBody = bodies.group
    if attack == "stale-group" {
      var envelope = try #require(JSONSerialization.jsonObject(with: groupBody) as? [String: Any])
      var group = try #require(envelope["data"] as? [String: Any])
      group["observed_at"] = "2026-11-04T12:00:05.000001Z"
      envelope["data"] = group
      groupBody = try JSONSerialization.data(withJSONObject: envelope)
    }
    let frozenGroup = groupBody
    await f.http.stub.respond { request, _ in
      .init(
        status: 200,
        body: request.url?.path.hasSuffix("/journal") == true ? bodies.page : frozenGroup)
    }
    let repo = try await MobileConversationHistoryRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle, lease: lease)
    let read = try await repo.threadJournal(context: context)
    let group = try await repo.group(linked: f.identity, context: context)
    #expect(
      ConversationMealEditHistoricalNotice.qualify(
        operation: changed, read: read, linked: f.identity, group: group) == nil)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
  }

  @Test func removedRegistrationNeverOffersANewEditOrUndoAction() async throws {
    let f = try await LinkedFlowUnitFixture.make(removed: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    await model.loadCurrentGroup(commandID: f.childID)
    #expect(model.currentGroup(commandID: f.childID)?.current == nil)
    #expect(model.mealEditActions(commandID: f.childID) == nil)
    await model.close()
  }
}

/// An unchanged existing closed page supplies genuine typed parent/child
/// observations. Current C11 facts are a controlled UNIT response only.
/// This does not claim a coherent actual server/SQL/HTTP capture.
struct LinkedFlowUnitFixture: Sendable {
  let disk: OutboxDiskFixture
  let http: ConversationHTTPFixture
  let owner: ConversationOutboxOwner
  let vault: ConversationOutboxKeyVault
  let editing: FlowConversationMealEditingDependencies
  let rawPage: Data
  let childID: UUID
  let editEventID: String
  let identity: ConversationMealLinkedIdentity
  let groupBody: Data
  let reportEvent: Data
  static func make(staleGroup: Bool = false, removed: Bool = false) async throws -> Self {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationThreadPagePublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationThreadPagePublicFixtures.json")
    #endif
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var page = try #require(root["data"] as? [String: Any])
    let events = try #require(page["items"] as? [[String: Any]])
    let completePage = try ConversationThreadPageSnapshot(
      data: JSONSerialization.data(withJSONObject: page))
    let parent = try #require(completePage.threads.first)
    let value = try #require(
      completePage.items.first {
        if case .fulfillment = $0.detail { return true }
        return false
      })
    guard case .fulfillment(let fulfillmentValue) = value.detail else {
      throw URLError(.badServerResponse)
    }
    let identity = try ConversationMealLinkedIdentity(
      parentBinding: parent.parentBinding, childBinding: fulfillmentValue.binding,
      parentDecisionHash: #require(parent.terminalReceipt?.decisionHash),
      receipt: fulfillmentValue.receipt)
    var edit = try #require(events.first { $0["kind"] as? String == "edit" })
    let fulfillment = try #require(events.first { $0["kind"] as? String == "fulfillment" })
    let receipt = try #require(fulfillment["receipt"] as? [String: Any])
    let child = try #require(edit["effect_binding"] as? [String: Any])
    var effect = try #require(edit["receipt"] as? [String: Any])
    if removed {
      effect["kind"] = "registration_undone"
      effect["undo_expires_at"] = NSNull()
      effect["new_item_ids"] = []
      effect["next_record_id"] = NSNull()
      edit["receipt"] = effect
    }
    page["items"] = [edit]
    let pageBytes = try JSONSerialization.data(withJSONObject: page)
    let parsed = try ConversationThreadPageSnapshot(data: pageBytes)
    let childID = try #require(parsed.items.first?.childBinding?.commandID)
    let oldIDs = try #require(receipt["log_ids"] as? [String])
    let newIDs = try #require(effect["new_item_ids"] as? [String])
    let itemID = try #require((staleGroup ? oldIDs : newIDs).first ?? oldIDs.first)
    let group: [String: Any] = [
      "schema": "conversation.meal-group.v2", "owner_id": page["owner_id"]!,
      "command_id": child["command_id"]!, "input_hash": child["input_hash"]!,
      "epoch": page["epoch"]!,
      "admitted_at": child["admitted_at"]!, "observed_at": page["observed_at"]!,
      "original_receipt": receipt, "revision": staleGroup ? 0 : 1, "lineage_compatible": true,
      "current": removed
        ? NSNull()
        : [
          "expected_version": "v1:" + String(repeating: "a", count: 64),
          "local_date": receipt["local_date"]!, "timezone": receipt["timezone"]!,
          "day_closed": false,
          "items": [
            [
              "id": itemID, "food_name": "Leite", "quantity_g": 200, "quantity_display": NSNull(),
              "kcal": 120, "protein_g": 6, "carbs_g": 10, "fat_g": 6, "source": "product_label",
              "consumed_at": receipt["consumed_at"]!, "meal_type": receipt["meal_type"]!,
            ]
          ],
        ],
      "last_operation": staleGroup ? NSNull() : effect,
      "registration_undo_expires_at": "2026-11-04T12:05:03.000001Z",
      "actions": [
        "save": removed
          ? ["allowed": false, "reason": "current_group_unavailable"] : ["allowed": true],
        "undo_registration": [
          "allowed": false, "reason": removed ? "current_group_unavailable" : "version_changed",
        ],
        "undo_save": removed
          ? ["allowed": false, "reason": "current_group_unavailable"] : ["allowed": true],
      ],
    ]
    _ = try ConversationMealGroupSnapshot(data: JSONSerialization.data(withJSONObject: group))
    let groupBody = try linkedEditorEnvelope(group)
    let pageBody = try linkedEditorEnvelope(page)
    let disk = try OutboxDiskFixture()
    let life = ConversationHTTPTestLifecycle()
    await life.replace(
      .init(
        userID: parsed.authUserID.uuidString.lowercased(), generation: 7,
        bearer: "synthetic-linked-flow-unit"))
    let http = try ConversationHTTPFixture(lifecycle: life)
    let owner = try ConversationOutboxOwner(lease: await life.leaseForRequest())
    let keys = OutboxKeychainFake()
    await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    let editKeys = OutboxKeychainFake()
    await editKeys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
    let session = try linkedEditorEnvelope([
      "schema": "conversation.session.v1", "auth_user_id": page["auth_user_id"]!,
      "owner_id": page["owner_id"]!, "epoch": page["epoch"]!,
      "observed_at": "2026-11-04T12:00:00.000000Z",
      "meal_command_protocol": "conversation.command.v1",
    ])
    await http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true {
        return .init(status: 200, body: session)
      }
      if request.url?.path.hasSuffix("/journal") == true {
        return .init(status: 200, body: pageBody)
      }
      return .init(status: 200, body: groupBody)
    }
    return .init(
      disk: disk, http: http, owner: owner, vault: .init(service: "synthetic", security: keys),
      editing: .init(
        store: .init(directory: disk.directory.appendingPathComponent("edits")),
        keyVault: .init(
          service: ConversationMealEditOutboxSession.keychainService, security: editKeys)),
      rawPage: pageBytes, childID: childID, editEventID: try #require(parsed.items.first?.eventID),
      identity: identity, groupBody: groupBody,
      reportEvent: try JSONSerialization.data(withJSONObject: #require(events.last)))
  }
  func open() async throws -> FlowConversationModel {
    try await .open(
      transport: http.transport, lifecycle: http.lifecycle, store: disk.store,
      keyVault: vault, editing: editing, historyVersion: .v2)
  }
  func savedReply(_ request: URLRequest) throws -> ConversationHTTPReply {
    let last = try #require(request.url?.lastPathComponent)
    let operation = try ConversationMealEditOperation(
      ownerID: identity.ownerID, commandID: identity.commandID,
      originalInputHash: identity.inputHash, epoch: identity.epoch,
      operationID: #require(UUID(uuidString: last)), wireBody: #require(request.httpBody))
    let bodies = try historyAndGroup(operation: operation)
    let page = try #require(JSONSerialization.jsonObject(with: bodies.page) as? [String: Any])
    let data = try #require(page["data"] as? [String: Any])
    let items = try #require(data["items"] as? [[String: Any]])
    let receipt = try #require(items.first?["receipt"])
    return .init(
      status: 200,
      body: try linkedEditorEnvelope([
        "schema": "conversation.meal-edit-result.v1", "status": "saved",
        "owner_id": identity.ownerID.uuidString.lowercased(),
        "command_id": identity.commandID.uuidString.lowercased(), "input_hash": identity.inputHash,
        "epoch": identity.epoch.uuidString.lowercased(), "receipt": receipt,
      ]))
  }
  func historyAndGroup(operation: ConversationMealEditOperation) throws -> (page: Data, group: Data)
  {
    var page = try #require(JSONSerialization.jsonObject(with: rawPage) as? [String: Any])
    var events = try #require(page["items"] as? [[String: Any]])
    var effect = try #require(events[0]["receipt"] as? [String: Any])
    effect["operation_id"] = operation.operationID.uuidString.lowercased()
    effect["input_hash"] = operation.operationInputHash
    events[0]["receipt"] = effect
    events[0]["event_id"] =
      "edit/\(operation.commandID.uuidString.lowercased())/\(operation.operationID.uuidString.lowercased())"
    page["items"] = events
    var envelope = try #require(JSONSerialization.jsonObject(with: groupBody) as? [String: Any])
    var group = try #require(envelope["data"] as? [String: Any])
    group["revision"] = 1
    group["last_operation"] = effect
    var current = try #require(group["current"] as? [String: Any])
    var items = try #require(current["items"] as? [[String: Any]])
    let ids = try #require(effect["new_item_ids"] as? [String])
    guard let firstID = ids.first else { throw URLError(.badServerResponse) }
    items[0]["id"] = firstID
    current["items"] = items
    group["current"] = current
    envelope["data"] = group
    return (try linkedEditorEnvelope(page), try JSONSerialization.data(withJSONObject: envelope))
  }
  func pageBody(changedHash: Bool) throws -> Data {
    var raw = try #require(JSONSerialization.jsonObject(with: rawPage) as? [String: Any])
    var events = try #require(raw["items"] as? [[String: Any]])
    var binding = try #require(events[0]["effect_binding"] as? [String: Any])
    if changedHash { binding["input_hash"] = String(repeating: "a", count: 64) }
    events[0]["effect_binding"] = binding
    raw["items"] = events
    _ = try ConversationThreadPageSnapshot(data: JSONSerialization.data(withJSONObject: raw))
    return try linkedEditorEnvelope(raw)
  }
}

@MainActor private final class LinkedHistoricalNoticeProbe {
  var notices: [ConversationMealEditHistoricalNotice] = []
  var saved: [ConversationMealEditResultSnapshot] = []
}
