import Foundation
import Observation

/// A local submission is deliberately separate from persisted conversation
/// messages. Only a POST acknowledgement can bind it to a server request.
struct FlowOutboxMessage: Identifiable, Equatable {
    enum State: Equatable { case sending, unconfirmed, accepted }
    let id: UUID
    let text: String
    var state: State
    var serverReply: FlowMessage?
    /// First later turn acknowledged in this session. It keeps an older
    /// unconfirmed submission before newer replies without guessing identity.
    var followingReply: FlowMessage?
}

/// Only a POST acknowledgement can add a turn here. A later official GET
/// may supply its paired user message, using the reply's server request ID.
private struct FlowAcknowledgedTurn {
    var reply: FlowMessage
    var user: FlowMessage?
}

enum FlowConversationItem: Identifiable {
    case message(FlowMessage)
    case outbox(FlowOutboxMessage)

    var id: String {
        switch self {
        case let .message(message): "message-\(message.id)"
        case let .outbox(message): "outbox-\(message.id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class FlowChatModel {
    enum SendPhase { case idle, awaitingReply, reconcilingHistory }

    let userID: String
    private(set) var messages: [FlowMessage] = []
    private(set) var outbox: [FlowOutboxMessage] = []
    var composer = ""
    private(set) var isLoading = false
    private(set) var sendPhase = SendPhase.idle
    // The acknowledged turn can reconcile in the background while the
    // patient submits the next turn. Only a pending POST owns the composer.
    var isSending: Bool { sendPhase == .awaitingReply }
    var isReconcilingHistory: Bool { isLoading && (!messages.isEmpty || !outbox.isEmpty) }
    private(set) var errorMessage: String?
    /// Opening review never confirms the patient's plan.
    private(set) var turnDraft: FlowTurnDraft?

    private let provider: any FlowChatProviding
    private let keyProvider: any IdempotencyKeyProviding
    private var generation = 0
    private var conversationID: String?
    private var readSequence = 0
    private var activeSendID: UUID?
    private var activeOutboxID: UUID?
    private var operation: Task<Void, Never>?
    private var keys: [UUID: IdempotencyKey] = [:]
    private var retryOutboxID: UUID?
    /// Acknowledged server turns remain visible across a briefly stale GET.
    /// This cache is bounded to the same 50-message window as the API.
    private var acknowledgedTurns: [FlowAcknowledgedTurn] = []

    init(userID: String, provider: any FlowChatProviding,
         keyProvider: any IdempotencyKeyProviding) {
        self.userID = userID
        self.provider = provider
        self.keyProvider = keyProvider
    }

    var conversationItems: [FlowConversationItem] {
        var result: [FlowConversationItem] = []
        var anchored: Set<UUID> = []
        for message in messages {
            for pending in outbox where anchor(for: pending) == message.id {
                result.append(.outbox(pending))
                anchored.insert(pending.id)
            }
            result.append(.message(message))
        }
        result.append(contentsOf: outbox.filter { !anchored.contains($0.id) }.map(FlowConversationItem.outbox))
        return result
    }

    func load() async {
        guard !isSending else { return }
        await readHistory(acknowledgedSend: false)
    }

    func send() async {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled, !text.isEmpty, text.count <= 4_000, !isSending else { return }
        do {
            let id = UUID()
            keys[id] = try keyProvider.nextKey()
            outbox.append(FlowOutboxMessage(id: id, text: text, state: .sending))
            // Transfer this draft to the outbox now. Later completion never
            // touches what the patient may type while awaiting the reply.
            composer = ""
            await startSend(outboxID: id)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func retry() async {
        guard !isSending else { return }
        if let retryOutboxID {
            await retry(outboxID: retryOutboxID)
        } else {
            await load()
        }
    }

    func retry(outboxID: UUID) async {
        guard !isSending,
              outbox.contains(where: { $0.id == outboxID && $0.state == .unconfirmed }) else { return }
        await startSend(outboxID: outboxID)
    }

    func cancel() {
        let pendingID = activeOutboxID
        let hadSend = isSending
        activeSendID = nil
        activeOutboxID = nil
        readSequence += 1
        operation?.cancel()
        operation = nil
        isLoading = false
        sendPhase = .idle
        if let pendingID, let index = outbox.firstIndex(where: { $0.id == pendingID }),
           outbox[index].state == .sending {
            outbox[index].state = .unconfirmed
            retryOutboxID = pendingID
        }
        if hadSend { errorMessage = Self.message(for: CancellationError()) }
    }

    func invalidate() {
        generation += 1
        cancel()
        messages.removeAll(keepingCapacity: false)
        outbox.removeAll(keepingCapacity: false)
        acknowledgedTurns.removeAll(keepingCapacity: false)
        conversationID = nil
        keys.removeAll(keepingCapacity: false)
        composer = ""
        errorMessage = nil
        retryOutboxID = nil
        turnDraft = nil
    }

    func consumeTurnDraft() { turnDraft = nil }

    private func startSend(outboxID: UUID) async {
        guard !isSending, !Task.isCancelled,
              let pending = outbox.first(where: { $0.id == outboxID }),
              let key = keys[outboxID] else { return }
        let sendID = UUID()
        activeSendID = sendID
        activeOutboxID = outboxID
        readSequence += 1 // A pre-send GET cannot replace this turn later.
        isLoading = false
        sendPhase = .awaitingReply
        errorMessage = nil
        turnDraft = nil
        retryOutboxID = outboxID
        updateOutbox(outboxID, state: .sending)
        let expectedGeneration = generation
        let task = Task {
            await self.performSend(pending, key: key, sendID: sendID,
                                   expectedGeneration: expectedGeneration)
        }
        operation = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performSend(_ pending: FlowOutboxMessage, key: IdempotencyKey,
                             sendID: UUID, expectedGeneration: Int) async {
        defer {
            if activeSendID == sendID {
                activeSendID = nil
                activeOutboxID = nil
                operation = nil
                sendPhase = .idle
            }
        }
        do {
            let response = try await provider.send(text: pending.text, idempotencyKey: key)
            try Task.checkCancellation()
            guard activeSendID == sendID, generation == expectedGeneration else { return }
            publish(response, outboxID: pending.id)
            retryOutboxID = nil
            sendPhase = .reconcilingHistory
            await readHistory(acknowledgedSend: true)
        } catch {
            guard activeSendID == sendID, generation == expectedGeneration else { return }
            updateOutbox(pending.id, state: .unconfirmed)
            retryOutboxID = pending.id
            errorMessage = Self.message(for: error)
        }
    }

    private func publish(_ response: FlowSendResponse, outboxID: UUID) {
        // The mobile Flow route has one conversation per session. Never carry
        // acknowledged content into a different conversation if that changes.
        if let conversationID, conversationID != response.conversationID {
            acknowledgedTurns.removeAll()
            messages.removeAll()
            outbox.removeAll { $0.id != outboxID }
            keys = keys.filter { $0.key == outboxID }
            retryOutboxID = nil
        }
        conversationID = response.conversationID
        if let index = outbox.firstIndex(where: { $0.id == outboxID }) {
            for earlier in outbox[..<index].indices
                where outbox[earlier].serverReply == nil && outbox[earlier].followingReply == nil {
                outbox[earlier].followingReply = response.message
            }
            outbox[index].state = .accepted
            outbox[index].serverReply = response.message
        }
        keys.removeValue(forKey: outboxID) // An acknowledged send is never POSTed again.
        // A same-key replay can return the current representation of an ID
        // already read from history. Publish the complete official DTO now,
        // preserving its position among groups with equal timestamps.
        if let index = messages.firstIndex(where: { $0.id == response.message.id }) {
            messages[index] = response.message
        } else {
            messages.append(response.message)
        }
        messages = Self.orderedWindow(messages)
        if let index = acknowledgedTurns.firstIndex(where: { $0.reply.id == response.message.id }) {
            acknowledgedTurns[index].reply = response.message
            if let user = acknowledgedTurns[index].user,
               user.conversationID != response.message.conversationID
                || user.requestID != response.message.requestID {
                acknowledgedTurns[index].user = nil
            }
        } else {
            acknowledgedTurns.append(FlowAcknowledgedTurn(reply: response.message, user: nil))
        }
        pruneAcknowledgedTurns()
        pruneWindowEvictedAcknowledgements()
        turnDraft = response.draft
    }

    private func readHistory(acknowledgedSend: Bool) async {
        guard !Task.isCancelled else { return }
        readSequence += 1
        let sequence = readSequence
        let expectedGeneration = generation
        isLoading = true
        errorMessage = nil
        defer {
            if sequence == readSequence { isLoading = false }
        }
        do {
            let response = try await provider.history(limit: 50)
            try Task.checkCancellation()
            guard sequence == readSequence, generation == expectedGeneration else { return }
            reconcile(response)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, sequence == readSequence,
                  generation == expectedGeneration else { return }
            errorMessage = acknowledgedSend
                ? String(localized: "flow.error.history") : Self.message(for: error)
        }
    }

    private func reconcile(_ response: FlowHistoryResponse) {
        if let conversationID, conversationID != response.conversationID {
            acknowledgedTurns.removeAll()
            outbox.removeAll()
            keys.removeAll()
            retryOutboxID = nil
            turnDraft = nil
        }
        conversationID = response.conversationID
        let ids = Set(response.messages.map(\.id))
        for index in acknowledgedTurns.indices {
            let reply = acknowledgedTurns[index].reply
            guard reply.conversationID == response.conversationID,
                  let officialReply = response.messages.first(where: { $0.id == reply.id }) else { continue }
            acknowledgedTurns[index].reply = officialReply
            let users = response.messages.filter {
                $0.role == .user && $0.conversationID == officialReply.conversationID
                    && $0.requestID == officialReply.requestID
            }
            if users.count == 1, !officialReply.requestID.isEmpty,
               officialReply.requestID != "request-unavailable" {
                acknowledgedTurns[index].user = users[0]
            }
        }
        // A full newer server window has moved an older acknowledged turn
        // beyond the API's 50-message horizon. A short/older GET has not.
        if response.messages.count >= 50,
           let oldestInWindow = response.messages.first?.createdAt {
            acknowledgedTurns.removeAll {
                !ids.contains($0.reply.id) && $0.reply.createdAt < oldestInWindow
            }
        }
        pruneAcknowledgedTurns()
        let acknowledged = acknowledgedTurns.flatMap { turn in
            [turn.user, turn.reply].compactMap { $0 }
        }
        var seen: Set<String> = []
        let candidates = (response.messages + acknowledged)
            .filter { $0.conversationID == response.conversationID && seen.insert($0.id).inserted }
        messages = Self.orderedWindow(candidates)
        outbox.removeAll { pending in
            guard let reply = pending.serverReply,
                  reply.conversationID == response.conversationID,
                  ids.contains(reply.id),
                  !reply.requestID.isEmpty, reply.requestID != "request-unavailable" else { return false }
            // Binding is learned from this POST's reply, not inferred from
            // equal text, idempotency keys, timestamps, or list position.
            return response.messages.filter {
                $0.role == .user && $0.conversationID == reply.conversationID
                    && $0.requestID == reply.requestID
            }.count == 1
        }
        pruneWindowEvictedAcknowledgements()
    }

    private static func orderedWindow(_ candidates: [FlowMessage]) -> [FlowMessage] {
        var requestOrder: [String: Int] = [:]
        for (offset, message) in candidates.enumerated() {
            let key = Self.sortGroupKey(for: message)
            if requestOrder[key] == nil { requestOrder[key] = offset }
        }
        return Array(candidates.enumerated().sorted { left, right in
            if left.element.createdAt != right.element.createdAt {
                return left.element.createdAt < right.element.createdAt
            }
            let leftRank = requestOrder[Self.sortGroupKey(for: left.element)] ?? left.offset
            let rightRank = requestOrder[Self.sortGroupKey(for: right.element)] ?? right.offset
            if leftRank != rightRank { return leftRank < rightRank }
            if left.element.role != right.element.role {
                return left.element.role == .user
            }
            return left.offset < right.offset
        }.map { $0.element }.suffix(50))
    }

    private func pruneAcknowledgedTurns() {
        var count = acknowledgedTurns.reduce(0) { $0 + ($1.user == nil ? 1 : 2) }
        while count > 50, !acknowledgedTurns.isEmpty {
            let removed = acknowledgedTurns.removeFirst()
            count -= removed.user == nil ? 1 : 2
        }
    }

    private func pruneWindowEvictedAcknowledgements() {
        // POST publication and GET reconciliation can each fill the visible
        // 50-message window. Keep cache and accepted outbox on that same
        // horizon so a stale GET cannot resurrect an evicted local turn.
        let visibleIDs = Set(messages.map(\.id))
        acknowledgedTurns.removeAll { !visibleIDs.contains($0.reply.id) }
        outbox.removeAll { pending in
            guard pending.state == .accepted, let reply = pending.serverReply else {
                return false
            }
            return !visibleIDs.contains(reply.id)
        }
    }

    private static func sortGroupKey(for message: FlowMessage) -> String {
        guard !message.requestID.isEmpty,
              message.requestID != "request-unavailable" else {
            return "message:\(message.id)"
        }
        return "request:\(message.conversationID):\(message.requestID)"
    }

    private func updateOutbox(_ id: UUID, state: FlowOutboxMessage.State) {
        guard let index = outbox.firstIndex(where: { $0.id == id }) else { return }
        outbox[index].state = state
    }

    private func anchor(for pending: FlowOutboxMessage) -> String? {
        if let reply = pending.serverReply { return reply.id }
        guard let following = pending.followingReply else { return nil }
        guard messages.contains(where: { $0.id == following.id }) else {
            // The following acknowledged turn left the history window, so
            // this still-unconfirmed submission is older than that window.
            return messages.first?.id
        }
        let users = messages.filter {
            $0.role == .user && $0.conversationID == following.conversationID
                && $0.requestID == following.requestID
        }
        return users.count == 1 ? users[0].id : following.id
    }

    private static func message(for error: Error) -> String {
        if error is CancellationError { return String(localized: "flow.error.cancelled") }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return String(localized: "flow.error.offline")
        }
        if case MobileAPITransportError.rateLimited = error { return String(localized: "flow.error.rate-limited") }
        if case MobileAPITransportError.unauthorized = error { return String(localized: "flow.error.session") }
        if case MobileAPITransportError.forbidden = error { return String(localized: "flow.error.forbidden") }
        return String(localized: "flow.error.generic")
    }
}
