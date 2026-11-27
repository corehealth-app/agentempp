import Foundation

/// Reuses the real media API without the legacy draft/extractor. Each call
/// retains the original Auth lease and patient precondition from an accepted
/// command context; neither an asset snapshot nor a URL establishes ownership.
struct MobileConversationMediaRepository: MealMediaProviding {
  private let media: MobileMediaRepository

  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding,
    lease: SessionLease, context: ConversationCommandContext
  ) async throws -> Self {
    let scoped = transport.scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    let envelope = ConversationOwnedMediaEnvelope(
      transport: scoped, lifecycle: lifecycle, lease: lease, context: context)
    try await envelope.validate()
    return .init(media: MobileMediaRepository(transport: envelope))
  }
  func create(_ attempt: MutationAttempt<MediaUploadRequest>) async throws -> MediaCreateSnapshot {
    try await media.create(attempt)
  }
  func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> MediaAssetSnapshot {
    try await media.complete(attempt)
  }
  func requestProcessing(_ attempt: MutationAttempt<MediaAssetCommand>) async throws
    -> MediaAssetSnapshot
  { try await media.requestProcessing(attempt) }
  func asset(id: String) async throws -> MediaAssetSnapshot { try await media.asset(id: id) }
  func transcriptForAudio(id: UUID) async throws -> String {
    let assetID = id.uuidString.lowercased()
    let response: ProcessedAudio = try await media.transport.executeMealCapture {
      try MobileAPIRequest(method: .get, path: MobileMediaRepository.assetPath(assetID))
    }
    guard response.id == assetID, response.kind == MediaUploadKind.audioNote.rawValue,
      response.status == "processed"
    else { throw MealCaptureFailure.unreadableMedia }
    guard let text = response.result?.text.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty, text.count <= MealMediaLimits.maximumTextLength
    else { throw MealCaptureFailure.nothingRecognized }
    return text
  }
  func delete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws {
    try await media.delete(attempt)
  }

  private struct ProcessedAudio: Codable, Sendable {
    struct Result: Codable, Sendable { let text: String }
    let id: String
    let kind: String
    let status: String
    let result: Result?
  }
}

private struct ConversationOwnedMediaEnvelope: MobileAPIEnvelopeExecuting {
  let transport: MobileAPITransport
  let lifecycle: any SessionLifecycleProviding
  let lease: SessionLease
  let context: ConversationCommandContext

  func validate() async throws {
    try Task.checkCancellation()
    try await lifecycle.validate(lease)
    guard !context.observation.isEnqueueOnly, context.authUserID == UUID(uuidString: lease.userID),
      context.sessionGeneration == lease.generation
    else { throw SessionLifecycleError.sessionSuperseded }
    try context.withCurrentAuthority {}
    try Task.checkCancellation()
  }
  func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>)
    async throws -> MobileResponse<Response>
  {
    try await validate()
    let response = try await transport.executeEnvelope(
      request.withConversationMediaOwner(context.ownerID))
    try await validate()
    return response
  }
}
