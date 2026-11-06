import Foundation
import Testing

@testable import BodyFlow

@MainActor @Suite("Genuine neutral meal ACK uses existing group and editor ports", .serialized)
struct FlowNeutralMealEditingBridgeTests {
  @Test func genuineNeutralReceiptLoadsActualGroupWithoutCreatingAnOriginalMealCommand()
    async throws
  {
    let f = try await neutralVisibleFixture()
    defer { f.disk.remove() }
    let editStore = EncryptedConversationMealEditOutboxStore(directory: f.disk.directory)
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault,
      editing: .init(
        store: editStore,
        keyVault: .init(
          service: ConversationMealEditOutboxSession.keychainService, security: OutboxKeychainFake()
        )),
      historyVersion: .v3, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "leite integral 206 g"
    neutral.mealTypeHint = .cafe
    await neutral.submit()
    let row = try #require(neutral.savedRows.first)
    guard case .meal(let saved) = row.acknowledgement else {
      Issue.record("Actual typed meal ACK required")
      return
    }
    let groupBody = try neutralBridgeGroup(saved: saved)
    let base = f.server
    await f.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/meal") == true { return .init(status: 200, body: groupBody) }
      return try await base.reply(request)
    }
    await model.loadCurrentGroup(commandID: row.childID)
    let group = try #require(model.currentGroup(commandID: row.childID))
    #expect(group.originalReceipt.report == saved.receipt)
    #expect(group.originalInputHash == saved.inputHash && group.commandID == row.childID)
    #expect(model.mealEditActions(commandID: row.childID) != nil)
    #expect(model.savedRows.isEmpty && model.pendingRows.isEmpty && model.savedEffectRevision == 1)
    let reads = await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/meal") == true }
    #expect(reads.count == 1 && reads[0].httpMethod == "GET")
    #expect(reads[0].value(forHTTPHeaderField: "X-Conversation-Input-Hash") == saved.inputHash)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await model.close()
  }
}

/// Controlled UNIT group projection around the unchanged real public neutral
/// meal ACK fixture and existing public group fixture. No new SQL/provider or
/// connected qualification is claimed; opaque server CAS is not reconstructed.
func neutralBridgeGroup(saved: SavedConversationMealCommandResultSnapshot) throws -> Data {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "Fixtures/ConversationMealEditPublicFixtures.json")
  let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  var envelope = fixture["milk"] as! [String: Any]
  var group = envelope["data"] as! [String: Any]
  let raw = try neutralMealUnit()["response"] as! [String: Any]
  let result = raw["result"] as! [String: Any]
  let receipt = result["receipt"] as! [String: Any]
  let packet = try JSONDecoder().decode(
    SavedConversationMealCommandResultSnapshot.self,
    from: JSONSerialization.data(withJSONObject: result))
  #expect(packet.receipt == saved.receipt)
  group["owner_id"] = saved.ownerID
  group["command_id"] = saved.commandID
  group["input_hash"] = saved.inputHash
  group["epoch"] = saved.epoch
  group["admitted_at"] = saved.admittedAt
  group["observed_at"] = "2026-11-03T12:00:04.000001Z"
  group["original_receipt"] = receipt
  group["registration_undo_expires_at"] = "2026-11-03T11:05:00.000000Z"
  var current = group["current"] as! [String: Any]
  var item = (current["items"] as! [[String: Any]])[0]
  let originalURL = url.deletingLastPathComponent().appendingPathComponent(
    "ConversationMealCommandResultFixtures.json")
  let original =
    try JSONSerialization.jsonObject(with: Data(contentsOf: originalURL)) as! [String: Any]
  let sameChild = ((original["cases"] as! [[String: Any]])[0]["payload"] as! [String: Any])
  let sameChildSnapshot = try JSONDecoder().decode(
    SavedConversationMealCommandResultSnapshot.self,
    from: JSONSerialization.data(withJSONObject: sameChild))
  #expect(sameChildSnapshot.receipt == saved.receipt)
  let feedback = sameChild["feedback"] as! [String: Any]
  let meal = feedback["recorded"] as! [String: Any]
  let food = (meal["items"] as! [[String: Any]])[0]
  current["local_date"] = saved.receipt.localDate
  current["timezone"] = saved.receipt.timezone
  item["id"] = saved.receipt.logIDs[0]
  item["consumed_at"] = saved.receipt.consumedAt
  item["meal_type"] = saved.receipt.mealType.rawValue
  for key in ["food_name", "quantity_g", "kcal", "protein_g", "carbs_g", "fat_g"] {
    item[key] = food[key]
  }
  item["source"] = food["nutrition_source"]
  current["items"] = [item]
  group["current"] = current
  group["actions"] = [
    "save": ["allowed": true], "undo_registration": ["allowed": false, "reason": "undo_expired"],
    "undo_save": ["allowed": false, "reason": "no_save_to_undo"],
  ]
  envelope["data"] = group
  return try JSONSerialization.data(withJSONObject: envelope)
}

/// An explicit UNIT server around public wire fixtures. It records the actual
/// outgoing native operation and returns bound public ACK/current-group data.
/// It does not represent a new SQL, SDK, provider or connected E2E fixture.
actor NeutralMealBridgeUnitServer {
  private let base: NeutralVisibleUnitServer
  private let originalSaved: Data
  private let originalFeedback: Data
  private var neutralResult: Data?
  private var currentGroup: Data
  private var originalGroup: Data
  private var applied: [UUID: (body: Data, reply: Data)] = [:]
  private var lastEffect: Data?
  private var loseNextEditResponse = false
  private var staleNextGroup = false
  private var preEditPage: ConversationHTTPReply?
  private var staleNextHistory = false
  init(base: NeutralVisibleUnitServer) throws {
    self.base = base
    let result = try neutralMealUnit()["response"] as! [String: Any]
    originalSaved = try JSONSerialization.data(withJSONObject: result["result"]!)
    let saved = try JSONDecoder().decode(
      SavedConversationMealCommandResultSnapshot.self, from: originalSaved)
    currentGroup = try neutralBridgeGroup(saved: saved)
    originalGroup = currentGroup
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
      "Fixtures/ConversationMealCommandResultFixtures.json")
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
    let payload = (root["cases"] as! [[String: Any]])[0]["payload"] as! [String: Any]
    originalFeedback = try JSONSerialization.data(withJSONObject: payload["feedback"]!)
  }
  func loseFirstEditResponse() { loseNextEditResponse = true }
  func returnStaleGroupOnce() { staleNextGroup = true }
  func returnPreEditHistoryOnce() { staleNextHistory = true }
  func reply(_ request: URLRequest) async throws -> ConversationHTTPReply {
    let path = request.url!.path
    if path.hasSuffix("/meal") {
      let stale = staleNextGroup
      staleNextGroup = false
      return .init(status: 200, body: stale ? originalGroup : currentGroup)
    }
    if path.contains("/edits/") {
      let response = try save(request)
      if loseNextEditResponse && !path.hasSuffix("/reconcile") {
        loseNextEditResponse = false
        throw URLError(.networkConnectionLost)
      }
      return .init(status: 200, body: response)
    }
    if path == "/api/mobile/v1/conversation/journal" {
      return try publicPage(request)
    }
    var response = try await base.reply(request)
    if path == "/api/mobile/v1/conversation/intakes", request.httpMethod == "POST" {
      var envelope = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
      var packet = envelope["data"] as! [String: Any]
      var result = packet["result"] as! [String: Any]
      result["feedback"] = try feedback(at: "2026-11-03T12:00:00.000001Z")
      packet["result"] = result
      envelope["data"] = packet
      response = .init(
        status: response.status, body: try JSONSerialization.data(withJSONObject: envelope),
        headers: response.headers)
      neutralResult = try JSONSerialization.data(withJSONObject: packet)
    }
    if request.value(forHTTPHeaderField: "X-Conversation-Feedback-Presentation") == "2" {
      response.headers["X-Conversation-Feedback-Presentation"] = "2"
    }
    return response
  }
  private func feedback(at clock: String) throws -> [String: Any] {
    var result = try JSONSerialization.jsonObject(with: originalFeedback) as! [String: Any]
    var policy = result["current_policy"] as! [String: Any]
    var provenance = result["provenance"] as! [String: Any]
    policy["observed_at"] = clock
    provenance["observed_at"] = clock
    result["current_policy"] = policy
    result["provenance"] = provenance
    return result
  }
  private func publicPage(_ request: URLRequest) throws -> ConversationHTTPReply {
    if staleNextHistory, let preEditPage {
      staleNextHistory = false
      return preEditPage
    }
    let packet = try JSONSerialization.jsonObject(with: #require(neutralResult)) as! [String: Any]
    let binding = packet["intake"] as! [String: Any]
    let child = packet["result"] as! [String: Any]
    let receipt = child["receipt"] as! [String: Any]
    let intakeID = binding["intake_id"]!
    let commandID = child["command_id"]!
    let epoch = child["epoch"]!
    let clock = lastEffect == nil ? "2026-11-03T12:00:04.000002Z" : "2026-11-03T12:00:07.000002Z"
    let record: [String: Any] = [
      "kind": "meal", "registration_id": receipt["registration_id"]!,
      "meal_type": receipt["meal_type"]!, "local_date": receipt["local_date"]!,
      "log_ids": receipt["log_ids"]!, "effect_version": receipt["effect_version"]!,
    ]
    var entries: [[String: Any]] = [
      [
        "event_id": "intake/" + (intakeID as! String), "at": "2026-11-03T10:00:00.000000Z",
        "thread_id": intakeID, "kind": "intake",
        "lineage": [
          "kind": "intake", "intake_id": intakeID, "command_id": commandID,
          "parent_command_id": NSNull(), "origin_epoch": epoch,
        ], "input": ["channel": "text", "text": "leite integral 206 g"],
        "outcome": ["status": "registered", "record": record, "feedback": try feedback(at: clock)],
      ]
    ]
    if let lastEffect {
      let effect = try JSONSerialization.jsonObject(with: lastEffect) as! [String: Any]
      let editRecord: [String: Any] = [
        "kind": "meal_edit", "operation_id": effect["operation_id"]!, "change": effect["kind"]!,
        "revision": effect["revision"]!, "applied_at": effect["applied_at"]!,
        "target_operation_id": effect["target_operation_id"]!,
        "removed_item_ids": effect["removed_item_ids"]!, "new_item_ids": effect["new_item_ids"]!,
        "next_record_id": effect["next_record_id"]!,
      ]
      entries.insert(
        [
          "event_id": "edit/\(commandID)/\(effect["operation_id"]!)", "at": effect["applied_at"]!,
          "thread_id": intakeID, "kind": "edit",
          "lineage": [
            "kind": "meal.edit", "intake_id": intakeID, "command_id": commandID,
            "parent_command_id": NSNull(), "origin_epoch": epoch,
          ], "input": NSNull(),
          "outcome": ["status": "registered", "record": editRecord, "feedback": NSNull()],
        ], at: 0)
    }
    let page: [String: Any] = [
      "schema": "conversation.journal-page.v3", "mode": "historical",
      "auth_user_id": request.value(forHTTPHeaderField: "X-Unit-Auth")
        ?? "90000000-0000-4000-8000-000000000001", "owner_id": child["owner_id"]!, "epoch": epoch,
      "observed_at": clock, "items": entries, "has_more": false, "next_cursor": NSNull(),
    ]
    let reply = try neutralHTTP(page)
    if lastEffect == nil { preEditPage = reply }
    return reply
  }
  private func save(_ request: URLRequest) throws -> Data {
    let saved = try JSONDecoder().decode(
      SavedConversationMealCommandResultSnapshot.self, from: originalSaved)
    let pieces = request.url!.path.split(separator: "/")
    let offset = pieces.last == "reconcile" ? 2 : 1
    let operationID = try #require(UUID(uuidString: String(pieces[pieces.count - offset])))
    let body = try #require(request.httpBody)
    if let old = applied[operationID] {
      #expect(old.body == body)
      return old.reply
    }
    let operation = try ConversationMealEditOperation(
      ownerID: UUID(uuidString: saved.ownerID)!, commandID: UUID(uuidString: saved.commandID)!,
      originalInputHash: saved.inputHash, epoch: UUID(uuidString: saved.epoch)!,
      operationID: operationID, wireBody: body)
    guard case .save(let recordID, let items) = operation.action, let item = items.first else {
      throw URLError(.badServerResponse)
    }
    var groupEnvelope = try JSONSerialization.jsonObject(with: currentGroup) as! [String: Any]
    var group = groupEnvelope["data"] as! [String: Any]
    var current = group["current"] as! [String: Any]
    var currentItem = (current["items"] as! [[String: Any]])[0]
    #expect(
      operation.expectedRevision == group["revision"] as? Int
        && operation.expectedVersion == current["expected_version"] as? String)
    #expect(recordID.uuidString.lowercased() == currentItem["id"] as? String)
    let nextID = UUID().uuidString.lowercased()
    let effect: [String: Any] = [
      "schema": "conversation.meal-edit-effect-public.v1", "owner_id": saved.ownerID,
      "command_id": saved.commandID, "operation_id": operationID.uuidString.lowercased(),
      "input_hash": operation.operationInputHash, "kind": "saved",
      "revision": operation.expectedRevision + 1, "applied_at": "2026-11-03T12:00:05.000001Z",
      "undo_expires_at": "2026-11-03T12:05:05.000001Z", "target_operation_id": NSNull(),
      "removed_item_ids": [recordID.uuidString.lowercased()], "new_item_ids": [nextID],
      "next_record_id": nextID,
    ]
    let response = try neutralHTTP([
      "schema": "conversation.meal-edit-result.v1", "status": "saved", "owner_id": saved.ownerID,
      "command_id": saved.commandID, "input_hash": saved.inputHash, "epoch": saved.epoch,
      "receipt": effect,
    ]).body
    applied[operationID] = (body, response)
    lastEffect = try JSONSerialization.data(withJSONObject: effect)
    // Explicit server-side UNIT values. The application receives these facts;
    // it does not calculate food nutrients or an opaque CAS locally.
    let ratio =
      NSDecimalNumber(decimal: item.quantityG).doubleValue / (currentItem["quantity_g"] as! Double)
    for key in ["kcal", "protein_g", "carbs_g", "fat_g"] {
      currentItem[key] = (currentItem[key] as! Double) * ratio
    }
    currentItem["id"] = nextID
    currentItem["food_name"] = item.foodName
    currentItem["quantity_g"] = NSDecimalNumber(decimal: item.quantityG)
    current["items"] = [currentItem]
    let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/ConversationMealEditPublicFixtures.json")
    let fixture =
      try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
    current["expected_version"] =
      (((fixture["whey"] as! [String: Any])["data"] as! [String: Any])["current"] as! [String: Any])[
        "expected_version"]
    group["current"] = current
    group["revision"] = operation.expectedRevision + 1
    group["last_operation"] = effect
    group["observed_at"] = "2026-11-03T12:00:06.000001Z"
    group["actions"] = [
      "save": ["allowed": true],
      "undo_registration": ["allowed": false, "reason": "no_save_to_undo"],
      "undo_save": ["allowed": true],
    ]
    groupEnvelope["data"] = group
    currentGroup = try JSONSerialization.data(withJSONObject: groupEnvelope)
    return response
  }
}

@MainActor extension FlowNeutralMealEditingBridgeTests {
  @Test func realNeutralMealCanSaveWithExistingCASAndReopenTheChangedQuantity() async throws {
    let f = try await neutralVisibleFixture()
    defer { f.disk.remove() }
    let server = try NeutralMealBridgeUnitServer(base: f.server)
    await f.http.stub.respond { request, _ in try await server.reply(request) }
    let editStore = EncryptedConversationMealEditOutboxStore(directory: f.disk.directory)
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault,
      editing: .init(
        store: editStore,
        keyVault: .init(
          service: ConversationMealEditOutboxSession.keychainService, security: OutboxKeychainFake()
        )), historyVersion: .v3, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = "leite integral 206 g"
    neutral.mealTypeHint = .cafe
    await neutral.submit()
    let row = try #require(neutral.savedRows.first)
    let bound = try #require(row.feedback)
    guard case .sections(_, let sections) = bound.presentation.content else {
      Issue.record("Actual six sections required")
      return
    }
    #expect(sections.map(\.key) == [.saved, .items, .summary, .day, .block, .education])
    await model.loadCurrentGroup(commandID: row.childID)
    let original = try #require(model.currentGroup(commandID: row.childID))
    let item = try #require(original.current?.items.first)
    await model.beginMealEdit(commandID: row.childID, itemID: item.id)
    let editor = try #require(model.mealEditor)
    #expect(editor.presentation != nil && editor.quantityText(language: .portugueseBrazil) == "200")
    editor.setQuantityText("250", language: .portugueseBrazil)
    #expect(editor.canSave(language: .portugueseBrazil))
    await editor.save(language: .portugueseBrazil)
    #expect(editor.lastSaved != nil && model.savedEffectRevision == 2)
    #expect(model.currentGroup(commandID: row.childID) == nil)
    await model.loadCurrentGroup(commandID: row.childID)
    let updated = try #require(model.currentGroup(commandID: row.childID))
    let updatedItem = try #require(updated.current?.items.first)
    #expect(updated.revision == 1 && updatedItem.quantityG == 257.5)
    #expect(updated.originalReceipt.report == original.originalReceipt.report)
    editor.dismiss()
    await model.beginMealEdit(commandID: row.childID, itemID: updatedItem.id)
    #expect(editor.quantityText(language: .portugueseBrazil) == "250")
    #expect(
      model.savedEffectRevision == 2 && neutral.savedRows.count == 1 && model.savedRows.isEmpty)
    let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(
      posts.count == 2 && posts.filter { $0.url?.path.contains("/edits/") == true }.count == 1)
    #expect(posts.allSatisfy { $0.url?.path != "/api/mobile/v1/conversation/meal-commands" })
    await model.close()
  }
}

@MainActor struct NeutralMealBridgeOpened {
  let fixture: NeutralVisibleFixture
  let server: NeutralMealBridgeUnitServer
  let model: FlowConversationModel
  let row: FlowNeutralIntakeSavedRow
  let editStore: EncryptedConversationMealEditOutboxStore
  let editVault: ConversationOutboxKeyVault
}
@MainActor func openNeutralMealBridge() async throws -> NeutralMealBridgeOpened {
  let f = try await neutralVisibleFixture()
  let server = try NeutralMealBridgeUnitServer(base: f.server)
  await f.http.stub.respond { request, _ in try await server.reply(request) }
  let editStore = EncryptedConversationMealEditOutboxStore(directory: f.disk.directory)
  let editVault = ConversationOutboxKeyVault(
    service: ConversationMealEditOutboxSession.keychainService, security: OutboxKeychainFake())
  let model = try await FlowConversationModel.open(
    transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
    keyVault: f.vault, editing: .init(store: editStore, keyVault: editVault), historyVersion: .v3,
    neutralIntakeEnabled: true)
  let neutral = try #require(model.neutralIntake)
  neutral.composer = "leite integral 206 g"
  neutral.mealTypeHint = .cafe
  await neutral.submit()
  return .init(
    fixture: f, server: server, model: model, row: try #require(neutral.savedRows.first),
    editStore: editStore, editVault: editVault)
}
@MainActor extension FlowNeutralMealEditingBridgeTests {
  @Test func actualEditInvalidatesPreEditClinicalCommentaryWithoutRemovingRealACKOrHistory()
    async throws
  {
    let f = try await openNeutralMealBridge()
    defer { f.fixture.disk.remove() }
    await f.model.loadHistory()
    let entry = try #require(f.model.unifiedRows.first)
    #expect(f.model.unifiedHistory.feedback(for: entry) != nil)
    #expect(f.model.neutralIntake?.savedRows.first?.feedback != nil)
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    let item = try #require(f.model.currentGroup(commandID: f.row.childID)?.current?.items.first)
    await f.model.beginMealEdit(commandID: f.row.childID, itemID: item.id)
    let editor = try #require(f.model.mealEditor)
    editor.setQuantityText("250", language: .portugueseBrazil)
    await editor.save(language: .portugueseBrazil)
    #expect(f.model.neutralIntake?.savedRows.first?.feedback == nil)
    #expect(f.model.unifiedHistory.feedback(for: entry) == nil)
    let retained = try #require(f.model.neutralIntake?.savedRows.first)
    guard case .meal(let originalACK) = f.row.acknowledgement,
      case .meal(let retainedACK) = retained.acknowledgement
    else {
      Issue.record("Actual meal ACK retained")
      return
    }
    #expect(f.model.unifiedRows.count == 1 && retainedACK.receipt == originalACK.receipt)
    #expect(
      retainedACK.commandID == originalACK.commandID
        && retainedACK.inputHash == originalACK.inputHash
        && retainedACK.epoch == originalACK.epoch && retainedACK.ownerID == originalACK.ownerID)
    #expect(f.model.savedEffectRevision == 2 && editor.lastSaved != nil)
    await f.server.returnPreEditHistoryOnce()
    await f.model.loadHistory()
    #expect(f.model.unifiedHistory.feedback(for: entry) == nil && f.model.unifiedHistoryUnavailable)
    #expect(f.model.unifiedRows.count == 1 && f.model.savedEffectRevision == 2)
    await f.model.loadHistory()
    let fresh = try #require(f.model.unifiedRows.first { $0.kind == .intake })
    #expect(f.model.unifiedHistory.feedback(for: fresh) != nil)
    #expect(f.model.neutralIntake?.savedRows.first?.feedback == nil)
    await f.model.close()
  }
  @Test func lateOwnedGroupCannotPublishAfterAuthGenerationChanges() async throws {
    let f = try await openNeutralMealBridge()
    defer { f.fixture.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.fixture.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/meal") == true { await barrier.enter() }
      return try await f.server.reply(request)
    }
    let read = Task {
      await f.model.loadCurrentGroup(commandID: f.row.childID)
      await barrier.finish()
    }
    #expect(await barrier.waitEnteredOrFinished())
    await f.fixture.http.lifecycle.replace(
      .init(
        userID: "90000000-0000-4000-8000-000000000001", generation: 8,
        bearer: "unit-next-generation"))
    await barrier.release()
    await read.value
    #expect(
      f.model.currentGroup(commandID: f.row.childID) == nil
        && f.model.mealEditActions(commandID: f.row.childID) == nil)
    #expect(!f.model.canRequestMealDetails(commandID: f.row.childID))
    #expect(await f.fixture.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await f.model.close()
  }
  @Test func v3DeduplicationRetainsOnlyGenuineRAMControlsAndColdReopenStaysReadOnly() async throws {
    let f = try await openNeutralMealBridge()
    defer { f.fixture.disk.remove() }
    await f.model.loadHistory()
    let event = try #require(f.model.unifiedRows.first)
    #expect(f.model.unifiedSavedIntakeIDs.contains(f.row.id))
    #expect(f.model.unifiedMealControlsCommandID(eventID: event.eventID) == f.row.childID)
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    #expect(f.model.mealEditActions(commandID: f.row.childID) != nil)
    #expect(f.model.savedEffectRevision == 1)
    await f.model.close()
    let reopened = try await FlowConversationModel.open(
      transport: f.fixture.http.transport, lifecycle: f.fixture.http.lifecycle,
      store: f.fixture.disk.store, keyVault: f.fixture.vault,
      editing: .init(store: f.editStore, keyVault: f.editVault),
      historyVersion: .v3, neutralIntakeEnabled: true)
    await reopened.loadHistory()
    #expect(reopened.unifiedRows.count == 1 && reopened.neutralIntake?.savedRows.isEmpty == true)
    #expect(reopened.unifiedMealControlsCommandID(eventID: event.eventID) == nil)
    #expect(!reopened.canRequestMealDetails(commandID: f.row.childID))
    #expect(
      reopened.mealEditActions(commandID: f.row.childID) == nil && reopened.savedEffectRevision == 0
    )
    #expect(await f.fixture.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await reopened.close()
  }
  @Test(arguments: ["owner_id", "epoch", "input_hash", "admitted_at", "registration_id", "log_ids"])
  func neutralACKNeverBindsASubstitutedCurrentGroup(_ attack: String) async throws {
    let f = try await openNeutralMealBridge()
    defer { f.fixture.disk.remove() }
    guard case .meal(let saved) = f.row.acknowledgement else { return }
    var envelope =
      try JSONSerialization.jsonObject(with: neutralBridgeGroup(saved: saved)) as! [String: Any]
    var group = envelope["data"] as! [String: Any]
    if ["registration_id", "log_ids"].contains(attack) {
      var receipt = group["original_receipt"] as! [String: Any]
      receipt[attack] =
        attack == "log_ids" ? [UUID().uuidString.lowercased()] : UUID().uuidString.lowercased()
      group["original_receipt"] = receipt
    } else if attack == "admitted_at" {
      group[attack] = "2026-11-03T10:00:00.000001Z"
    } else {
      group[attack] =
        attack == "input_hash" ? String(repeating: "a", count: 64) : UUID().uuidString.lowercased()
    }
    envelope["data"] = group
    let body = try JSONSerialization.data(withJSONObject: envelope)
    await f.fixture.http.stub.respond { _, _ in .init(status: 200, body: body) }
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    #expect(f.model.currentGroup(commandID: f.row.childID) == nil)
    #expect(
      f.model.mealEditActions(commandID: f.row.childID) == nil
        && f.model.groupUnavailable(commandID: f.row.childID))
    #expect(f.model.savedEffectRevision == 1 && f.model.neutralIntake?.savedRows.count == 1)
    await f.model.close()
  }
  @Test func lostEditACKKeepsOriginalOperationWhileV3HistoryAndGroupCannotSettleIt() async throws {
    let f = try await openNeutralMealBridge()
    defer { f.fixture.disk.remove() }
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    let item = try #require(f.model.currentGroup(commandID: f.row.childID)?.current?.items.first)
    await f.model.beginMealEdit(commandID: f.row.childID, itemID: item.id)
    let editor = try #require(f.model.mealEditor)
    editor.setQuantityText("250", language: .portugueseBrazil)
    await f.server.loseFirstEditResponse()
    await editor.save(language: .portugueseBrazil)
    let original = try #require(editor.pendingOperation)
    #expect(editor.lastSaved == nil && editor.isLocked && f.model.savedEffectRevision == 1)
    let owner = try ConversationOutboxOwner(lease: await f.fixture.http.lifecycle.leaseForRequest())
    let before = try Data(contentsOf: f.editStore.fileURL(owner: owner))
    await f.model.loadHistory()
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    #expect(f.model.unifiedRows.count == 2 && !f.model.unifiedHistoryUnavailable)
    #expect(try Data(contentsOf: f.editStore.fileURL(owner: owner)) == before)
    #expect(
      editor.pendingOperation?.wireBody == original.wireBody && editor.lastSaved == nil
        && f.model.savedEffectRevision == 1)
    await editor.reconcile()
    #expect(
      editor.lastSaved?.receipt.operationID == original.operationID
        && editor.pendingOperation == nil)
    #expect(f.model.savedEffectRevision == 2)
    let key = try await f.editVault.key(owner: owner, mayCreate: false)
    #expect(try f.editStore.load(owner: owner, key: key).isEmpty)
    let requests = await f.fixture.http.stub.requests.filter {
      $0.url?.path.contains("/edits/") == true
    }
    #expect(requests.count == 2 && requests[0].httpBody == requests[1].httpBody)
    #expect(
      requests[0].value(forHTTPHeaderField: "Idempotency-Key")
        == requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
    #expect(requests[1].url?.path.hasSuffix("/reconcile") == true)
    await f.model.close()
  }
  @Test func laterStaleGroupCannotUndoActualEditACKOrItsKnownRevision() async throws {
    let f = try await openNeutralMealBridge()
    defer { f.fixture.disk.remove() }
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    let item = try #require(f.model.currentGroup(commandID: f.row.childID)?.current?.items.first)
    await f.model.beginMealEdit(commandID: f.row.childID, itemID: item.id)
    let editor = try #require(f.model.mealEditor)
    editor.setQuantityText("250", language: .portugueseBrazil)
    await editor.save(language: .portugueseBrazil)
    #expect(
      f.model.knownEditRevision(commandID: f.row.childID) == 1 && f.model.savedEffectRevision == 2)
    await f.server.returnStaleGroupOnce()
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    #expect(
      f.model.currentGroup(commandID: f.row.childID) == nil
        && f.model.groupUnavailable(commandID: f.row.childID))
    #expect(editor.lastSaved != nil && f.model.savedEffectRevision == 2)
    await f.model.loadCurrentGroup(commandID: f.row.childID)
    #expect(f.model.currentGroup(commandID: f.row.childID)?.revision == 1)
    await f.model.close()
  }
}

#if canImport(UIKit)
  import SwiftUI
  import UIKit
  @MainActor extension FlowNeutralMealEditingBridgeTests {
    @Test(arguments: [false, true], [false, true])
    func actualUpdatedCurrentQuantityIsVisibleWithoutRestoringMaskedMacrosOrOldCommentary(
      _ english: Bool, _ deduplicated: Bool
    ) async throws {
      let f = try await openNeutralMealBridge()
      defer { f.fixture.disk.remove() }
      await f.model.loadCurrentGroup(commandID: f.row.childID)
      let item = try #require(f.model.currentGroup(commandID: f.row.childID)?.current?.items.first)
      await f.model.beginMealEdit(commandID: f.row.childID, itemID: item.id)
      let editor = try #require(f.model.mealEditor)
      editor.setQuantityText("250", language: .portugueseBrazil)
      await editor.save(language: .portugueseBrazil)
      await f.model.loadCurrentGroup(commandID: f.row.childID)
      let content: AnyView
      if deduplicated {
        await f.model.loadHistory()
        let event = try #require(f.model.unifiedRows.first { $0.kind == .intake })
        #expect(f.model.unifiedSavedIntakeIDs.contains(f.row.id))
        #expect(f.model.unifiedMealControlsCommandID(eventID: event.eventID) == f.row.childID)
        content = AnyView(
          FlowConversationMealControlsContent(model: f.model, commandID: f.row.childID))
      } else {
        content = AnyView(
          FlowNeutralIntakeTranscriptContent(
            model: try #require(f.model.neutralIntake), conversation: f.model))
      }
      let host = SignUpRenderingProbe.host(
        content.environment(\.locale, Locale(identifier: english ? "en_US" : "pt_BR")), width: 390,
        height: 2400)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(
        nodes.contains {
          $0.label.contains("250 mL") && $0.label.contains(english ? "257.5" : "257,5")
        })
      #expect(
        nodes.contains {
          $0.label
            == (english
              ? "Updated after the original registration" : "Atualizada após o registro original")
        })
      #expect(
        !nodes.contains {
          $0.identifier.hasPrefix("conversation.feedback.section.") || $0.label.contains("kcal")
            || $0.label.contains("P ")
        })
      await f.model.close()
    }
    @Test(arguments: [false, true])
    func unavailableCurrentReadOffersRetryAndPreservesTheGenuineRegistration(_ english: Bool)
      async throws
    {
      let f = try await openNeutralMealBridge()
      defer { f.fixture.disk.remove() }
      await f.fixture.http.stub.respond { request, _ in
        if request.url?.path.hasSuffix("/meal") == true { return .failure(503, "INTERNAL_ERROR") }
        return try await f.server.reply(request)
      }
      await f.model.loadCurrentGroup(commandID: f.row.childID)
      #expect(
        f.model.groupUnavailable(commandID: f.row.childID)
          && !f.model.isLoadingMealDetails(commandID: f.row.childID))
      let host = SignUpRenderingProbe.host(
        FlowConversationMealControlsContent(model: f.model, commandID: f.row.childID)
          .environment(\.locale, Locale(identifier: english ? "en_US" : "pt_BR")), width: 390,
        height: 1000)
      defer { host.detach() }
      let nodes = host.nodes()
      #expect(nodes.contains { $0.label.contains(english ? "unavailable" : "indisponíveis") })
      #expect(
        nodes.contains {
          $0.isButton && $0.isEnabled && $0.label == (english ? "Try again" : "Tentar novamente")
        })
      #expect(f.model.savedEffectRevision == 1 && f.model.neutralIntake?.savedRows.count == 1)
      #expect(!nodes.contains { $0.identifier.hasPrefix("conversation.meal.edit.") })
      await f.fixture.http.stub.respond { request, _ in try await f.server.reply(request) }
      await f.model.loadCurrentGroup(commandID: f.row.childID)
      #expect(
        host.nodes().contains { $0.identifier.hasPrefix("conversation.meal.edit.") && $0.isEnabled }
      )
      #expect(await f.fixture.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
      await f.model.close()
    }
    @Test(arguments: [false, true])
    func actualNeutralTranscriptShowsSixSectionsAndTheGenuineMealPencil(_ english: Bool)
      async throws
    {
      let f = try await openNeutralMealBridge()
      defer { f.fixture.disk.remove() }
      await f.model.loadCurrentGroup(commandID: f.row.childID)
      let item = try #require(f.model.currentGroup(commandID: f.row.childID)?.current?.items.first)
      let neutral = try #require(f.model.neutralIntake)
      let host = SignUpRenderingProbe.host(
        FlowNeutralIntakeTranscriptContent(model: neutral, conversation: f.model).environment(
          \.locale, Locale(identifier: english ? "en_US" : "pt_BR")), width: 390, height: 2400)
      defer { host.detach() }
      let nodes = host.nodes()
      for key in ["saved", "items", "summary", "day", "block", "education"] {
        #expect(nodes.contains { $0.identifier == "conversation.feedback.section." + key })
      }
      #expect(
        nodes.contains {
          $0.identifier == "conversation.meal.edit." + item.id.uuidString.lowercased()
            && $0.isEnabled && $0.frame.width > 0 && $0.frame.height > 0
        })
      await f.model.close()
    }
  }
#endif
