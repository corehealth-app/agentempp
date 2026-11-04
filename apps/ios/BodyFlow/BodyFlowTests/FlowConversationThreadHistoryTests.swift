import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Actual Flow opts into linked history without writer authority")
@MainActor
struct FlowConversationThreadHistoryTests {
  @Test func concreteRuntimeFactorySelectsV2WithRealControllersAndOriginalAuthLease() async throws {
    let f = try await Harness.make()
    defer { f.disk.remove() }
    let edits = EncryptedConversationMealEditOutboxStore(
      directory: f.disk.directory.appendingPathComponent("edit-outbox"))
    let editKeys = OutboxKeychainFake()
    let source = FlowConversationSessionSource(
      transport: f.http.transport, lifecycle: f.http.lifecycle, media: nil,
      store: f.disk.store, keyVault: f.vault,
      editing: .init(
        store: edits,
        keyVault: .init(
          service: ConversationMealEditOutboxSession.keychainService, security: editKeys)))
    let session = try await source.open(expectedUserID: f.page.authUserID.uuidString.lowercased())
    #expect(session.model.mealEditor != nil)
    await session.model.loadHistory()
    #expect(session.model.threadRows.count == 5 && session.model.journalRows.isEmpty)
    let request = try #require(
      await f.http.stub.requests.first { $0.url?.path.hasSuffix("/journal") == true })
    let url = try #require(request.url)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first { $0.name == "version" }?.value == "2")
    #expect(session.model.acceptedIdentity?.authUserID == f.page.authUserID)
    #expect(session.model.acceptedIdentity?.ownerID == f.page.ownerID)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await session.close()
    #expect(session.model.threadRows.isEmpty)
  }

  @Test func coldReopenReadsActualV2AndDeduplicatesOriginalWithoutAcknowledgingCiphertext()
    async throws
  {
    let f = try await Harness.make(seed: true)
    defer { f.disk.remove() }
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    let model = try await f.open()
    #expect(model.pendingRows.count == 1)
    await model.loadHistory()
    #expect(model.threadRows.count == 5 && model.journalRows.isEmpty)
    #expect(model.pendingRows.isEmpty && model.savedRows.isEmpty)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == before)
    let child = try #require(f.page.threads.first?.continuation?.fulfilledBy)
    #expect(model.currentGroup(commandID: child) == nil)
    await model.loadCurrentGroup(commandID: child)
    let requests = await f.http.stub.requests
    #expect(requests.allSatisfy { $0.httpMethod == "GET" })
    let history = try #require(requests.first { $0.url?.path.hasSuffix("/journal") == true })
    let historyURL = try #require(history.url)
    let query = try #require(
      URLComponents(url: historyURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first { $0.name == "version" }?.value == "2")
    #expect(
      history.value(forHTTPHeaderField: "X-Conversation-Owner")
        == f.page.ownerID.uuidString.lowercased())
    #expect(
      history.value(forHTTPHeaderField: "X-Conversation-Epoch")
        == f.page.epoch.uuidString.lowercased())
    #expect(!requests.contains { $0.url?.path.hasSuffix("/meal") == true })
    await model.close()
    #expect(model.threadRows.isEmpty)
    let reopened = try await f.open()
    await reopened.loadHistory()
    #expect(reopened.threadRows.count == 5 && reopened.pendingRows.isEmpty)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == before)
    await reopened.close()
  }

  @Test func actualPaginationKeepsServerOrderAndOpaqueCursorWithoutDuplicateRows() async throws {
    let f = try await Harness.make(paginated: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    #expect(model.threadRows.count == 2 && model.hasMoreHistory)
    await model.loadHistory(reset: false)
    #expect(model.threadRows.count == 4 && model.hasMoreHistory)
    await model.loadHistory(reset: false)
    #expect(model.threadRows.count == 5 && !model.hasMoreHistory)
    #expect(model.threadRows.map(\.eventID) == f.page.items.map(\.eventID))
    #expect(Set(model.threadRows.map(\.eventID)).count == 5)
    let requests = await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/journal") == true }
    #expect(requests.count == 3 && requests.allSatisfy { $0.httpMethod == "GET" })
    let secondURL = try #require(requests[1].url)
    let second = try #require(URLComponents(url: secondURL, resolvingAgainstBaseURL: false))
    #expect(second.queryItems?.first { $0.name == "cursor" }?.value == f.pages[0].nextCursor)
    await model.close()
  }

  @Test func duplicatePageAppendFailsWithoutErasingAlreadyPublishedHistory() async throws {
    let f = try await Harness.make(paginated: true, duplicate: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    let first = model.threadRows.map(\.eventID)
    await model.loadHistory(reset: false)
    #expect(model.historyUnavailable && model.threadRows.map(\.eventID) == first)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  @Test func reopenedUnfulfilledQuestionNeverTurnsAnAnswerIntoAnUnlinkedFreshReport() async throws {
    let f = try await Harness.make(seed: true, unfulfilled: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    #expect(model.terminalQuestion?.reason == "missing_quantity")
    #expect(model.terminalQuestion?.observedQuestion?.foodName == "leite")
    let questionEventID = try #require(model.threadRows.first?.eventID)
    #expect(model.observedThreadQuestion(eventID: questionEventID) == nil)
    model.composer = "200 mL"
    #expect(!model.canSubmit)
    await model.submit()
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    let original = try #require(f.page.threads.first?.originalCommand)
    #expect(
      try f.disk.store.load(owner: f.owner, key: f.disk.key).map(\.commandID) == [
        original.commandID
      ])
    model.beginIndependentReport()
    #expect(model.composer.isEmpty && model.terminalQuestion == nil)
    await model.close()
  }

  @Test func logoutWhilePageIsInFlightClearsRetainedModelAndRefusesOldBody() async throws {
    let barrier = ConversationControllerBarrier()
    let f = try await Harness.make(barrier: barrier)
    defer { f.disk.remove() }
    let model = try await f.open()
    let read = Task {
      await model.loadHistory()
      await barrier.finish()
    }
    try #require(await barrier.waitEnteredOrFinished())
    await f.http.lifecycle.replace(
      .init(userID: UUID().uuidString.lowercased(), generation: 8, bearer: "synthetic-next"))
    #expect(model.threadRows.isEmpty && model.composer.isEmpty)
    await barrier.release()
    await read.value
    #expect(model.threadRows.isEmpty && model.journalRows.isEmpty)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  @Test func sameAuthPatientRemapRevokesInFlightPageWithoutTouchingOriginalCiphertext() async throws
  {
    let barrier = ConversationControllerBarrier()
    let f = try await Harness.make(seed: true, barrier: barrier)
    defer { f.disk.remove() }
    let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    let model = try await f.open()
    let read = Task {
      await model.loadHistory()
      await barrier.finish()
    }
    try #require(await barrier.waitEnteredOrFinished())
    let nextPatient = UUID()
    let nextSession = try JSONSerialization.data(withJSONObject: [
      "data": [
        "schema": "conversation.session.v1",
        "auth_user_id": f.page.authUserID.uuidString.lowercased(),
        "owner_id": nextPatient.uuidString.lowercased(),
        "epoch": f.page.epoch.uuidString.lowercased(),
        "observed_at": "2026-11-04T12:03:00.000001Z",
        "meal_command_protocol": "conversation.command.v1",
      ], "meta": ["api_version": "v1", "request_id": "synthetic-remapped-session"],
    ])
    await f.http.stub.respond { _, _ in .init(status: 200, body: nextSession) }
    await model.refresh()
    #expect(model.acceptedIdentity?.ownerID == nextPatient)
    await barrier.release()
    await read.value
    #expect(model.threadRows.isEmpty && model.pendingRows.isEmpty && model.journalRows.isEmpty)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  @Test(arguments: ["202", "private-envelope", "foreign-auth", "oversized-envelope"])
  func realReadBoundaryWithholdsInvalidResponseWithoutAcknowledging(_ vector: String) async throws {
    let f = try await Harness.make(seed: true)
    defer { f.disk.remove() }
    let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    let model = try await f.open()
    var body = f.bodies[0]
    var status = 200
    if vector == "202" {
      status = 202
    } else if vector == "oversized-envelope" {
      body = Data(repeating: 32, count: 262_145)
    } else {
      var object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      if vector == "private-envelope" {
        object["private"] = true
      } else {
        var data = try #require(object["data"] as? [String: Any])
        data["auth_user_id"] = UUID().uuidString.lowercased()
        object["data"] = data
      }
      body = try JSONSerialization.data(withJSONObject: object)
    }
    let response = ConversationHTTPReply(status: status, body: body)
    await f.http.stub.respond { _, _ in response }
    await model.loadHistory()
    #expect(model.historyUnavailable && model.threadRows.isEmpty && model.pendingRows.count == 1)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  @Test(arguments: ["prepared-hash", "reply-amount", "edit-revision"])
  func resetCannotRewriteAnAlreadyObservedImmutableEvent(_ vector: String) async throws {
    let f = try await Harness.make()
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    let originalIDs = model.threadRows.map(\.eventID)
    var top = try #require(JSONSerialization.jsonObject(with: f.bodies[0]) as? [String: Any])
    var data = try #require(top["data"] as? [String: Any])
    var items = try #require(data["items"] as? [[String: Any]])
    if vector == "prepared-hash" {
      items[2]["prepared_hash"] = String(repeating: "b", count: 64)
    } else if vector == "reply-amount" {
      var body = try #require(items[3]["body"] as? [String: Any])
      var answer = try #require(body["answer"] as? [String: Any])
      answer["amount"] = 250
      body["answer"] = answer
      items[3]["body"] = body
    } else {
      var receipt = try #require(items[0]["receipt"] as? [String: Any])
      receipt["revision"] = 2
      items[0]["receipt"] = receipt
    }
    data["items"] = items
    top["data"] = data
    let response = try JSONSerialization.data(withJSONObject: top)
    await f.http.stub.respond { _, _ in .init(status: 200, body: response) }
    await model.loadHistory()
    #expect(model.historyUnavailable && model.threadRows.map(\.eventID) == originalIDs)
    guard case .replyResult(let prepared) = model.threadRows[2].detail,
      case .reply(let reply) = model.threadRows[3].detail,
      case .quantity(_, let amount, _) = reply.body.answer,
      case .edit(let edit) = model.threadRows[0].detail
    else {
      Issue.record("Actual original events required")
      return
    }
    #expect(prepared.preparedHash == String(repeating: "a", count: 64))
    #expect(amount == 200 && edit.receipt.revision == 1)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await model.close()
  }

  private struct Harness: Sendable {
    let disk: OutboxDiskFixture
    let http: ConversationHTTPFixture
    let owner: ConversationOutboxOwner
    let vault: ConversationOutboxKeyVault
    let page: ConversationThreadPageSnapshot
    let pages: [ConversationThreadPageSnapshot]
    let bodies: [Data]
    static func make(
      seed: Bool = false, paginated: Bool = false, duplicate: Bool = false,
      unfulfilled: Bool = false, barrier: ConversationControllerBarrier? = nil
    ) async throws -> Self {
      #if SWIFT_PACKAGE
        let url = try #require(
          Bundle.module.url(
            forResource: "ConversationThreadPagePublicFixtures", withExtension: "json"))
      #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
          .appendingPathComponent("Fixtures/ConversationThreadPagePublicFixtures.json")
      #endif
      let top = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      var raw = try #require(top["data"] as? [String: Any])
      if unfulfilled {
        let events = try #require(raw["items"] as? [[String: Any]])
        let question = try #require(
          events.first(where: { $0["kind"] as? String == "reply" })?["question"])
        var descriptor = try #require((raw["threads"] as? [[String: Any]])?.first)
        descriptor["continuation"] = [
          "revision": 0, "question": question, "fulfilled_by": NSNull(),
        ]
        raw["threads"] = [descriptor]
        raw["items"] = events.filter { $0["kind"] as? String == "report" }
      }
      let page = try ConversationThreadPageSnapshot(
        data: JSONSerialization.data(withJSONObject: raw))
      let all = try #require(raw["items"] as? [[String: Any]])
      let chunks = paginated ? [Array(all[0..<2]), Array(all[2..<4]), Array(all[4...])] : [all]
      var bodies: [Data] = []
      var pages: [ConversationThreadPageSnapshot] = []
      for (i, rows) in chunks.enumerated() {
        var part = raw
        part["items"] = rows
        part["has_more"] = i < chunks.count - 1
        if i < chunks.count - 1 {
          let last = try #require(rows.last)
          let at = try #require(last["at"] as? String)
          let id = try #require(last["event_id"] as? String)
          let cursor =
            "{\"v\":2,\"owner_id\":\"\(page.ownerID.uuidString.lowercased())\",\"epoch\":\"\(page.epoch.uuidString.lowercased())\",\"at\":\"\(at)\",\"id\":\"\(id)\"}"
          part["next_cursor"] = Data(cursor.utf8).base64EncodedString().replacingOccurrences(
            of: "+", with: "-"
          ).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        } else {
          part["next_cursor"] = NSNull()
        }
        pages.append(
          try ConversationThreadPageSnapshot(data: JSONSerialization.data(withJSONObject: part)))
        bodies.append(
          try JSONSerialization.data(withJSONObject: [
            "data": part, "meta": ["api_version": "v1", "request_id": "synthetic-thread-page"],
          ]))
      }
      let sessionBody = try JSONSerialization.data(withJSONObject: [
        "data": [
          "schema": "conversation.session.v1",
          "auth_user_id": page.authUserID.uuidString.lowercased(),
          "owner_id": page.ownerID.uuidString.lowercased(),
          "epoch": page.epoch.uuidString.lowercased(), "observed_at": "2026-11-04T12:00:00.000000Z",
          "meal_command_protocol": "conversation.command.v1",
        ], "meta": ["api_version": "v1", "request_id": "synthetic-thread-session"],
      ])
      let disk = try OutboxDiskFixture()
      let lifecycle = ConversationHTTPTestLifecycle()
      await lifecycle.replace(
        .init(
          userID: page.authUserID.uuidString.lowercased(), generation: 7, bearer: "synthetic-thread"
        ))
      let http = try ConversationHTTPFixture(lifecycle: lifecycle)
      let owner = try ConversationOutboxOwner(lease: await lifecycle.leaseForRequest())
      let keys = OutboxKeychainFake()
      await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
      if seed {
        let command = try #require(page.threads.first?.originalCommand)
        try disk.store.update(owner: owner, key: disk.key) {
          var entry = ConversationOutboxEntry(
            command: command, originalServerEpoch: page.epoch, originalPatientOwnerID: page.ownerID)
          entry.state = .dispatchedUnknown
          $0.append(entry)
        }
      }
      let frozenBodies = bodies
      let counter = ConversationControllerCounter()
      await http.stub.respond { request, _ in
        if request.url?.path.hasSuffix("/session") == true {
          return .init(status: 200, body: sessionBody)
        }
        guard request.url?.path.hasSuffix("/journal") == true else { throw URLError(.badURL) }
        if let barrier { await barrier.enter() }
        let index = paginated && !duplicate ? await counter.next() - 1 : 0
        guard frozenBodies.indices.contains(index) else { throw URLError(.badURL) }
        return .init(status: 200, body: frozenBodies[index])
      }
      return .init(
        disk: disk, http: http, owner: owner, vault: .init(service: "synthetic", security: keys),
        page: page, pages: pages, bodies: bodies)
    }
    func open() async throws -> FlowConversationModel {
      try await .open(
        transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: vault,
        historyVersion: .v2)
    }
  }
}
