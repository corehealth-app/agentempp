import Foundation
import Observation

@MainActor
@Observable
final class FlowChatModel {
    let userID: String
    var messages: [FlowMessage] = []
    var composer = ""
    var isLoading = false
    var isSending = false
    var errorMessage: String?

    private let provider: any FlowChatProviding
    private let keyProvider: any IdempotencyKeyProviding
    private var generation = 0
    private var operation: Task<FlowHistoryResponse, Error>?
    private var retryAttempt: (text: String, key: IdempotencyKey)?

    init(
        userID: String,
        provider: any FlowChatProviding,
        keyProvider: any IdempotencyKeyProviding
    ) {
        self.userID = userID
        self.provider = provider
        self.keyProvider = keyProvider
    }

    func load() async {
        let expectedGeneration = generation
        isLoading = true
        errorMessage = nil
        do {
            let response = try await provider.history(limit: 50)
            guard generation == expectedGeneration else { return }
            messages = response.messages
        } catch is CancellationError {
            return
        } catch {
            guard generation == expectedGeneration else { return }
            errorMessage = Self.message(for: error)
        }
        if generation == expectedGeneration { isLoading = false }
    }

    func send() async {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4_000, !isSending else { return }
        do {
            try await performSend(text: text, key: keyProvider.nextKey())
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func retry() async {
        guard let retryAttempt, !isSending else {
            await load()
            return
        }
        do {
            try await performSend(text: retryAttempt.text, key: retryAttempt.key)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func cancel() {
        operation?.cancel()
        operation = nil
        isSending = false
    }

    func invalidate() {
        generation += 1
        operation?.cancel()
        operation = nil
        messages.removeAll(keepingCapacity: false)
        composer = ""
        errorMessage = nil
        retryAttempt = nil
        isLoading = false
        isSending = false
    }

    private func performSend(text: String, key: IdempotencyKey) async throws {
        let expectedGeneration = generation
        isSending = true
        errorMessage = nil
        retryAttempt = (text, key)
        let provider = self.provider
        let task = Task {
            _ = try await provider.send(text: text, idempotencyKey: key)
            return try await provider.history(limit: 50)
        }
        operation = task
        do {
            let history = try await task.value
            guard generation == expectedGeneration else { return }
            messages = history.messages
            composer = ""
            retryAttempt = nil
            isSending = false
            operation = nil
        } catch {
            guard generation == expectedGeneration else { return }
            isSending = false
            operation = nil
            throw error
        }
    }

    private static func message(for error: Error) -> String {
        if error is CancellationError { return String(localized: "flow.error.cancelled") }
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet {
            return String(localized: "flow.error.offline")
        }
        if case MobileAPITransportError.rateLimited = error {
            return String(localized: "flow.error.rate-limited")
        }
        if case MobileAPITransportError.unauthorized = error {
            return String(localized: "flow.error.session")
        }
        if case MobileAPITransportError.forbidden = error {
            return String(localized: "flow.error.forbidden")
        }
        return String(localized: "flow.error.generic")
    }
}
