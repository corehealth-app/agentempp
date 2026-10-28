import Foundation

protocol FlowChatProviding: Sendable {
    func scoped(for userID: String) async throws -> any FlowChatProviding
    func history(limit: Int) async throws -> FlowHistoryResponse
    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse
}

extension FlowChatProviding {
    func scoped(for userID: String) async throws -> any FlowChatProviding { self }
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
    private var replies: [String: (text: String, response: FlowSendResponse)] = [:]

    func history(limit: Int) -> FlowHistoryResponse {
        FlowHistoryResponse(
            conversationID: "flow",
            messages: Array(messages.suffix(max(1, limit)))
        )
    }

    func send(text: String, idempotencyKey: IdempotencyKey) throws -> FlowSendResponse {
        if let prior = replies[idempotencyKey.value] {
            guard prior.text == text else { throw URLError(.badServerResponse) }
            return prior.response
        }
        let now = Date()
        let requestID = UUID().uuidString
        let user = FlowMessage(
            id: "demo-user-\(idempotencyKey.value)",
            conversationID: "flow",
            role: .user,
            content: text,
            state: .completed,
            requestID: requestID,
            createdAt: now
        )
        let assistant = FlowMessage(
            id: "demo-flow-\(idempotencyKey.value)",
            conversationID: "flow",
            role: .assistant,
            content: "Estou aqui. Esta resposta é uma simulação local do Flow; a resposta real será validada no staging.",
            state: .completed,
            requestID: requestID,
            createdAt: now
        )
        messages.append(contentsOf: [user, assistant])
        // With the plan draft scenario, a request for a workout answers with
        // the synthetic proposal of that scenario.
        let proposes = DemoPlanDraftScenario.isEnabled(
            arguments: ProcessInfo.processInfo.arguments
        ) && text.localizedCaseInsensitiveContains("treino")
        let response = FlowSendResponse(
            conversationID: "flow",
            message: assistant,
            draft: proposes
                ? FlowTurnDraft(id: DemoPlanDraftScenario.draftID, domain: .training) : nil
        )
        replies[idempotencyKey.value] = (text, response)
        return response
    }
}
#endif
