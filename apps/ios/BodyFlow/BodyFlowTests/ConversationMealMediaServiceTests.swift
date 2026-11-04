import Foundation
import Testing

@testable import BodyFlow

@Suite("Command media preparation preserves owned assets and processing identity")
struct ConversationMealMediaServiceTests {
  @Test func aFileOutsideItsOwnedStagingAreaCannotLeaveTheDevice() async throws {
    let f = try await Fixture.make()
    defer { f.remove() }
    let outside = f.directory.appendingPathComponent("not-a-capture.jpg")
    try Data("private outside bytes".utf8).write(to: outside)
    await f.http.stub.respond { request, _ in try f.reply(request) }
    let service = try await f.open()
    let staged = StagedMedia(
      fileURL: outside, kind: .mealPhoto, mimeType: "image/jpeg", sizeBytes: 21, duration: nil,
      channel: .camera)
    await #expect(throws: MealCaptureFailure.invalidInput) {
      try await service.upload(staged, captureID: UUID(), context: f.context)
    }
    #expect(await f.http.stub.requests.isEmpty)
    #expect(await f.uploader.count == 0)
    #expect(FileManager.default.fileExists(atPath: outside.path))
    await service.close()
  }

  @Test func alreadyProcessingOnlyReadsAndNeverRequestsAnotherModelAttempt() async throws {
    let f = try await Fixture.make()
    defer { f.remove() }
    await f.http.stub.respond { request, _ in try f.reply(request, assetState: "processing") }
    let service = try await f.open()
    let command = try ConversationMealCommand(
      source: .media(assetID: #require(UUID(uuidString: f.assetID)), caption: nil))
    await #expect(throws: MealCaptureFailure.processingTimedOut) {
      try await service.process(
        command: command, expectedContext: f.context.identity, context: f.context)
    }
    let requests = await f.http.stub.requests
    #expect(requests.count == 3 && requests.allSatisfy { $0.httpMethod == "GET" })
    await service.close()
  }

  @Test func unqueuedCaptureCanBeExplicitlyDiscardedButCannotSilentlyRestart() async throws {
    let f = try await Fixture.make()
    defer { f.remove() }
    await f.http.stub.respond { request, _ in try f.reply(request) }
    let service = try await f.open()
    let capture = UUID()
    _ = try await service.upload(f.staged, captureID: capture, context: f.context)
    try await service.discard(captureID: capture, context: f.context)
    let requests = await f.http.stub.requests
    #expect(requests.filter { $0.httpMethod == "DELETE" }.count == 1)
    await #expect(throws: (any Error).self) {
      try await service.upload(f.staged, captureID: capture, context: f.context)
    }
    #expect(await f.http.stub.requests.count == requests.count)
    await service.close()
  }

  @Test func uploadDoesNotInvokeExtractorAndProtectedAssetSurvivesClose() async throws {
    let f = try await Fixture.make()
    defer { f.remove() }
    await f.http.stub.respond { request, _ in try f.reply(request) }
    let service = try await f.open()
    let capture = UUID()
    let asset = try await service.upload(f.staged, captureID: capture, context: f.context)
    #expect(asset.uuidString.lowercased() == f.assetID)
    #expect(
      !(await f.http.stub.requests).contains {
        $0.url?.path.hasSuffix("/process") == true || $0.url?.path.contains("meal-drafts") == true
      })
    #expect(await f.uploader.count == 1)
    #expect(!FileManager.default.fileExists(atPath: f.staged.fileURL.path))
    let command = try ConversationMealCommand(
      source: .media(assetID: asset, caption: "original caption"))
    try await service.retainForEnqueue(
      captureID: capture, command: command, expectedContext: f.context.identity)
    try await service.discard(captureID: capture, context: f.context)
    await service.close()
    #expect(!(await f.http.stub.requests).contains { $0.httpMethod == "DELETE" })
  }

  @Test func explicitProcessingUsesOriginalCommandKeyAndNeverCallsMealDrafts() async throws {
    let f = try await Fixture.make()
    defer { f.remove() }
    await f.http.stub.respond { request, _ in
      try f.reply(request, assetState: request.httpMethod == "GET" ? "uploaded" : "processed")
    }
    let service = try await f.open()
    let command = try ConversationMealCommand(
      source: .media(assetID: #require(UUID(uuidString: f.assetID)), caption: nil))
    try await service.process(
      command: command, expectedContext: f.context.identity, context: f.context)
    let requests = await f.http.stub.requests
    let posts = requests.filter { $0.httpMethod == "POST" }
    #expect(posts.count == 1 && posts[0].url?.path.hasSuffix("/process") == true)
    #expect(
      posts[0].value(forHTTPHeaderField: "Idempotency-Key")
        == "cmedia1:\(command.commandID.uuidString.lowercased()):process")
    #expect(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "X-Conversation-Owner")
          == f.context.ownerID.uuidString.lowercased()
      })
    #expect(!requests.contains { $0.url?.path.contains("meal-drafts") == true })
    await service.close()
  }

  @Test func unknownProcessingOutcomeOnlyReadsOnExplicitResumeAndNeverRenewsKey() async throws {
    let f = try await Fixture.make()
    defer { f.remove() }
    let phase = ConversationControllerCounter()
    await f.http.stub.respond { request, _ in
      if request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
      return try f.reply(request, assetState: await phase.next() == 1 ? "uploaded" : "processed")
    }
    let service = try await f.open()
    let command = try ConversationMealCommand(
      source: .media(assetID: #require(UUID(uuidString: f.assetID)), caption: nil))
    await #expect(throws: (any Error).self) {
      try await service.process(
        command: command, expectedContext: f.context.identity, context: f.context)
    }
    try await service.process(
      command: command, expectedContext: f.context.identity, context: f.context)
    #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
    await service.close()
  }

  private struct Fixture: Sendable {
    let directory: URL
    let staging: MediaStagingStore
    let staged: StagedMedia
    let http: ConversationHTTPFixture
    let lease: SessionLease
    let context: ConversationCommandContext
    let uploader = ConversationMediaUploaderProbe()
    let assetID = "40000000-0000-4000-8000-000000000001"
    static func make() async throws -> Self {
      let http = try ConversationHTTPFixture()
      let lease = await http.lifecycle.leaseForRequest()
      let authUserID = try #require(UUID(uuidString: lease.userID))
      let context = ConversationCommandContext(
        observation: .init(
          authUserID: authUserID, ownerID: http.ownerID, localSessionGeneration: lease.generation,
          epoch: http.epoch), observedAt: "2026-11-04T12:00:00Z")
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "conversation-media-test-\(UUID())")
      let staging = MediaStagingStore(temporaryDirectory: directory)
      let url = try stageConversationSyntheticMedia(
        staging: staging, data: Data("synthetic-media".utf8), fileExtension: "jpg")
      return .init(
        directory: directory, staging: staging,
        staged: .init(
          fileURL: url, kind: .mealPhoto, mimeType: "image/jpeg", sizeBytes: 15, duration: nil,
          channel: .camera), http: http, lease: lease, context: context)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func open() async throws -> ConversationMealMediaService {
      try await .open(
        transport: http.transport, lifecycle: http.lifecycle, lease: lease, uploader: uploader,
        staging: staging, pollInterval: .zero, maximumPolls: 2)
    }
    func reply(_ request: URLRequest, assetState: String = "uploaded") throws
      -> ConversationHTTPReply
    {
      let asset: [String: Any] = [
        "id": assetID, "kind": "meal_photo", "status": assetState, "failure_stage": NSNull(),
        "failure_code": NSNull(),
      ]
      let create = request.url?.path == "/api/mobile/v1/media"
      let ticket: [String: Any] = [
        "signed_url":
          "https://synthetic.invalid/storage/v1/object/upload/sign/bucket/fixture?token=synthetic",
        "method": "PUT", "headers": ["content-type": "image/jpeg"],
        "expires_at": "2030-01-01T00:00:00Z",
      ]
      var created = asset
      created["status"] = "pending_upload"
      let data: [String: Any] =
        create ? ["asset": created, "upload": ticket, "replayed": false] : asset
      return .init(
        status: 200,
        body: try JSONSerialization.data(withJSONObject: [
          "data": data, "meta": ["api_version": "v1", "request_id": "media-pipeline-test"],
        ]))
    }
  }
}

actor ConversationMediaUploaderProbe: StorageUploading {
  private(set) var count = 0
  func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
    #expect(FileManager.default.fileExists(atPath: media.fileURL.path))
    #expect(ticket.method == "PUT")
    count += 1
  }
}

/// Fixture preparation only. macOS Foundation currently refuses the iOS data
/// protection write option (NSCocoaError513; isolated probe in evidence). The
/// iOS native tests continue through the actual protected staging API.
func stageConversationSyntheticMedia(staging: MediaStagingStore, data: Data, fileExtension: String)
  throws -> URL
{
  #if SWIFT_PACKAGE && os(macOS)
    let folder = staging.root.appendingPathComponent(
      UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let file = folder.appendingPathComponent("capture.\(fileExtension)")
    try data.write(to: file, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    return file
  #else
    return try staging.stage(data, fileExtension: fileExtension)
  #endif
}
