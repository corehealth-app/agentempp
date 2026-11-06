import Foundation

/// Real authenticated transport bound once to the original lease. The neutral
/// ticket is never sent through a meal/workout endpoint or retagged on retry.
struct MobileConversationIntakeRepository: Sendable {
  static let responseBodyLimit = 262_144
  private let transport: MobileAPITransport
  private let lease: SessionLease
  private let feedbackPresentation: ConversationFeedbackPresentationSelection?
  static func scoped(
    transport: MobileAPITransport, lease: SessionLease,
    feedbackPresentation: ConversationFeedbackPresentationSelection? = nil
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(responseBodyLimit).scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    return .init(transport: scoped, lease: lease, feedbackPresentation: feedbackPresentation)
  }
  /// Bounded lookup only. It never constructs an input/ticket or retries a POST.
  func questionOrigins(cursor: String? = nil, limit: Int = 10, context: ConversationCommandContext)
    async throws -> FlowMealQuestionOriginsPageSnapshot
  {
    try await validateOrigins(context)
    guard (1...25).contains(limit) else { throw MobileAPITransportError.invalidResponse }
    var query = [URLQueryItem(name: "limit", value: String(limit))]
    if let cursor { query.append(.init(name: "cursor", value: cursor)) }
    let response = try await transport.executeHTTP(
      MobileAPIRequest<FlowMealQuestionOriginsPageSnapshot>(method: .get,
        path: "/api/mobile/v1/conversation/intakes", queryItems: query,
        conversation: .intakeQuestionOrigins(epoch: context.epoch, ownerID: context.ownerID), unauthorizedReplay: .never))
    try await validateOrigins(context)
    guard response.statusCode == 200, response.data.matches(context), response.data.items.count <= limit,
      let observed = ConversationProtocolInstant(response.data.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt), observed >= accepted,
      response.data.nextCursor != cursor || response.data.nextCursor == nil,
      try response.data.follows(cursor: cursor)
    else { throw MobileAPITransportError.invalidResponse }
    return response.data
  }
  private func validateOrigins(_ context: ConversationCommandContext) async throws {
    guard !context.observation.isEnqueueOnly, context.authUserID == UUID(uuidString: lease.userID), context.sessionGeneration == lease.generation
    else { throw ConversationOutboxError.invalidServerObservation }
    try await transport.validateOriginalSession(lease)
    try Task.checkCancellation()
    try context.withCurrentAuthority {}
  }
  func session() async throws -> FlowNeutralIntakeSessionSnapshot {
    let r = try await transport.executeHTTP(
      MobileAPIRequest<FlowNeutralIntakeSessionSnapshot>(
        method: .get, path: "/api/mobile/v1/conversation/intakes/session",
        conversation: .intakeSession))
    guard r.statusCode == 200 else { throw MobileAPITransportError.invalidResponse }
    return r.data
  }
  func submit(_ ticket: FlowNeutralIntakeTicket) async throws -> FlowNeutralIntakeResponseSnapshot {
    let r = try await transport.executeHTTP(
      MobileAPIRequest<FlowNeutralIntakeResponseSnapshot>(
        method: .post, path: "/api/mobile/v1/conversation/intakes", body: ticket.input.wireBody,
        idempotencyKey: IdempotencyKey(validating: ticket.input.idempotencyKey),
        timeout: MobileAPITransport.longestRequestTimeout, conversation: .intakeSubmit(ticket),
        unauthorizedReplay: .never, feedbackPresentation: feedbackPresentation))
    return try checked(r, ticket: ticket)
  }
  func read(_ ticket: FlowNeutralIntakeTicket) async throws -> FlowNeutralIntakeResponseSnapshot {
    let r = try await transport.executeHTTP(
      MobileAPIRequest<FlowNeutralIntakeResponseSnapshot>(
        method: .get,
        path: "/api/mobile/v1/conversation/intakes/"
          + ticket.input.intakeID.uuidString.lowercased(),
        conversation: .intakeReconciliation(ticket), feedbackPresentation: feedbackPresentation))
    return try checked(r, ticket: ticket)
  }
  private func checked(
    _ r: MobileAPIHTTPResponse<FlowNeutralIntakeResponseSnapshot>, ticket: FlowNeutralIntakeTicket
  ) throws -> FlowNeutralIntakeResponseSnapshot {
    var pending = r.data.status == .pending || r.data.status == .held
    switch r.data.result {
    case .meal(.state(let value)): pending = value.status == .pending
    case .workout(.state(let value)): pending = value.status == .pending
    default: break
    }
    guard r.statusCode == (pending ? 202 : 200), r.data.matches(ticket) else {
      throw MobileAPITransportError.invalidResponse
    }
    return r.data
  }
}
