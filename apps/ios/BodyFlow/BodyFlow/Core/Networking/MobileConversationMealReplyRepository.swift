import Foundation

/// Real typed reply routes only; never falls back to meal.report or an agent.
struct MobileConversationMealReplyRepository: Sendable {
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let lease: SessionLease
  private let feedbackPresentation: ConversationFeedbackPresentationSelection?
  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease,
    feedbackPresentation: ConversationFeedbackPresentationSelection? = nil
  ) async throws -> Self {
    let transport = transport.withResponseBodyLimit(
      MobileConversationCommandRepository.responseBodyLimit
    ).scoped(to: lease)
    try await transport.validateOriginalSession(lease)
    return .init(transport: transport, lifecycle: lifecycle, lease: lease, feedbackPresentation: feedbackPresentation)
  }
  /// Reads only the selected typed parent. It neither allocates a reply ID nor writes.
  func readParent(child: FlowNeutralIntakeChild, context: ConversationCommandContext)
    async throws -> ConversationMealParentQuestionSnapshot
  {
    try await validateParent(child, context: context)
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationMealParentQuestionSnapshot>(
        method: .get,
        path: "/api/mobile/v1/conversation/commands/\(child.commandID.uuidString.lowercased())/replies",
        queryItems: [.init(name: "parent_input_hash", value: child.inputHash)],
        conversation: .mealParentQuestion(child)))
    try await validateParent(child, context: context)
    guard response.statusCode == 200, response.data.matches(child: child, context: context),
      let observed = ConversationProtocolInstant(response.data.observedAt),
      let accepted = ConversationProtocolInstant(context.observedAt), observed >= accepted
    else { throw MobileAPITransportError.invalidResponse }
    return response.data
  }
  private func validateParent(_ child: FlowNeutralIntakeChild, context: ConversationCommandContext) async throws {
    guard !context.observation.isEnqueueOnly, child.kind == .meal,
      child.ownerID == context.ownerID, child.epoch == context.epoch,
      context.authUserID == UUID(uuidString: lease.userID), context.sessionGeneration == lease.generation
    else { throw ConversationOutboxError.invalidServerObservation }
    try await lifecycle.validate(lease)
    try Task.checkCancellation()
    try context.withCurrentAuthority {}
  }
  func submit(_ ticket: ConversationMealReplyOutboxTicket, context: ConversationCommandContext)
    async throws -> ConversationMealReplyResultSnapshot
  {
    try await validate(ticket, context: context)
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationMealReplyResultSnapshot>(
        method: .post, path: path(ticket), body: ticket.wireBody,
        idempotencyKey: IdempotencyKey(validating: ticket.idempotencyKey),
        timeout: MobileAPITransport.longestRequestTimeout,
        conversation: .mealReplySubmit(ticket.intent), unauthorizedReplay: .never, feedbackPresentation: feedbackPresentation))
    try await validate(ticket, context: context)
    guard response.data.acceptsHTTPStatus(response.statusCode),
      response.data.matches(intent: ticket.intent, authUserID: context.authUserID)
    else { throw MobileAPITransportError.invalidResponse }
    return response.data
  }
  /// Pure GET of the exact original hashes. No new admission or automatic POST.
  func reconcile(_ ticket: ConversationMealReplyOutboxTicket, context: ConversationCommandContext)
    async throws -> ConversationMealReplyResultSnapshot
  {
    try await validate(ticket, context: context)
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationMealReplyResultSnapshot>(
        method: .get, path: path(ticket) + "/" + ticket.replyID.uuidString.lowercased(),
        queryItems: [
          .init(name: "parent_input_hash", value: ticket.parentInputHash),
          .init(name: "reply_input_hash", value: ticket.replyInputHash),
        ],
        conversation: .mealReplyReconciliation(ticket.intent), feedbackPresentation: feedbackPresentation))
    try await validate(ticket, context: context)
    guard response.data.acceptsHTTPStatus(response.statusCode),
      response.data.matches(intent: ticket.intent, authUserID: context.authUserID)
    else { throw MobileAPITransportError.invalidResponse }
    return response.data
  }
  private func path(_ ticket: ConversationMealReplyOutboxTicket) -> String {
    "/api/mobile/v1/conversation/commands/\(ticket.parentCommandID.uuidString.lowercased())/replies"
  }
  private func validate(
    _ ticket: ConversationMealReplyOutboxTicket, context: ConversationCommandContext
  ) async throws {
    guard !context.observation.isEnqueueOnly, context.authUserID == UUID(uuidString: lease.userID),
      context.sessionGeneration == lease.generation,
      ticket.localSessionGeneration == lease.generation,
      ticket.originalPatientOwnerID == context.ownerID, ticket.originalServerEpoch == context.epoch
    else { throw ConversationOutboxError.invalidServerObservation }
    try await lifecycle.validate(lease)
    try Task.checkCancellation()
    try context.withCurrentAuthority {}
  }
}
