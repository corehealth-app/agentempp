import Foundation

/// Read-only actual BFF facts. No read acknowledges an outbox entry, mutates a
/// registration or establishes owner authority from a header/payload alone.
struct MobileConversationHistoryRepository: Sendable {
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let lease: SessionLease
  private let feedbackPresentation: ConversationFeedbackPresentationSelection?
  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease,
    feedbackPresentation: ConversationFeedbackPresentationSelection? = nil
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(
      MobileConversationCommandRepository.responseBodyLimit
    ).scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    return .init(transport: scoped, lifecycle: lifecycle, lease: lease, feedbackPresentation: feedbackPresentation)
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
  /// Actual two-phase cold read. The observed reference grants no write; only
  /// the owned response's genuine original effect completes the identity.
  func linkedOrigin(commandID: UUID, context: ConversationCommandContext) async throws
    -> ConversationMealLinkedOriginSnapshot
  {
    try await validate(context)
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationMealLinkedOriginSnapshot>(
        method: .get,
        path: "/api/mobile/v1/conversation/meal-commands/\(commandID.uuidString.lowercased())/origin",
        conversation: .mealLinkedOrigin(epoch: context.epoch, ownerID: context.ownerID),
        unauthorizedReplay: .never))
    try await validate(context)
    let origin = response.data
    guard response.statusCode == 200, origin.authUserID == context.authUserID,
      origin.ownerID == context.ownerID, origin.epoch == context.epoch,
      origin.identity.commandID == commandID,
      let observed = ConversationProtocolInstant(origin.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt), observed >= accepted
    else { throw MobileAPITransportError.invalidResponse }
    return origin
  }
  func linkedGroup(
    reference: ConversationMealLinkedReadReference, context: ConversationCommandContext
  ) async throws -> ConversationMealLinkedGroupRead {
    try await validate(context)
    guard reference.ownerID == context.ownerID, reference.epoch == context.epoch else {
      throw ConversationOutboxError.invalidServerObservation
    }
    let group = try await self.group(
      commandID: reference.commandID, originalInputHash: reference.inputHash, context: context)
    try await validate(context)
    guard let identity = try? reference.resolve(group: group) else {
      throw MobileAPITransportError.invalidResponse
    }
    return .init(group: group, identity: identity, context: context)
  }
  func group(linked identity: ConversationMealLinkedIdentity, context: ConversationCommandContext)
    async throws -> ConversationMealGroupSnapshot
  {
    let read = try await linkedGroup(reference: identity.reference, context: context)
    try await validate(context)
    guard read.identity == identity else { throw MobileAPITransportError.invalidResponse }
    return read.group
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
        conversation: .journal(epoch: context.epoch, ownerID: context.ownerID), feedbackPresentation: feedbackPresentation))
    try await validate(context)
    guard response.statusCode == 200,
      response.data.matches(
        authUserID: context.authUserID, ownerID: context.ownerID, epoch: context.epoch),
      let observed = ConversationProtocolInstant(response.data.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt), observed >= accepted
    else { throw MobileAPITransportError.invalidResponse }
    return .init(page: response.data, context: context)
  }
  /// Explicit independent read protocol. The original cmsg1 command and the
  /// default v1 journal method are unchanged. A v2 page cannot ACK an intent.
  func threadJournal(cursor: String? = nil, limit: Int = 10, context: ConversationCommandContext)
    async throws -> ConversationThreadJournalRead
  {
    try await validate(context)
    var query = [
      URLQueryItem(name: "version", value: "2"), .init(name: "limit", value: String(limit)),
    ]
    if let cursor { query.append(.init(name: "cursor", value: cursor)) }
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationThreadPageSnapshot>(
        method: .get, path: "/api/mobile/v1/conversation/journal", queryItems: query,
        conversation: .threadJournal(epoch: context.epoch, ownerID: context.ownerID), feedbackPresentation: feedbackPresentation))
    try await validate(context)
    guard response.statusCode == 200, response.data.items.count <= limit,
      response.data.matches(
        authUserID: context.authUserID, ownerID: context.ownerID, epoch: context.epoch),
      let observed = ConversationProtocolInstant(response.data.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt), observed >= accepted
    else { throw MobileAPITransportError.invalidResponse }
    return .init(page: response.data, context: context)
  }
  /// Historical-only schema3. No request/echo3, original intent or ACK is derived.
  func unifiedJournal(cursor: String? = nil, limit: Int = 10, context: ConversationCommandContext)
    async throws -> ConversationJournalV3Read
  {
    try await validate(context)
    guard (1...25).contains(limit) else { throw MobileAPIRequestError.invalidConversationHeaders }
    if let cursor {
      try ConversationJournalV3PageSnapshot.validateCursor(
        cursor, ownerID: context.ownerID, epoch: context.epoch)
    }
    var query = [
      URLQueryItem(name: "version", value: "3"), .init(name: "limit", value: String(limit)),
    ]
    if let cursor { query.append(.init(name: "cursor", value: cursor)) }
    let response = try await transport.withResponseBodyLimit(262_144).executeHTTP(
      MobileAPIRequest<ConversationJournalV3PageSnapshot>(
        method: .get,
        path: "/api/mobile/v1/conversation/journal", queryItems: query,
        conversation: .unifiedJournal(epoch: context.epoch, ownerID: context.ownerID)))
    try await validate(context)
    guard response.statusCode == 200, response.data.items.count <= limit,
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

/// No v1 delivery/ACK capability is derived from this owned history read.
struct ConversationThreadJournalRead: Sendable {
  let page: ConversationThreadPageSnapshot
  let context: ConversationCommandContext
  fileprivate init(page: ConversationThreadPageSnapshot, context: ConversationCommandContext) {
    self.page = page
    self.context = context
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

/// Produced only after the real adapter's Auth/lease/current-grant checks and
/// full original-effect binding. It is not an outbox or write capability.
struct ConversationMealLinkedGroupRead: Sendable {
  let group: ConversationMealGroupSnapshot
  let identity: ConversationMealLinkedIdentity
  let context: ConversationCommandContext
  fileprivate init(
    group: ConversationMealGroupSnapshot, identity: ConversationMealLinkedIdentity,
    context: ConversationCommandContext
  ) {
    self.group = group
    self.identity = identity
    self.context = context
  }
}

/// Adapter-only observation carrier. It has no write/delivery capability.
struct ConversationJournalV3Read: Sendable {
  let page: ConversationJournalV3PageSnapshot
  let context: ConversationCommandContext
  fileprivate init(page: ConversationJournalV3PageSnapshot, context: ConversationCommandContext) {
    self.page = page; self.context = context
  }
}
