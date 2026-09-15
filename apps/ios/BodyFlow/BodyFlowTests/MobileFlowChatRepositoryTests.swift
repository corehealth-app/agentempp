import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile Flow Chat Repository")
struct MobileFlowChatRepositoryTests {
    @Test("history uses the authenticated Flow endpoint")
    func historyRequest() async throws {
        let transport = FlowChatRecordingTransport(
            history: FlowHistoryResponse(conversationID: "flow", messages: [])
        )
        let repository = MobileFlowChatRepository(transport: transport)

        _ = try await repository.history(limit: 20)

        let request = try #require(await transport.lastRequest)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/flow/chat")
        #expect(request.queryItems == [URLQueryItem(name: "limit", value: "20")])
    }

    @Test("send carries bounded text and a stable idempotency key")
    func sendRequest() async throws {
        let response = FlowSendResponse(
            conversationID: "flow",
            message: FlowMessage(
                id: "assistant-1",
                conversationID: "flow",
                role: .assistant,
                content: "Olá!",
                state: .completed,
                requestID: "request-flow-0001",
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        let transport = FlowChatRecordingTransport(send: response)
        let repository = MobileFlowChatRepository(transport: transport)

        let result = try await repository.send(
            text: "Olá, Flow",
            idempotencyKey: IdempotencyKey(validating: "flow-key-0001")
        )

        #expect(result == response)
        let request = try #require(await transport.lastRequest)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/flow/chat")
        #expect(request.idempotencyKey == "flow-key-0001")
        #expect(String(data: try #require(request.body), encoding: .utf8)?.contains("Olá, Flow") == true)
    }
}

private actor FlowChatRecordingTransport: MobileAPIExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let queryItems: [URLQueryItem]
        let body: Data?
        let idempotencyKey: String?
    }

    private let historyResponse: FlowHistoryResponse?
    private let sendResponse: FlowSendResponse?
    private(set) var lastRequest: Recorded?

    init(history: FlowHistoryResponse? = nil, send: FlowSendResponse? = nil) {
        historyResponse = history
        sendResponse = send
    }

    func execute<Response>(_ request: MobileAPIRequest<Response>) async throws -> Response
    where Response: Decodable & Sendable {
        let key: String? = if case .required(let value) = request.idempotency {
            value.value
        } else {
            nil
        }
        lastRequest = Recorded(
            method: request.method,
            path: request.path,
            queryItems: request.queryItems,
            body: request.body,
            idempotencyKey: key
        )
        if let response = historyResponse as? Response { return response }
        if let response = sendResponse as? Response { return response }
        throw BodyFlowCapabilityError.operationUnavailable
    }
}
