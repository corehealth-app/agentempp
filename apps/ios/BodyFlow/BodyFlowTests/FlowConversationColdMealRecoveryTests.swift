import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
#endif

@MainActor @Suite("Cold meal canonical origin recovery", .serialized)
struct FlowConversationColdMealRecoveryTests {
  #if canImport(UIKit)
    @Test(arguments: [false, true])
    func independentlyRecoveredMealRendersActualPerItemPencil(_ english: Bool) async throws {
      let f = try await ColdMealRecoveryFixture()
      defer { f.disk.remove() }
      let session = try await f.open()
      await session.model.loadHistory()
      await session.model.loadCurrentGroup(commandID: f.commandID)
      let group = try #require(session.model.currentGroup(commandID: f.commandID))
      let item = try #require(group.current?.items.first)
      let host = SignUpRenderingProbe.host(
        FlowConversationMealControlsContent(model: session.model, commandID: f.commandID)
          .environment(\.locale, Locale(identifier: english ? "en-US" : "pt-BR")),
        width: 390, height: 800)
      defer { host.detach() }
      let nodes = host.nodes()
      let pencil = try #require(
        nodes.first {
          $0.identifier == "conversation.meal.edit.\(item.id.uuidString.lowercased())"
        })
      #expect(
        pencil.isButton && pencil.isEnabled && pencil.frame.width > 0 && pencil.frame.height > 0)
      #expect(pencil.label == (english ? "Edit iogurte natural" : "Editar iogurte natural"))
      #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 0)
      await session.close()
    }
  #endif
  @Test func publicHistoryAloneOffersOnlyAReadAndNeverAnEditingAuthority() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    let session = try await f.open()
    await session.model.loadHistory()
    let entry = try #require(session.model.unifiedRows.first)
    #expect(session.model.unifiedMealControlsCommandID(eventID: entry.eventID) == nil)
    #expect(session.model.unifiedMealDetailsCommandID(eventID: entry.eventID) == f.commandID)
    #expect(session.model.canLoadMealDetails(commandID: f.commandID))
    #expect(!session.model.canRequestMealDetails(commandID: f.commandID))
    #expect(session.model.mealEditActions(commandID: f.commandID) == nil)
    #expect(session.model.savedRows.isEmpty)
    await session.close()
  }
  @Test func reopeningRecoversOwnedOriginalBeforeCurrentGroupWithoutAcknowledgingOrWriting()
    async throws
  {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    let session = try await f.open()
    let model = session.model
    await model.loadHistory()
    #expect(model.unifiedRows.count == 1)
    #expect(model.savedRows.isEmpty)
    #expect(model.mealEditActions(commandID: f.commandID) == nil)
    await model.loadCurrentGroup(commandID: f.commandID)
    #expect(model.currentGroup(commandID: f.commandID)?.commandID == f.commandID)
    #expect(model.mealEditActions(commandID: f.commandID) != nil)
    #expect(model.savedRows.isEmpty)
    #expect(model.savedEffectRevision == 0)
    let requests = await f.http.stub.requests
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    let canonical = requests.filter {
      $0.url?.path == "/api/mobile/v1/conversation/journal"
        && URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(
          where: { $0.name == "version" }) != true
    }
    #expect(canonical.count == 1)
    let groups = requests.filter { $0.url?.path.hasSuffix("/meal") == true }
    #expect(groups.count == 1)
    await session.close()
  }

  @Test(arguments: ["registration_id", "meal_type", "local_date", "log_ids", "effect_version"])
  func independentReceiptMustMatchOriginalPublicFacts(_ field: String) async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var page = f.publicPage
    var row = (page["items"] as! [[String: Any]])[0]
    var outcome = row["outcome"] as! [String: Any]
    var record = outcome["record"] as! [String: Any]
    switch field {
    case "registration_id": record[field] = UUID().uuidString.lowercased()
    case "meal_type": record[field] = "cafe"
    case "local_date": record[field] = "2026-11-03"
    case "log_ids": record[field] = [UUID().uuidString.lowercased()]
    default: record[field] = "cmeal1:" + String(repeating: "c", count: 64)
    }
    outcome["record"] = record
    row["outcome"] = outcome
    page["items"] = [row]
    await f.install(publicReply: try neutralHTTP(page))
    let session = try await f.open()
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 1)
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.groupUnavailable(commandID: f.commandID))
    #expect(session.model.savedEffectRevision == 0)
    #expect(
      await f.http.stub.requests.allSatisfy {
        $0.httpMethod == "GET" && $0.url?.path.hasSuffix("/meal") != true
      })
    await session.close()
  }

  @Test(arguments: ["missing", "owner", "epoch", "hash", "unavailable"])
  func unavailableOrInvalidIndependentSourceCannotEnableControls(_ attack: String) async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var canonical = f.canonical
    switch attack {
    case "missing": canonical["items"] = []
    case "owner": canonical["owner_id"] = UUID().uuidString.lowercased()
    case "epoch": canonical["epoch"] = UUID().uuidString.lowercased()
    case "hash":
      var rows = canonical["items"] as! [[String: Any]]
      var result = rows[0]["result"] as! [String: Any]
      result["input_hash"] = String(repeating: "a", count: 64)
      rows[0]["result"] = result
      canonical["items"] = rows
    default: break
    }
    await f.install(canonicalPages: [
      "": attack == "unavailable" ? .failure(503, "unavailable") : try neutralHTTP(canonical)
    ])
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.groupUnavailable(commandID: f.commandID))
    #expect(session.model.unifiedRows.count == 1)
    #expect(session.model.savedEffectRevision == 0)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await session.close()
  }

  @Test func paginatesShortCanonicalPagesAndCachesOnlyOriginNotCurrentGroup() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var first = f.canonical
    let raw =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ConversationJournalPublicFixtures.json")))
      as! [String: Any]
    first["items"] = ((raw["data"] as! [String: Any])["items"] as! [[String: Any]]).filter {
      $0["event_id"] as? String == "command/10000000-0000-4000-8000-000000000008"
    }
    first["has_more"] = true
    first["next_cursor"] = "older-owned-page"
    await f.install(canonicalPages: [
      "": try neutralHTTP(first), "older-owned-page": try neutralHTTP(f.canonical),
    ])
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) != nil)
    await session.model.loadCurrentGroup(commandID: f.commandID)
    let requests = await f.http.stub.requests
    #expect(requests.filter { $0.url?.path.hasSuffix("/meal") == true }.count == 2)
    #expect(requests.filter { $0.url?.path.hasSuffix("/journal") == true }.count == 3)
    #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 0)
    await session.close()
  }

  @Test func closingDuringCanonicalReadDiscardsLateSourceAndNeverReadsGroup() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    let session = try await f.open()
    await session.model.loadHistory()
    let barrier = ConversationControllerBarrier()
    await f.install(barrier: barrier)
    let load = Task {
      await session.model.loadCurrentGroup(commandID: f.commandID)
      await barrier.finish()
    }
    #expect(await barrier.waitEnteredOrFinished())
    await session.close()
    await barrier.release()
    await load.value
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.savedEffectRevision == 0)
    #expect(await f.http.stub.requests.allSatisfy { $0.url?.path.hasSuffix("/meal") != true })
  }

  @Test func explicitRetryCanFindAnOriginThatWasPreviouslyAbsent() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var empty = f.canonical
    empty["items"] = []
    await f.install(canonicalPages: ["": try neutralHTTP(empty)])
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.groupUnavailable(commandID: f.commandID))
    await f.install()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) != nil)
    #expect(session.model.savedEffectRevision == 0)
    await session.close()
  }

  @Test func laterObservedEditRejectsAnOlderCurrentGroup() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var page = try publicJournalV3Pages()[6]
    page["auth_user_id"] = f.publicPage["auth_user_id"]
    await f.install(publicReply: try neutralHTTP(page))
    let session = try await f.open()
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 2)
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.mealEditActions(commandID: f.commandID) == nil)
    #expect(session.model.savedEffectRevision == 0)
    await session.close()
  }

  @Test func intakeTimeIsNotMistakenForCanonicalChildAdmissionTime() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var page = f.publicPage
    var row = (f.publicPage["items"] as! [[String: Any]])[0]
    let intake = "70000000-0000-4000-8000-000000000001"
    row["event_id"] = "intake/" + intake
    row["thread_id"] = intake
    row["kind"] = "intake"
    row["at"] = "2026-11-04T12:00:00.000000Z"
    var lineage = row["lineage"] as! [String: Any]
    lineage["kind"] = "intake"
    lineage["intake_id"] = intake
    row["lineage"] = lineage
    page["items"] = [row]
    await f.install(publicReply: try neutralHTTP(page))
    let session = try await f.open()
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 1)
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.mealEditActions(commandID: f.commandID) != nil)
    #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 0)
    await session.close()
  }

  @Test func repeatedCursorCannotPublishAnOriginOrLoopForever() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var first = f.canonical
    let raw =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ConversationJournalPublicFixtures.json")))
      as! [String: Any]
    first["items"] = ((raw["data"] as! [String: Any])["items"] as! [[String: Any]]).filter {
      $0["event_id"] as? String == "command/10000000-0000-4000-8000-000000000008"
    }
    first["has_more"] = true
    first["next_cursor"] = "loop"
    var second = f.canonical
    second["has_more"] = true
    second["next_cursor"] = "loop"
    await f.install(canonicalPages: ["": try neutralHTTP(first), "loop": try neutralHTTP(second)])
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.groupUnavailable(commandID: f.commandID))
    #expect(
      await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/journal") == true }.count == 3)
    await session.close()
  }

  @Test(arguments: [false, true])
  func identicalConsumptionsHaveDistinctCanonicalOriginsAndShareOneScan(_ cancelFirst: Bool)
    async throws
  {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    let secondID = UUID(uuidString: "10000000-0000-4000-8000-000000000006")!
    let key = secondID.uuidString.lowercased()
    let command = try ConversationMealCommand(
      commandID: secondID, source: .text("Comi arroz 100 g"), mealType: .almoco)
    var row = (f.canonical["items"] as! [[String: Any]])[0]
    var result = row["result"] as! [String: Any]
    var receipt = result["receipt"] as! [String: Any]
    let logID = "10000000-0000-4000-8000-000000000007"
    receipt["command_id"] = key
    receipt["input_hash"] = command.inputHash
    receipt["registration_id"] = "10000000-0000-4000-8000-000000000010"
    receipt["provider_key"] = "conversation.meal/10000000-0000-4000-8000-000000000001/" + key
    receipt["log_ids"] = [logID]
    result["command_id"] = key
    result["input_hash"] = command.inputHash
    result["receipt"] = receipt
    result["admitted_at"] = "2026-11-04T12:00:00.000002Z"
    row["event_id"] = "command/" + key
    row["at"] = result["admitted_at"]
    row["result"] = result
    row["original_command"] = try JSONSerialization.jsonObject(with: command.wireBody)
    var canonical = f.canonical
    canonical["items"] = [row] + (f.canonical["items"] as! [[String: Any]])
    var secondGroup = f.group
    secondGroup["command_id"] = key
    secondGroup["input_hash"] = command.inputHash
    secondGroup["admitted_at"] = result["admitted_at"]
    secondGroup["original_receipt"] = receipt
    var current = secondGroup["current"] as! [String: Any]
    var item = (current["items"] as! [[String: Any]])[0]
    item["id"] = logID
    current["items"] = [item]
    secondGroup["current"] = current
    var page = f.publicPage
    var publicRow = (page["items"] as! [[String: Any]])[0]
    publicRow["event_id"] = "command/" + key
    publicRow["thread_id"] = key
    publicRow["at"] = row["at"]
    var lineage = publicRow["lineage"] as! [String: Any]
    lineage["command_id"] = key
    publicRow["lineage"] = lineage
    var outcome = publicRow["outcome"] as! [String: Any]
    var record = outcome["record"] as! [String: Any]
    record["registration_id"] = receipt["registration_id"]
    record["log_ids"] = [logID]
    outcome["record"] = record
    publicRow["outcome"] = outcome
    page["items"] = [publicRow] + (page["items"] as! [[String: Any]])
    let barrier = ConversationControllerBarrier()
    await f.install(
      canonicalPages: ["": try neutralHTTP(canonical)], publicReply: try neutralHTTP(page),
      groupReplies: [key: try neutralHTTP(secondGroup)], barrier: barrier)
    let session = try await f.open()
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 2)
    let first = Task {
      await session.model.loadCurrentGroup(commandID: f.commandID)
      await barrier.finish()
    }
    #expect(await barrier.waitEnteredOrFinished())
    let second = Task { await session.model.loadCurrentGroup(commandID: secondID) }
    for _ in 0..<100 where !session.model.isLoadingMealDetails(commandID: secondID) {
      await Task.yield()
    }
    #expect(session.model.isLoadingMealDetails(commandID: secondID))
    let publication = ConversationControllerBarrier()
    if cancelFirst {
      first.cancel()
      await f.http.lifecycle.holdNextVisible(publication)
    }
    await barrier.release()
    if cancelFirst {
      #expect(await publication.waitEnteredOrFinished())
      await first.value
      await publication.release()
    }
    await first.value
    await second.value
    if !cancelFirst { #expect(session.model.mealEditActions(commandID: f.commandID) != nil) }
    #expect(session.model.mealEditActions(commandID: secondID) != nil)
    #expect(session.model.currentGroup(commandID: secondID)?.commandID == secondID)
    #expect(
      await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/journal") == true }.count == 2)
    #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 0)
    await session.close()
  }

  @Test func closedDayKeepsServerActionsAndDoesNotOpenEditor() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    var group = f.group
    var current = f.group["current"] as! [String: Any]
    current["day_closed"] = true
    group["current"] = current
    var actions = group["actions"] as! [String: Any]
    actions["save"] = ["allowed": false, "reason": "day_closed"]
    actions["undo_registration"] = ["allowed": false, "reason": "day_closed"]
    group["actions"] = actions
    await f.install(groupReplies: [f.commandID.uuidString.lowercased(): try neutralHTTP(group)])
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    let loaded = try #require(session.model.currentGroup(commandID: f.commandID))
    #expect(!loaded.actions.save.allowed && !loaded.actions.undoRegistration.allowed)
    await session.model.beginMealEdit(
      commandID: f.commandID, itemID: try #require(loaded.current?.items.first?.id))
    #expect(session.model.mealEditor?.presentation == nil)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await session.close()
  }

  @Test func coldRecoveredItemSavesOnceAndReopensWithCurrentFactsAndOriginalReceipt() async throws {
    let f = try await ColdMealRecoveryFixture()
    defer { f.disk.remove() }
    let server = try ColdMealEditUnitServer(group: JSONSerialization.data(withJSONObject: f.group))
    await f.install(editingServer: server)
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    let original = try #require(session.model.currentGroup(commandID: f.commandID))
    let item = try #require(original.current?.items.first)
    await session.model.beginMealEdit(commandID: f.commandID, itemID: item.id)
    let editor = try #require(session.model.mealEditor)
    #expect(editor.presentation != nil)
    editor.setQuantityText("100", language: .portugueseBrazil)
    #expect(editor.canSave(language: .portugueseBrazil))
    await editor.save(language: .portugueseBrazil)
    #expect(editor.lastSaved?.receipt.revision == 1)
    #expect(editor.pendingEntries.isEmpty)
    #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 1)
    await session.model.loadCurrentGroup(commandID: f.commandID)
    let changed = try #require(session.model.currentGroup(commandID: f.commandID))
    #expect(changed.current?.items.first?.quantityG == 100)
    #expect(changed.current?.items.first?.id != item.id)
    #expect(changed.originalReceipt.report == original.originalReceipt.report)
    await session.close()

    let reopened = try await f.open()
    await reopened.model.loadHistory()
    await reopened.model.loadCurrentGroup(commandID: f.commandID)
    let retained = try #require(reopened.model.currentGroup(commandID: f.commandID))
    #expect(retained.current?.items.first?.quantityG == 100 && retained.revision == 1)
    #expect(retained.originalReceipt.report == original.originalReceipt.report)
    #expect(reopened.model.mealEditActions(commandID: f.commandID) != nil)
    #expect(reopened.model.savedRows.isEmpty && reopened.model.savedEffectRevision == 0)
    let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 1 && posts[0].url?.path.contains("/edits/") == true)
    await reopened.close()
  }
}

@MainActor private struct ColdMealRecoveryFixture {
  let http: ConversationHTTPFixture
  let disk: OutboxDiskFixture
  let vault: ConversationOutboxKeyVault
  let editVault: ConversationOutboxKeyVault
  let commandID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
  let canonical: [String: Any]
  let publicPage: [String: Any]
  let group: [String: Any]
  let mealSession: ConversationHTTPReply
  let intakeSession: ConversationHTTPReply

  init() async throws {
    http = try ConversationHTTPFixture()
    disk = try OutboxDiskFixture()
    vault = .init(service: "cold-meal-origin-unit", security: OutboxKeychainFake())
    editVault = .init(
      service: ConversationMealEditOutboxSession.keychainService, security: OutboxKeychainFake())
    let lease = await http.lifecycle.leaseForRequest()
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
    let raw =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: fixtures.appendingPathComponent("ConversationJournalPublicFixtures.json")))
      as! [String: Any]
    var journal = raw["data"] as! [String: Any]
    journal["auth_user_id"] = lease.userID
    journal["items"] = (journal["items"] as! [[String: Any]]).filter {
      $0["event_id"] as? String == "command/10000000-0000-4000-8000-000000000002"
    }
    canonical = journal
    var page = try publicJournalV3Pages()[6]
    page["auth_user_id"] = lease.userID
    page["items"] = (page["items"] as! [[String: Any]]).filter { $0["kind"] as? String == "report" }
    publicPage = page
    let rawGroup =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: fixtures.appendingPathComponent("ConversationMealEditPublicFixtures.json")))
      as! [String: Any]
    group = (rawGroup["group"] as! [String: Any])["data"] as! [String: Any]
    // Validate both independent wire fixtures before testing model behavior.
    _ = try JSONDecoder().decode(
      ConversationJournalV3PageSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
    _ = try ConversationJournalPageSnapshot.Envelope(data: neutralHTTP(journal).body)
    _ = try ConversationMealGroupSnapshot(data: JSONSerialization.data(withJSONObject: group))
    let owner = journal["owner_id"]!
    let epoch = journal["epoch"]!
    mealSession = try neutralHTTP([
      "schema": "conversation.session.v1", "auth_user_id": lease.userID,
      "owner_id": owner, "epoch": epoch, "observed_at": "2026-11-04T12:00:00Z",
      "meal_command_protocol": "conversation.command.v1",
    ])
    intakeSession = try neutralHTTP([
      "schema": "conversation.intake-session.v1", "auth_user_id": lease.userID,
      "owner_id": owner, "epoch": epoch, "observed_at": "2026-11-04T12:00:00Z",
      "intake_protocol": "conversation.intake.v1",
    ])
    await install()
  }
  func install(
    canonicalPages: [String: ConversationHTTPReply]? = nil,
    publicReply: ConversationHTTPReply? = nil, groupReplies: [String: ConversationHTTPReply] = [:],
    barrier: ConversationControllerBarrier? = nil, editingServer: ColdMealEditUnitServer? = nil
  ) async {
    let pages = canonicalPages ?? ["": try! neutralHTTP(canonical)]
    let v3 = publicReply ?? (try! neutralHTTP(publicPage))
    let g = try! neutralHTTP(group)
    let mealSession = self.mealSession
    let intakeSession = self.intakeSession
    await http.stub.respond { request, _ in
      if let editingServer,
        request.url?.path.hasSuffix("/meal") == true
          || request.url?.path.contains("/edits/") == true
      {
        return try await editingServer.reply(request)
      }
      if request.url?.path == "/api/mobile/v1/conversation/journal" {
        let version = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
          .first { $0.name == "version" }?.value
        if version == "3" { return v3 }
        if let barrier { await barrier.enter() }
        let cursor =
          URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
            $0.name == "cursor"
          }?.value ?? ""
        return pages[cursor] ?? .failure(503, "missing_page")
      }
      if request.url?.path.hasSuffix("/meal") == true {
        let command = request.url!.path.split(separator: "/").dropLast().last.map(String.init) ?? ""
        return groupReplies[command] ?? g
      }
      if request.url?.path == "/api/mobile/v1/conversation/intakes/session" { return intakeSession }
      return mealSession
    }
  }
  @MainActor func open() async throws -> FlowConversationBoundSession {
    let lease = await http.lifecycle.leaseForRequest()
    return try await FlowConversationSessionSource(
      transport: http.transport, lifecycle: http.lifecycle, media: nil,
      store: disk.store, keyVault: vault,
      editing: .init(
        store: .init(directory: disk.directory),
        keyVault: editVault),
      neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
  }
}

/// Synthetic HTTP boundary only. Existing real model, durable edit controller,
/// operation codec and scoped transport execute the save; no domain or UI
/// implementation is substituted inside the app under test.
private actor ColdMealEditUnitServer {
  private var group: Data
  init(group: Data) throws {
    _ = try ConversationMealGroupSnapshot(data: group)
    self.group = group
  }
  func reply(_ request: URLRequest) throws -> ConversationHTTPReply {
    var value = try JSONSerialization.jsonObject(with: group) as! [String: Any]
    if request.httpMethod == "GET" { return try neutralHTTP(value) }
    #expect(request.httpMethod == "POST")
    let id = try #require(UUID(uuidString: request.url!.lastPathComponent))
    let operation = try ConversationMealEditOperation(
      ownerID: UUID(uuidString: value["owner_id"] as! String)!,
      commandID: UUID(uuidString: value["command_id"] as! String)!,
      originalInputHash: value["input_hash"] as! String,
      epoch: UUID(uuidString: value["epoch"] as! String)!, operationID: id,
      wireBody: try #require(request.httpBody))
    guard case .save(let recordID, let items) = operation.action else {
      throw URLError(.badServerResponse)
    }
    var current = value["current"] as! [String: Any]
    #expect(operation.expectedRevision == value["revision"] as? Int)
    #expect(operation.expectedVersion == current["expected_version"] as? String)
    #expect(items.count == 1 && items[0].quantityG == 100)
    let next = "10000000-0000-4000-8000-000000000081"
    let clock = ISO8601DateFormatter()
    clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let observed = try #require(clock.date(from: value["observed_at"] as! String))
    let appliedAt = clock.string(from: observed.addingTimeInterval(60))
    let effect: [String: Any] = [
      "schema": "conversation.meal-edit-effect-public.v1", "owner_id": value["owner_id"]!,
      "command_id": value["command_id"]!, "operation_id": id.uuidString.lowercased(),
      "input_hash": operation.operationInputHash, "kind": "saved", "revision": 1,
      "applied_at": appliedAt,
      "undo_expires_at": clock.string(from: observed.addingTimeInterval(360)),
      "target_operation_id": NSNull(),
      "removed_item_ids": [recordID.uuidString.lowercased()], "new_item_ids": [next],
      "next_record_id": next,
    ]
    var item = (current["items"] as! [[String: Any]])[0]
    #expect(item["id"] as? String == recordID.uuidString.lowercased())
    item["id"] = next
    item["quantity_g"] = 100
    // Explicit synthetic returned facts; the application does not calculate them.
    item["kcal"] = 65
    item["protein_g"] = 3.5
    item["carbs_g"] = 5.3
    item["fat_g"] = 3.2
    current["items"] = [item]
    current["expected_version"] = "v1:" + String(repeating: "c", count: 64)
    value["current"] = current
    value["revision"] = 1
    value["last_operation"] = effect
    value["observed_at"] = clock.string(from: observed.addingTimeInterval(120))
    value["actions"] = [
      "save": ["allowed": true],
      "undo_registration": ["allowed": false, "reason": "version_changed"],
      "undo_save": ["allowed": true],
    ]
    group = try JSONSerialization.data(withJSONObject: value)
    _ = try ConversationMealGroupSnapshot(data: group)
    return try neutralHTTP([
      "schema": "conversation.meal-edit-result.v1", "status": "saved",
      "owner_id": value["owner_id"]!,
      "command_id": value["command_id"]!, "input_hash": value["input_hash"]!,
      "epoch": value["epoch"]!,
      "receipt": effect,
    ])
  }
}

@MainActor @Suite("Cold linked meals keep genuine clarification origins", .serialized)
struct FlowConversationColdLinkedMealRecoveryTests {
  @Test(arguments: ["wrong-protocol", "cached"])
  func originRequiresItsOwnUncachedResponseProtocol(_ attack: String) async throws {
    let f = try await ColdLinkedMealFixture()
    defer { f.disk.remove() }
    await f.install(
      originProtocol: attack == "wrong-protocol" ? "meal-command-v1" : "meal-linked-origin-v1",
      cacheControl: attack == "cached" ? "public" : "no-store")
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.groupUnavailable(commandID: f.commandID))
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(
      await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/origin") == true }.count == 1)
    #expect(await f.http.stub.requests.allSatisfy { $0.url?.path.hasSuffix("/meal") != true })
    await session.close()
  }
  @Test func closureDuringOriginReadCannotPublishEditingFactsOrStartAGroupRead() async throws {
    let f = try await ColdLinkedMealFixture()
    defer { f.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.install(barrier: barrier)
    let session = try await f.open()
    await session.model.loadHistory()
    let task = Task { await session.model.loadCurrentGroup(commandID: f.commandID) }
    #expect(await barrier.waitEnteredOrFinished())
    await session.close()
    await barrier.release()
    await task.value
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.mealEditActions(commandID: f.commandID) == nil)
    #expect(await f.http.stub.requests.allSatisfy { $0.url?.path.hasSuffix("/meal") != true })
  }
  @Test(arguments: [false, true])
  func reopeningRecoversLinkedOriginBeforeGroupWithoutFabricatingAnAcknowledgement(
    neutralIntake: Bool
  )
    async throws
  {
    let f = try await ColdLinkedMealFixture(neutralIntake: neutralIntake)
    defer { f.disk.remove() }
    let session = try await f.open()
    await session.model.loadHistory()
    let row = try #require(session.model.unifiedRows.first)
    #expect(session.model.unifiedMealDetailsCommandID(eventID: row.eventID) == f.commandID)
    #expect(session.model.mealEditActions(commandID: f.commandID) == nil)
    await session.model.loadCurrentGroup(commandID: f.commandID)
    let group = try #require(session.model.currentGroup(commandID: f.commandID))
    #expect(group.originalReceipt.linked?.commandID == f.commandID)
    #expect(session.model.mealEditActions(commandID: f.commandID) != nil)
    #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 0)
    let reads = await f.http.stub.requests.filter {
      $0.url?.path.hasSuffix("/origin") == true || $0.url?.path.hasSuffix("/meal") == true
    }
    #expect(reads.count == 2 && reads[0].url?.path.hasSuffix("/origin") == true)
    #expect(reads[0].value(forHTTPHeaderField: "X-Conversation-Input-Hash") == nil)
    #expect(reads.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    await session.close()
  }
  @Test(
    arguments: [
      "owner_id", "epoch", "parent_decision_hash", "registration_id", "effect_version",
      "parent_command_id", "private",
    ], [false, true])
  func foreignOrContradictoryLinkedOriginDoesNotGrantEditing(_ field: String, neutralIntake: Bool)
    async throws
  {
    let f = try await ColdLinkedMealFixture(neutralIntake: neutralIntake)
    defer { f.disk.remove() }
    var origin = f.origin
    switch field {
    case "owner_id", "epoch": origin[field] = UUID().uuidString.lowercased()
    case "parent_decision_hash": origin[field] = String(repeating: "a", count: 64)
    case "private": origin["source"] = ["unsafe": true]
    default:
      var receipt = origin["receipt"] as! [String: Any]
      receipt[field] =
        field == "effect_version"
        ? "cmeal1:" + String(repeating: "a", count: 64) : UUID().uuidString.lowercased()
      origin["receipt"] = receipt
    }
    await f.install(origin: try neutralHTTP(origin))
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.mealEditActions(commandID: f.commandID) == nil)
    #expect(session.model.savedEffectRevision == 0)
    #expect(
      await f.http.stub.requests.allSatisfy {
        $0.httpMethod == "GET" && $0.url?.path.hasSuffix("/meal") != true
      })
    #expect(
      await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/origin") == true }.count == 1)
    await session.close()
  }
  @Test func failedOriginCanBeExplicitlyRetriedWithoutRegisteringAnotherMeal() async throws {
    let f = try await ColdLinkedMealFixture()
    defer { f.disk.remove() }
    await f.install(origin: .failure(503, "unavailable"))
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.groupUnavailable(commandID: f.commandID))
    await f.install()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) != nil)
    #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 0)
    #expect(
      await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/origin") == true }.count == 2)
    await session.close()
  }
  @Test func freshGroupCannotSubstituteAnotherOtherwiseValidOriginalReceipt() async throws {
    let f = try await ColdLinkedMealFixture()
    defer { f.disk.remove() }
    var group = f.group
    var receipt = group["original_receipt"] as! [String: Any]
    receipt["consumed_at"] = "2026-11-04T18:15:29.256012Z"
    group["original_receipt"] = receipt
    group["registration_undo_expires_at"] = "2026-11-04T18:20:29.256012Z"
    var current = group["current"] as! [String: Any]
    var items = current["items"] as! [[String: Any]]
    items[0]["consumed_at"] = receipt["consumed_at"]
    current["items"] = items
    group["current"] = current
    _ = try ConversationMealGroupSnapshot(data: JSONSerialization.data(withJSONObject: group))
    await f.install(groupOverride: try neutralHTTP(group))
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    #expect(session.model.currentGroup(commandID: f.commandID) == nil)
    #expect(session.model.mealEditActions(commandID: f.commandID) == nil)
    await session.close()
  }
  @Test(arguments: [false, true])
  func linkedSaveUsesExistingControllerOnceAndSurvivesAnotherColdOpen(neutralIntake: Bool)
    async throws
  {
    let f = try await ColdLinkedMealFixture(neutralIntake: neutralIntake)
    defer { f.disk.remove() }
    let server = try ColdMealEditUnitServer(group: JSONSerialization.data(withJSONObject: f.group))
    await f.install(editingServer: server)
    let session = try await f.open()
    await session.model.loadHistory()
    await session.model.loadCurrentGroup(commandID: f.commandID)
    let initial = try #require(session.model.currentGroup(commandID: f.commandID))
    await session.model.beginMealEdit(
      commandID: f.commandID, itemID: try #require(initial.current?.items.first?.id))
    let editor = try #require(session.model.mealEditor)
    #expect(editor.presentation != nil)
    editor.setQuantityText("100", language: .portugueseBrazil)
    await editor.save(language: .portugueseBrazil)
    #expect(editor.lastSaved?.receipt.revision == 1)
    #expect(session.model.savedRows.isEmpty && session.model.savedEffectRevision == 1)
    await session.close()
    let reopened = try await f.open()
    await reopened.model.loadHistory()
    await reopened.model.loadCurrentGroup(commandID: f.commandID)
    let retained = try #require(reopened.model.currentGroup(commandID: f.commandID))
    #expect(retained.revision == 1 && retained.current?.items.first?.quantityG == 100)
    #expect(
      retained.originalReceipt.linked?.registrationID
        == initial.originalReceipt.linked?.registrationID)
    #expect(reopened.model.mealEditActions(commandID: f.commandID) != nil)
    #expect(reopened.model.savedEffectRevision == 0)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await reopened.close()
  }
}

@MainActor private struct ColdLinkedMealFixture {
  let http: ConversationHTTPFixture
  let disk: OutboxDiskFixture
  let vault: ConversationOutboxKeyVault
  let editVault: ConversationOutboxKeyVault
  let commandID: UUID
  let origin: [String: Any]
  let group: [String: Any]
  let page: [String: Any]
  let mealSession: ConversationHTTPReply
  let intakeSession: ConversationHTTPReply
  init(neutralIntake: Bool = false) async throws {
    http = try ConversationHTTPFixture()
    disk = try OutboxDiskFixture()
    vault = .init(service: "cold-linked-unit", security: OutboxKeychainFake())
    editVault = .init(
      service: ConversationMealEditOutboxSession.keychainService, security: OutboxKeychainFake())
    let lease = await http.lifecycle.leaseForRequest()
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
    let sdk =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: fixtures.appendingPathComponent("ConversationLinkedFeedbackSDKFixtures.json"))
      ) as! [String: Any]
    let rootGroup =
      try JSONSerialization.jsonObject(
        with: Data(
          contentsOf: fixtures.appendingPathComponent(
            "ConversationMealLinkedGroupPublicFixture.json"))) as! [String: Any]
    group = rootGroup["group"] as! [String: Any]
    let parent = sdk["parentBinding"] as! [String: Any]
    let child = sdk["childBinding"] as! [String: Any]
    let receipt = sdk["receipt"] as! [String: Any]
    let owner = child["owner_id"]!
    let epoch = child["epoch"]!
    let parentID = parent["command_id"] as! String
    let childID = child["command_id"] as! String
    commandID = UUID(uuidString: childID)!
    origin = [
      "schema": "conversation.meal-linked-origin.v1", "auth_user_id": lease.userID,
      "owner_id": owner, "epoch": epoch, "observed_at": group["observed_at"]!,
      "parent_binding": parent, "child_binding": child,
      "parent_decision_hash": sdk["parentDecisionHash"]!, "receipt": receipt,
    ]
    // Synthetic public row assembled from the real qualified binding/receipt golden.
    var publicPage = try publicJournalV3Pages()[5]
    publicPage["auth_user_id"] = lease.userID
    publicPage["owner_id"] = owner
    publicPage["epoch"] = epoch
    publicPage["observed_at"] = group["observed_at"]!
    var row = (publicPage["items"] as! [[String: Any]]).first {
      $0["kind"] as? String == "fulfillment"
    }!
    row["event_id"] = "fulfillment/\(parentID)/\(childID)"
    let intakeID = neutralIntake ? UUID().uuidString.lowercased() : nil
    row["thread_id"] = intakeID ?? parentID
    row["at"] = receipt["consumed_at"]!
    row["lineage"] = [
      "kind": "meal.clarify", "intake_id": intakeID as Any? ?? NSNull(), "command_id": childID,
      "parent_command_id": parentID, "origin_epoch": epoch,
    ]
    row["outcome"] = [
      "status": "registered", "feedback": NSNull(),
      "record": [
        "kind": "meal", "registration_id": receipt["registration_id"]!,
        "meal_type": receipt["meal_type"]!, "local_date": receipt["local_date"]!,
        "log_ids": receipt["log_ids"]!, "effect_version": receipt["effect_version"]!,
      ],
    ]
    publicPage["items"] = [row]
    page = publicPage
    _ = try JSONDecoder().decode(
      ConversationJournalV3PageSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
    _ = try ConversationMealGroupSnapshot(data: JSONSerialization.data(withJSONObject: group))
    mealSession = try neutralHTTP([
      "schema": "conversation.session.v1", "auth_user_id": lease.userID, "owner_id": owner,
      "epoch": epoch, "observed_at": parent["admitted_at"]!,
      "meal_command_protocol": "conversation.command.v1",
    ])
    intakeSession = try neutralHTTP([
      "schema": "conversation.intake-session.v1", "auth_user_id": lease.userID, "owner_id": owner,
      "epoch": epoch, "observed_at": parent["admitted_at"]!,
      "intake_protocol": "conversation.intake.v1",
    ])
    await install()
  }
  func install(
    origin: ConversationHTTPReply? = nil, groupOverride: ConversationHTTPReply? = nil,
    editingServer: ColdMealEditUnitServer? = nil, originProtocol: String = "meal-linked-origin-v1",
    cacheControl: String = "no-store", barrier: ConversationControllerBarrier? = nil
  ) async {
    let originReply = origin ?? (try! neutralHTTP(self.origin))
    let pageReply = try! neutralHTTP(page)
    let groupReply = groupOverride ?? (try! neutralHTTP(group))
    let mealSession = self.mealSession
    let intakeSession = self.intakeSession
    await http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/origin") == true {
        if let barrier { await barrier.enter() }
        var reply = originReply
        reply.headers["X-Conversation-Protocol"] = originProtocol
        reply.headers["Cache-Control"] = cacheControl
        return reply
      }
      if request.url?.path.hasSuffix("/meal") == true
        || request.url?.path.contains("/edits/") == true
      {
        if let editingServer { return try await editingServer.reply(request) }
        return groupReply
      }
      if request.url?.path.hasSuffix("/journal") == true { return pageReply }
      if request.url?.path == "/api/mobile/v1/conversation/intakes/session" { return intakeSession }
      return mealSession
    }
  }
  func open() async throws -> FlowConversationBoundSession {
    let lease = await http.lifecycle.leaseForRequest()
    return try await FlowConversationSessionSource(
      transport: http.transport, lifecycle: http.lifecycle, media: nil, store: disk.store,
      keyVault: vault, editing: .init(store: .init(directory: disk.directory), keyVault: editVault),
      neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
  }
}
