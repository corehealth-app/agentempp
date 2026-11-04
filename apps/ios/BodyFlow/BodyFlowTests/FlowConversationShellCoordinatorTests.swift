import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

#if canImport(UIKit)
  import SwiftUI
#endif

@Suite("Actual authenticated Flow shell owns its factory and teardown")
@MainActor
struct FlowConversationShellCoordinatorTests {
  #if canImport(UIKit)
    @Test func actualRootShowsUnavailableRetryInsteadOfDemoOrSavedFood() async throws {
      let f = try await RuntimeSourceFixture.make()
      defer { f.remove() }
      await f.edit.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
      let coordinator = FlowConversationShellCoordinator(
        userID: f.edit.disk.lease.userID, source: f.source)
      await coordinator.load()
      let host = SignUpRenderingProbe.host(
        FlowConversationRootView(coordinator: coordinator)
          .environment(\.locale, Locale(identifier: "en_US")), width: 390, height: 900)
      defer { host.detach() }
      let nodes = host.nodes()
      let diagnostic = Comment(rawValue: nodes.map(\.description).joined(separator: "\n"))
      #expect(nodes.contains { $0.identifier == "conversation.runtime.unavailable" }, diagnostic)
      #expect(
        nodes.contains { $0.identifier == "conversation.runtime.retry" && $0.isButton }, diagnostic)
      #expect(
        !nodes.contains {
          $0.identifier.hasPrefix("conversation.saved.") || $0.identifier == "conversation.composer"
        }, diagnostic)
      #expect(coordinator.model == nil)
      #expect(await f.edit.http.stub.requests.allSatisfy { $0.httpMethod == "GET" })
      await coordinator.close()
    }
  #endif
  @Test
  func synchronousWithdrawalSchedulesOwnedRAMAndWorkCleanupWithoutWaitingForOtherRootTeardown()
    async throws
  {
    let f = try await RuntimeSourceFixture.make()
    defer { f.remove() }
    await f.sessionReplies()
    let coordinator = FlowConversationShellCoordinator(
      userID: f.edit.disk.lease.userID, source: f.source)
    await coordinator.load()
    let owned = await f.edit.http.lifecycle.workIDs
    #expect(owned.count == 6)
    let events = await f.edit.http.lifecycle.finishedWorkEvents
    let completed = Task { () -> Bool in
      var iterator = events.makeAsyncIterator()
      var seen: Set<UUID> = []
      while !owned.isSubset(of: seen) {
        guard let id = await iterator.next() else { return false }
        seen.insert(id)
      }
      return true
    }
    coordinator.invalidateSynchronously()
    let finished = await withTaskGroup(of: Bool.self) { group in
      group.addTask { await completed.value }
      group.addTask {
        try? await Task.sleep(for: .seconds(2))
        return false
      }
      let result = await group.next() ?? false
      completed.cancel()
      group.cancelAll()
      return result
    }
    #expect(finished)
    #expect(await f.edit.http.lifecycle.workCount == 0)
    await coordinator.close()
  }
  @Test func opensOnceAndSynchronouslyWithdrawsTheOldOwner() async throws {
    let f = try await RuntimeSourceFixture.make()
    defer { f.remove() }
    await f.sessionReplies()
    let coordinator = FlowConversationShellCoordinator(
      userID: f.edit.disk.lease.userID, source: f.source)
    #expect(coordinator.model == nil && coordinator.phase == .idle)
    await coordinator.load()
    let model = try #require(coordinator.model)
    #expect(coordinator.phase == .ready && model.mealEditor != nil)
    model.composer = "owned synthetic text"
    await coordinator.load()
    #expect(await f.edit.http.stub.requests.count == 1)
    coordinator.invalidateSynchronously()
    #expect(coordinator.model == nil && coordinator.phase == .closed)
    #expect(model.isClosed && model.composer.isEmpty)
    await coordinator.close()
    await coordinator.load()
    #expect(await f.edit.http.lifecycle.workCount == 0)
    #expect(await f.edit.http.stub.requests.count == 1)
  }
  @Test func lateOpenAfterOwnerWithdrawalCannotPublishOrRestart() async throws {
    let f = try await RuntimeSourceFixture.make()
    defer { f.remove() }
    let barrier = ConversationControllerBarrier()
    await f.edit.http.stub.respond { _, _ in
      await barrier.enter()
      return try f.wire.sessionReply(epoch: f.edit.group.epoch)
    }
    let coordinator = FlowConversationShellCoordinator(
      userID: f.edit.disk.lease.userID, source: f.source)
    let opening = Task { await coordinator.load() }
    #expect(await barrier.waitEnteredOrFinished())
    #expect(coordinator.phase == .loading && coordinator.model == nil)
    coordinator.invalidateSynchronously()
    await barrier.release()
    await opening.value
    #expect(coordinator.model == nil && coordinator.phase == .closed)
    await coordinator.close()
    await coordinator.load()
    #expect(await f.edit.http.stub.requests.count == 1)
    #expect(await f.edit.http.lifecycle.workCount == 0)
  }
  @Test func unavailableColdSessionOffersActualRetryWithoutDemoOrInventedPatient() async throws {
    let f = try await RuntimeSourceFixture.make()
    defer { f.remove() }
    await f.edit.http.stub.respond { _, _ in throw URLError(.networkConnectionLost) }
    let coordinator = FlowConversationShellCoordinator(
      userID: f.edit.disk.lease.userID, source: f.source)
    await coordinator.load()
    #expect(coordinator.model == nil && coordinator.phase == .unavailable)
    #expect(await f.edit.http.lifecycle.workCount == 0)
    await f.sessionReplies()
    await coordinator.load()
    #expect(
      coordinator.phase == .ready
        && coordinator.model?.acceptedIdentity?.ownerID == f.edit.group.ownerID)
    #expect(await f.edit.http.stub.requests.count == 2)
    await coordinator.close()
  }
  @Test func closingTheShellPreservesOriginalEncryptedUnknownIntent() async throws {
    let f = try await RuntimeSourceFixture.make()
    defer { f.remove() }
    await f.edit.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true {
        return try f.wire.sessionReply(epoch: f.edit.group.epoch)
      }
      throw URLError(.networkConnectionLost)
    }
    let coordinator = FlowConversationShellCoordinator(
      userID: f.edit.disk.lease.userID, source: f.source)
    await coordinator.load()
    let model = try #require(coordinator.model)
    model.composer = "arroz200g owned original"
    await model.submit()
    let original = try Data(contentsOf: f.report.store.fileURL(owner: f.edit.disk.owner))
    let entries = try f.report.store.load(owner: f.edit.disk.owner, key: f.report.key)
    #expect(entries.count == 1 && entries.first?.hold == .unknownOutcome)
    coordinator.invalidateSynchronously()
    #expect(coordinator.model == nil && model.pendingRows.isEmpty && model.composer.isEmpty)
    await coordinator.close()
    #expect(try Data(contentsOf: f.report.store.fileURL(owner: f.edit.disk.owner)) == original)
    #expect(await f.edit.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    #expect(await f.edit.http.lifecycle.workCount == 0)
  }
}

struct RuntimeSourceFixture: Sendable {
  let edit: EditControllerFixture
  let report: OutboxDiskFixture
  let wire: ConversationControllerWireFixture
  let source: FlowConversationSessionSource
  static func make() async throws -> Self {
    let edit = try EditControllerFixture()
    let report = try OutboxDiskFixture()
    await edit.seedKey()
    let keys = OutboxKeychainFake()
    await keys.seed(report.key.withUnsafeBytes { Data($0) }, owner: edit.disk.owner.hash)
    let source = FlowConversationSessionSource(
      transport: edit.http.transport, lifecycle: edit.http.lifecycle,
      media: nil, store: report.store, keyVault: .init(service: "synthetic", security: keys),
      editing: .init(store: edit.disk.store, keyVault: edit.vault))
    return .init(edit: edit, report: report, wire: try .init(), source: source)
  }
  func sessionReplies() async {
    await edit.http.stub.respond { _, _ in try wire.sessionReply(epoch: edit.group.epoch) }
  }
  func remove() {
    edit.disk.remove()
    report.remove()
  }
}
