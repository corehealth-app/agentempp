import Foundation

/// Read-only actual BFF facts. No read acknowledges an outbox entry, mutates a
/// registration or establishes owner authority from a header/payload alone.
struct MobileConversationHistoryRepository: Sendable {
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let lease: SessionLease
  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(
      MobileConversationCommandRepository.responseBodyLimit
    ).scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    return .init(transport: scoped, lifecycle: lifecycle, lease: lease)
  }
  func group(commandID: UUID, originalInputHash: String, context: ConversationCommandContext)
    async throws -> ConversationMealGroupSnapshot
  {
    try await validate(context)
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationMealGroupSnapshot>(
        method: .get,
        path: "/api/mobile/v1/conversation/meal-commands/\(commandID.uuidString.lowercased())/meal",
        conversation: .mealGroup(
          epoch: context.epoch, ownerID: context.ownerID, inputHash: originalInputHash)))
    try await validate(context)
    let group = response.data
    guard response.statusCode == 200, group.ownerID == context.ownerID,
      group.commandID == commandID,
      group.epoch == context.epoch, group.originalInputHash == originalInputHash,
      let observed = ConversationProtocolInstant(group.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt),
      observed >= accepted
    else { throw MobileAPITransportError.invalidResponse }
    return group
  }
  /// Returning this read does not acknowledge or remove any outbox intent.
  /// Terminal delivery is an explicit separate controller capability.
  func journal(cursor: String? = nil, limit: Int = 10, context: ConversationCommandContext)
    async throws -> ConversationJournalRead
  {
    try await validate(context)
    var query = [URLQueryItem(name: "limit", value: String(limit))]
    if let cursor { query.append(.init(name: "cursor", value: cursor)) }
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationJournalPageSnapshot>(
        method: .get,
        path: "/api/mobile/v1/conversation/journal", queryItems: query,
        conversation: .journal(epoch: context.epoch, ownerID: context.ownerID)))
    try await validate(context)
    guard response.statusCode == 200,
      response.data.matches(
        authUserID: context.authUserID, ownerID: context.ownerID, epoch: context.epoch),
      let observed = ConversationProtocolInstant(response.data.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt), observed >= accepted
    else { throw MobileAPITransportError.invalidResponse }
    return .init(page: response.data, context: context)
  }
  private func validate(_ context: ConversationCommandContext) async throws {
    guard !context.observation.isEnqueueOnly, context.authUserID == UUID(uuidString: lease.userID),
      context.sessionGeneration == lease.generation
    else { throw ConversationOutboxError.invalidServerObservation }
    try await lifecycle.validate(lease)
    try Task.checkCancellation()
    try context.withCurrentAuthority {}
  }
}

/// Constructible only by the actual owned read adapter after its pre/post
/// lease, mapping, epoch, clock and closed HTTP-envelope checks.
struct ConversationJournalRead: Sendable {
  let page: ConversationJournalPageSnapshot
  let context: ConversationCommandContext
  fileprivate init(page: ConversationJournalPageSnapshot, context: ConversationCommandContext) {
    self.page = page
    self.context = context
  }
}
