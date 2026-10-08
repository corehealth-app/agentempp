import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Flow Chat exact concurrency regressions")
struct FlowChatConcurrencyTests {
    @Test("same-key replay replaces the full official DTO before a failed GET and preserves composer B",
          arguments: [FlowMessageState.processing, .completed])
    func idempotentReplayUpsertsOfficialDTOBeforeFailedHistory(oldState: FlowMessageState) async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let user = message(id: "official-user-a", role: .user, text: "Mensagem A", requestID: "official-request-a")
        let old = replayMessage("Bloco 7700: 3120 kcal. Orçamento 14d: 5850 kcal.", state: oldState)
        let current = replayMessage("Evite amendoim por sua alergia. Consumido: 541 / 2.980 kcal.")
        let response = FlowSendResponse(conversationID: "conversation", message: current,
                                        draft: FlowTurnDraft(id: "official-draft-a", domain: .nutrition))
        model.composer = "Mensagem A"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .failure(URLError(.timedOut)))
        await first.value
        let pendingID = model.outbox.first?.id
        let originalKeys = await provider.sentKeys
        #expect(originalKeys.count == 1)
        #expect(model.outbox.map(\.state) == [.unconfirmed])
        #expect(model.outbox.first?.serverReply == nil)

        let load = Task { await model.load() }
        await provider.waitForHistories(1)
        await provider.completeHistory(0, with: .success(history([user, old])))
        await load.value
        #expect(model.messages == [user, old])
        #expect(model.outbox.map(\.state) == [.unconfirmed])
        #expect(model.outbox.first?.serverReply == nil)
        let draftB = "Rascunho B: bloco 7700 / orçamento 14d"
        model.composer = draftB
        let retry = Task {
            await model.retry()
            await provider.sendAttemptReturned(expectedCount: 2)
        }
        let started = await provider.waitForSendOrReturnedAttempt(2)
        #expect(started)
        guard started else { await retry.value; return }
        #expect(await provider.sentKeys == originalKeys + originalKeys)
        await provider.completeSend(1, with: .success(response))
        await provider.waitForHistories(2)
        // Full equality catches stale content/state despite an unchanged ID.
        #expect(model.messages == [user, current])
        #expect(model.messages.filter { $0.id == current.id }.count == 1)
        #expect(model.composer == draftB)
        #expect(model.turnDraft == response.draft)
        #expect(model.outbox.count == 1)
        #expect(model.outbox.first?.id == pendingID)
        #expect(model.outbox.first?.state == .accepted)
        #expect(model.outbox.first?.serverReply == current)
        #expect(!model.isSending && model.isLoading)
        await provider.completeHistory(1, with: .failure(URLError(.notConnectedToInternet)))
        await retry.value
        #expect(model.messages == [user, current])
        #expect(model.errorMessage == String(localized: "flow.error.history"))
        #expect(model.turnDraft == response.draft)
        #expect(model.composer == draftB)
        #expect(!model.isSending && !model.isLoading)

        // Drain a wrong extra POST rather than hanging a RED on the double.
        await provider.automaticallyReply(with: response)
        let readRetry = Task { await model.retry() }
        await provider.waitForHistories(3)
        #expect(await provider.sentKeys == originalKeys + originalKeys)
        await provider.completeHistory(2, with: .success(history([user, current])))
        await readRetry.value
        #expect(model.messages == [user, current])
        #expect(model.outbox.isEmpty && model.errorMessage == nil)
        let stale = Task { await model.load() }
        await provider.waitForHistories(4)
        await provider.completeHistory(3, with: .success(history([])))
        await stale.value
        #expect(model.messages == [user, current])
        #expect(model.composer == draftB)
        #expect(model.turnDraft == response.draft)
        #expect(model.outbox.isEmpty)
        #expect(await provider.sentKeys == originalKeys + originalKeys)
        #expect(await provider.historyCount == 4)
    }

    @Test("a latest GET refreshes the acknowledged full DTO before an empty GET")
    func latestHistoryDTORefreshesAcknowledgedCacheBeforeEmptyHistory() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let user = message(id: "official-user-a", role: .user, text: "Mensagem A", requestID: "official-request-a")
        let old = replayMessage("Bloco 7700: 3120 kcal.", state: .processing)
        let current = replayMessage("Evite amendoim por sua alergia. Consumido: 541 / 2.980 kcal.")
        let response = FlowSendResponse(conversationID: "conversation", message: old,
                                        draft: FlowTurnDraft(id: "official-draft-a", domain: .nutrition))
        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .success(response))
        await provider.waitForHistories(1)
        await provider.completeHistory(0, with: .success(history([user, old])))
        await send.value
        #expect(model.messages == [user, old])
        #expect(model.outbox.isEmpty)
        model.composer = "Rascunho B: bloco 7700 / orçamento 14d"
        let load = Task { await model.load() }
        await provider.waitForHistories(2)
        await provider.completeHistory(1, with: .success(history([user, current])))
        await load.value
        #expect(model.messages == [user, current])
        let empty = Task { await model.load() }
        await provider.waitForHistories(3)
        await provider.completeHistory(2, with: .success(history([])))
        await empty.value
        #expect(model.messages == [user, current])
        #expect(model.messages.filter { $0.id == current.id }.count == 1)
        #expect(model.composer == "Rascunho B: bloco 7700 / orçamento 14d")
        #expect(model.turnDraft == response.draft)
        #expect(model.outbox.isEmpty && model.errorMessage == nil)
        #expect(await provider.sentKeys.count == 1)
        #expect(await provider.historyCount == 3)
    }

    @Test("cancelled A1 cannot revert the same official ID after retry A2 receives its current DTO")
    func cancelledReplayCannotRevertSameOfficialMessageDTO() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let user = message(id: "official-user-a", role: .user, text: "Mensagem A", requestID: "official-request-a")
        let current = replayMessage("Evite amendoim por sua alergia. Consumido: 541 / 2.980 kcal.")
        let response = FlowSendResponse(conversationID: "conversation", message: current,
                                        draft: FlowTurnDraft(id: "official-draft-a", domain: .nutrition))
        let old = FlowSendResponse(conversationID: "conversation", message: replayMessage("Bloco 7700: 3120 kcal."),
                                  draft: FlowTurnDraft(id: "old-draft-a", domain: .training))
        model.composer = "Mensagem A"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        let originalKeys = await provider.sentKeys
        model.cancel()
        #expect(model.outbox.map(\.state) == [.unconfirmed])
        #expect(model.messages.isEmpty && !model.isSending)
        model.composer = "Rascunho B: bloco 7700 / orçamento 14d"
        let retry = Task {
            await model.retry()
            await provider.sendAttemptReturned(expectedCount: 2)
        }
        let started = await provider.waitForSendOrReturnedAttempt(2)
        #expect(started)
        guard started else {
            await provider.completeSend(0, with: .success(old))
            await first.value
            await retry.value
            return
        }
        #expect(await provider.sentKeys == originalKeys + originalKeys)
        await provider.completeSend(1, with: .success(response))
        await provider.waitForHistories(1)
        #expect(model.messages == [current])
        #expect(model.turnDraft == response.draft)
        await provider.completeSend(0, with: .success(old))
        await first.value
        #expect(model.messages == [current])
        #expect(model.turnDraft == response.draft)
        #expect(model.composer == "Rascunho B: bloco 7700 / orçamento 14d")
        #expect(model.outbox.map(\.state) == [.accepted])
        #expect(model.outbox.first?.serverReply == current)
        #expect(model.errorMessage == nil)
        #expect(model.isLoading && !model.isSending)
        #expect(await provider.historyCount == 1)
        await provider.completeHistory(0, with: .success(history([user, current])))
        await retry.value
        #expect(model.messages == [user, current])
        #expect(model.outbox.isEmpty && model.errorMessage == nil)
        #expect(!model.isLoading && !model.isSending)
        #expect(model.turnDraft == response.draft)
        #expect(model.composer == "Rascunho B: bloco 7700 / orçamento 14d")
        #expect(await provider.sentKeys == originalKeys + originalKeys)
        #expect(await provider.historyCount == 1)
    }

    @Test("sending A and typing B preserves B when A completes")
    func preservesNewComposer() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        #expect(model.outbox.map(\.text) == ["Mensagem A"])
        #expect(model.outbox.first?.state == .sending)
        #expect(model.messages.isEmpty)
        #expect(model.composer.isEmpty)
        model.composer = "Rascunho B"
        await provider.completeSend(0, with: .success(reply("a")))
        await send.value
        #expect(model.composer == "Rascunho B")
        #expect(!model.isSending)
    }

    @Test("a cancelled noncooperative POST failure cannot clear a newer pending send")
    func cancelledFailureCannotPublishIntoNewSend() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        model.cancel()
        model.composer = "Mensagem B"
        let second = Task { await model.send() }
        await provider.waitForSends(2)
        await provider.completeSend(0, with: .failure(URLError(.timedOut)))
        await first.value
        #expect(model.isSending)
        #expect(model.errorMessage == nil)
        await provider.completeSend(1, with: .success(reply("b")))
        await second.value
        #expect(model.messages.contains { $0.id == "reply-b" })
    }

    @Test("a cancelled noncooperative POST success cannot publish after a newer send starts")
    func cancelledSuccessCannotPublishIntoNewSend() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        model.cancel()
        model.composer = "Mensagem B"
        let second = Task { await model.send() }
        await provider.waitForSends(2)
        await provider.completeSend(0, with: .success(reply("a")))
        await first.value
        #expect(model.isSending)
        #expect(!model.messages.contains { $0.id == "reply-a" })
        await provider.completeSend(1, with: .success(reply("b")))
        await second.value
        #expect(model.messages.contains { $0.id == "reply-b" })
    }

    @Test("reopening Flow after the first POST fails or is cancelled shows pending GET without dropping outbox or repeating POST", arguments: [false, true])
    func pendingHistoryWithOnlyUnconfirmedOutboxShowsReconciliation(cancelled: Bool) async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let initialLoad = Task { await model.load() }
        await provider.waitForHistories(1)
        #expect(model.isLoading)
        #expect(model.conversationItems.isEmpty)
        #expect(!model.isReconcilingHistory)
        await provider.completeHistory(0, with: .success(history([])))
        await initialLoad.value

        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        if cancelled {
            model.cancel()
            await provider.completeSend(0, with: .failure(CancellationError()))
        } else {
            await provider.completeSend(0, with: .failure(URLError(.timedOut)))
        }
        await send.value
        #expect(model.messages.isEmpty)
        #expect(model.outbox.map(\.text) == ["Mensagem A"])
        #expect(model.outbox.map(\.state) == [.unconfirmed])
        #expect(!model.isSending)
        #expect(!model.isLoading)
        #expect(!model.isReconcilingHistory)
        let preservedOutbox = model.outbox
        let sentKeys = await provider.sentKeys
        #expect(sentKeys.count == 1)
        #expect(await provider.historyCount == 1)

        // The view cancels locally on disappearance and loads on re-entry.
        // Hold that GET at the existing explicit network barrier.
        model.cancel()
        let reopened = Task { await model.load() }
        await provider.waitForHistories(2)
        #expect(model.isLoading)
        #expect(model.messages.isEmpty)
        #expect(!model.conversationItems.isEmpty)
        #expect(model.isReconcilingHistory)
        #expect(!model.isSending)
        #expect(model.outbox == preservedOutbox)
        #expect(await provider.sentKeys == sentKeys)

        // Drain even on RED: #expect does not throw or strand the GET.
        await provider.completeHistory(1, with: .success(history([])))
        await reopened.value
        #expect(!model.isLoading)
        #expect(!model.isReconcilingHistory)
        #expect(model.messages.isEmpty)
        #expect(model.outbox == preservedOutbox)
        #expect(await provider.sentKeys == sentKeys)
        #expect(await provider.historyCount == 2)
    }

    @Test("reversed GET completion keeps the most recently requested history")
    func reversedHistory() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let first = Task { await model.load() }
        await provider.waitForHistories(1)
        let second = Task { await model.load() }
        await provider.waitForHistories(2)
        await provider.completeHistory(1, with: .success(history([reply("new").message])))
        await second.value
        await provider.completeHistory(0, with: .success(history([reply("old").message])))
        await first.value
        #expect(model.messages.map(\.id) == ["reply-new"])
        #expect(!model.isLoading)
    }

    @Test("a cancelled GET that ignores cancellation cannot publish history")
    func cancelledHistoryCannotPublish() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let load = Task { await model.load() }
        await provider.waitForHistories(1)
        load.cancel()
        await provider.completeHistory(0, with: .success(history([reply("late").message])))
        await load.value
        #expect(model.messages.isEmpty)
        #expect(!model.isLoading)
    }

    @Test("POST publishes its official reply and draft before reconciliation GET completes")
    func officialPostIsImmediate() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        let response = FlowSendResponse(
            conversationID: "conversation", message: reply("a").message,
            draft: FlowTurnDraft(id: "draft-a", domain: .nutrition)
        )
        await provider.completeSend(0, with: .success(response))
        await provider.waitForHistories(1)
        #expect(model.messages.map(\.id) == ["reply-a"])
        #expect(model.turnDraft?.id == "draft-a")
        await provider.completeHistory(0, with: .success(history([response.message])))
        await send.value
        #expect(model.messages.map(\.id) == ["reply-a"])
    }

    @Test("ACK A releases send B while GET A is suspended; late GET A cannot replace B and history retry never POSTs", arguments: [false, true])
    func acknowledgedPostReleasesNextSend(failsCurrentHistory: Bool) async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .success(reply("a")))
        await provider.waitForHistories(1)
        // GET A remains suspended throughout the entire B turn.
        #expect(!model.isSending)
        #expect(model.isLoading)
        model.composer = "Mensagem B"
        let second = Task {
            await model.send()
            await provider.sendAttemptReturned(expectedCount: 2)
        }
        let startedSecondPost = await provider.waitForSendOrReturnedAttempt(2)
        #expect(startedSecondPost)
        guard startedSecondPost else {
            // The regression rejects B synchronously. Drain A explicitly so
            // RED reports the contract failure without leaked continuations.
            await provider.completeHistory(0, with: .success(history([reply("a").message])))
            await first.value
            await second.value
            return
        }
        #expect(model.composer.isEmpty)
        #expect(model.isSending)
        #expect(model.outbox.map(\.state) == [.accepted, .sending])
        #expect(await provider.sentKeys.count == 2)
        #expect(await provider.sentKeys.first != provider.sentKeys.last)

        await provider.completeSend(1, with: .success(reply("b")))
        await provider.waitForHistories(2)
        #expect(model.messages.map(\.id) == ["reply-a", "reply-b"])
        #expect(!model.isSending)
        let official = [
            message(id: "user-a", role: .user, text: "Mensagem A", requestID: "request-a"),
            reply("a").message,
            message(id: "user-b", role: .user, text: "Mensagem B", requestID: "request-b"),
            reply("b").message,
        ]
        await provider.completeHistory(1, with: failsCurrentHistory
            ? .failure(URLError(.notConnectedToInternet))
            : .success(history(official)))
        await second.value
        let idsAfterB = model.messages.map(\.id)
        let errorAfterB = model.errorMessage
        #expect((errorAfterB != nil) == failsCurrentHistory)

        await provider.completeHistory(0, with: .success(history(Array(official.prefix(2)))))
        await first.value
        #expect(model.messages.map(\.id) == idsAfterB)
        #expect(model.messages.contains { $0.id == "reply-b" })
        #expect(model.errorMessage == errorAfterB)
        #expect(!model.isSending)
        #expect(!model.isLoading)

        if failsCurrentHistory {
            // A wrong POST retry must fail on counts rather than hang.
            await provider.automaticallyReply(with: reply("b"))
            let retry = Task { await model.retry() }
            await provider.waitForHistories(3)
            #expect(await provider.sentKeys.count == 2)
            await provider.completeHistory(2, with: .success(history(official)))
            await retry.value
        }
        #expect(model.messages.map(\.id) == official.map(\.id))
        #expect(model.outbox.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(await provider.sentKeys.count == 2)
    }

    @Test("POST success plus GET failure keeps reply and retry performs GET only")
    func acceptedSendDoesNotPostAgainAfterHistoryFailure() async {
        let provider = ControlledFlowProvider(historyError: URLError(.notConnectedToInternet))
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        let response = reply("a")
        await provider.completeSend(0, with: .success(response))
        await send.value
        #expect(model.messages.map(\.id) == ["reply-a"])
        #expect(model.errorMessage != nil)
        // If the regression repeats POST, return immediately so the test
        // fails on request counts rather than hanging on its test double.
        await provider.automaticallyReply(with: response)
        await model.retry()
        #expect(await provider.sentKeys.count == 1)
        #expect(await provider.historyCount == 2)
        #expect(model.messages.map(\.id) == ["reply-a"])
    }

    @Test("an older GET cannot erase a turn already acknowledged by POST and confirmed by history")
    func staleHistoryPreservesConfirmedTurnWithoutAnotherPost() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let user = message(id: "user-a", role: .user, text: "Mensagem A", requestID: "request-a")
        let assistant = reply("a").message
        let canonical = history([user, assistant])

        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .success(reply("a")))
        await provider.waitForHistories(1)
        await provider.completeHistory(0, with: .success(canonical))
        await send.value
        #expect(model.messages.map(\.id) == ["user-a", "reply-a"])
        #expect(model.outbox.isEmpty)

        let staleLoad = Task { await model.load() }
        await provider.waitForHistories(2)
        await provider.completeHistory(1, with: .success(history([])))
        await staleLoad.value
        #expect(model.messages.map(\.id) == ["user-a", "reply-a"])
        #expect(model.outbox.isEmpty)
        #expect(await provider.sentKeys.count == 1)

        let older = FlowMessage(
            id: "older-user", conversationID: "conversation", role: .user,
            content: "Anterior", state: .completed, requestID: "older-request",
            createdAt: Date(timeIntervalSince1970: 900)
        )
        let olderLoad = Task { await model.load() }
        await provider.waitForHistories(3)
        await provider.completeHistory(2, with: .success(history([older])))
        await olderLoad.value
        #expect(model.messages.map(\.id) == ["older-user", "user-a", "reply-a"])

        let refreshedLoad = Task { await model.load() }
        await provider.waitForHistories(4)
        await provider.completeHistory(3, with: .success(canonical))
        await refreshedLoad.value
        #expect(model.messages.map(\.id) == ["user-a", "reply-a"])
        #expect(await provider.sentKeys.count == 1)

        let newerWindow = (0..<50).map { index in
            FlowMessage(
                id: "newer-\(index)", conversationID: "conversation", role: .user,
                content: "Novo \(index)", state: .completed,
                requestID: "newer-request-\(index)",
                createdAt: Date(timeIntervalSince1970: 2_000 + Double(index))
            )
        }
        let laterLoad = Task { await model.load() }
        await provider.waitForHistories(5)
        await provider.completeHistory(4, with: .success(history(newerWindow)))
        await laterLoad.value
        #expect(model.messages.map(\.id) == newerWindow.map(\.id))
        #expect(await provider.sentKeys.count == 1)

        model.invalidate()
        #expect(model.messages.isEmpty)
        #expect(model.outbox.isEmpty)
    }

    @Test("a different conversation never inherits an acknowledged turn or its local outbox")
    func changedConversationDoesNotMergePreviousTurn() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .success(reply("a")))
        await provider.waitForHistories(1)
        let other = FlowMessage(
            id: "other-user", conversationID: "other-conversation", role: .user,
            content: "Outra conversa", state: .completed, requestID: "other-request",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        await provider.completeHistory(0, with: .success(FlowHistoryResponse(
            conversationID: "other-conversation", messages: [other]
        )))
        await send.value
        #expect(model.messages.map(\.id) == ["other-user"])
        #expect(model.outbox.isEmpty)
        #expect(await provider.sentKeys.count == 1)
    }

    @Test("equal timestamps and interleaved server rows keep a deterministic official turn order")
    func tiedTimestampsDoNotCycleDuringReconciliation() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        let userA = message(id: "user-a", role: .user, text: "A", requestID: "request-a")
        let userB = message(id: "user-b", role: .user, text: "B", requestID: "request-b")
        let replyA = reply("a").message
        let replyB = reply("b").message

        model.composer = "A"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.setHistory([userA, replyA])
        await provider.completeSend(0, with: .success(reply("a")))
        await first.value

        model.composer = "B"
        let second = Task { await model.send() }
        await provider.waitForSends(2)
        await provider.setHistory([replyA, userB, userA, replyB])
        await provider.completeSend(1, with: .success(reply("b")))
        await second.value
        #expect(model.messages.map(\.id) == ["user-a", "reply-a", "user-b", "reply-b"])
        #expect(model.outbox.isEmpty)
        #expect(await provider.sentKeys.count == 2)
    }

    @Test("an accepted outbox leaves the 50-message window while an unconfirmed retry keeps its key")
    func windowPrunesAcceptedOutboxButPreservesUnconfirmedRetry() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)

        model.composer = "Mensagem A"
        let accepted = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .success(reply("a")))
        await provider.waitForHistories(1)
        await provider.completeHistory(0, with: .success(history([])))
        await accepted.value
        #expect(model.outbox.map(\.state) == [.accepted])

        model.composer = "Mensagem B"
        let uncertain = Task { await model.send() }
        await provider.waitForSends(2)
        await provider.completeSend(1, with: .failure(URLError(.timedOut)))
        await uncertain.value
        #expect(model.outbox.map(\.state) == [.accepted, .unconfirmed])
        let keyBeforeRetry = await provider.sentKeys[1]

        let newerWindow = (0..<50).map { index in
            FlowMessage(
                id: "newer-\(index)", conversationID: "conversation", role: .user,
                content: "Novo \(index)", state: .completed,
                requestID: "newer-request-\(index)",
                createdAt: Date(timeIntervalSince1970: 2_000 + Double(index))
            )
        }
        let reload = Task { await model.load() }
        await provider.waitForHistories(2)
        await provider.completeHistory(1, with: .success(history(newerWindow)))
        await reload.value
        #expect(model.messages.map(\.id) == newerWindow.map(\.id))
        #expect(model.outbox.map(\.text) == ["Mensagem B"])
        #expect(model.outbox.map(\.state) == [.unconfirmed])
        #expect(model.conversationItems.count == 51)
        #expect(model.conversationItems.last?.id.hasPrefix("outbox-") == true)

        let retry = Task { await model.retry() }
        await provider.waitForSends(3)
        #expect(await provider.sentKeys[2] == keyBeforeRetry)
        await provider.completeSend(2, with: .success(reply("b")))
        await provider.waitForHistories(3)
        await provider.completeHistory(2, with: .success(history(newerWindow)))
        await retry.value
    }

    @Test("51 acknowledged posts without canonical GET retain only the last 50 accepted turns")
    func repeatedAcknowledgementsBoundAcceptedOutbox() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        for index in 0..<51 {
            model.composer = "Mensagem \(index)"
            let send = Task { await model.send() }
            await provider.waitForSends(index + 1)
            await provider.completeSend(index, with: .success(reply("\(index)")))
            await send.value
        }
        #expect(model.messages.count == 50)
        #expect(model.outbox.count == 50)
        #expect(model.outbox.first?.text == "Mensagem 1")
        #expect(model.outbox.last?.text == "Mensagem 50")
        #expect(await provider.sentKeys.count == 51)
    }

    @Test("49 newer server rows evict the first of two accepted replies without leaving an orphan outbox")
    func shortHistoryWindowEvictsAcceptedOutboxWhoseReplyIsNoLongerVisible() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)

        for (index, suffix) in ["a", "b"].enumerated() {
            model.composer = "Mensagem \(suffix)"
            let send = Task { await model.send() }
            await provider.waitForSends(index + 1)
            let acknowledged = FlowMessage(
                id: "reply-\(suffix)", conversationID: "conversation", role: .assistant,
                content: "Resposta \(suffix)", state: .completed,
                requestID: "request-\(suffix)",
                createdAt: Date(timeIntervalSince1970: 1_000 + Double(index))
            )
            await provider.completeSend(index, with: .success(FlowSendResponse(
                conversationID: "conversation", message: acknowledged
            )))
            await provider.waitForHistories(index + 1)
            await provider.completeHistory(index, with: .success(history([])))
            await send.value
        }
        #expect(model.messages.map(\.id) == ["reply-a", "reply-b"])
        #expect(model.outbox.map(\.text) == ["Mensagem a", "Mensagem b"])

        let newer = (0..<49).map { index in
            FlowMessage(
                id: "newer-\(index)", conversationID: "conversation", role: .user,
                content: "Novo \(index)", state: .completed,
                requestID: "newer-request-\(index)",
                createdAt: Date(timeIntervalSince1970: 2_000 + Double(index))
            )
        }
        let load = Task { await model.load() }
        await provider.waitForHistories(3)
        await provider.completeHistory(2, with: .success(history(newer)))
        await load.value

        #expect(model.messages.map(\.id) == ["reply-b"] + newer.map(\.id))
        #expect(model.outbox.map(\.text) == ["Mensagem b"])
        #expect(model.conversationItems.count == 51)
        #expect(model.conversationItems.last?.id == "message-newer-48")

        // A later stale GET must not resurrect A after the merged 50-message
        // horizon evicted both its reply and its local accepted submission.
        let staleLoad = Task { await model.load() }
        await provider.waitForHistories(4)
        await provider.completeHistory(3, with: .success(history([])))
        await staleLoad.value
        #expect(model.messages.map(\.id) == ["reply-b"])
        #expect(model.outbox.map(\.text) == ["Mensagem b"])
        #expect(model.conversationItems.map(\.id).last == "message-reply-b")
        #expect(await provider.sentKeys.count == 2)
    }

    @Test("a third POST evicts the oldest accepted turn from a full merged window without resurrection")
    func publishEvictsAcknowledgedTurnWithItsAcceptedOutbox() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)

        for (index, suffix) in ["a", "b"].enumerated() {
            model.composer = "Mensagem \(suffix)"
            let send = Task { await model.send() }
            await provider.waitForSends(index + 1)
            let acknowledged = FlowMessage(
                id: "reply-\(suffix)", conversationID: "conversation", role: .assistant,
                content: "Resposta \(suffix)", state: .completed,
                requestID: "request-\(suffix)",
                createdAt: Date(timeIntervalSince1970: 1_000 + Double(index))
            )
            await provider.completeSend(index, with: .success(FlowSendResponse(
                conversationID: "conversation", message: acknowledged
            )))
            await provider.waitForHistories(index + 1)
            await provider.completeHistory(index, with: .success(history([])))
            await send.value
        }

        let newer = (0..<48).map { index in
            FlowMessage(
                id: "newer-\(index)", conversationID: "conversation", role: .user,
                content: "Novo \(index)", state: .completed,
                requestID: "newer-request-\(index)",
                createdAt: Date(timeIntervalSince1970: 2_000 + Double(index))
            )
        }
        let load = Task { await model.load() }
        await provider.waitForHistories(3)
        await provider.completeHistory(2, with: .success(history(newer)))
        await load.value
        #expect(model.messages.map(\.id) == ["reply-a", "reply-b"] + newer.map(\.id))
        #expect(model.outbox.map(\.text) == ["Mensagem a", "Mensagem b"])

        model.composer = "Mensagem c"
        let third = Task { await model.send() }
        await provider.waitForSends(3)
        let replyC = FlowMessage(
            id: "reply-c", conversationID: "conversation", role: .assistant,
            content: "Resposta c", state: .completed, requestID: "request-c",
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        await provider.completeSend(2, with: .success(FlowSendResponse(
            conversationID: "conversation", message: replyC
        )))
        await provider.waitForHistories(4)
        #expect(model.messages.map(\.id) == ["reply-b"] + newer.map(\.id) + ["reply-c"])
        #expect(model.outbox.map(\.text) == ["Mensagem b", "Mensagem c"])

        await provider.completeHistory(3, with: .success(history([])))
        await third.value
        #expect(model.messages.map(\.id) == ["reply-b", "reply-c"])
        #expect(model.outbox.map(\.text) == ["Mensagem b", "Mensagem c"])
        #expect(model.conversationItems.last?.id == "message-reply-c")
        #expect(await provider.sentKeys.count == 3)
    }

    @Test("POST into a new conversation clears the prior history even without an ACK cache")
    func changedConversationAfterHistoryOnlyDoesNotMixSnapshots() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let old = message(id: "old-user", role: .user, text: "A", requestID: "old-request")
        let initial = Task { await model.load() }
        await provider.waitForHistories(1)
        await provider.completeHistory(0, with: .success(history([old])))
        await initial.value
        #expect(model.messages.map(\.id) == ["old-user"])

        model.composer = "Mensagem B"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        let newReply = FlowMessage(
            id: "new-reply", conversationID: "other-conversation", role: .assistant,
            content: "Resposta B", state: .completed, requestID: "new-request",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        await provider.completeSend(0, with: .success(FlowSendResponse(
            conversationID: "other-conversation", message: newReply
        )))
        await provider.waitForHistories(2)
        #expect(model.messages.map(\.id) == ["new-reply"])
        #expect(model.outbox.count == 1)
        await provider.completeHistory(1, with: .success(FlowHistoryResponse(
            conversationID: "other-conversation", messages: [newReply]
        )))
        await send.value
        #expect(model.messages.map(\.id) == ["new-reply"])
    }

    @Test("a failed POST retries the same key and reconciles an unrelated server request ID")
    func retryKeepsIdempotencyWithoutAssumingServerRequestID() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        model.composer = "Mensagem repetida"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .failure(URLError(.timedOut)))
        await first.value
        #expect(model.outbox.count == 1)
        #expect(model.outbox.first?.state == .unconfirmed)
        let retry = Task { await model.retry() }
        await provider.waitForSends(2)
        #expect(model.outbox.count == 1)
        let user = message(id: "server-user", role: .user, text: "Mensagem repetida", requestID: "server-request-unrelated")
        let response = FlowSendResponse(conversationID: "conversation", message:
            message(id: "server-reply", role: .assistant, text: "Recebido", requestID: "server-request-unrelated"))
        await provider.setHistory([user, response.message])
        await provider.completeSend(1, with: .success(response))
        await retry.value
        #expect(await provider.sentKeys.count == 2)
        #expect(await provider.sentKeys.first == provider.sentKeys.last)
        #expect(await provider.sentKeys.first != "server-request-unrelated")
        #expect(model.messages.map(\.id) == ["server-user", "server-reply"])
        #expect(model.outbox.isEmpty)
    }

    @Test("an older idempotent replay keeps official chronology and the latest 50 on GET failure", arguments: [40, 50])
    func oldRetryDoesNotMoveAheadOfNewerOfficialHistory(windowSize: Int) async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        model.composer = "Mensagem repetida"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .failure(URLError(.timedOut)))
        await first.value
        #expect(model.outbox.map(\.state) == [.unconfirmed])

        let newer = (0..<windowSize).map { index in
            FlowMessage(
                id: "newer-\(index)", conversationID: "conversation", role: .user,
                content: index == 0 ? "Mensagem repetida" : "Novo \(index)",
                state: .completed, requestID: "newer-request-\(index)",
                createdAt: Date(timeIntervalSince1970: 2_000 + Double(index))
            )
        }
        let load = Task { await model.load() }
        await provider.waitForHistories(1)
        await provider.completeHistory(0, with: .success(history(newer)))
        await load.value
        #expect(model.messages.map(\.id) == newer.map(\.id))
        #expect(model.outbox.map(\.text) == ["Mensagem repetida"])

        let retry = Task { await model.retry() }
        await provider.waitForSends(2)
        #expect(await provider.sentKeys.count == 2)
        #expect(await provider.sentKeys.first == provider.sentKeys.last)
        let oldReply = FlowMessage(
            id: "old-reply", conversationID: "conversation", role: .assistant,
            content: "Resposta anterior", state: .completed,
            requestID: "old-server-request", createdAt: Date(timeIntervalSince1970: 1_000)
        )
        await provider.completeSend(1, with: .success(FlowSendResponse(
            conversationID: "conversation", message: oldReply
        )))
        await provider.waitForHistories(2)
        await provider.completeHistory(1, with: .failure(URLError(.notConnectedToInternet)))
        await retry.value

        let expectedIDs = windowSize == 50
            ? newer.map(\.id)
            : [oldReply.id] + newer.map(\.id)
        #expect(model.messages.map(\.id) == expectedIDs)
        #expect(model.messages.map(\.createdAt) == model.messages.map(\.createdAt).sorted())
        #expect(model.messages.contains(where: { $0.id == "newer-0" && $0.content == "Mensagem repetida" }))
        if windowSize == 50 {
            #expect(model.outbox.isEmpty)
        } else {
            #expect(model.outbox.map(\.state) == [.accepted])
            #expect(model.conversationItems.first?.id.hasPrefix("outbox-") == true)
        }
    }

    @Test("the initial GET cannot replace the conversation after a send has started")
    func preSendHistoryCannotOverwriteNewReply() async {
        let provider = ControlledFlowProvider(suspendsHistory: true)
        let model = makeModel(provider)
        let oldLoad = Task { await model.load() }
        await provider.waitForHistories(1)
        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .success(reply("a")))
        await provider.waitForHistories(2)
        await provider.completeHistory(1, with: .success(history([reply("a").message])))
        await send.value
        await provider.completeHistory(0, with: .success(history([reply("old").message])))
        await oldLoad.value
        #expect(model.messages.map(\.id) == ["reply-a"])
    }

    @Test("equal text in an unrelated server turn cannot reconcile a local submission")
    func matchingTextDoesNotBindOutbox() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        model.composer = "Mensagem repetida"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        let unrelatedUser = message(id: "other-user", role: .user, text: "Mensagem repetida", requestID: "other-request")
        await provider.setHistory([unrelatedUser, reply("a").message])
        await provider.completeSend(0, with: .success(reply("a")))
        await send.value
        #expect(model.messages.map(\.id) == ["other-user", "reply-a"])
        #expect(model.outbox.map(\.text) == ["Mensagem repetida"])
        #expect(model.outbox.first?.state == .accepted)
    }

    @Test("two equal texts remain separate official turns with distinct server identities")
    func repeatedTextKeepsSeparateTurns() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        var official: [FlowMessage] = []
        for (index, suffix) in ["a", "b"].enumerated() {
            model.composer = "Mesmo texto"
            let send = Task { await model.send() }
            await provider.waitForSends(index + 1)
            official.append(message(id: "user-\(suffix)", role: .user, text: "Mesmo texto", requestID: "request-\(suffix)"))
            official.append(reply(suffix).message)
            await provider.setHistory(official)
            await provider.completeSend(index, with: .success(reply(suffix)))
            await send.value
        }
        #expect(model.messages.map(\.id) == ["user-a", "reply-a", "user-b", "reply-b"])
        #expect(model.outbox.isEmpty)
        #expect(await provider.sentKeys.first != provider.sentKeys.last)
    }

    @Test("session invalidation clears the outbox and ignores a noncooperative late POST")
    func invalidationClearsLocalSubmission() async {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let send = Task { await model.send() }
        await provider.waitForSends(1)
        model.invalidate()
        #expect(model.outbox.isEmpty)
        await provider.completeSend(0, with: .success(reply("a")))
        await send.value
        #expect(model.outbox.isEmpty)
        #expect(model.messages.isEmpty)
        #expect(model.composer.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.turnDraft == nil)
    }

    @Test("an older unconfirmed submission stays before the next acknowledged turn")
    func earlierPendingDoesNotFollowNewReply() async throws {
        let provider = ControlledFlowProvider()
        let model = makeModel(provider)
        model.composer = "Mensagem A"
        let first = Task { await model.send() }
        await provider.waitForSends(1)
        await provider.completeSend(0, with: .failure(URLError(.timedOut)))
        await first.value
        let pendingID = try #require(model.outbox.first?.id)
        model.composer = "Mensagem B"
        let second = Task { await model.send() }
        await provider.waitForSends(2)
        let user = message(id: "user-b", role: .user, text: "Mensagem B", requestID: "request-b")
        await provider.setHistory([user, reply("b").message])
        await provider.completeSend(1, with: .success(reply("b")))
        await second.value
        #expect(model.conversationItems.map(\.id) == [
            "outbox-\(pendingID.uuidString)", "message-user-b", "message-reply-b"
        ])
    }

#if DEBUG
    @Test("two demo turns reconcile without leaving duplicate accepted local submissions")
    func demoTurnsHaveDistinctServerIdentities() async {
        let model = FlowChatModel(userID: "demo-user", provider: DemoFlowChatRepository(),
                                  keyProvider: RandomIdempotencyKeyProvider())
        model.composer = "Mesmo texto"
        await model.send()
        model.composer = "Mesmo texto"
        await model.send()
        #expect(model.messages.count == 4)
        #expect(model.outbox.isEmpty)
        #expect(model.conversationItems.count == 4)
    }

    @Test("demo replay of the same key retains the official reply and only one turn")
    func demoIdempotentReplay() async throws {
        let provider = DemoFlowChatRepository()
        let key = try IdempotencyKey(validating: "demo-replay-key")
        let first = try await provider.send(text: "Mesmo texto", idempotencyKey: key)
        let replay = try await provider.send(text: "Mesmo texto", idempotencyKey: key)
        #expect(first == replay)
        #expect(await provider.history(limit: 50).messages.count == 2)
    }
#endif

    private func makeModel(_ provider: ControlledFlowProvider) -> FlowChatModel {
        FlowChatModel(userID: "user-a", provider: provider, keyProvider: RandomIdempotencyKeyProvider())
    }

    private func reply(_ suffix: String) -> FlowSendResponse {
        FlowSendResponse(conversationID: "conversation", message:
            message(id: "reply-\(suffix)", role: .assistant, text: "Resposta \(suffix)", requestID: "request-\(suffix)"))
    }

    private func replayMessage(_ content: String, state: FlowMessageState = .completed) -> FlowMessage {
        FlowMessage(id: "official-reply-a", conversationID: "conversation", role: .assistant,
                    content: content, state: state, requestID: "official-request-a",
                    createdAt: Date(timeIntervalSince1970: 1_000))
    }

    private func message(id: String, role: FlowMessageRole, text: String, requestID: String) -> FlowMessage {
        FlowMessage(id: id, conversationID: "conversation", role: role, content: text,
                    state: .completed, requestID: requestID, createdAt: Date(timeIntervalSince1970: 1_000))
    }

    private func history(_ messages: [FlowMessage]) -> FlowHistoryResponse {
        FlowHistoryResponse(conversationID: "conversation", messages: messages)
    }
}

/// Network boundary with explicitly ordered completions. It deliberately
/// ignores task cancellation to exercise publication guards in the model.
private actor ControlledFlowProvider: FlowChatProviding {
    private let suspendsHistory: Bool
    private let historyError: URLError?
    private var automaticReply: FlowSendResponse?
    private var historyMessages: [FlowMessage] = []
    private(set) var sentKeys: [String] = []
    private(set) var historyCount = 0
    private var sends: [Int: CheckedContinuation<FlowSendResponse, any Error>] = [:]
    private var histories: [Int: CheckedContinuation<FlowHistoryResponse, any Error>] = [:]
    private var sendWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var historyWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var returnedSendAttempts: Set<Int> = []
    private var sendAttemptWaiters: [(Int, CheckedContinuation<Bool, Never>)] = []

    init(suspendsHistory: Bool = false, historyError: URLError? = nil) {
        self.suspendsHistory = suspendsHistory
        self.historyError = historyError
    }

    func send(text: String, idempotencyKey: IdempotencyKey) async throws -> FlowSendResponse {
        let index = sentKeys.count
        sentKeys.append(idempotencyKey.value)
        let startedAttempts = sendAttemptWaiters.filter { $0.0 <= sentKeys.count }
        sendAttemptWaiters.removeAll { $0.0 <= sentKeys.count }
        startedAttempts.forEach { $0.1.resume(returning: true) }
        if let automaticReply { return automaticReply }
        return try await withCheckedThrowingContinuation { continuation in
            sends[index] = continuation
            let ready = sendWaiters.filter { $0.0 <= sentKeys.count }
            sendWaiters.removeAll { $0.0 <= sentKeys.count }
            ready.forEach { $0.1.resume() }
        }
    }

    func history(limit: Int) async throws -> FlowHistoryResponse {
        let index = historyCount
        historyCount += 1
        if suspendsHistory {
            return try await withCheckedThrowingContinuation { continuation in
                histories[index] = continuation
                let ready = historyWaiters.filter { $0.0 <= historyCount }
                historyWaiters.removeAll { $0.0 <= historyCount }
                ready.forEach { $0.1.resume() }
            }
        }
        if let historyError { throw historyError }
        return FlowHistoryResponse(conversationID: "conversation", messages: historyMessages)
    }

    func waitForSends(_ count: Int) async {
        guard sentKeys.count < count else { return }
        await withCheckedContinuation { sendWaiters.append((count, $0)) }
    }

    func waitForHistories(_ count: Int) async {
        guard historyCount < count else { return }
        await withCheckedContinuation { historyWaiters.append((count, $0)) }
    }

    func waitForSendOrReturnedAttempt(_ count: Int) async -> Bool {
        if sentKeys.count >= count { return true }
        if returnedSendAttempts.contains(count) { return false }
        return await withCheckedContinuation { sendAttemptWaiters.append((count, $0)) }
    }

    func sendAttemptReturned(expectedCount: Int) {
        returnedSendAttempts.insert(expectedCount)
        let finished = sendAttemptWaiters.filter { $0.0 == expectedCount }
        sendAttemptWaiters.removeAll { $0.0 == expectedCount }
        finished.forEach { $0.1.resume(returning: sentKeys.count >= expectedCount) }
    }

    func completeSend(_ index: Int, with result: Result<FlowSendResponse, any Error>) {
        sends.removeValue(forKey: index)?.resume(with: result)
    }

    func completeHistory(_ index: Int, with result: Result<FlowHistoryResponse, any Error>) {
        histories.removeValue(forKey: index)?.resume(with: result)
    }

    func setHistory(_ messages: [FlowMessage]) { historyMessages = messages }
    func automaticallyReply(with response: FlowSendResponse) { automaticReply = response }
}
