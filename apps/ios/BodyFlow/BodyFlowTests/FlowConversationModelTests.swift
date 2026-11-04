import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@Suite("Actual command-backed Flow feature model")
@MainActor
struct FlowConversationModelTests {
  @Test func photoCommandIsDurableBeforeProcessingAndProcessingLossRestoresSameQueuedIntent()
    async throws
  {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    let staging = MediaStagingStore(
      temporaryDirectory: f.disk.store.root.appendingPathComponent("staging"))
    let url = try stageConversationSyntheticMedia(
      staging: staging, data: Data("synthetic-media".utf8), fileExtension: "jpg")
    let media = StagedMedia(
      fileURL: url, kind: .mealPhoto, mimeType: "image/jpeg", sizeBytes: 15, duration: nil,
      channel: .gallery)
    let assetID = "40000000-0000-4000-8000-000000000001"
    let processCount = FlowModelMediaPhaseProbe()
    await f.http.stub.respond { request, _ in
      let path = request.url?.path ?? ""
      if path.hasSuffix("/session") { return try f.wire.sessionReply() }
      if path.contains("/media") {
        if path.hasSuffix("/process") {
          let stored = try f.disk.store.load(owner: f.owner, key: f.disk.key)
          #expect(stored.count == 1 && stored[0].state == .queued)
          let command = try ConversationMealCommand(wireBody: #require(stored.first?.wireBody))
          #expect(
            request.value(forHTTPHeaderField: "Idempotency-Key")
              == "cmedia1:\(command.commandID.uuidString.lowercased()):process")
          _ = await processCount.next()
          throw URLError(.networkConnectionLost)
        }
        return try modelMediaReply(
          request, assetID: assetID, state: await processCount.value > 0 ? "processed" : "uploaded")
      }
      return try f.wire.savedReply(forPosted: request)
    }
    let dependencies = FlowConversationMediaDependencies(
      uploader: ConversationMediaUploaderProbe(), staging: staging)
    let m = try await f.open(media: dependencies)
    let identity = try #require(m.captureContext)
    try m.attach(media, expectedContext: identity)
    m.composer = "  legenda e\u{301} 😀  "
    await m.submit()
    let stored = try #require(f.disk.store.load(owner: f.owner, key: f.disk.key).first)
    #expect(stored.state == .queued && m.savedRows.isEmpty && m.pendingRows.count == 1)
    let original = stored.wireBody
    let id = stored.commandID
    #expect(
      await f.http.stub.requests.filter { $0.url?.path.hasSuffix("/meal-commands") == true }.isEmpty
    )
    await m.close()
    let reopened = try await f.open(media: dependencies)
    await reopened.sendQueued(commandID: id)
    #expect(reopened.savedRows.first?.id == id && reopened.pendingRows.isEmpty)
    let requests = await f.http.stub.requests
    #expect(requests.filter { $0.url?.path.hasSuffix("/process") == true }.count == 1)
    let posts = requests.filter { $0.url?.path.hasSuffix("/meal-commands") == true }
    #expect(posts.count == 1 && posts.first?.httpBody == original)
    #expect(
      !requests.contains {
        $0.url?.path.contains("meal-drafts") == true || $0.httpMethod == "DELETE"
      })
    await reopened.close()
  }

  @Test func captureFromFormerPatientCannotAttachAfterSameAuthMappingChanges() async throws {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    let mapping = ConversationControllerMapping(owner: f.wire.ownerID)
    await f.http.stub.respond { _, _ in try f.wire.sessionReply(owner: await mapping.owner) }
    let staging = MediaStagingStore(
      temporaryDirectory: f.disk.store.root.appendingPathComponent("staging"))
    let m = try await f.open(
      media: .init(uploader: ConversationMediaUploaderProbe(), staging: staging))
    let old = try #require(m.captureContext)
    let file = try stageConversationSyntheticMedia(
      staging: staging, data: Data("synthetic-media".utf8), fileExtension: "jpg")
    await mapping.replace(UUID())
    await m.refresh()
    #expect(throws: (any Error).self) {
      try m.attach(
        .init(
          fileURL: file, kind: .mealPhoto, mimeType: "image/jpeg", sizeBytes: 15, duration: nil,
          channel: .camera), expectedContext: old)
    }
    #expect(m.attachment == nil && !m.canSubmit)
    #expect(await f.http.stub.requests.allSatisfy { $0.url?.path.hasSuffix("/session") == true })
    #expect(!FileManager.default.fileExists(atPath: file.path))
    await m.close()
  }

  @Test func terminalQuestionNeverTurnsReplyIntoUnlinkedFreshMeal() async throws {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    await f.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
      return try f.wire.stateReply(
        "not_recorded", for: ConversationMealCommand(wireBody: #require(request.httpBody)))
    }
    let m = try await f.open()
    m.composer = "comi arroz"
    await m.submit()
    let original = try #require(f.disk.store.load(owner: f.owner, key: f.disk.key).first)
    #expect(m.terminalQuestion?.reason == "missing_quantity")
    #expect(
      m.pendingRows.first?.id == original.commandID && m.savedRows.isEmpty
        && m.savedEffectRevision == 0)
    m.composer = "30g"
    #expect(!m.canSubmit)
    await m.submit()
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    #expect(
      try f.disk.store.load(owner: f.owner, key: f.disk.key).first?.wireBody == original.wireBody)
    m.beginIndependentReport()
    #expect(
      m.composer.isEmpty && m.terminalQuestion == nil && m.pendingRows.first?.hold == .notRecorded)
    m.composer = "outra refeição independente"
    #expect(m.canSubmit)
    await m.close()
  }

  @Test func supersededPOSTFailureCannotReplaceNewerRefreshPresentation() async throws {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
      await barrier.enter()
      throw URLError(.networkConnectionLost)
    }
    let m = try await f.open()
    m.composer = "arroz200g"
    let old = Task {
      await m.submit()
      await barrier.finish()
    }
    try #require(await barrier.waitEnteredOrFinished())
    await m.refresh()
    #expect(m.failure == nil && m.pendingRows.count == 1)
    await barrier.release()
    await old.value
    #expect(m.failure == nil)
    #expect(m.pendingRows.first?.state == .dispatchedUnknown)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await m.close()
  }

  @Test func newTextHasOnePreparedIdentityAndOnlyFactualACKPublishesSaved() async throws {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    await f.http.stub.respond { request, _ in
      request.url?.path.hasSuffix("/session") == true
        ? try f.wire.sessionReply() : try f.wire.savedReply(forPosted: request)
    }
    let m = try await f.open()
    m.composer = "  arroz200g e\u{301} 😀  "
    try #require(m.canSubmit)
    await m.submit()
    #expect(m.composer.isEmpty)
    #expect(m.savedRows.count == 1 && m.savedRows[0].feedback == nil && m.savedEffectRevision == 1)
    #expect(m.pendingRows.isEmpty)
    let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 1)
    let command = try ConversationMealCommand(wireBody: #require(posts.first?.httpBody))
    if case .text(let text) = command.source {
      #expect(text.utf16.elementsEqual("  arroz200g e\u{301} 😀  ".utf16))
    } else {
      Issue.record("Text source must remain text")
    }
    #expect(m.savedRows[0].command.commandID == command.commandID)
    #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
    await m.close()
  }

  @Test func failedLocalPersistenceKeepsDraftAndPreparedIDForExplicitRetry() async throws {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    await f.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
      throw URLError(.networkConnectionLost)
    }
    let m = try await f.open()
    m.composer = "source that must not be renewed"
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: f.disk.store.root.path)
    await m.submit()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: f.disk.store.root.path)
    let originalID = try #require(m.pendingDraftID)
    #expect(m.composer == "source that must not be renewed" && m.savedRows.isEmpty)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
    await m.submit()
    let rows = try f.disk.store.load(owner: f.owner, key: f.disk.key)
    #expect(rows.count == 1 && rows[0].commandID == originalID && rows[0].hold == .unknownOutcome)
    #expect(m.composer.isEmpty && m.savedRows.isEmpty)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await m.close()
  }

  @Test func nextDraftTypedDuringPOSTSurvivesItsCompletion() async throws {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    let barrier = ConversationControllerBarrier()
    await f.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
      await barrier.enter()
      return try f.wire.savedReply(forPosted: request)
    }
    let m = try await f.open()
    m.composer = "first original source"
    let work = Task {
      await m.submit()
      await barrier.finish()
    }
    try #require(await barrier.waitEnteredOrFinished())
    m.composer = "next unsent draft"
    await barrier.release()
    await work.value
    #expect(m.composer == "next unsent draft" && m.savedRows.count == 1)
    await m.close()
  }

  @Test func unknownOutcomeUsesGETAndOnlyExplicitReadPermissionCanReplay() async throws {
    let f = try await Fixture.make()
    defer { f.disk.remove() }
    await f.http.stub.respond { request, _ in
      if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
      if request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
      let command = try ConversationMealCommand(
        wireBody: #require(f.disk.store.load(owner: f.owner, key: f.disk.key).first?.wireBody))
      return try f.wire.stateReply("pending", for: command)
    }
    let m = try await f.open()
    m.composer = "arroz200g"
    await m.submit()
    let id = try #require(f.disk.store.load(owner: f.owner, key: f.disk.key).first?.commandID)
    #expect(m.savedRows.isEmpty)
    await m.reconcile(commandID: id)
    #expect(m.canResubmit(commandID: id))
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await m.resubmit(commandID: id)
    #expect(!m.canResubmit(commandID: id))
    let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 2 && posts[0].httpBody == posts[1].httpBody)
    #expect(m.savedRows.isEmpty)
    await m.close()
  }

  @Test func newPatientSameEpochRedactsOldPendingAndClearsItsDraft() async throws {
    let f = try await Fixture.make(seed: true)
    defer { f.disk.remove() }
    let mapping = ConversationControllerMapping(owner: f.wire.ownerID)
    await f.http.stub.respond { _, _ in try f.wire.sessionReply(owner: await mapping.owner) }
    let m = try await f.open()
    #expect(m.pendingRows.count == 1)
    m.composer = "patient A private draft"
    let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
    await mapping.replace(UUID())
    await m.refresh()
    #expect(m.pendingRows.isEmpty && m.savedRows.isEmpty && m.composer.isEmpty)
    #expect(m.heldRows.count == 1)
    #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
    await m.close()
  }

  @Test func authCancellationClearsRetainedModelAndNeverPublishesOldSource() async throws {
    let f = try await Fixture.make(seed: true)
    defer { f.disk.remove() }
    await f.http.stub.respond { _, _ in try f.wire.sessionReply() }
    let m = try await f.open()
    let events = await f.http.lifecycle.finishedWorkEvents
    m.composer = "private draft"
    let work = await f.http.lifecycle.workIDs
    #expect(work.count == 3)
    await f.http.lifecycle.replace(
      .init(userID: "90000000-0000-4000-8000-000000000002", generation: 8, bearer: "synthetic-B"))
    let closed = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        var left = work
        for await id in events {
          left.remove(id)
          if left.isEmpty { return true }
        }
        return false
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(1))
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }
    #expect(
      closed && m.isClosed && m.composer.isEmpty && m.pendingRows.isEmpty && m.savedRows.isEmpty)
    await m.submit()
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
  }

  private struct Fixture {
    let disk: OutboxDiskFixture
    let http: ConversationHTTPFixture
    let owner: ConversationOutboxOwner
    let vault: ConversationOutboxKeyVault
    let wire: ConversationControllerWireFixture
    static func make(seed: Bool = false) async throws -> Self {
      let disk = try OutboxDiskFixture()
      let http = try ConversationHTTPFixture()
      let wire = try ConversationControllerWireFixture()
      let owner = try ConversationOutboxOwner(lease: await http.lifecycle.leaseForRequest())
      let keys = OutboxKeychainFake()
      await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
      _ = try disk.store.containsCiphertext(owner: owner)
      if seed {
        try disk.store.update(owner: owner, key: disk.key) {
          $0.append(
            .init(
              command: wire.command, originalServerEpoch: wire.epoch,
              originalPatientOwnerID: wire.ownerID))
        }
      }
      return .init(
        disk: disk, http: http, owner: owner, vault: .init(service: "synthetic", security: keys),
        wire: wire)
    }
    func open(media: FlowConversationMediaDependencies? = nil) async throws -> FlowConversationModel
    {
      try await .open(
        transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: vault,
        media: media)
    }
  }
}

extension ConversationControllerWireFixture {
  func savedReply(forPosted request: URLRequest) throws -> ConversationHTTPReply {
    let command = try ConversationMealCommand(wireBody: #require(request.httpBody))
    return try retarget(savedReply(), command: command)
  }
  func stateReply(_ status: String, for command: ConversationMealCommand) throws
    -> ConversationHTTPReply
  {
    try retarget(stateReply(status), command: command)
  }
  private func retarget(_ original: ConversationHTTPReply, command: ConversationMealCommand) throws
    -> ConversationHTTPReply
  {
    var envelope = try #require(JSONSerialization.jsonObject(with: original.body) as? [String: Any])
    var packet = try #require(envelope["data"] as? [String: Any])
    let id = command.commandID.uuidString.lowercased()
    packet["command_id"] = id
    packet["input_hash"] = command.inputHash
    if var receipt = packet["receipt"] as? [String: Any] {
      receipt["command_id"] = id
      receipt["input_hash"] = command.inputHash
      receipt["provider_key"] = "conversation.meal/\(ownerID.uuidString.lowercased())/\(id)"
      packet["receipt"] = receipt
      packet["feedback"] = NSNull()
    }
    envelope["data"] = packet
    return .init(
      status: original.status, body: try JSONSerialization.data(withJSONObject: envelope))
  }
}

private func modelMediaReply(_ request: URLRequest, assetID: String, state: String) throws
  -> ConversationHTTPReply
{
  let asset: [String: Any] = [
    "id": assetID, "kind": "meal_photo", "status": state, "failure_stage": NSNull(),
    "failure_code": NSNull(),
  ]
  var created = asset
  created["status"] = "pending_upload"
  let ticket: [String: Any] = [
    "signed_url":
      "https://synthetic.invalid/storage/v1/object/upload/sign/bucket/fixture?token=synthetic",
    "method": "PUT", "headers": ["content-type": "image/jpeg"],
    "expires_at": "2030-01-01T00:00:00Z",
  ]
  let data: [String: Any] =
    request.url?.path == "/api/mobile/v1/media"
    ? ["asset": created, "upload": ticket, "replayed": false] : asset
  return .init(
    status: 200,
    body: try JSONSerialization.data(withJSONObject: [
      "data": data, "meta": ["api_version": "v1", "request_id": "media-model-test"],
    ]))
}

private actor FlowModelMediaPhaseProbe {
  private(set) var value = 0
  func next() -> Int {
    value += 1
    return value
  }
}
