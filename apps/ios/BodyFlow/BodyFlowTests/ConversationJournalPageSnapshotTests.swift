import Foundation
import Testing

@testable import BodyFlow

@Suite("Closed immutable conversation journal pages")
struct ConversationJournalPageSnapshotTests {
  @Test func exactServerFixtureKeepsAllKindsAndOpaqueProof() throws {
    let envelope = try decode(ConversationJournalPageSnapshot.Envelope.self, fixtureEnvelope())
    let page = envelope.data
    #expect(page.authUserID != page.ownerID)
    #expect(page.matches(authUserID: page.authUserID, ownerID: page.ownerID, epoch: page.epoch))
    #expect(!page.matches(authUserID: UUID(), ownerID: page.ownerID, epoch: page.epoch))
    #expect(page.items.count == 4 && !page.hasMore && page.nextCursor == nil)
    guard case .edit(let edit) = page.items[0], case .command(let terminal) = page.items[1],
      case .command(let pending) = page.items[2], case .command(let saved) = page.items[3]
    else {
      Issue.record("All actual entry types required")
      return
    }
    #expect(edit.result.receipt.operationInputHash == String(repeating: "e", count: 64))
    #expect(terminal.terminalReceipt?.decisionHash == String(repeating: "d", count: 64))
    #expect(terminal.terminalReceipt?.sealedAt == "2026-11-04T12:01:00.000004Z")
    #expect(pending.terminalReceipt == nil && saved.terminalReceipt == nil)
    #expect(
      terminal.originalCommand.commandID.uuidString.lowercased()
        == "10000000-0000-4000-8000-000000000009")
    guard case .state(let state) = terminal.result else {
      Issue.record("Terminal state required")
      return
    }
    #expect(terminal.terminalReceipt?.matches(state: state) == true)
  }
  @Test func recordedHttpSevenPagesReplayNineteenEventsWithoutInventedBindings() throws {
    let fixture = try object("ConversationJournalHTTPFixtures")
    let pages = try #require(fixture["pages"] as? [[String: Any]])
    #expect(pages.count == 7)
    var entries: [ConversationJournalPageSnapshot.Entry] = []
    for raw in pages {
      let page = try decode(ConversationJournalPageSnapshot.Envelope.self, raw).data
      #expect(page.authUserID.uuidString.lowercased() == fixture["auth_user_id"] as? String)
      entries += page.items
    }
    #expect(entries.count == 19 && Set(entries.map(\.eventID)).count == 19)
    for (left, right) in zip(entries, entries.dropFirst()) {
      let l = try #require(ConversationProtocolInstant(left.at))
      let r = try #require(ConversationProtocolInstant(right.at))
      #expect(l > r || (l == r && right.eventID.utf8.lexicographicallyPrecedes(left.eventID.utf8)))
    }
  }
  @Test(
    "closed page rejects intrinsic scope, ordering and source changes",
    arguments: [
      "extra", "private", "schema", "auth", "owner", "epoch", "observed", "future", "items-many",
      "items-duplicate", "wrong-order", "entry-extra", "entry-kind", "entry-id", "source-extra",
      "source-text", "source-meal", "source-command", "source-asset", "original-hash",
      "result-owner", "result-epoch", "result-absent", "saved-admission", "saved-selected-meal",
      "saved-terminal", "pending-terminal", "terminal-null", "terminal-extra", "terminal-schema",
      "terminal-status", "terminal-owner", "terminal-command", "terminal-hash", "terminal-epoch",
      "terminal-reason", "terminal-index", "terminal-index-order", "terminal-index-duplicate",
      "terminal-index-bool", "terminal-decision", "terminal-before", "terminal-future", "edit-id",
      "edit-at", "edit-owner", "edit-epoch", "edit-private", "hasmore-no-cursor",
      "cursor-without-more", "cursor-empty", "cursor-long",
    ]) func rejectsPage(_ attack: String) throws
  {
    var p = try page()
    switch attack {
    case "extra": p["unknown"] = true
    case "private": p["current_policy"] = ["hide": false]
    case "schema": p["schema"] = "conversation.journal-page.v2"
    case "auth": p["auth_user_id"] = NSNull()
    case "owner": p["owner_id"] = UUID().uuidString.lowercased()
    case "epoch": p["epoch"] = UUID().uuidString.lowercased()
    case "observed": p["observed_at"] = "2026-02-30T12:03:00Z"
    case "future": p["observed_at"] = "2026-11-04T12:00:00.000000Z"
    case "items-many": p["items"] = Array(repeating: try entry(0), count: 26)
    case "items-duplicate": p["items"] = [try entry(0), try entry(0)]
    case "wrong-order": p["items"] = Array((try #require(p["items"] as? [Any])).reversed())
    case "entry-extra": try put(&p, ["items", "0", "snapshot"], ["private": true])
    case "entry-kind": try put(&p, ["items", "0", "kind"], "workout")
    case "entry-id":
      try put(&p, ["items", "2", "event_id"], "command/" + UUID().uuidString.lowercased())
    case "source-extra":
      try put(&p, ["items", "2", "original_command", "source", "url"], "https://private.invalid")
    case "source-text":
      try put(&p, ["items", "2", "original_command", "source", "text"], "Comi feijao")
    case "source-meal": try put(&p, ["items", "2", "original_command", "meal_type"], "jantar")
    case "source-command":
      try put(&p, ["items", "2", "original_command", "command_id"], UUID().uuidString.lowercased())
    case "source-asset":
      try put(
        &p, ["items", "2", "original_command", "source"],
        [
          "channel": "media", "media_asset_id": UUID().uuidString.lowercased(),
          "user_action": "analyze",
        ])
    case "original-hash":
      try put(&p, ["items", "2", "result", "input_hash"], String(repeating: "f", count: 64))
    case "result-owner":
      try put(&p, ["items", "2", "result", "owner_id"], UUID().uuidString.lowercased())
    case "result-epoch":
      try put(&p, ["items", "2", "result", "epoch"], UUID().uuidString.lowercased())
    case "result-absent": try put(&p, ["items", "2", "result", "status"], "absent")
    case "saved-admission":
      try put(&p, ["items", "3", "result", "admitted_at"], "2026-11-04T12:00:00.000002Z")
    case "saved-selected-meal":
      try put(&p, ["items", "3", "result", "receipt", "meal_type"], "jantar")
    case "saved-terminal": try put(&p, ["items", "3", "terminal_receipt"], try terminal())
    case "pending-terminal": try put(&p, ["items", "2", "terminal_receipt"], try terminal())
    case "terminal-null": try put(&p, ["items", "1", "terminal_receipt"], NSNull())
    case "terminal-extra":
      try put(
        &p, ["items", "1", "terminal_receipt", "source_hash"], String(repeating: "a", count: 64))
    case "terminal-schema":
      try put(&p, ["items", "1", "terminal_receipt", "schema"], "conversation.meal-decision.v1")
    case "terminal-status": try put(&p, ["items", "1", "terminal_receipt", "status"], "saved")
    case "terminal-owner":
      try put(&p, ["items", "1", "terminal_receipt", "owner_id"], UUID().uuidString.lowercased())
    case "terminal-command":
      try put(&p, ["items", "1", "terminal_receipt", "command_id"], UUID().uuidString.lowercased())
    case "terminal-hash":
      try put(
        &p, ["items", "1", "terminal_receipt", "input_hash"], String(repeating: "f", count: 64))
    case "terminal-epoch":
      try put(&p, ["items", "1", "terminal_receipt", "epoch"], UUID().uuidString.lowercased())
    case "terminal-reason": try put(&p, ["items", "1", "terminal_receipt", "reason"], "future")
    case "terminal-index": try put(&p, ["items", "1", "terminal_receipt", "food_indexes"], [30])
    case "terminal-index-order":
      try put(&p, ["items", "1", "terminal_receipt", "food_indexes"], [1, 0])
    case "terminal-index-duplicate":
      try put(&p, ["items", "1", "terminal_receipt", "food_indexes"], [0, 0])
    case "terminal-index-bool":
      try put(&p, ["items", "1", "terminal_receipt", "food_indexes"], [true])
    case "terminal-decision":
      try put(&p, ["items", "1", "terminal_receipt", "decision_hash"], "bad")
    case "terminal-before":
      try put(
        &p, ["items", "1", "terminal_receipt", "sealed_at"], "2026-11-04T12:00:00.000002999Z")
    case "terminal-future":
      try put(
        &p, ["items", "1", "terminal_receipt", "sealed_at"], "2026-11-04T12:03:00.000001001Z")
    case "edit-id":
      try put(
        &p, ["items", "0", "event_id"],
        "edit/" + UUID().uuidString.lowercased() + "/10000000-0000-4000-8000-000000000080")
    case "edit-at": try put(&p, ["items", "0", "at"], "2026-11-04T12:01:00.123456001Z")
    case "edit-owner":
      try put(&p, ["items", "0", "result", "owner_id"], UUID().uuidString.lowercased())
    case "edit-epoch":
      try put(&p, ["items", "0", "result", "epoch"], UUID().uuidString.lowercased())
    case "edit-private":
      try put(&p, ["items", "0", "result", "receipt", "snapshot"], ["daily_balance": 0])
    case "hasmore-no-cursor": p["has_more"] = true
    case "cursor-without-more": p["next_cursor"] = "opaque"
    case "cursor-empty":
      p["has_more"] = true
      p["next_cursor"] = ""
    case "cursor-long":
      p["has_more"] = true
      p["next_cursor"] = String(repeating: "a", count: 1025)
    default: Issue.record("Unknown attack")
    }
    #expect(throws: (any Error).self) { try decode(ConversationJournalPageSnapshot.self, p) }
  }
  @Test func opaqueCursorIsNotReconstructedOrUsedAsWriteAuthority() throws {
    var p = try page()
    p["has_more"] = true
    p["next_cursor"] = "opaque-token-kept-byte-for-byte"
    let v = try decode(ConversationJournalPageSnapshot.self, p)
    #expect(v.nextCursor == p["next_cursor"] as? String)
    p["items"] = [] as [Any]
    #expect(throws: (any Error).self) { try decode(ConversationJournalPageSnapshot.self, p) }
    p["has_more"] = false
    p["next_cursor"] = NSNull()
    #expect(try decode(ConversationJournalPageSnapshot.self, p).items.isEmpty)
  }
  @Test func serverOrderKeepsTieIDsAndAllowsSameOperationAcrossCommands() throws {
    var p = try page()
    var a = try entry(0)
    var b = a
    let old = "10000000-0000-4000-8000-000000000002"
    let new = "10000000-0000-4000-8000-000000000003"
    b["event_id"] = "edit/\(new)/10000000-0000-4000-8000-000000000080"
    try put(&b, ["result", "command_id"], new)
    try put(&b, ["result", "receipt", "command_id"], new)
    p["items"] = [b, a]
    #expect(try decode(ConversationJournalPageSnapshot.self, p).items.count == 2)
    p["items"] = [a, b]
    #expect(throws: (any Error).self) { try decode(ConversationJournalPageSnapshot.self, p) }
    a["event_id"] = "edit/\(old)/10000000-0000-4000-8000-000000000080"
  }
  @Test func originalMediaSourceIsCanonicalAndNeverInventsTranscript() throws {
    var p = try page()
    var e = try entry(2)
    let command = try ConversationMealCommand(
      commandID: UUID(uuidString: "10000000-0000-4000-8000-000000000008")!,
      source: .media(
        assetID: UUID(uuidString: "10000000-0000-4000-8000-000000000090")!,
        caption: "cafe/é e\u{301}"), mealType: .cafe)
    e["original_command"] = try JSONSerialization.jsonObject(with: command.wireBody)
    try put(&e, ["result", "input_hash"], command.inputHash)
    p["items"] = [e]
    let value = try decode(ConversationJournalPageSnapshot.self, p)
    guard case .command(let row) = value.items[0] else {
      Issue.record("Command required")
      return
    }
    #expect(row.originalCommand.wireBody == command.wireBody)
    #expect(row.originalCommand.inputHash == command.inputHash)
  }
  @Test(
    "complete envelope is closed",
    arguments: ["extra", "meta-extra", "meta-version", "meta-null", "meta-request", "missing-data"])
  func rejectsEnvelope(_ attack: String) throws {
    var envelope = try fixtureEnvelope()
    switch attack {
    case "extra": envelope["private"] = true
    case "meta-extra": try put(&envelope, ["meta", "debug"], "private")
    case "meta-version": try put(&envelope, ["meta", "api_version"], "v2")
    case "meta-null": envelope["meta"] = NSNull()
    case "meta-request": try put(&envelope, ["meta", "request_id"], 1)
    default: envelope.removeValue(forKey: "data")
    }
    #expect(throws: (any Error).self) {
      try decode(ConversationJournalPageSnapshot.Envelope.self, envelope)
    }
  }
  @Test func exactUtf8DataAndEnvelopeByteCapsApplyBeforeOptionalFeedbackIsDropped() throws {
    var p = try page()
    try put(&p, ["items", "3", "result", "feedback"], ["padding": ""])
    let base = try bytes(p).count
    try put(
      &p, ["items", "3", "result", "feedback"],
      ["padding": String(repeating: "x", count: 240000 - base)])
    let exact = try bytes(p)
    #expect(exact.count == 240000)
    _ = try ConversationJournalPageSnapshot(data: exact)
    try put(
      &p, ["items", "3", "result", "feedback"],
      ["padding": String(repeating: "x", count: 240001 - base)])
    #expect(throws: (any Error).self) { try ConversationJournalPageSnapshot(data: bytes(p)) }
    let normal = try bytes(fixtureEnvelope())
    let wire = normal + Data(repeating: 32, count: 262144 - normal.count)
    #expect(wire.count == 262144)
    _ = try ConversationJournalPageSnapshot.Envelope(data: wire)
    #expect(throws: (any Error).self) {
      try ConversationJournalPageSnapshot.Envelope(data: wire + Data([32]))
    }
  }
  @Test func equivalentAdmissionOffsetsPreserveLiteralsWithoutReorderingServerTime() throws {
    var p = try page()
    try put(&p, ["items", "3", "result", "admitted_at"], "2026-11-04T12:00:00.000001+00:00")
    let decoded = try decode(ConversationJournalPageSnapshot.self, p)
    guard case .command(let entry) = decoded.items[3], case .saved(let result) = entry.result else {
      Issue.record("Saved command required")
      return
    }
    #expect(entry.at == "2026-11-04T12:00:00.000001Z")
    #expect(result.admittedAt == "2026-11-04T12:00:00.000001+00:00")
  }
  @Test func multibyteOverflowUsesBytesRatherThanCharacterCount() throws {
    var p = try page()
    try put(
      &p, ["items", "3", "result", "feedback"], ["padding": String(repeating: "é", count: 120000)])
    let wire = try bytes(p)
    #expect(wire.count > 240000)
    #expect(try #require(String(data: wire, encoding: .utf8)).utf16.count < 240000)
    #expect(throws: (any Error).self) { try ConversationJournalPageSnapshot(data: wire) }
  }
  private func object(_ name: String) throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/\(name).json")
    #endif
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  private func fixtureEnvelope() throws -> [String: Any] {
    try object("ConversationJournalPublicFixtures")
  }
  private func page() throws -> [String: Any] {
    try #require(fixtureEnvelope()["data"] as? [String: Any])
  }
  private func entry(_ index: Int) throws -> [String: Any] {
    try #require((page()["items"] as? [[String: Any]])?[index])
  }
  private func terminal() throws -> [String: Any] {
    try #require(entry(1)["terminal_receipt"] as? [String: Any])
  }
  private func bytes(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
  }
  private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    try JSONDecoder().decode(type, from: bytes(object))
  }
  private func put(_ p: inout [String: Any], _ path: [String], _ value: Any) throws {
    func update(_ original: Any, _ path: ArraySlice<String>) throws -> Any {
      guard let key = path.first else { return value }
      if var array = original as? [Any], let n = Int(key) {
        array[n] = try update(array[n], path.dropFirst())
        return array
      }
      var object = try #require(original as? [String: Any])
      object[key] = try update(object[key] ?? [:], path.dropFirst())
      return object
    }
    p = try #require(update(p, path[...]) as? [String: Any])
  }
}
