import Foundation
import Testing

@testable import BodyFlow

@Suite("Public journal v3 historical facts")
struct ConversationJournalV3Tests {
  @Test func actualPublicServicePagesDecodeWithoutPrivateSchemaOrWriteProofs() throws {
    let pages = try publicJournalV3Pages()
    #expect(pages.count == 10)
    for page in pages {
      _ = try JSONDecoder().decode(
        ConversationJournalV3PageSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
    }
  }
}
func publicJournalV3Pages() throws -> [[String: Any]] {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
    "Fixtures/ConversationJournalV3PublicFixtures.json")
  let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  return root["pages"] as! [[String: Any]]
}

@MainActor @Suite("Actual neutral candidate cold history", .serialized)
struct FlowConversationJournalV3RuntimeTests {
  @Test func qualifiedNeutralCandidateUsesReadOnlyVersion3AndNeverPostsOnReopen() async throws {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let source = FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let session = try await source.open(expectedUserID: lease.userID)
    await session.model.loadHistory()
    let requests = await f.http.stub.requests
    let journals = requests.filter { $0.url?.path == "/api/mobile/v1/conversation/journal" }
    #expect(journals.count == 1)
    #expect(
      URLComponents(url: journals[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(
        where: { $0.name == "version" })?.value == "3")
    #expect(session.model.savedEffectRevision == 0)
    #expect(session.model.unifiedRows.count == 1)
    let row = try #require(session.model.unifiedRows.first)
    let bound = try #require(session.model.unifiedHistory.feedback(for: row))
    guard case .v3Sections(_, let sections) = bound.presentation.content else {
      Issue.record("Six historical sections required")
      return
    }
    #expect(sections.map(\.key) == [.saved, .items, .summary, .day, .block, .education])
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    await session.close()
  }
}
struct JournalV3HTTPFixture {
  let http: ConversationHTTPFixture
  let disk: OutboxDiskFixture
  let vault: ConversationOutboxKeyVault
  let page: Data
  let mealSession: ConversationHTTPReply
  let intakeSession: ConversationHTTPReply
}
func journalV3HTTPFixture(pageIndex: Int = 3) async throws -> JournalV3HTTPFixture {
  let http = try ConversationHTTPFixture()
  let disk = try OutboxDiskFixture()
  let lease = await http.lifecycle.leaseForRequest()
  var page = try publicJournalV3Pages()[pageIndex]
  page["auth_user_id"] = lease.userID
  let pageReply = try neutralHTTP(page)
  let owner = page["owner_id"]!
  let epoch = page["epoch"]!
  let mealReply = try neutralHTTP([
    "schema": "conversation.session.v1", "auth_user_id": lease.userID, "owner_id": owner,
    "epoch": epoch, "observed_at": "2026-11-05T05:12:16.000000Z",
    "meal_command_protocol": "conversation.command.v1",
  ])
  let intakeReply = try neutralHTTP([
    "schema": "conversation.intake-session.v1", "auth_user_id": lease.userID, "owner_id": owner,
    "epoch": epoch, "observed_at": "2026-11-05T05:12:16.000000Z",
    "intake_protocol": "conversation.intake.v1",
  ])
  await http.stub.respond { request, _ in
    if request.url?.path == "/api/mobile/v1/conversation/journal" { return pageReply }
    if request.url?.path == "/api/mobile/v1/conversation/intakes/session" { return intakeReply }
    return mealReply
  }
  return .init(
    http: http, disk: disk,
    vault: .init(service: "journal-v3-unit", security: OutboxKeychainFake()),
    page: try JSONSerialization.data(withJSONObject: page), mealSession: mealReply,
    intakeSession: intakeReply)
}

extension ConversationJournalV3Tests {
  @Test(arguments: [
    "schema", "private", "epoch", "intake", "child", "event", "future", "record", "duplicate",
    "order", "energy", "workoutID", "editClock", "questionLease", "sourceURL",
  ])
  func rejectsAmbiguousOrPrivateHistoricalPackets(_ attack: String) throws {
    var page = try publicJournalV3Pages()[
      attack == "editClock" || attack == "duplicate" || attack == "order" ? 2 : 0]
    var rows = page["items"] as! [[String: Any]]
    var row = rows[0]
    var lineage = row["lineage"] as! [String: Any]
    var outcome = row["outcome"] as! [String: Any]
    switch attack {
    case "schema": page["schema"] = "conversation.journal-page.v2"
    case "private": row["input_hash"] = String(repeating: "a", count: 64)
    case "epoch": page["epoch"] = UUID().uuidString.lowercased()
    case "intake":
      lineage["intake_id"] = UUID().uuidString.lowercased()
      row["lineage"] = lineage
    case "child":
      lineage["command_id"] = lineage["intake_id"]
      row["lineage"] = lineage
    case "event": row["event_id"] = "command/" + (lineage["intake_id"] as! String)
    case "future": row["at"] = "2099-11-06T02:44:12.703115Z"
    case "record":
      outcome.removeValue(forKey: "record")
      row["outcome"] = outcome
    case "duplicate": rows.append(rows[0])
    case "order": rows.reverse()
    case "energy", "workoutID":
      var record = outcome["record"] as! [String: Any]
      var activity = record["activity"] as! [String: Any]
      if attack == "energy" {
        activity["estimated_kcal"] = -1
      } else {
        activity["log_id"] = UUID().uuidString.lowercased()
      }
      record["activity"] = activity
      outcome["record"] = record
      row["outcome"] = outcome
    case "editClock":
      let index = rows.firstIndex { $0["kind"] as? String == "edit" }!
      var edit = rows[index]
      var out = edit["outcome"] as! [String: Any]
      var record = out["record"] as! [String: Any]
      record["applied_at"] = "2026-11-06T02:44:11.613880Z"
      out["record"] = record
      edit["outcome"] = out
      rows[index] = edit
    case "questionLease":
      outcome["observed_question"] = [
        "field": "duration_min", "text": "Quantos minutos?",
        "key": String(repeating: "a", count: 64),
      ]
      row["outcome"] = outcome
    default:
      var input = row["input"] as! [String: Any]
      input["source_url"] = "https://invalid.example/private"
      row["input"] = input
    }
    if !["duplicate", "order", "editClock"].contains(attack) { rows[0] = row }
    page["items"] = rows
    #expect(throws: (any Error).self) { try decodePublicJournalV3(page) }
  }
  @Test func byteShortPageKeepsExactOwnedCursorRatherThanAssumingLimitFull() throws {
    var page = try publicJournalV3Pages()[2]
    let row = (page["items"] as! [[String: Any]])[0]
    let cursor = try journalV3Cursor(page: page, row: row)
    page["items"] = [row]
    page["has_more"] = true
    page["next_cursor"] = cursor
    let parsed = try decodePublicJournalV3(page)
    #expect(parsed.items.count == 1 && parsed.hasMore && parsed.nextCursor == cursor)
    for key in ["v", "owner_id", "epoch", "at", "id"] {
      var anchor = try journalV3CursorObject(page: page, row: row)
      anchor[key] = key == "v" ? 2 : "wrong"
      page["next_cursor"] = try journalV3Base64(anchor)
      #expect(throws: (any Error).self) { try decodePublicJournalV3(page) }
    }
  }
  @Test func optionalCommentaryNeverErasesRegisteredFactsAndNullEnergyIsNotZero() throws {
    var page = try publicJournalV3Pages()[0]
    var row = (page["items"] as! [[String: Any]])[0]
    var out = row["outcome"] as! [String: Any]
    out["feedback"] = ["schema": "unknown"]
    row["outcome"] = out
    page["items"] = [row]
    let parsed = try decodePublicJournalV3(page)
    #expect(parsed.items[0].status == .registered && parsed.items[0].feedback == nil)
    guard case .workout(let workout) = parsed.items[0].record else {
      Issue.record("Actual historical workout required")
      return
    }
    #expect(workout.estimatedKcal == nil)
    var record = out["record"] as! [String: Any]
    var activity = record["activity"] as! [String: Any]
    activity["estimated_kcal"] = 0
    record["activity"] = activity
    out["record"] = record
    row["outcome"] = out
    page["items"] = [row]
    guard case .workout(let known) = try decodePublicJournalV3(page).items[0].record else { return }
    #expect(known.estimatedKcal == 0)
  }
  @Test(arguments: [false, true])
  func historicalPresentationIncludesLiteralSourceFactsAndUnknownEnergy(_ english: Bool) throws {
    let entry = try decodePublicJournalV3(publicJournalV3Pages()[0]).items[0]
    let view = FlowConversationJournalV3Presentation(entry: entry, english: english)
    #expect(view.lines.contains { $0.contains("30 min") && $0.contains("caminhada") })
    #expect(
      view.lines.contains(
        english ? "Energy expenditure unavailable." : "Gasto energético indisponível."))
    #expect(!view.lines.contains { $0.contains("0 kcal") })
  }
}
func decodePublicJournalV3(_ page: [String: Any]) throws -> ConversationJournalV3PageSnapshot {
  try JSONDecoder().decode(
    ConversationJournalV3PageSnapshot.self, from: JSONSerialization.data(withJSONObject: page))
}
func journalV3CursorObject(page: [String: Any], row: [String: Any]) throws -> [String: Any] {
  [
    "v": 3, "owner_id": page["owner_id"]!, "epoch": page["epoch"]!, "at": row["at"]!,
    "id": row["event_id"]!,
  ]
}
func journalV3Base64(_ object: [String: Any]) throws -> String {
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString()
    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}
func journalV3Cursor(page: [String: Any], row: [String: Any]) throws -> String {
  try journalV3Base64(journalV3CursorObject(page: page, row: row))
}

@MainActor extension FlowConversationJournalV3RuntimeTests {
  @Test func sameIdentityGrantRefreshCannotRewritePinnedOriginalOrInventAnEffect() async throws {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let source = FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true)
    let session = try await source.open(expectedUserID: lease.userID)
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 1)
    var changed = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    var rows = changed["items"] as! [[String: Any]]
    var row = rows[0]
    row["input"] = ["channel": "text", "text": "Changed immutable original"]
    rows[0] = row
    changed["items"] = rows
    let pageReply = try neutralHTTP(changed)
    await f.http.stub.respond { request, _ in
      if request.url?.path == "/api/mobile/v1/conversation/journal" { return pageReply }
      if request.url?.path == "/api/mobile/v1/conversation/intakes/session" {
        return f.intakeSession
      }
      return f.mealSession
    }
    await session.model.refreshConversation()
    #expect(session.model.unifiedHistoryUnavailable)
    #expect(session.model.unifiedRows.isEmpty)
    #expect(session.model.savedEffectRevision == 0)
    await session.close()
  }
  @Test func failedReadWithholdsCommentaryButKeepsFactsAndNoRetryEffect() async throws {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    await session.model.loadHistory()
    let row = try #require(session.model.unifiedRows.first)
    #expect(session.model.unifiedHistory.feedback(for: row) != nil)
    await f.http.stub.respond { _, _ in .failure(503, "conversation_journal_unavailable") }
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 1 && session.model.unifiedHistoryUnavailable)
    #expect(session.model.unifiedHistory.feedback(for: row) == nil)
    #expect(session.model.savedEffectRevision == 0)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await session.close()
    #expect(session.model.unifiedRows.isEmpty)
  }
}

extension ConversationJournalV3Tests {
  @Test func nestedQuestionReferenceCannotSmuggleOperationalProofs() throws {
    var page = try publicJournalV3Pages()[7]
    var row = (page["items"] as! [[String: Any]])[0]
    var outcome = row["outcome"] as! [String: Any]
    let reference = MealQuantityDisplay.reference(for: "leite")!
    var r =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference)) as! [String: Any]
    r["revision"] = 1
    outcome["observed_question"] = [
      "kind": "quantity", "food_index": 0, "food_name": "leite",
      "allowed_units": ["g", "kg", "mL", "L", "caneca"], "quantity_reference": r,
    ]
    row["outcome"] = outcome
    page["items"] = [row]
    #expect(throws: (any Error).self) { try decodePublicJournalV3(page) }
  }
  @Test(arguments: ["command_id", "epoch", "registration_id", "clock", "energy"])
  func historicalCommentaryBindsOnlyOwnedLineageExactFactsAndFullPrecision(_ attack: String) throws
  {
    var page = try publicJournalV3Pages()[3]
    var row = (page["items"] as! [[String: Any]])[0]
    var outcome = row["outcome"] as! [String: Any]
    var feedback = outcome["feedback"] as! [String: Any]
    if attack == "registration_id" {
      var original = feedback["original"] as! [String: Any]
      original["registration_id"] = UUID().uuidString.lowercased()
      feedback["original"] = original
    } else if attack == "energy" {
      var facts = feedback["recorded"] as! [String: Any]
      facts["estimated_kcal"] = NSNull()
      feedback["recorded"] = facts
    } else {
      var provenance = feedback["provenance"] as! [String: Any]
      if attack == "clock" {
        provenance["observed_at"] = "2026-11-05T05:12:16.874708Z"
        var policy = feedback["current_policy"] as! [String: Any]
        policy["observed_at"] = provenance["observed_at"]
        feedback["current_policy"] = policy
      } else {
        provenance[attack] = UUID().uuidString.lowercased()
      }
      feedback["provenance"] = provenance
    }
    outcome["feedback"] = feedback
    row["outcome"] = outcome
    page["items"] = [row]
    let parsed = try decodePublicJournalV3(page)
    let entry = parsed.items[0]
    #expect(entry.status == .registered)
    #expect(
      entry.feedback?.boundHistorical(
        entry, ownerID: parsed.ownerID, epoch: parsed.epoch, sessionGeneration: 7,
        pageObservedAt: parsed.observedAt) == nil)
  }
  @Test func journal3RequestCannotBecomePostOrRelaxOldVersionNegotiation() throws {
    let epoch = UUID()
    let owner = UUID()
    let headers = MobileConversationRequestHeaders.unifiedJournal(epoch: epoch, ownerID: owner)
    let good = [URLQueryItem(name: "version", value: "3"), .init(name: "limit", value: "10")]
    try headers.validate(
      method: .get, path: "/api/mobile/v1/conversation/journal", query: good, body: nil, key: nil,
      replay: .standard)
    #expect(!headers.supportsFeedbackPresentation)
    #expect(throws: (any Error).self) {
      try headers.validate(
        method: .post, path: "/api/mobile/v1/conversation/journal", query: good, body: Data(),
        key: nil, replay: .never)
    }
    for value in [
      MobileConversationRequestHeaders.journal(epoch: epoch, ownerID: owner),
      .threadJournal(epoch: epoch, ownerID: owner),
    ] {
      #expect(throws: (any Error).self) {
        try value.validate(
          method: .get, path: "/api/mobile/v1/conversation/journal", query: good, body: nil,
          key: nil, replay: .standard)
      }
    }
  }
}
@MainActor extension FlowConversationJournalV3RuntimeTests {
  @Test func byteShortPaginationUsesExactCursorAndKeepsPublicOrdering() async throws {
    let f = try await journalV3HTTPFixture(pageIndex: 2)
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    var first = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    var second = first
    let rows = first["items"] as! [[String: Any]]
    let cursor = try journalV3Cursor(page: first, row: rows[0])
    first["items"] = [rows[0]]
    first["has_more"] = true
    first["next_cursor"] = cursor
    second["items"] = Array(rows.dropFirst())
    second["has_more"] = false
    second["next_cursor"] = NSNull()
    let a = try neutralHTTP(first)
    let b = try neutralHTTP(second)
    await f.http.stub.respond { request, _ in
      let next = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first
      { $0.name == "cursor" }?.value
      return next == cursor ? b : a
    }
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 1 && session.model.hasMoreHistory)
    await session.model.loadHistory(reset: false)
    #expect(
      session.model.unifiedRows.count == 10 && !session.model.hasMoreHistory
        && !session.model.unifiedHistoryUnavailable)
    #expect(session.model.unifiedRows.map(\.eventID) == rows.map { $0["event_id"] as! String })
    #expect(session.model.savedEffectRevision == 0)
    await session.close()
  }
  @Test func historyCannotSettleSharedFiftyUnknownOriginalsEvenWithObservedIntakeID() async throws {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let key = try await f.vault.key(owner: owner, mayCreate: true)
    let page = try decodePublicJournalV3(
      JSONSerialization.jsonObject(with: f.page) as! [String: Any])
    try f.disk.store.update(owner: owner, key: key) { rows in
      for index in 0..<49 {
        let command = try ConversationMealCommand(
          source: .text("Preserved unknown original \(index)"))
        var entry = ConversationOutboxEntry(
          command: command, originalServerEpoch: page.epoch, originalPatientOwnerID: page.ownerID)
        entry.state = .dispatchedUnknown
        rows.append(entry)
      }
    }
    let input = try FlowNeutralIntakeInput(
      intakeID: page.items[0].intakeID!,
      source: .text("Encrypted original cannot be reconstructed from history"))
    try f.disk.store.updateIntakes(owner: owner, key: key) { rows in
      var entry = ConversationNeutralIntakeOutboxEntry(
        input: input, ownerID: page.ownerID, epoch: page.epoch)
      entry.state = .dispatchedUnknown
      rows.append(entry)
    }
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: owner))
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.count == 1)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: owner)) == before)
    #expect(try f.disk.store.load(owner: owner, key: key).count == 49)
    let remaining = try #require(f.disk.store.loadIntakes(owner: owner, key: key).first)
    #expect(
      remaining.state == .dispatchedUnknown && remaining.input.wireBody == input.wireBody
        && remaining.input.inputHash == input.inputHash)
    #expect(
      session.model.savedEffectRevision == 0
        && session.model.neutralIntake?.savedRows.isEmpty == true)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await session.close()
  }
}

@MainActor extension FlowConversationJournalV3RuntimeTests {
  @Test(arguments: ["auth_user_id", "owner_id", "observed_at"])
  func unownedOrOlderActualHTTPPageNeverPublishes(_ attack: String) async throws {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    var page = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    page[attack] =
      attack == "observed_at" ? "2026-11-05T05:12:15.999999Z" : UUID().uuidString.lowercased()
    let response = try neutralHTTP(page)
    await f.http.stub.respond { _, _ in response }
    await session.model.loadHistory()
    #expect(session.model.unifiedRows.isEmpty && session.model.unifiedHistoryUnavailable)
    #expect(session.model.savedEffectRevision == 0)
    await session.close()
  }
  @Test(arguments: ["cancel", "close", "account", "grant"])
  func lateActualHTTPReadCannotSurviveCancellationOrSessionChange(_ change: String) async throws {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    let response = try neutralHTTP(JSONSerialization.jsonObject(with: f.page))
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.url?.path == "/api/mobile/v1/conversation/journal" {
        await barrier.enter()
        return response
      }
      return f.mealSession
    }
    let pending = Task { await session.model.loadHistory() }
    #expect(await barrier.waitEnteredOrFinished())
    switch change {
    case "cancel": session.model.cancelTransientWork()
    case "close": await session.close()
    case "account":
      await f.http.lifecycle.replace(
        .init(
          userID: UUID().uuidString.lowercased(), generation: lease.generation + 1,
          bearer: "synthetic-next"))
    default: await session.model.refresh()
    }
    await barrier.release()
    await pending.value
    #expect(session.model.unifiedRows.isEmpty && session.model.savedEffectRevision == 0)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await session.close()
  }
}

@MainActor extension FlowConversationJournalV3RuntimeTests {
  @Test(arguments: ["reopen", "account", "epoch"])
  func genuineRAMReceiptKeepsOperationalIdentityButUsesFreshHistoricalPolicyOnly(_ end: String)
    async throws
  {
    let http = try ConversationHTTPFixture()
    let disk = try OutboxDiskFixture()
    let wire = try ConversationControllerWireFixture()
    defer { disk.remove() }
    let lease = await http.lifecycle.leaseForRequest()
    let owner = try ConversationOutboxOwner(lease: lease)
    let vault = ConversationOutboxKeyVault(
      service: "journal-v3-ack-unit", security: OutboxKeychainFake())
    let key = try await vault.key(owner: owner, mayCreate: true)
    try disk.store.update(owner: owner, key: key) { rows in
      var entry = ConversationOutboxEntry(
        command: wire.command, originalServerEpoch: wire.epoch, originalPatientOwnerID: wire.ownerID
      )
      entry.state = .dispatchedUnknown
      rows.append(entry)
    }
    let publicACK = try wire.savedReply()
    let mealSession = try wire.sessionReply()
    let packet = try JSONSerialization.jsonObject(with: publicACK.body) as! [String: Any]
    let ack = packet["data"] as! [String: Any]
    let receipt = ack["receipt"] as! [String: Any]
    var feedback = ack["feedback"] as! [String: Any]
    var policy = feedback["current_policy"] as! [String: Any]
    var hide = policy["hide"] as! [String: Any]
    var provenance = feedback["provenance"] as! [String: Any]
    hide["protein"] = true
    policy["hide"] = hide
    policy["observed_at"] = "2026-11-04T12:00:01.000001Z"
    feedback["current_policy"] = policy
    provenance["observed_at"] = policy["observed_at"]
    feedback["provenance"] = provenance
    feedback["sections"] = ["saved", "items", "summary", "day", "block", "education"].map {
      ["key": $0, "text": "Current policy hides protein: " + $0]
    }
    // Explicit UNIT projection from a genuine public v1 ACK fixture, using only
    // public journal fields. It is not a service/PG/live-session qualification.
    let eventID = "command/" + wire.command.commandID.uuidString.lowercased()
    let page: [String: Any] = [
      "schema": "conversation.journal-page.v3", "mode": "historical", "auth_user_id": lease.userID,
      "owner_id": wire.ownerID.uuidString.lowercased(), "epoch": wire.epoch.uuidString.lowercased(),
      "observed_at": "2026-11-04T12:00:02.000000Z", "has_more": false, "next_cursor": NSNull(),
      "items": [
        [
          "event_id": eventID, "at": "2026-11-03T10:00:00.000000Z",
          "thread_id": wire.command.commandID.uuidString.lowercased(), "kind": "report",
          "lineage": [
            "kind": "meal.report", "intake_id": NSNull(),
            "command_id": wire.command.commandID.uuidString.lowercased(),
            "parent_command_id": NSNull(), "origin_epoch": wire.epoch.uuidString.lowercased(),
          ], "input": ["channel": "text", "text": "Original controlled public meal"],
          "outcome": [
            "status": "registered",
            "record": [
              "kind": "meal", "registration_id": receipt["registration_id"]!,
              "meal_type": receipt["meal_type"]!, "local_date": receipt["local_date"]!,
              "log_ids": receipt["log_ids"]!, "effect_version": receipt["effect_version"]!,
            ], "feedback": feedback,
          ],
        ]
      ],
    ]
    let historyReply = try neutralHTTP(page)
    await http.stub.respond { request, _ in
      if request.url?.path == "/api/mobile/v1/conversation/session" { return mealSession }
      if request.url?.path == "/api/mobile/v1/conversation/journal" { return historyReply }
      return publicACK
    }
    let model = try await FlowConversationModel.open(
      transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: vault,
      historyVersion: .v3)
    await model.reconcile(commandID: wire.command.commandID)
    #expect(model.savedEffectRevision == 1 && model.savedRows.count == 1)
    let genuine = model.savedRows[0]
    #expect(genuine.feedback?.presentation.currentPolicy.hide.protein == false)
    await model.loadHistory()
    let operational = try #require(model.unifiedOperationalSavedRow(eventID: eventID))
    #expect(
      operational.command.wireBody == wire.command.wireBody
        && operational.command.inputHash == wire.command.inputHash)
    #expect(operational.receipt == genuine.receipt)
    #expect(operational.feedback?.presentation.currentPolicy.hide.protein == true)
    guard case .sections(_, let sections) = operational.feedback?.presentation.content else {
      Issue.record("Fresh historical sections required")
      return
    }
    #expect(sections.allSatisfy { $0.text.hasPrefix("Current policy hides protein:") })
    #expect(model.savedEffectRevision == 1 && model.savedRows.isEmpty)
    if end == "account" {
      await http.lifecycle.replace(
        .init(
          userID: UUID().uuidString.lowercased(), generation: lease.generation + 1,
          bearer: "synthetic-next"))
      #expect(
        model.unifiedOperationalSavedRow(eventID: eventID) == nil && model.unifiedRows.isEmpty)
      await model.close()
      return
    }
    if end == "epoch" {
      let resetSession = try wire.sessionReply(epoch: UUID())
      await http.stub.respond { _, _ in resetSession }
      await model.refresh()
      #expect(
        model.unifiedOperationalSavedRow(eventID: eventID) == nil && model.unifiedRows.isEmpty)
      #expect(model.savedEffectRevision == 1)
      await model.close()
      return
    }
    await model.close()
    #expect(model.unifiedOperationalSavedRow(eventID: eventID) == nil)
    let reopened = try await FlowConversationModel.open(
      transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: vault,
      historyVersion: .v3)
    await reopened.loadHistory()
    #expect(
      reopened.unifiedRows.count == 1
        && reopened.unifiedOperationalSavedRow(eventID: eventID) == nil)
    #expect(reopened.savedEffectRevision == 0)
    await http.lifecycle.replace(
      .init(
        userID: UUID().uuidString.lowercased(), generation: lease.generation + 1,
        bearer: "synthetic-next"))
    #expect(
      reopened.unifiedOperationalSavedRow(eventID: eventID) == nil && reopened.unifiedRows.isEmpty)
    await reopened.close()
    #expect(await http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
  }
}

@MainActor extension FlowConversationJournalV3RuntimeTests {
  @Test func refreshedCommentaryCannotBeBypassedByRetainingAnOlderHistoricalEntry() async throws {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    await session.model.loadHistory()
    let old = try #require(session.model.unifiedRows.first)
    #expect(session.model.unifiedHistory.feedback(for: old) != nil)
    var page = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    var row = (page["items"] as! [[String: Any]])[0]
    var outcome = row["outcome"] as! [String: Any]
    var feedback = outcome["feedback"] as! [String: Any]
    var policy = feedback["current_policy"] as! [String: Any]
    var provenance = feedback["provenance"] as! [String: Any]
    var sections = feedback["sections"] as! [[String: Any]]
    policy["observed_at"] = "2026-11-05T05:12:20.000001Z"
    provenance["observed_at"] = policy["observed_at"]
    sections[5]["text"] = "Current education was refreshed without changing the historical effect."
    feedback["current_policy"] = policy
    feedback["provenance"] = provenance
    feedback["sections"] = sections
    outcome["feedback"] = feedback
    row["outcome"] = outcome
    page["items"] = [row]
    page["observed_at"] = "2026-11-05T05:12:20.000002Z"
    let response = try neutralHTTP(page)
    await f.http.stub.respond { _, _ in response }
    await session.model.loadHistory()
    let current = try #require(session.model.unifiedRows.first)
    #expect(session.model.unifiedHistory.feedback(for: old) == nil)
    let shown = try #require(session.model.unifiedHistory.feedback(for: current))
    guard case .v3Sections(_, let actual) = shown.presentation.content else {
      Issue.record("Fresh commentary required")
      return
    }
    #expect(
      actual[5].text == "Current education was refreshed without changing the historical effect.")
    #expect(session.model.savedEffectRevision == 0)
    await session.close()
  }
}

@MainActor extension FlowConversationJournalV3RuntimeTests {
  @Test(arguments: ["meal:match", "meal:effect", "workout:match", "workout:clock"])
  func neutralRAMDedupeRequiresActualIntakeChildAndEveryRecordedFact(_ example: String) async throws
  {
    let kind = String(example.split(separator: ":")[0])
    let matching = example.hasSuffix("match")
    let f = try await neutralVisibleFixture(
      variant: kind == "meal" ? "meal_unit" : "workout_known_unit")
    defer { f.disk.remove() }
    let model = try await FlowConversationModel.open(
      transport: f.http.transport, lifecycle: f.http.lifecycle, store: f.disk.store,
      keyVault: f.vault, historyVersion: .v3, neutralIntakeEnabled: true)
    let neutral = try #require(model.neutralIntake)
    neutral.composer = kind == "meal" ? "leite integral 206 g" : "Fiz 30 minutos de caminhada."
    await neutral.submit()
    let row = try #require(neutral.savedRows.first)
    var record: [String: Any]
    switch row.acknowledgement {
    case .meal(let saved):
      record = [
        "kind": "meal", "registration_id": saved.receipt.registrationID,
        "meal_type": saved.receipt.mealType.rawValue, "local_date": saved.receipt.localDate,
        "log_ids": saved.receipt.logIDs,
        "effect_version": matching
          ? saved.receipt.effectVersion : "cmeal1:" + String(repeating: "d", count: 64),
      ]
    case .workout(let saved):
      let r = saved.registration
      let a = saved.activity
      record = [
        "kind": "workout",
        "registration": [
          "provenance": "conversation.workout.v1",
          "registration_id": r.registrationID.uuidString.lowercased(),
          "workout_id": r.workoutID.uuidString.lowercased(), "performed_at": r.performedAt,
          "local_date": r.localDate, "time_zone": r.timeZone,
          "committed_at": matching ? r.committedAt : "2026-11-06T11:00:00.000001Z",
          "effect_version": 1,
        ],
        "activity": [
          "kind": "workout", "log_id": a.logID.uuidString.lowercased(),
          "workout_type": a.workoutType, "duration_min": a.durationMin,
          "intensity": a.intensity as Any? ?? NSNull(),
          "estimated_kcal": a.estimatedKcal as Any? ?? NSNull(),
        ],
      ]
    }
    let input: [String: Any] = [
      "channel": "text",
      "text": kind == "meal" ? "leite integral 206 g" : "Fiz 30 minutos de caminhada.",
    ]
    let page: [String: Any] = [
      "schema": "conversation.journal-page.v3", "mode": "historical",
      "auth_user_id": row.identity.authUserID.uuidString.lowercased(),
      "owner_id": row.identity.ownerID.uuidString.lowercased(),
      "epoch": row.identity.epoch.uuidString.lowercased(),
      "observed_at": "2026-11-06T12:00:00.000000Z", "has_more": false, "next_cursor": NSNull(),
      "items": [
        [
          "event_id": "intake/" + row.id.uuidString.lowercased(),
          "at": "2026-11-03T00:00:00.000000Z", "thread_id": row.id.uuidString.lowercased(),
          "kind": "intake",
          "lineage": [
            "kind": "intake", "intake_id": row.id.uuidString.lowercased(),
            "command_id": row.childID.uuidString.lowercased(), "parent_command_id": NSNull(),
            "origin_epoch": row.identity.epoch.uuidString.lowercased(),
          ], "input": input,
          "outcome": ["status": "registered", "record": record, "feedback": NSNull()],
        ]
      ],
    ]
    let response = try neutralHTTP(page)
    await f.http.stub.respond { _, _ in response }
    await model.loadHistory()
    #expect(!model.unifiedHistoryUnavailable && model.unifiedRows.count == 1)
    #expect(model.unifiedSavedIntakeIDs.contains(row.id) == matching)
    #expect(neutral.savedRows.count == 1 && model.savedEffectRevision == 1)
    await model.close()
  }
}

extension ConversationJournalV3Tests {
  @Test(arguments: ["save_undone", "registration_undone"])
  func realPublicUndoLiteralsDecodeAndDisplayTheirActualMeaning(_ change: String) throws {
    var page = try journalV3EditPageUnit(change: change)
    var row = (page["items"] as! [[String: Any]])[0]
    var out = row["outcome"] as! [String: Any]
    var record = out["record"] as! [String: Any]
    let entry = try decodePublicJournalV3(page).items[0]
    #expect(
      FlowConversationJournalV3Presentation(entry: entry, english: true).title
        == (change == "save_undone" ? "Meal change undone" : "Meal registration undone"))
    #expect(
      FlowConversationJournalV3Presentation(entry: entry, english: false).title
        == (change == "save_undone"
          ? "Alteração de refeição desfeita" : "Registro de refeição desfeito"))
    record["change"] = "undone"
    out["record"] = record
    row["outcome"] = out
    page["items"] = [row]
    #expect(throws: (any Error).self) { try decodePublicJournalV3(page) }
  }
  @Test func registeredMealCannotExistBeforeItsActualIntakeChildWasAssigned() throws {
    var page = try publicJournalV3Pages()[1]
    var row = (page["items"] as! [[String: Any]])[0]
    var lineage = row["lineage"] as! [String: Any]
    lineage["command_id"] = NSNull()
    row["lineage"] = lineage
    page["items"] = [row]
    #expect(throws: (any Error).self) { try decodePublicJournalV3(page) }
  }
}
@MainActor extension FlowConversationJournalV3RuntimeTests {
  @Test func sameIntakeCanAdvanceRoutingThenAssignItsOneChildWithoutCreatingSavedEffect()
    async throws
  {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    let original = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    let row = (original["items"] as! [[String: Any]])[0]
    let child = (row["lineage"] as! [String: Any])["command_id"] as! String
    for (command, reason) in [
      (nil, "intake_pending"), (nil, "routing_reconciliation_required"),
      (Optional(child), "reconciliation_required"),
    ] {
      let pending = journalV3PendingUnit(original, child: command, reason: reason)
      try await useJournalV3Page(f, page: pending)
      await session.model.loadHistory()
      #expect(
        !session.model.unifiedHistoryUnavailable
          && session.model.unifiedRows.first?.reason == reason)
      #expect(session.model.unifiedRows.first?.commandID == command.flatMap(UUID.init(uuidString:)))
    }
    try await useJournalV3Page(f, page: original)
    await session.model.loadHistory()
    #expect(
      !session.model.unifiedHistoryUnavailable
        && session.model.unifiedRows.first?.status == .registered)
    var changed = original
    var changedRow = row
    var lineage = row["lineage"] as! [String: Any]
    var out = row["outcome"] as! [String: Any]
    var record = out["record"] as! [String: Any]
    var registration = record["registration"] as! [String: Any]
    let replacement = UUID().uuidString.lowercased()
    lineage["command_id"] = replacement
    registration["registration_id"] = replacement
    record["registration"] = registration
    out["record"] = record
    changedRow["lineage"] = lineage
    changedRow["outcome"] = out
    changed["items"] = [changedRow]
    try await useJournalV3Page(f, page: changed)
    await session.model.loadHistory()
    #expect(
      session.model.unifiedHistoryUnavailable
        && session.model.unifiedRows.first?.commandID == UUID(uuidString: child))
    #expect(session.model.savedEffectRevision == 0)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await session.close()
  }
  @Test func currentObservedQuestionCanChangeAndDisappearWhileOriginalDecisionRemainsNotRecorded()
    async throws
  {
    let f = try await journalV3HTTPFixture(pageIndex: 2)
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    var page = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    let all = page["items"] as! [[String: Any]]
    var report = all.first { $0["kind"] as? String == "report" }!
    var outcome = report["outcome"] as! [String: Any]
    page["items"] = [report]
    try await useJournalV3Page(f, page: page)
    await session.model.loadHistory()
    #expect(!session.model.unifiedHistoryUnavailable)
    outcome["observed_question"] =
      (all.first { $0["kind"] as? String == "reply" }!["outcome"] as! [String: Any])[
        "observed_question"]!
    report["outcome"] = outcome
    page["items"] = [report]
    try await useJournalV3Page(f, page: page)
    await session.model.loadHistory()
    #expect(
      !session.model.unifiedHistoryUnavailable && session.model.unifiedRows.first?.question != nil)
    outcome.removeValue(forKey: "observed_question")
    report["outcome"] = outcome
    page["items"] = [report]
    try await useJournalV3Page(f, page: page)
    await session.model.loadHistory()
    #expect(
      !session.model.unifiedHistoryUnavailable && session.model.unifiedRows.first?.question == nil)
    #expect(
      session.model.unifiedRows.first?.status == .notRecorded
        && session.model.savedEffectRevision == 0)
    await session.close()
  }
  @Test(arguments: ["restrictive", "absent", "after_failure"])
  func olderPageCommentaryIsNotReauthorizedByNewerReadUnderChangedPolicy(_ scenario: String)
    async throws
  {
    let f = try await journalV3HTTPFixture()
    defer { f.disk.remove() }
    let lease = await f.http.lifecycle.leaseForRequest()
    let session = try await FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil, store: f.disk.store,
      keyVault: f.vault, neutralIntakeEnabled: true
    ).open(expectedUserID: lease.userID)
    var first = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    var original = (first["items"] as! [[String: Any]])[0]
    var out = original["outcome"] as! [String: Any]
    var feedback = out["feedback"] as! [String: Any]
    var policy = feedback["current_policy"] as! [String: Any]
    policy["assessment"] = "complete"
    policy["target_source"] = "assigned_phase"
    policy["hide"] = [
      "objective": false, "calories": false, "protein": false, "balance": false, "block": false,
      "budget": false,
    ]
    feedback["current_policy"] = policy
    out["feedback"] = feedback
    original["outcome"] = out
    first["items"] = [original]
    first["has_more"] = true
    first["next_cursor"] = try journalV3Cursor(page: first, row: original)
    try await useJournalV3Page(f, page: first)
    await session.model.loadHistory()
    let old = try #require(session.model.unifiedRows.first)
    #expect(session.model.unifiedHistory.feedback(for: old)?.presentation.isRestricted == false)
    if scenario == "after_failure" {
      await f.http.stub.respond { _, _ in .failure(503, "conversation_journal_unavailable") }
      await session.model.loadHistory()
      #expect(
        session.model.unifiedHistoryUnavailable
          && session.model.unifiedHistory.feedback(for: old) == nil)
    }
    // Explicit independent synthetic public entry, with no write/ACK proof.
    var second = try JSONSerialization.jsonObject(with: f.page) as! [String: Any]
    var older = (second["items"] as! [[String: Any]])[0]
    var lineage = older["lineage"] as! [String: Any]
    var olderOut = older["outcome"] as! [String: Any]
    var record = olderOut["record"] as! [String: Any]
    var registration = record["registration"] as! [String: Any]
    var activity = record["activity"] as! [String: Any]
    var freshFeedback = olderOut["feedback"] as! [String: Any]
    var identity = freshFeedback["original"] as! [String: Any]
    var provenance = freshFeedback["provenance"] as! [String: Any]
    var facts = freshFeedback["recorded"] as! [String: Any]
    var freshPolicy = freshFeedback["current_policy"] as! [String: Any]
    let intakeID = UUID().uuidString.lowercased()
    let commandID = UUID().uuidString.lowercased()
    let logID = UUID().uuidString.lowercased()
    older["event_id"] = "intake/" + intakeID
    older["thread_id"] = intakeID
    older["at"] = "2026-11-05T05:12:16.000001Z"
    lineage["intake_id"] = intakeID
    lineage["command_id"] = commandID
    older["lineage"] = lineage
    registration["registration_id"] = commandID
    registration["workout_id"] = logID
    activity["log_id"] = logID
    record["registration"] = registration
    record["activity"] = activity
    olderOut["record"] = record
    identity["registration_id"] = commandID
    provenance["command_id"] = commandID
    provenance["observed_at"] = "2026-11-05T05:12:20.000001Z"
    freshPolicy["observed_at"] = provenance["observed_at"]
    facts["log_id"] = logID
    freshFeedback["original"] = identity
    freshFeedback["provenance"] = provenance
    freshFeedback["current_policy"] = freshPolicy
    freshFeedback["recorded"] = facts
    olderOut["feedback"] = scenario == "absent" ? NSNull() : freshFeedback
    older["outcome"] = olderOut
    second["items"] = [older]
    second["observed_at"] = "2026-11-05T05:12:20.000002Z"
    try await useJournalV3Page(f, page: second)
    await session.model.loadHistory(reset: false)
    #expect(!session.model.unifiedHistoryUnavailable && session.model.unifiedRows.count == 2)
    #expect(session.model.unifiedHistory.feedback(for: old) == nil)
    let current = try #require(session.model.unifiedRows.last)
    if scenario == "absent" {
      #expect(session.model.unifiedHistory.feedback(for: current) == nil)
    } else {
      #expect(
        session.model.unifiedHistory.feedback(for: current)?.presentation.isRestricted == true)
    }
    #expect(session.model.savedEffectRevision == 0)
    await session.close()
  }
}
func journalV3PendingUnit(_ original: [String: Any], child: String?, reason: String) -> [String:
  Any]
{
  var page = original
  var row = (original["items"] as! [[String: Any]])[0]
  var lineage = row["lineage"] as! [String: Any]
  lineage["command_id"] = child as Any? ?? NSNull()
  row["lineage"] = lineage
  row["outcome"] = ["status": "pending", "reason": reason, "feedback": NSNull()]
  page["items"] = [row]
  return page
}
@MainActor func useJournalV3Page(_ f: JournalV3HTTPFixture, page: [String: Any]) async throws {
  let response = try neutralHTTP(page)
  await f.http.stub.respond { _, _ in response }
}

func journalV3EditPageUnit(change: String) throws -> [String: Any] {
  var page = try publicJournalV3Pages()[2]
  var row = (page["items"] as! [[String: Any]]).first { $0["kind"] as? String == "edit" }!
  var outcome = row["outcome"] as! [String: Any]
  var record = outcome["record"] as! [String: Any]
  record["change"] = change
  if change == "save_undone" {
    record["revision"] = 2
    record["target_operation_id"] = "c1450000-0000-4000-8000-000000000099"
  }
  if change == "registration_undone" {
    record["new_item_ids"] = [String]()
    record["next_record_id"] = NSNull()
  }
  outcome["record"] = record
  row["outcome"] = outcome
  page["items"] = [row]
  return page
}
extension ConversationJournalV3Tests {
  @Test(arguments: [
    "saveTarget", "selfTarget", "revision", "restoreCount", "nextID", "removeOverlap",
    "registrationNew", "registrationTarget", "savedTarget",
  ])
  func publicEditHistoryRejectsContradictoryFactualRelationships(_ attack: String) throws {
    let change =
      attack.hasPrefix("registration")
      ? "registration_undone" : attack == "savedTarget" ? "saved" : "save_undone"
    var page = try journalV3EditPageUnit(change: change)
    var row = (page["items"] as! [[String: Any]])[0]
    var outcome = row["outcome"] as! [String: Any]
    var record = outcome["record"] as! [String: Any]
    switch attack {
    case "saveTarget": record["target_operation_id"] = NSNull()
    case "selfTarget": record["target_operation_id"] = record["operation_id"]
    case "revision": record["revision"] = 1
    case "restoreCount":
      record["new_item_ids"] = [String]()
      record["next_record_id"] = NSNull()
    case "nextID": record["next_record_id"] = UUID().uuidString.lowercased()
    case "removeOverlap": record["removed_item_ids"] = record["new_item_ids"]
    case "registrationNew": record["new_item_ids"] = [UUID().uuidString.lowercased()]
    default: record["target_operation_id"] = UUID().uuidString.lowercased()
    }
    outcome["record"] = record
    row["outcome"] = outcome
    page["items"] = [row]
    #expect(throws: (any Error).self) { try decodePublicJournalV3(page) }
  }
}
