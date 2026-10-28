import Foundation

protocol MobileAPIExecuting: Sendable {
    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response
}

extension MobileAPITransport: MobileAPIExecuting {}

struct MobileFlowChatRepository: FlowChatProviding {
    let transport: any MobileAPIExecuting
    let sessionLifecycle: (any SessionLifecycleProviding)?
    private let sessionLease: SessionLease?
    let clinicalRepresentation: CurrentClinicalRepresentation

    init(transport: any MobileAPIExecuting,
         sessionLifecycle: (any SessionLifecycleProviding)? = nil,
         clinicalRepresentation: CurrentClinicalRepresentation = .legacy) {
        self.transport = transport
        self.sessionLifecycle = sessionLifecycle
        self.clinicalRepresentation = clinicalRepresentation
        sessionLease = nil
    }
    private init(transport: any MobileAPIExecuting, sessionLifecycle: any SessionLifecycleProviding,
                 sessionLease: SessionLease, clinicalRepresentation: CurrentClinicalRepresentation) {
        self.transport = transport
        self.sessionLifecycle = sessionLifecycle
        self.sessionLease = sessionLease
        self.clinicalRepresentation = clinicalRepresentation
    }
    func scoped(for userID: String) async throws -> any FlowChatProviding {
        if let sessionLease {
            guard sessionLease.userID == userID, let sessionLifecycle else { throw SessionLifecycleError.sessionSuperseded }
            try await sessionLifecycle.validate(sessionLease)
            return self
        }
        guard let sessionLifecycle else {
            if case .currentV1 = clinicalRepresentation { throw SessionLifecycleError.sessionSuperseded }
            return self
        }
        let lease = try await sessionLifecycle.leaseForRequest()
        guard lease.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
        try await sessionLifecycle.validate(lease)
        let scoped: any MobileAPIExecuting = if let mobile = transport as? MobileAPITransport { mobile.scoped(to: lease) } else { transport }
        return MobileFlowChatRepository(transport: scoped, sessionLifecycle: sessionLifecycle,
                                        sessionLease: lease, clinicalRepresentation: clinicalRepresentation)
    }
    private func validateScope() async throws {
        guard let sessionLease else {
            if sessionLifecycle != nil { throw SessionLifecycleError.sessionSuperseded }
            if case .currentV1 = clinicalRepresentation { throw SessionLifecycleError.sessionSuperseded }
            return
        }
        guard let sessionLifecycle else { throw SessionLifecycleError.sessionSuperseded }
        try await sessionLifecycle.validate(sessionLease)
    }
    private func validateRepresentation(_ policy: CurrentClinicalPolicy?) throws {
        if case .currentV1 = clinicalRepresentation, policy == nil { throw MobileAPITransportError.invalidResponse }
    }

    func history(limit: Int) async throws -> FlowHistoryResponse {
        try await validateScope()
        let response: FlowHistoryResponse = try await transport.execute(MobileAPIRequest(
            method: .get,
            path: "/api/mobile/v1/flow/chat",
            queryItems: clinicalRepresentation.queryItems + [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))]
        ))
        try await validateScope()
        try validateRepresentation(response.clinicalPolicy)
        return response
    }

    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse {
        try await validateScope()
        let body = try JSONEncoder().encode(FlowSendBody(text: text))
        let response: FlowSendResponse = try await transport.execute(MobileAPIRequest(
            method: .post,
            path: "/api/mobile/v1/flow/chat",
            queryItems: clinicalRepresentation.queryItems,
            body: body,
            idempotencyKey: idempotencyKey,
            // A turn that builds a plan takes 60-90 s (staging 2026-09-28: 77 s);
            // its generator may take up to 120 s on its own.
            timeout: .seconds(180)
        ))
        try await validateScope()
        try validateRepresentation(response.clinicalPolicy)
        return response
    }
}

private struct FlowSendBody: Encodable {
    let text: String
}
