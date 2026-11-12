import Foundation
import Testing

@testable import BodyFlow

@MainActor @Suite("Cold meal canonical origin recovery", .serialized)
struct FlowConversationColdMealRecoveryTests {
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
}

@MainActor private struct ColdMealRecoveryFixture {
  let http: ConversationHTTPFixture
  let disk: OutboxDiskFixture
  let vault: ConversationOutboxKeyVault
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
    barrier: ConversationControllerBarrier? = nil
  ) async {
    let pages = canonicalPages ?? ["": try! neutralHTTP(canonical)]
    let v3 = publicReply ?? (try! neutralHTTP(publicPage))
    let g = try! neutralHTTP(group)
    let mealSession = self.mealSession
    let intakeSession = self.intakeSession
    await http.stub.respond { request, _ in
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
        keyVault: .init(
          service: ConversationMealEditOutboxSession.keychainService, security: OutboxKeychainFake()
        )),
      neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
  }
}
