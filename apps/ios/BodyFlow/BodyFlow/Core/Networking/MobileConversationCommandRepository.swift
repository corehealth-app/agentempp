import Foundation

/// The actual existing authenticated transport, scoped once to the original
/// Auth lease. No legacy Flow endpoint, model tool or writer fallback exists.
struct MobileConversationCommandRepository: Sendable {
    static let responseBodyLimit = 262_144
    private static let base = "/api/mobile/v1/conversation/meal-commands"
    private let transport: MobileAPITransport
    private let feedbackPresentation: ConversationFeedbackPresentationSelection?

    static func scoped(transport: MobileAPITransport, lease: SessionLease, feedbackPresentation: ConversationFeedbackPresentationSelection? = nil) async throws -> Self {
        let scoped = transport.withResponseBodyLimit(responseBodyLimit).scoped(to: lease)
        try await scoped.validateOriginalSession(lease)
        return .init(transport: scoped, feedbackPresentation: feedbackPresentation)
    }
    func session() async throws -> ConversationSessionSnapshot {
        do {
            return try await readSession()
        } catch MobileAPITransportError.conflict(let code, _) where code == "conversation_session_initialization_required" {
            // An explicit, idempotent initialization under this same Auth lease.
            // Never infer it from a timeout, general failure or historical row.
            return try await Self.initializeSession(transport: transport)
        }
    }
    /// Only a transport already scoped to the original Auth lease may call this.
    static func initializeSession(transport: MobileAPITransport) async throws -> ConversationSessionSnapshot {
        let response = try await transport.executeHTTP(MobileAPIRequest<ConversationSessionSnapshot>(method: .post,
            path: "/api/mobile/v1/conversation/session",
            body: MobileConversationRequestHeaders.sessionInitializationBody,
            idempotencyKey: IdempotencyKey(validating: MobileConversationRequestHeaders.sessionInitializationKey),
            conversation: .sessionInitialization, unauthorizedReplay: .never))
        guard response.statusCode == 200 else { throw MobileAPITransportError.invalidResponse }
        return response.data
    }
    private func readSession() async throws -> ConversationSessionSnapshot {
        let response = try await transport.executeHTTP(MobileAPIRequest<ConversationSessionSnapshot>(method: .get,
            path: "/api/mobile/v1/conversation/session", conversation: .session))
        guard response.statusCode == 200 else { throw MobileAPITransportError.invalidResponse }
        return response.data
    }
    func submit(_ ticket: ConversationOutboxTicket) async throws -> ConversationMealCommandReply {
        let response = try await transport.executeHTTP(MobileAPIRequest<ConversationMealCommandReply>(method: .post,
            path: Self.base, body: ticket.wireBody, idempotencyKey: IdempotencyKey(validating: ticket.idempotencyKey),
            // Reuse the existing bounded Flow turn ceiling. The server keeps
            // its own shorter provider/route budgets; this adds no retry.
            timeout: MobileAPITransport.longestRequestTimeout,
            conversation: .submit(epoch: ticket.originalServerEpoch, ownerID: ticket.originalPatientOwnerID), unauthorizedReplay: .never, feedbackPresentation: feedbackPresentation))
        guard response.data.acceptsHTTPStatus(response.statusCode) else { throw MobileAPITransportError.invalidResponse }
        return response.data
    }
    func read(_ ticket: ConversationOutboxTicket) async throws -> ConversationMealCommandReply {
        let response = try await transport.executeHTTP(MobileAPIRequest<ConversationMealCommandReply>(method: .get,
            path: Self.base + "/" + ticket.commandID.uuidString.lowercased(),
            conversation: .reconciliation(epoch: ticket.originalServerEpoch, ownerID: ticket.originalPatientOwnerID, inputHash: ticket.inputHash), feedbackPresentation: feedbackPresentation))
        guard response.data.acceptsHTTPStatus(response.statusCode) else { throw MobileAPITransportError.invalidResponse }
        return response.data
    }
}
