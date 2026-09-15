import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Flow Chat Model")
struct FlowChatModelTests {
    @Test("loads persisted history and sends only confirmed server state")
    func loadAndSend() async throws {
        let provider = FlowChatTestProvider()
        await provider.setHistory([flowMessage(id: "first", role: .assistant, content: "Bem-vindo")])
        let model = FlowChatModel(
            userID: "user-a",
            provider: provider,
            keyProvider: RandomIdempotencyKeyProvider()
        )

        await model.load()
        #expect(model.messages.map(\.id) == ["first"])

        model.composer = "Olá"
        await model.send()
        #expect(model.messages.last?.content == "Resposta real")
        #expect(model.composer.isEmpty)
        #expect(!model.isSending)
    }

    @Test("invalidate clears sensitive history and ignores a late response")
    func ignoresLateResponse() async {
        let provider = FlowChatTestProvider(delay: .milliseconds(100))
        let model = FlowChatModel(
            userID: "user-a",
            provider: provider,
            keyProvider: RandomIdempotencyKeyProvider()
        )
        model.composer = "Mensagem antiga"

        let task = Task { await model.send() }
        await Task.yield()
        model.invalidate()
        await task.value

        #expect(model.messages.isEmpty)
        #expect(model.composer.isEmpty)
    }

    @Test("failed sends retain a safe retry with the same idempotency key")
    func retryUsesSameKey() async {
        let provider = FlowChatTestProvider(failsOnce: true)
        let model = FlowChatModel(
            userID: "user-a",
            provider: provider,
            keyProvider: RandomIdempotencyKeyProvider()
        )
        model.composer = "Tentar"

        await model.send()
        #expect(model.errorMessage != nil)
        await model.retry()

        #expect(model.errorMessage == nil)
        #expect(await provider.sentKeys.count == 2)
        #expect(await provider.sentKeys.first == provider.sentKeys.last)
    }

    @Test("cancel stops a post-send history refresh before it can update the session")
    func cancelStopsHistoryRefresh() async throws {
        let provider = FlowChatTestProvider(historyDelayAfterSend: .seconds(1))
        let model = FlowChatModel(
            userID: "user-a",
            provider: provider,
            keyProvider: RandomIdempotencyKeyProvider()
        )
        model.composer = "Cancelar"

        let send = Task { await model.send() }
        for _ in 0..<100 where await provider.sentKeys.isEmpty {
            await Task.yield()
        }
        #expect(await provider.sentKeys.count == 1)
        model.cancel()
        await send.value

        #expect(model.messages.isEmpty)
        #expect(!model.isSending)
    }
}

private actor FlowChatTestProvider: FlowChatProviding {
    private var historyMessages: [FlowMessage] = []
    private let delay: Duration?
    private let historyDelayAfterSend: Duration?
    private var failsRemaining: Int
    private(set) var sentKeys: [String] = []

    init(
        delay: Duration? = nil,
        historyDelayAfterSend: Duration? = nil,
        failsOnce: Bool = false
    ) {
        self.delay = delay
        self.historyDelayAfterSend = historyDelayAfterSend
        failsRemaining = failsOnce ? 1 : 0
    }

    func setHistory(_ messages: [FlowMessage]) {
        historyMessages = messages
    }

    func history(limit: Int) async throws -> FlowHistoryResponse {
        if !sentKeys.isEmpty, let historyDelayAfterSend {
            try await Task.sleep(for: historyDelayAfterSend)
        }
        return FlowHistoryResponse(conversationID: "flow", messages: historyMessages)
    }

    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse {
        sentKeys.append(idempotencyKey.value)
        if let delay { try await Task.sleep(for: delay) }
        if failsRemaining > 0 {
            failsRemaining -= 1
            throw URLError(.notConnectedToInternet)
        }
        let user = flowMessage(id: "user", role: .user, content: text)
        let assistant = flowMessage(id: "assistant", role: .assistant, content: "Resposta real")
        historyMessages = [user, assistant]
        return FlowSendResponse(conversationID: "flow", message: assistant)
    }
}

private func flowMessage(id: String, role: FlowMessageRole, content: String) -> FlowMessage {
    FlowMessage(
        id: id,
        conversationID: "flow",
        role: role,
        content: content,
        state: .completed,
        requestID: "request-test",
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
}
