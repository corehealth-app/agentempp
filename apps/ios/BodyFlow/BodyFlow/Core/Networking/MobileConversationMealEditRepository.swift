import Foundation

/// Actual authenticated edit routes, scoped to the original Auth lease. The
/// context remains the command controller's revocable patient/epoch grant.
struct MobileConversationMealEditRepository: Sendable {
  private let transport: MobileAPITransport
  private let lifecycle: any SessionLifecycleProviding
  private let lease: SessionLease
  static func scoped(
    transport: MobileAPITransport, lifecycle: any SessionLifecycleProviding, lease: SessionLease
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(
      MobileConversationCommandRepository.responseBodyLimit
    )
    .scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    return .init(transport: scoped, lifecycle: lifecycle, lease: lease)
  }
  func submit(_ ticket: ConversationMealEditOutboxTicket, context: ConversationCommandContext)
    async throws -> ConversationMealEditResultSnapshot
  {
    try await validate(ticket, context: context)
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationMealEditResultSnapshot>(
        method: .post, path: path(ticket), body: ticket.wireBody,
        idempotencyKey: IdempotencyKey(validating: ticket.idempotencyKey),
        timeout: MobileAPITransport.longestRequestTimeout,
        conversation: .mealEdit(
          epoch: ticket.originalServerEpoch,
          ownerID: ticket.originalPatientOwnerID, inputHash: ticket.originalInputHash),
        unauthorizedReplay: .never))
    try await validate(ticket, context: context)
    guard response.statusCode == 200, response.data.matches(operation: ticket.operation) else {
      throw MobileAPITransportError.invalidResponse
    }
    return response.data
  }
  /// This POST is strictly a read of the exact original input. It has no
  /// automatic retry, mutation cache or permission to create another edit.
  func reconcile(_ ticket: ConversationMealEditOutboxTicket, context: ConversationCommandContext)
    async throws -> ConversationMealEditReply
  {
    try await validate(ticket, context: context)
    let response = try await transport.executeHTTP(
      MobileAPIRequest<ConversationMealEditReply>(
        method: .post, path: path(ticket) + "/reconcile", body: ticket.wireBody,
        idempotencyKey: IdempotencyKey(validating: ticket.idempotencyKey),
        conversation: .mealEditReconciliation(
          epoch: ticket.originalServerEpoch,
          ownerID: ticket.originalPatientOwnerID, inputHash: ticket.originalInputHash),
        unauthorizedReplay: .never))
    try await validate(ticket, context: context)
    guard response.data.acceptsHTTPStatus(response.statusCode),
      response.data.matches(operation: ticket.operation)
    else { throw MobileAPITransportError.invalidResponse }
    return response.data
  }
  private func path(_ ticket: ConversationMealEditOutboxTicket) -> String {
    "/api/mobile/v1/conversation/meal-commands/\(ticket.commandID.uuidString.lowercased())/edits/\(ticket.operationID.uuidString.lowercased())"
  }
  private func validate(
    _ ticket: ConversationMealEditOutboxTicket, context: ConversationCommandContext
  )
    async throws
  {
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
