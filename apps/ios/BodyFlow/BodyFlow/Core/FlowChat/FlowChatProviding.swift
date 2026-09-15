import Foundation

protocol FlowChatProviding: Sendable {
    func history(limit: Int) async throws -> FlowHistoryResponse
    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse
}

struct UnavailableFlowChatRepository: FlowChatProviding {
    func history(limit: Int) async throws -> FlowHistoryResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

#if DEBUG
actor DemoFlowChatRepository: FlowChatProviding {
    private var messages: [FlowMessage] = []

    func history(limit: Int) -> FlowHistoryResponse {
        FlowHistoryResponse(
            conversationID: "flow",
            messages: Array(messages.suffix(max(1, limit)))
        )
    }

    func send(text: String, idempotencyKey: IdempotencyKey) -> FlowSendResponse {
        let now = Date()
        let user = FlowMessage(
            id: "demo-user-\(idempotencyKey.value)",
            conversationID: "flow",
            role: .user,
            content: text,
            state: .completed,
            requestID: "demo-request",
            createdAt: now
        )
        let assistant = FlowMessage(
            id: "demo-flow-\(idempotencyKey.value)",
            conversationID: "flow",
            role: .assistant,
            content: "Estou aqui. Esta resposta é uma simulação local do Flow; a resposta real será validada no staging.",
            state: .completed,
            requestID: "demo-request",
            createdAt: now
        )
        messages.append(contentsOf: [user, assistant])
        return FlowSendResponse(conversationID: "flow", message: assistant)
    }
}
#endif
