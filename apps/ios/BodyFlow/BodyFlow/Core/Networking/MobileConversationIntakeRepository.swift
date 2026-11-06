import Foundation

/// Real authenticated transport bound once to the original lease. The neutral
/// ticket is never sent through a meal/workout endpoint or retagged on retry.
struct MobileConversationIntakeRepository: Sendable {
  static let responseBodyLimit = 262_144
  private let transport: MobileAPITransport
  private let feedbackPresentation: ConversationFeedbackPresentationSelection?
  static func scoped(
    transport: MobileAPITransport, lease: SessionLease,
    feedbackPresentation: ConversationFeedbackPresentationSelection? = nil
  ) async throws -> Self {
    let scoped = transport.withResponseBodyLimit(responseBodyLimit).scoped(to: lease)
    try await scoped.validateOriginalSession(lease)
    return .init(transport: scoped, feedbackPresentation: feedbackPresentation)
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
