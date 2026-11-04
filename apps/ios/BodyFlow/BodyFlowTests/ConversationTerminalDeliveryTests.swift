import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("A sealed negative decision closes delivery without food acknowledgement")
struct ConversationTerminalDeliveryTests {
  @Test func exactTerminalProofRemovesOnlyDeliveredUnknownAndRejectsLateEnqueue() async throws {
    let f = try Fixture()
    defer { f.disk.remove() }
    let session = try await f.open()
    let original = f.entry.originalCommand
    _ = try await session.enqueue(command: original, server: f.server)
    let other = try ConversationMealCommand(source: original.source, mealType: original.mealType)
    _ = try await session.enqueue(command: other, server: f.server)
    let ticket = try await session.prepareDispatch(commandID: original.commandID, server: f.server)
    try await session.closeTerminalDelivery(ticket: ticket, entry: f.entry, server: f.server)
    let remaining = try f.disk.store.load(owner: f.disk.owner, key: f.disk.key)
    #expect(
      remaining.count == 1 && remaining[0].commandID == other.commandID
        && remaining[0].state == .queued)
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await session.enqueue(command: original, server: f.server)
    }
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).count == 1)
    await session.invalidate()
  }
  @Test func failedAtomicDeliveryClosePreservesCiphertextAndDoesNotInstallClosedGuard() async throws
  {
    let f = try Fixture()
    defer { f.disk.remove() }
    let session = try await f.open()
    let original = f.entry.originalCommand
    _ = try await session.enqueue(command: original, server: f.server)
    let ticket = try await session.prepareDispatch(commandID: original.commandID, server: f.server)
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.disk.store.root.path)
    await #expect(throws: ConversationOutboxError.storageUnavailable) {
      try await session.closeTerminalDelivery(ticket: ticket, entry: f.entry, server: f.server)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.disk.store.root.path)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == before)
    #expect(try await session.enqueue(command: original, server: f.server) == original.commandID)
    try await session.closeTerminalDelivery(ticket: ticket, entry: f.entry, server: f.server)
    #expect(try f.disk.store.load(owner: f.disk.owner, key: f.disk.key).isEmpty)
    await session.invalidate()
  }
  @Test func foreignEpochResetAndQueuedWorkCannotBeClosedByNegativeDelivery() async throws {
    let f = try Fixture()
    defer { f.disk.remove() }
    let session = try await f.open()
    let original = f.entry.originalCommand
    _ = try await session.enqueue(command: original, server: f.server)
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await session.reconciliationTicket(commandID: original.commandID)
    }
    let ticket = try await session.prepareDispatch(commandID: original.commandID, server: f.server)
    let foreign = ConversationOutboxServerObservation(
      authUserID: f.server.authUserID, ownerID: f.server.ownerID,
      localSessionGeneration: f.server.localSessionGeneration, epoch: UUID())
    await #expect(throws: (any Error).self) {
      try await session.closeTerminalDelivery(ticket: ticket, entry: f.entry, server: foreign)
    }
    try await session.markWaiting(ticket: ticket, hold: .reset, server: f.server)
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner))
    await #expect(throws: ConversationOutboxError.reconciliationRequired) {
      try await session.closeTerminalDelivery(ticket: ticket, entry: f.entry, server: f.server)
    }
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.disk.owner)) == before)
    await session.invalidate()
  }
  private struct Fixture {
    let disk: OutboxDiskFixture
    let entry: ConversationJournalPageSnapshot.CommandEntry
    let server: ConversationOutboxServerObservation
    let keys = OutboxKeychainFake()
    init() throws {
      disk = try OutboxDiskFixture()
      #if SWIFT_PACKAGE
        let url = try #require(
          Bundle.module.url(forResource: "ConversationJournalPublicFixtures", withExtension: "json")
        )
      #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
          .appendingPathComponent("Fixtures/ConversationJournalPublicFixtures.json")
      #endif
      let page = try ConversationJournalPageSnapshot.Envelope(data: Data(contentsOf: url)).data
      entry = try #require(
        page.items.compactMap { item -> ConversationJournalPageSnapshot.CommandEntry? in
          if case .command(let v) = item, v.terminalReceipt != nil { return v }
          return nil
        }.first)
      server = try .init(
        authUserID: #require(UUID(uuidString: disk.lease.userID)), ownerID: page.ownerID,
        localSessionGeneration: disk.lease.generation, epoch: page.epoch)
    }
    func open() async throws -> ConversationOutboxSession {
      await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: disk.owner.hash)
      return try await .open(
        lifecycle: OutboxLifecycleFake(lease: disk.lease), store: disk.store,
        keyVault: .init(service: "synthetic", security: keys))
    }
  }
}

@Suite("Journal reading and terminal delivery remain separate capabilities")
@MainActor
struct ConversationJournalDeliveryControllerTests {
  @Test func readAloneCannotACKButExplicitBoundNegativeDeliveryClosesOnlyItsIdentity() async throws
  {
    let f = try await Harness.make()
    defer { f.disk.remove() }
    let controller = try await f.open()
    let probe = ConversationControllerProbe()
    try await controller.publishSnapshot { probe.events.append($0) }
    let context = try #require(
      probe.events.compactMap {
        if case .scopeAccepted(let v) = $0 { return v }
        return nil
      }.last)
    let repository = try await MobileConversationHistoryRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      lease: await f.http.lifecycle.leaseForRequest())
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    let read = try await repository.journal(context: context)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == before)
    #expect(probe.saved.isEmpty)
    try await controller.closeTerminalDelivery(read: read, commandID: f.command.commandID) {
      probe.events.append($0)
    }
    #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
    #expect(probe.saved.isEmpty)
    await #expect(throws: ConversationOutboxError.invalidTransition) {
      try await controller.enqueue(command: f.command, expectedContext: context.identity) {
        probe.events.append($0)
      }
    }
    #expect(await f.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
    await controller.close()
  }
  @Test func aLaterAcceptedSessionRevokesEarlierPageDeliveryEvenForSamePatientAndEpoch()
    async throws
  {
    let f = try await Harness.make()
    defer { f.disk.remove() }
    let controller = try await f.open()
    let probe = ConversationControllerProbe()
    try await controller.publishSnapshot { probe.events.append($0) }
    let context = try #require(
      probe.events.compactMap {
        if case .scopeAccepted(let v) = $0 { return v }
        return nil
      }.last)
    let repository = try await MobileConversationHistoryRepository.scoped(
      transport: f.http.transport, lifecycle: f.http.lifecycle,
      lease: await f.http.lifecycle.leaseForRequest())
    let read = try await repository.journal(context: context)
    let before = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    try await controller.refreshSession { probe.events.append($0) }
    await #expect(throws: ConversationOutboxError.invalidServerObservation) {
      try await controller.closeTerminalDelivery(read: read, commandID: f.command.commandID) {
        probe.events.append($0)
      }
    }
    #expect(
      try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == before && probe.saved.isEmpty)
    await controller.close()
  }
  private struct Harness: Sendable {
    let disk: OutboxDiskFixture
    let http: ConversationHTTPFixture
    let owner: ConversationOutboxOwner
    let vault: ConversationOutboxKeyVault
    let command: ConversationMealCommand
    static func make() async throws -> Self {
      #if SWIFT_PACKAGE
        let url = try #require(
          Bundle.module.url(forResource: "ConversationJournalPublicFixtures", withExtension: "json")
        )
      #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
          .appendingPathComponent("Fixtures/ConversationJournalPublicFixtures.json")
      #endif
      let body = try Data(contentsOf: url)
      let page = try ConversationJournalPageSnapshot.Envelope(data: body).data
      let entry = try #require(
        page.items.compactMap { item -> ConversationJournalPageSnapshot.CommandEntry? in
          if case .command(let v) = item, v.terminalReceipt != nil { return v }
          return nil
        }.first)
      let session: [String: Any] = [
        "schema": "conversation.session.v1",
        "auth_user_id": page.authUserID.uuidString.lowercased(),
        "owner_id": page.ownerID.uuidString.lowercased(),
        "epoch": page.epoch.uuidString.lowercased(), "observed_at": page.observedAt,
        "meal_command_protocol": "conversation.command.v1",
      ]
      let sessionBody = try JSONSerialization.data(withJSONObject: [
        "data": session, "meta": ["api_version": "v1", "request_id": "journal-delivery-session"],
      ])
      let disk = try OutboxDiskFixture()
      let lifecycle = ConversationHTTPTestLifecycle()
      await lifecycle.replace(
        .init(
          userID: page.authUserID.uuidString.lowercased(), generation: 7,
          bearer: "synthetic-journal-auth"))
      let http = try ConversationHTTPFixture(lifecycle: lifecycle)
      let owner = try ConversationOutboxOwner(lease: await lifecycle.leaseForRequest())
      let keys = OutboxKeychainFake()
      await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
      try disk.store.update(owner: owner, key: disk.key) { entries in
        var row = ConversationOutboxEntry(
          command: entry.originalCommand, originalServerEpoch: page.epoch,
          originalPatientOwnerID: page.ownerID)
        row.state = .dispatchedUnknown
        entries.append(row)
      }
      await http.stub.respond { request, _ in
        if request.url?.path.hasSuffix("/session") == true {
          return .init(status: 200, body: sessionBody)
        }
        if request.url?.path.hasSuffix("/journal") == true { return .init(status: 200, body: body) }
        throw URLError(.badURL)
      }
      return .init(
        disk: disk, http: http, owner: owner, vault: .init(service: "synthetic", security: keys),
        command: entry.originalCommand)
    }
    func open() async throws -> ConversationMealCommandController {
      try await .open(
        transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: vault)
    }
  }
}
