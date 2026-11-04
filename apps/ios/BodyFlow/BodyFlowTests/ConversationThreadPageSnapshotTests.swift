import Foundation
import Testing

@testable import BodyFlow

@Suite("Actual closed linked Flow history")
struct ConversationThreadPageSnapshotTests {
  @Test func knownWholeNameCannotLoseItsApprovedReferenceButUnknownFoodKeepsGrams() throws {
    for name in ["leite", "whey", "fruta sem referência de porção"] {
      var page = try pageObject()
      try put(&page, ["items", "3", "question", "food_name"], name)
      try put(&page, ["items", "3", "question", "quantity_reference"], NSNull())
      try put(&page, ["items", "3", "question", "allowed_units"], ["g", "kg"])
      try put(&page, ["items", "3", "body", "answer", "unit"], "g")
      if name == "leite" || name == "whey" {
        #expect(throws: (any Error).self) { try ConversationThreadPageSnapshot(data: bytes(page)) }
      } else {
        let value = try ConversationThreadPageSnapshot(data: bytes(page))
        guard case .reply(let reply) = value.items[3].detail else {
          Issue.record("Actual reply variant required")
          return
        }
        #expect(reply.question.foodName == name && reply.question.quantityReference == nil)
        #expect(reply.question.allowedUnits == ["g", "kg"])
      }
    }
  }

  @Test func actualSDKLinkedPiecesBindTheDistinctRegistrationIDWithoutInventingAPage() throws {
    // This coherent SDK artifact is not a journal page or an Auth capability.
    // Decode only its actual closed pieces; never synthesize missing events.
    let raw = try sdkPieces()
    let child = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self, from: bytes(#require(raw["childBinding"])))
    let parent = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.Binding.self, from: bytes(#require(raw["parentBinding"])))
    let receipt = try JSONDecoder().decode(
      ConversationThreadPageSnapshot.LinkedReceipt.self, from: bytes(#require(raw["receipt"])))
    let presentation = try JSONDecoder().decode(
      ConversationFeedbackPresentationSnapshot.self, from: bytes(#require(raw["presentation"])))
    #expect(receipt.registrationID != child.commandID)
    let decisionHash = try #require(raw["parentDecisionHash"] as? String)
    #expect(receipt.matches(child: child, parent: parent, decisionHash: decisionHash))
    let scope = ConversationFeedbackPresentationSnapshot.Scope(
      ownerID: child.ownerID.uuidString.lowercased(), sessionGeneration: 7,
      epoch: child.epoch.uuidString.lowercased())
    let bound = try #require(receipt.boundFeedback(presentation, binding: child, scope: scope))
    #expect(
      bound.presentation.original.registrationID == receipt.registrationID.uuidString.lowercased())
    guard case .sections(let recorded, let sections) = bound.presentation.content else {
      Issue.record("Actual six sections required")
      return
    }
    #expect(
      sections.count == 6
        && Set(recorded.items.map(\.logID))
          == Set(receipt.logIDs.map { $0.uuidString.lowercased() })
    )
    #expect(recorded.totals.kcal == 128.3)
    let wrong = ConversationFeedbackPresentationSnapshot.Scope(
      ownerID: UUID().uuidString.lowercased(), sessionGeneration: 7, epoch: scope.epoch)
    #expect(receipt.boundFeedback(presentation, binding: child, scope: wrong) == nil)
  }

  @Test func actualProjectorFixturePreservesFiveKindsAndDistinctOriginalAndLinkedEffect() throws {
    let page = try ConversationThreadPageSnapshot(data: bytes(pageObject()))
    #expect(page.authUserID != page.ownerID)
    #expect(page.threads.count == 1 && page.items.count == 5)
    let thread = try #require(page.threads.first)
    #expect(thread.terminalReceipt?.reason == "missing_quantity")
    #expect(thread.continuation?.fulfilledBy != thread.threadID)
    guard case .text(let originalText) = thread.originalCommand.source else {
      Issue.record("Actual original text source required")
      return
    }
    #expect(originalText == "Comi leite")
    guard case .fulfillment(let linked) = page.items[1].detail,
      case .reply(let reply) = page.items[3].detail,
      case .report(let report) = page.items[4].detail
    else {
      Issue.record("Actual variants required")
      return
    }
    #expect(report.status == .notRecorded && report.receipt == nil)
    #expect(linked.receipt.commandID == thread.continuation?.fulfilledBy)
    #expect(linked.receipt.parentCommandID == thread.threadID)
    #expect(linked.binding.commandProtocol == "conversation.clarification.v1")
    #expect(linked.receipt.providerKey.hasSuffix(thread.threadID.uuidString.lowercased()))
    #expect(reply.question.foodName == "leite")
    #expect(reply.question.allowedUnits == ["g", "kg", "mL", "L", "caneca"])
    #expect(reply.body.questionKey == reply.question.questionKey)
    #expect(page.items[0].at == "2026-11-04T12:00:04.123456Z")
    #expect(page.matches(authUserID: page.authUserID, ownerID: page.ownerID, epoch: page.epoch))
    #expect(!page.matches(authUserID: UUID(), ownerID: page.ownerID, epoch: page.epoch))
  }

  @Test(arguments: [
    "top-private", "thread-private", "event-private", "wrong-schema", "duplicate-parent",
    "unused-parent", "missing-parent", "wrong-parent-hash", "foreign-owner", "epoch",
    "parent-protocol", "child-protocol", "child-is-parent", "child-hash-drift",
    "child-other-thread",
    "clock-no-micros", "future", "order", "duplicate-event", "report-status", "report-receipt",
    "negative-missing-proof", "negative-hash", "negative-clock", "head-revision", "head-fulfilled",
    "question-unknown", "question-reference", "reply-key", "reply-revision", "reply-food",
    "reply-unit", "reply-amount", "reply-extra", "result-status", "result-hash", "result-clock",
    "linked-schema", "linked-owner", "linked-command", "linked-parent", "linked-decision",
    "linked-provider", "linked-epoch", "linked-logs", "linked-date", "linked-meal",
    "edit-binding", "edit-extra", "edit-op-hash", "edit-time", "hasmore", "cursor-empty",
    "cursor-private",
  ]) func malformedWholeGraphIsUnavailable(_ attack: String) throws {
    var p = try pageObject()
    switch attack {
    case "top-private": p["source"] = ["clinical": true]
    case "thread-private": try put(&p, ["threads", "0", "context"], ["owner": true])
    case "event-private": try put(&p, ["items", "0", "snapshot"], ["balance": 12])
    case "wrong-schema": p["schema"] = "conversation.journal-page.v1"
    case "duplicate-parent":
      p["threads"] = try #require(p["threads"] as? [Any]) + #require(p["threads"] as? [Any])
    case "unused-parent":
      var parent = try #require((p["threads"] as? [[String: Any]])?.first)
      parent["thread_id"] = UUID().uuidString.lowercased()
      p["threads"] = try #require(p["threads"] as? [Any]) + [parent]
    case "missing-parent": p["threads"] = []
    case "wrong-parent-hash":
      try put(&p, ["threads", "0", "parent_binding", "input_hash"], hash("a"))
    case "foreign-owner": p["owner_id"] = UUID().uuidString.lowercased()
    case "epoch": p["epoch"] = UUID().uuidString.lowercased()
    case "parent-protocol":
      try put(
        &p, ["threads", "0", "parent_binding", "command_protocol"], "conversation.clarification.v1")
    case "child-protocol":
      try put(&p, ["items", "1", "child_binding", "command_protocol"], "conversation.command.v1")
    case "child-is-parent":
      try put(
        &p, ["items", "1", "child_binding", "command_id"], "10000000-0000-4000-8000-000000000002")
    case "child-hash-drift": try put(&p, ["items", "3", "child_binding", "input_hash"], hash("a"))
    case "child-other-thread":
      try put(&p, ["items", "3", "thread_id"], UUID().uuidString.lowercased())
    case "clock-no-micros": p["observed_at"] = "2026-11-04T12:03:00Z"
    case "future": p["observed_at"] = "2026-11-04T11:59:59.000001Z"
    case "order": p["items"] = try #require(p["items"] as? [Any]).reversed().map { $0 }
    case "duplicate-event":
      var events = try #require(p["items"] as? [Any])
      events[1] = events[0]
      p["items"] = events
    case "report-status": try put(&p, ["items", "4", "status"], "registered")
    case "report-receipt": try put(&p, ["items", "4", "receipt"], [:])
    case "negative-missing-proof": try put(&p, ["threads", "0", "terminal_receipt"], NSNull())
    case "negative-hash":
      try put(&p, ["threads", "0", "terminal_receipt", "input_hash"], hash("a"))
    case "negative-clock":
      try put(&p, ["threads", "0", "terminal_receipt", "sealed_at"], "2026-11-04T11:00:00.000001Z")
    case "head-revision": try put(&p, ["threads", "0", "continuation", "revision"], 32)
    case "head-fulfilled":
      try put(&p, ["threads", "0", "continuation", "fulfilled_by"], UUID().uuidString.lowercased())
    case "question-unknown": try put(&p, ["items", "3", "question", "clinical"], true)
    case "question-reference":
      try put(&p, ["items", "3", "question", "quantity_reference", "grams_per_unit"], 200)
    case "reply-key": try put(&p, ["items", "3", "body", "question_key"], hash("a"))
    case "reply-revision": try put(&p, ["items", "3", "body", "expected_revision"], 10)
    case "reply-food": try put(&p, ["items", "3", "body", "answer", "food_index"], 1)
    case "reply-unit": try put(&p, ["items", "3", "body", "answer", "unit"], "scoop")
    case "reply-amount": try put(&p, ["items", "3", "body", "answer", "amount"], 0)
    case "reply-extra":
      try put(&p, ["items", "3", "body", "owner_id"], UUID().uuidString.lowercased())
    case "result-status": try put(&p, ["items", "2", "status"], "needs_reply")
    case "result-hash": try put(&p, ["items", "2", "prepared_hash"], "opaque-but-invalid")
    case "result-clock": try put(&p, ["items", "2", "at"], "2026-11-04T11:00:00.000001Z")
    case "linked-schema":
      try put(&p, ["items", "1", "receipt", "schema"], "conversation.meal-effect.v1")
    case "linked-owner":
      try put(&p, ["items", "1", "receipt", "owner_id"], UUID().uuidString.lowercased())
    case "linked-command":
      try put(&p, ["items", "1", "receipt", "command_id"], UUID().uuidString.lowercased())
    case "linked-parent": try put(&p, ["items", "1", "receipt", "parent_input_hash"], hash("a"))
    case "linked-decision":
      try put(&p, ["items", "1", "receipt", "parent_decision_hash"], hash("a"))
    case "linked-provider":
      try put(&p, ["items", "1", "receipt", "provider_key"], "conversation.meal/fake")
    case "linked-epoch":
      try put(&p, ["items", "1", "receipt", "epoch"], UUID().uuidString.lowercased())
    case "linked-logs": try put(&p, ["items", "1", "receipt", "log_ids"], [])
    case "linked-date": try put(&p, ["items", "1", "receipt", "local_date"], "2026-11-03")
    case "linked-meal": try put(&p, ["items", "1", "receipt", "meal_type"], "jantar")
    case "edit-binding": try put(&p, ["items", "0", "effect_binding", "input_hash"], hash("a"))
    case "edit-extra": try put(&p, ["items", "0", "receipt", "snapshot"], [:])
    case "edit-op-hash": try put(&p, ["items", "0", "receipt", "input_hash"], "bad")
    case "edit-time":
      try put(&p, ["items", "0", "receipt", "applied_at"], "2026-11-04T12:00:05.123456Z")
    case "hasmore": p["has_more"] = true
    case "cursor-empty":
      p["has_more"] = true
      p["next_cursor"] = ""
    default:
      p["has_more"] = true
      p["next_cursor"] = "https://private.invalid"
    }
    #expect(throws: (any Error).self) { try ConversationThreadPageSnapshot(data: bytes(p)) }
  }

  @Test func wholeDataCapAndStrictEnvelopeDoNotIgnorePrivateFields() throws {
    #expect(throws: (any Error).self) {
      try ConversationThreadPageSnapshot(data: Data(repeating: 32, count: 240_001))
    }
    let p = try pageObject()
    let envelope: [String: Any] = [
      "data": p, "meta": ["api_version": "v1", "request_id": "synthetic-v2"],
    ]
    #expect(
      try ConversationThreadPageSnapshot.Envelope(data: bytes(envelope)).data.items.count == 5)
    var privateEnvelope = envelope
    privateEnvelope["private"] = true
    #expect(throws: (any Error).self) {
      try ConversationThreadPageSnapshot.Envelope(data: bytes(privateEnvelope))
    }
  }

  @Test func opaqueCursorRetainsExactServerBytesAndRejectsForeignOrUnanchoredData() throws {
    var page = try pageObject()
    let last = try #require((page["items"] as? [[String: Any]])?.last)
    let at = try #require(last["at"] as? String)
    let id = try #require(last["event_id"] as? String)
    let owner = try #require(page["owner_id"] as? String)
    let epoch = try #require(page["epoch"] as? String)
    let canonical =
      "{\"v\":2,\"owner_id\":\"\(owner)\",\"epoch\":\"\(epoch)\",\"at\":\"\(at)\",\"id\":\"\(id)\"}"
    func token(_ value: String) -> String {
      Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    page["has_more"] = true
    page["next_cursor"] = token(canonical)
    #expect(try ConversationThreadPageSnapshot(data: bytes(page)).nextCursor == token(canonical))
    for bad in [
      canonical.replacingOccurrences(of: "\"v\":2", with: "\"v\":1"),
      canonical.replacingOccurrences(of: owner, with: UUID().uuidString.lowercased()),
      canonical.replacingOccurrences(of: epoch, with: UUID().uuidString.lowercased()),
      canonical.replacingOccurrences(of: at, with: "2026-11-04T12:00:00.000002Z"),
      canonical.replacingOccurrences(of: id, with: "command/\(UUID().uuidString.lowercased())"),
      canonical.replacingOccurrences(of: "{", with: "{\"private\":true,"),
      " " + canonical,
    ] {
      page["next_cursor"] = token(bad)
      #expect(throws: (any Error).self) { try ConversationThreadPageSnapshot(data: bytes(page)) }
    }
    for bad in ["a", token(canonical) + "=", token(canonical) + "A"] {
      page["next_cursor"] = bad
      #expect(throws: (any Error).self) { try ConversationThreadPageSnapshot(data: bytes(page)) }
    }
  }

  @Test func wholeDataBudgetIsAppliedBeforeMalformedOptionalFeedbackIsDiscarded() throws {
    var page = try pageObject()
    try put(&page, ["items", "1", "feedback"], ["unknown": String(repeating: "x", count: 1_000)])
    let smaller = try ConversationThreadPageSnapshot(data: bytes(page))
    guard case .fulfillment(let effect) = smaller.items[1].detail else {
      Issue.record("Actual linked effect required")
      return
    }
    #expect(effect.feedback == nil)
    try put(&page, ["items", "1", "feedback"], ["unknown": String(repeating: "x", count: 240_000)])
    #expect(throws: (any Error).self) { try ConversationThreadPageSnapshot(data: bytes(page)) }
    // Generic Decodable is the actual HTTP path, not only init(data:).
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(ConversationThreadPageSnapshot.self, from: bytes(page))
    }
  }

  @Test func currentHeadAndHistoricalReplyQuestionStayDistinct() throws {
    var page = try pageObject()
    let nextQuestion: [String: Any] = [
      "schema": "conversation.meal-question.v1", "question_key": hash("b"), "revision": 1,
      "kind": "meal_type", "food_index": NSNull(), "food_name": NSNull(),
      "allowed_units": [], "quantity_reference": NSNull(),
    ]
    var events = try #require(page["items"] as? [[String: Any]])
    events = Array(events.dropFirst(2))
    events[0]["status"] = "needs_reply"
    events[0]["next_question"] = nextQuestion
    page["items"] = events
    try put(
      &page, ["threads", "0", "continuation"],
      ["revision": 1, "question": nextQuestion, "fulfilled_by": NSNull()])
    let decoded = try ConversationThreadPageSnapshot(data: bytes(page))
    #expect(decoded.threads.first?.continuation?.question?.kind == "meal_type")
    guard case .reply(let reply) = decoded.items[1].detail else {
      Issue.record("Historical reply required")
      return
    }
    #expect(reply.question.kind == "quantity" && reply.question.revision == 0)
    #expect(
      reply.question.questionKey != decoded.threads.first?.continuation?.question?.questionKey)
  }

  private func hash(_ s: String) -> String { String(repeating: s, count: 64) }
  private func sdkPieces() throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationLinkedFeedbackSDKFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationLinkedFeedbackSDKFixtures.json")
    #endif
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  private func bytes(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value)
  }
  private func pageObject() throws -> [String: Any] {
    #if SWIFT_PACKAGE
      let url = try #require(
        Bundle.module.url(
          forResource: "ConversationThreadPagePublicFixtures", withExtension: "json"))
    #else
      let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
        "Fixtures/ConversationThreadPagePublicFixtures.json")
    #endif
    let top = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return try #require(top["data"] as? [String: Any])
  }
  private func put(_ object: inout [String: Any], _ path: [String], _ value: Any) throws {
    func update(_ raw: Any, _ keys: ArraySlice<String>) throws -> Any {
      guard let key = keys.first else { return value }
      if var array = raw as? [Any], let i = Int(key), array.indices.contains(i) {
        array[i] = try update(array[i], keys.dropFirst())
        return array
      }
      var map = try #require(raw as? [String: Any])
      map[key] = try update(map[key] ?? NSNull(), keys.dropFirst())
      return map
    }
    object = try #require(update(object, path[...]) as? [String: Any])
  }
}
