import Foundation
import Testing

@testable import BodyFlow

@Suite("Owned Flow media uses the actual scoped HTTP repository")
struct ConversationMediaTransportTests {
  @Test func everyAssetCallKeepsOriginalPatientPreconditionAndLegacyOmitsIt() async throws {
    let f = try ConversationHTTPFixture()
    let assetID = UUID().uuidString.lowercased()
    await f.stub.respond { request, _ in
      try mediaReply(assetID: assetID, create: request.url?.path == "/api/mobile/v1/media")
    }
    let lease = await f.lifecycle.leaseForRequest()
    let context = await makeContext(f)
    let repo = try await MobileConversationMediaRepository.scoped(
      transport: f.transport, lifecycle: f.lifecycle, lease: lease, context: context)
    let upload = MediaUploadRequest(
      kind: .mealPhoto, mimeType: "image/jpeg", sizeBytes: 20, durationMS: nil)
    let created = try await repo.create(attempt(.mediaCreate, upload, "media-create"))
    #expect(created.asset.id == assetID)
    let command = MediaAssetCommand(assetID: assetID)
    _ = try await repo.complete(attempt(.mediaComplete, command, "media-complete"))
    _ = try await repo.requestProcessing(attempt(.mediaProcess, command, "media-process"))
    _ = try await repo.asset(id: assetID)
    try await repo.delete(attempt(.mediaDelete, command, "media-delete"))
    let requests = await f.stub.requests
    #expect(requests.count == 5)
    #expect(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "X-Conversation-Owner") == f.ownerID.uuidString.lowercased()
      })
    #expect(
      requests.allSatisfy {
        $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(lease.bearer)"
      })
    _ = try await MobileMediaRepository(transport: f.transport).asset(id: assetID)
    #expect(await f.stub.requests.last?.value(forHTTPHeaderField: "X-Conversation-Owner") == nil)
  }

  @Test func revokedPatientMappingCannotReadOrMutateOldAssetOrRetagTransport() async throws {
    let f = try ConversationHTTPFixture()
    let authority = ConversationOutboxObservationAuthority()
    let lease = await f.lifecycle.leaseForRequest()
    let id = try authority.beginRefresh()
    let observed = try authority.accept(
      refreshID: id, authUserID: UUID(uuidString: lease.userID)!, ownerID: f.ownerID,
      localSessionGeneration: lease.generation, epoch: f.epoch)
    let context = ConversationCommandContext(
      observation: observed, observedAt: "2026-11-04T12:00:00Z")
    let repo = try await MobileConversationMediaRepository.scoped(
      transport: f.transport, lifecycle: f.lifecycle, lease: lease, context: context)
    let changed = try authority.beginRefresh()
    _ = try authority.accept(
      refreshID: changed, authUserID: observed.authUserID, ownerID: UUID(),
      localSessionGeneration: lease.generation, epoch: f.epoch)
    await #expect(throws: (any Error).self) {
      try await repo.asset(id: UUID().uuidString.lowercased())
    }
    #expect(await f.stub.requests.isEmpty)
    let other = SessionLease(
      userID: UUID().uuidString.lowercased(), generation: 8, bearer: "synthetic-other")
    await #expect(throws: (any Error).self) {
      try await MobileConversationMediaRepository.scoped(
        transport: f.transport.scoped(to: other), lifecycle: f.lifecycle, lease: lease,
        context: context)
    }
    #expect(await f.stub.requests.isEmpty)
  }

  private func makeContext(_ f: ConversationHTTPFixture) async -> ConversationCommandContext {
    let lease = await f.lifecycle.leaseForRequest()
    return .init(
      observation: .init(
        authUserID: UUID(uuidString: lease.userID)!, ownerID: f.ownerID,
        localSessionGeneration: lease.generation, epoch: f.epoch),
      observedAt: "2026-11-04T12:00:00Z")
  }
  private func attempt<P>(_ operation: MutationOperation, _ payload: P, _ key: String) throws
    -> MutationAttempt<P>
  {
    .init(
      operation: operation, key: try IdempotencyKey(validating: key), payload: payload,
      createdAt: Date(timeIntervalSince1970: 1_000))
  }
  private func mediaReply(assetID: String, create: Bool) throws -> ConversationHTTPReply {
    let asset: [String: Any] = [
      "id": assetID, "kind": "meal_photo", "status": "processed", "failure_stage": NSNull(),
      "failure_code": NSNull(),
    ]
    let data: [String: Any] =
      create ? ["asset": asset, "upload": NSNull(), "replayed": false] : asset
    return .init(
      status: 200,
      body: try JSONSerialization.data(withJSONObject: [
        "data": data, "meta": ["api_version": "v1", "request_id": "media-test"],
      ]))
  }
}
