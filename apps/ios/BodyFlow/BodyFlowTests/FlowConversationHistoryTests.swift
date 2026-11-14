import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Flow loads the owned journal without duplicating pending intents")
@MainActor
struct FlowConversationHistoryTests {
  @Test func coldReopenDeduplicatesAndExplicitlyClosesOnlyProvenNegativeDelivery() async throws {
    let f = try await Harness.make(seedTerminal: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    #expect(model.pendingRows.count == 1)
    await model.loadHistory()
    #expect(model.journalRows.count == 4 && model.pendingRows.isEmpty && model.savedRows.isEmpty)
    #expect(model.acknowledgedMealCommandIDs.isEmpty)
    #expect(model.terminalQuestion?.reason == "nutrition_unresolved")
    #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    model.beginIndependentReport()
    model.composer = "novo relato independente"
    await model.loadHistory()
    #expect(model.terminalQuestion == nil && model.canSubmit)
    #expect(model.journalRows.count == 4)
    await model.close()
  }
  @Test func allSevenActualHTTPPagesKeepNineteenEventsAndTheirOpaqueCursors() async throws {
    let f = try await Harness.make(httpPages: true)
    defer { f.disk.remove() }
    let model = try await f.open()
    await model.loadHistory()
    for _ in 1..<7 { await model.loadHistory(reset: false) }
    #expect(model.journalRows.count == 19 && !model.hasMoreHistory)
    #expect(Set(model.journalRows.map(\.eventID)).count == 19)
    let reads = await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/journal") == true }
    #expect(reads.count == 7 && reads.allSatisfy { $0.httpMethod == "GET" })
    let firstURL = try #require(reads[0].url)
    #expect(
      URLComponents(url: firstURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "cursor"
      }) == nil)
    for (i, read) in reads.dropFirst().enumerated() {
      let url = try #require(read.url)
      let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
      #expect(
        components.queryItems?.first(where: { $0.name == "cursor" })?.value == f.pages[i].nextCursor
      )
    }
    await model.close()
  }
  private struct Harness: Sendable {
    let disk: OutboxDiskFixture
    let http: ConversationHTTPFixture
    let owner: ConversationOutboxOwner
    let vault: ConversationOutboxKeyVault
    let pages: [ConversationJournalPageSnapshot]
    static func make(seedTerminal: Bool = false, httpPages: Bool = false) async throws -> Self {
      #if SWIFT_PACKAGE
        let url = try #require(
          Bundle.module.url(
            forResource: httpPages
              ? "ConversationJournalHTTPFixtures" : "ConversationJournalPublicFixtures",
            withExtension: "json"))
      #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
          .appendingPathComponent(
            "Fixtures/\(httpPages ? "ConversationJournalHTTPFixtures" : "ConversationJournalPublicFixtures").json"
          )
      #endif
      let raw = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      let objects = httpPages ? try #require(raw["pages"] as? [[String: Any]]) : [raw]
      let bodies = try objects.map { try JSONSerialization.data(withJSONObject: $0) }
      let pages = try bodies.map { try ConversationJournalPageSnapshot.Envelope(data: $0).data }
      let first = try #require(pages.first)
      let session: [String: Any] = [
        "schema": "conversation.session.v1",
        "auth_user_id": first.authUserID.uuidString.lowercased(),
        "owner_id": first.ownerID.uuidString.lowercased(),
        "epoch": first.epoch.uuidString.lowercased(), "observed_at": first.observedAt,
        "meal_command_protocol": "conversation.command.v1",
      ]
      let sessionBody = try JSONSerialization.data(withJSONObject: [
        "data": session, "meta": ["api_version": "v1", "request_id": "journal-flow-session"],
      ])
      let disk = try OutboxDiskFixture()
      let lifecycle = ConversationHTTPTestLifecycle()
      await lifecycle.replace(
        .init(
          userID: first.authUserID.uuidString.lowercased(), generation: 7,
          bearer: "synthetic-journal-flow"))
      let http = try ConversationHTTPFixture(lifecycle: lifecycle)
      let owner = try ConversationOutboxOwner(lease: await lifecycle.leaseForRequest())
      let keys = OutboxKeychainFake()
      await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
      if seedTerminal {
        let command = try #require(
          first.items.compactMap { row -> ConversationMealCommand? in
            if case .command(let v) = row, v.terminalReceipt != nil { return v.originalCommand }
            return nil
          }.first)
        try disk.store.update(owner: owner, key: disk.key) {
          var row = ConversationOutboxEntry(
            command: command, originalServerEpoch: first.epoch,
            originalPatientOwnerID: first.ownerID)
          row.state = .dispatchedUnknown
          $0.append(row)
        }
      }
      let counter = ConversationControllerCounter()
      await http.stub.respond { request, _ in
        if request.url?.path.hasSuffix("/session") == true {
          return .init(status: 200, body: sessionBody)
        }
        let index = httpPages ? await counter.next() - 1 : 0
        guard index < bodies.count else { throw URLError(.badURL) }
        return .init(status: 200, body: bodies[index])
      }
      return .init(
        disk: disk, http: http, owner: owner, vault: .init(service: "synthetic", security: keys),
        pages: pages)
    }
    func open() async throws -> FlowConversationModel {
      try await .open(
        transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: vault,
        historyPageSize: pages.count == 7 ? 3 : 10)
    }
  }
}
