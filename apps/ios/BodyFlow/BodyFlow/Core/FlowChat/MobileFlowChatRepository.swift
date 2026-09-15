import Foundation

protocol MobileAPIExecuting: Sendable {
    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response
}

extension MobileAPITransport: MobileAPIExecuting {}

struct MobileFlowChatRepository: FlowChatProviding {
    let transport: any MobileAPIExecuting

    func history(limit: Int) async throws -> FlowHistoryResponse {
        try await transport.execute(MobileAPIRequest(
            method: .get,
            path: "/api/mobile/v1/flow/chat",
            queryItems: [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))]
        ))
    }

    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse {
        let body = try JSONEncoder().encode(FlowSendBody(text: text))
        return try await transport.execute(MobileAPIRequest(
            method: .post,
            path: "/api/mobile/v1/flow/chat",
            body: body,
            idempotencyKey: idempotencyKey
        ))
    }
}

private struct FlowSendBody: Encodable {
    let text: String
}
