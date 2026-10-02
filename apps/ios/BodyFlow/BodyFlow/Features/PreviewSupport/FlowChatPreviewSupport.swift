#if DEBUG
import Foundation

enum FlowPreviewScenario: String, CaseIterable, Sendable {
    case empty, loading, processing, response, error, offline, longHistory, retryOnce
    case pendingCancellation

    static func resolve(arguments: [String]) -> FlowPreviewScenario? {
        guard arguments.contains("--ui-testing") else { return nil }
        let prefix = "--ui-testing-flow-"
        let matches = arguments.filter { $0.hasPrefix(prefix) }
        guard matches.count == 1, let flag = matches.first else { return nil }
        return Self(rawValue: String(flag.dropFirst(prefix.count)))
    }
}

/// Deterministic local QA only; no provider, network or remote completion.
actor FlowPreviewRepository: FlowChatProviding {
    private let scenario: FlowPreviewScenario
    private let replyWait: @Sendable (Duration?) async throws -> Void
    private var messages: [FlowMessage]
    private var responses: [String: FlowSendResponse] = [:]
    private var submittedText: [String: String] = [:]
    private var hasLoaded = false
    private var hasFailedSend = false
    private(set) var sendCallCount = 0
    private(set) var sentKeys: [String] = []

    init(
        scenario: FlowPreviewScenario,
        replyWait: @escaping @Sendable (Duration?) async throws -> Void = {
            try await FlowPreviewRepository.waitForReply($0)
        }
    ) {
        self.scenario = scenario
        self.replyWait = replyWait
        messages = Self.seed(scenario)
    }

    func history(limit: Int) async throws -> FlowHistoryResponse {
        if scenario == .offline { throw URLError(.notConnectedToInternet) }
        if scenario == .error { throw URLError(.cannotConnectToHost) }
        if scenario == .loading && !hasLoaded {
            hasLoaded = true
            try await Task.sleep(for: .seconds(2))
        }
        try Task.checkCancellation()
        return FlowHistoryResponse(conversationID: "flow", messages: Array(messages.suffix(max(1, limit))))
    }

    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse {
        sendCallCount += 1
        sentKeys.append(idempotencyKey.value)
        if scenario == .offline { throw URLError(.notConnectedToInternet) }
        if scenario == .error { throw URLError(.cannotConnectToHost) }
        if scenario == .retryOnce && !hasFailedSend {
            hasFailedSend = true
            throw URLError(.timedOut)
        }
        if let response = try replay(text: text, key: idempotencyKey.value) { return response }
        // Cancellation QA must remain pending even when AX idle takes longer
        // than a timed reply. Other scenarios retain their two-second delay.
        try await replyWait(scenario == .pendingCancellation ? nil : .seconds(2))
        try Task.checkCancellation()
        if let response = try replay(text: text, key: idempotencyKey.value) { return response }
        let requestID = UUID().uuidString
        let user = Self.message(id: "qa-user-\(idempotencyKey.value)", role: .user, content: text,
                                requestID: requestID)
        let assistant = Self.message(
            id: "qa-flow-\(idempotencyKey.value)", role: .assistant,
            content: scenario == .response ? Self.longResponse
                : "QA local: resposta simulada do Flow. Nenhum provider ou completion real. QA_REPLY_VISIBLE",
            requestID: requestID
        )
        let response = FlowSendResponse(conversationID: "flow", message: assistant)
        submittedText[idempotencyKey.value] = text
        responses[idempotencyKey.value] = response
        messages.append(contentsOf: [user, assistant])
        return response
    }

    /// A nil duration has no timer and ends only when the caller cancels.
    nonisolated static func waitForReply(_ duration: Duration?) async throws {
        if let duration {
            try await Task.sleep(for: duration)
            return
        }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        throw CancellationError()
    }

    private func replay(text: String, key: String) throws -> FlowSendResponse? {
        guard let response = responses[key] else { return nil }
        guard submittedText[key] == text else { throw URLError(.badServerResponse) }
        return response
    }

    private static func seed(_ scenario: FlowPreviewScenario) -> [FlowMessage] {
        switch scenario {
        case .processing:
            [message(id: "qa-processing", role: .assistant,
                     content: "QA local: estado processing fornecido pelo DTO.", state: .processing)]
        case .response:
            [message(id: "qa-long-response", role: .assistant, content: longResponse)]
        case .longHistory:
            (0..<40).map { index in
                message(id: "qa-seed-\(index)", role: index.isMultiple(of: 2) ? .user : .assistant,
                        content: "QA histórico local \(index). Leitura preservada, sem dados reais ou rede.")
            }
        default: []
        }
    }

    private static var longResponse: String {
        Array(repeating: "**QA literal** — Texto longo de simulação local do Flow. O conteúdo permanece texto puro, selecionável e legível, sem interpretação Markdown ou dados reais.", count: 24)
            .joined(separator: "\n\n") + "\nQA_END_OF_LONG_RESPONSE"
    }

    private static func message(id: String, role: FlowMessageRole, content: String,
                                state: FlowMessageState = .completed,
                                requestID: String = "qa-local-request") -> FlowMessage {
        FlowMessage(id: id, conversationID: "flow", role: role, content: content,
                    state: state, requestID: requestID,
                    createdAt: Date(timeIntervalSince1970: 1_789_603_200))
    }
}
#endif
