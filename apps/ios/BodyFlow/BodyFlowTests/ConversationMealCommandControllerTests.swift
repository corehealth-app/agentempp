import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Dormant authenticated conversation command controller")
struct ConversationMealCommandControllerTests {
    @Test func terminalNotRecordedRestoresAfterReopenWithoutFoodACKOrAnotherPOST() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { request, _ in
            request.url?.path.hasSuffix("/session") == true ? try f.wire.sessionReply() : try f.wire.stateReply("not_recorded")
        }
        let first = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        try await first.send(commandID: f.wire.command.commandID) { probe.events.append($0) }
        await first.close()
        let original = try f.disk.store.load(owner: f.owner, key: f.disk.key)
        let reopened = try await f.open()
        try await reopened.reconcile(commandID: f.wire.command.commandID) { probe.events.append($0) }
        let decision = try #require(await probe.states.last)
        #expect(decision.value.status == .notRecorded && decision.value.reason == "missing_quantity" && decision.value.foodIndexes == [0])
        let saved = await probe.saved
        #expect(!decision.canResubmit && saved.isEmpty)
        await #expect(throws: ConversationMealCommandControllerError.reconciliationRequired) { try await reopened.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        let rows = try f.disk.store.load(owner: f.owner, key: f.disk.key)
        #expect(rows.count == 1 && rows[0].commandID == original[0].commandID && rows[0].wireBody == original[0].wireBody && rows[0].hold == .notRecorded)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        await reopened.close()
    }

    @Test func preparedSourceCannotBeRetaggedToNewPatientBeforeEnqueueStarts() async throws {
        let f = try await Fixture.make(seed: false); defer { f.disk.remove() }
        let mapping = ConversationControllerMapping(owner: f.wire.ownerID)
        await f.http.stub.respond { _, _ in try f.wire.sessionReply(owner: await mapping.owner) }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        try await c.refreshSession { probe.events.append($0) }
        let original = try #require(await probe.contexts.last)
        let command = try ConversationMealCommand(source: .text("source prepared for patient A"))
        await mapping.replace(UUID())
        try await c.refreshSession { probe.events.append($0) }
        await #expect(throws: ConversationOutboxError.invalidServerObservation) {
            try await c.enqueue(command: command, expectedContext: original.identity) { probe.events.append($0) }
        }
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
        await c.close()
    }

    @Test func acceptedContextCarriesRealBackendIdentityAndOldGrantRevokesOnRefresh() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { _, _ in try f.wire.sessionReply() }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        try await c.refreshSession { probe.events.append($0) }
        let first = try #require(await probe.contexts.last)
        #expect(first.authUserID.uuidString.lowercased() == f.lease.userID)
        #expect(first.ownerID == f.wire.ownerID && first.authUserID != first.ownerID)
        #expect(first.epoch == f.wire.epoch && first.sessionGeneration == f.lease.generation)
        #expect(first.observedAt == "2026-11-04T12:00:00.000000001Z")
        try first.withCurrentAuthority {}
        try await c.refreshSession { probe.events.append($0) }
        #expect(throws: ConversationOutboxError.staleObservation) { try first.withCurrentAuthority {} }
        try #require(await probe.contexts.last).withCurrentAuthority {}
        await c.close()
        #expect(throws: ConversationOutboxError.staleObservation) { try first.withCurrentAuthority {} }
    }

    @Test func accountCancellationClosesRetainedControllerAndFinishesItsOwnedWork() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { _, _ in try f.wire.sessionReply() }
        let c = try await f.open(), expected = await f.http.lifecycle.workIDs
        #expect(expected.count == 2) // Outbox and controller remain registered after HTTP finishes.
        let events = await f.http.lifecycle.finishedWorkEvents
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        await f.http.lifecycle.replace(.init(userID: "90000000-0000-4000-8000-000000000002", generation: 8, bearer: "synthetic-B"))
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var remaining = expected
                for await id in events { remaining.remove(id); if remaining.isEmpty { return true } }
                return false
            }
            group.addTask { try? await Task.sleep(for: .milliseconds(200)); return false }
            let value = await group.next() ?? false; group.cancelAll(); return value
        }
        #expect(finished) // Revocation must also close owned RAM/work while c remains retained.
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        await #expect(throws: (any Error).self) { try await c.enqueue(source: .text("late A")) { _ in } }
        #expect(await f.http.stub.requests.count == 1)
        await c.close()
    }

    @Test func savedPacketUsesActualTransportPatientBindingAndFactualACK() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            return try f.wire.savedReply()
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
        let saved = await probe.saved
        #expect(saved.count == 1 && saved[0].receipt.ownerID == f.wire.ownerID.uuidString.lowercased())
        #expect(saved.first?.feedback?.scope.ownerID != f.lease.userID)
        let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
        #expect(posts.count == 1 && posts[0].httpBody == f.wire.command.wireBody)
        #expect(posts[0].value(forHTTPHeaderField: "X-Conversation-Owner") == f.wire.ownerID.uuidString.lowercased())
        #expect(await f.http.stub.requests.allSatisfy { $0.url?.path.hasPrefix("/api/mobile/v1/conversation/") == true })
        await c.close()
    }

    @Test func pendingIsNotACKAndOnlyAuthoritativeGETAllowsOneExplicitExactReplay() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { request, _ in request.url?.path.hasSuffix("/session") == true ? try f.wire.sessionReply() : try f.wire.stateReply("pending") }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) }
        await #expect(throws: ConversationMealCommandControllerError.reconciliationRequired) { try await c.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        try await c.reconcile(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.states.last?.canResubmit == true)
        try await c.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) }
        await #expect(throws: ConversationMealCommandControllerError.reconciliationRequired) { try await c.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        let posts = await f.http.stub.requests.filter { $0.httpMethod == "POST" }
        #expect(posts.count == 2)
        #expect(posts.allSatisfy { $0.httpBody == f.wire.command.wireBody && $0.value(forHTTPHeaderField: "Idempotency-Key") == f.wire.command.idempotencyKey && $0.value(forHTTPHeaderField: "X-Conversation-Epoch") == f.wire.epoch.uuidString.lowercased() })
        #expect(await probe.saved.isEmpty)
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).count == 1)
        await c.close()
    }

    @Test func lostResponseAndRestartReadSavedResultWithoutAnotherPOSTOrNewUUID() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            if request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
            return try f.wire.savedReply()
        }
        let first = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        await #expect(throws: MobileAPITransportError.network) { try await first.send(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        #expect(await probe.saved.isEmpty)
        let pending = try f.disk.store.load(owner: f.owner, key: f.disk.key)
        #expect(pending.first?.commandID == f.wire.command.commandID && pending.first?.wireBody == f.wire.command.wireBody)
        await first.close()
        let second = try await f.open()
        try await second.reconcile(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.saved.count == 1)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).isEmpty)
        await second.close()
    }

    @Test func observedPatientChangeWithSameEpochWithholdsOldSourceAndPreventsPOST() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let mapping = ConversationControllerMapping(owner: f.wire.ownerID)
        await f.http.stub.respond { _, _ in try f.wire.sessionReply(owner: await mapping.owner) }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        await mapping.replace(UUID())
        try await c.refreshSession { probe.events.append($0) }
        let snapshots = await probe.snapshots
        #expect(snapshots.last?.entries.isEmpty == true)
        #expect(snapshots.last?.held.count == 1)
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        await #expect(throws: ConversationOutboxError.invalidServerObservation) { try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        #expect(await probe.saved.isEmpty)
        await c.close()
    }

    @Test("HTTP status cannot masquerade as a factual receipt", arguments: ["pending200", "saved202"])
    func contradictoryHTTPStatusDoesNotACK(_ attack: String) async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            return attack == "pending200" ? try f.wire.stateReply("pending", httpStatus: 200) : try f.wire.savedReply(status: 202)
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        await #expect(throws: MobileAPITransportError.invalidResponse) { try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        #expect(await probe.saved.isEmpty)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).count == 1)
        await c.close()
    }

    @Test("known refusals and outages never blindly replay POST", arguments: [401, 409, 429, 503])
    func refusalKeepsOriginalAndDoesNotAutomaticallyResend(_ status: Int) async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            return .failure(status, status == 409 ? "conversation_patient_changed" : status == 429 ? "conversation_admission_rate_limited" : "conversation_command_unavailable")
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        await #expect(throws: (any Error).self) { try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        #expect(await probe.saved.isEmpty)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        #expect(await f.http.lifecycle.refreshCount == 0)
        let entry = try #require(f.disk.store.load(owner: f.owner, key: f.disk.key).first)
        #expect(entry.commandID == f.wire.command.commandID && entry.wireBody == f.wire.command.wireBody)
        #expect(entry.hold == (status == 409 ? .serverChanged : .unknownOutcome))
        await #expect(throws: ConversationMealCommandControllerError.reconciliationRequired) { try await c.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        await c.close()
    }

    @Test func notRecordedRemainsHeldAndCannotGainReplayPermissionFromLaterPending() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            return try f.wire.stateReply(request.httpMethod == "POST" ? "not_recorded" : "pending")
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.states.last?.value.status == .notRecorded)
        #expect(await probe.saved.isEmpty)
        try await c.reconcile(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.states.last?.canResubmit == false)
        await #expect(throws: ConversationMealCommandControllerError.reconciliationRequired) { try await c.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).first?.hold == .notRecorded)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        await c.close()
    }

    @Test func activeSessionOfflineEnqueueUsesNewIDsButResetNeverRetagsEither() async throws {
        let f = try await Fixture.make(seed: false); defer { f.disk.remove() }
        let mapping = ConversationControllerEpoch(epoch: f.wire.epoch)
        await f.http.stub.respond { _, _ in try f.wire.sessionReply(epoch: await mapping.epoch) }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        let a = try await c.enqueue(source: .text("same user source")) { probe.events.append($0) }
        let b = try await c.enqueue(source: .text("same user source")) { probe.events.append($0) }
        #expect(a != b)
        #expect(await f.http.stub.requests.count == 1) // No network in these active-session enqueue actions.
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        await mapping.replace(UUID())
        await #expect(throws: ConversationOutboxError.reconciliationRequired) { try await c.send(commandID: a) { probe.events.append($0) } }
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.isEmpty)
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        let rows = try f.disk.store.load(owner: f.owner, key: f.disk.key)
        #expect(rows.count == 2 && rows.allSatisfy { $0.originalServerEpoch == f.wire.epoch && $0.state == .queued })
        #expect(await probe.snapshots.last?.entries.isEmpty == true)
        #expect(await probe.snapshots.last?.held.count == 2)
        await c.close()
    }

    @Test func wrongAuthSessionResponseAndForeignPreboundTransportFailWithoutPublication() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        await f.http.stub.respond { _, _ in try f.wire.sessionReply(auth: UUID()) }
        await #expect(throws: MobileAPITransportError.invalidResponse) { try await f.open() }
        #expect(await f.http.lifecycle.workCount == 0)
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        let other = ConversationHTTPTestLifecycle()
        await other.replace(.init(userID: "90000000-0000-4000-8000-000000000002", generation: 8, bearer: "synthetic-B"))
        let count = await f.http.stub.requests.count
        await #expect(throws: SessionLifecycleError.sessionSuperseded) {
            try await ConversationMealCommandController.open(transport: f.http.transport.scoped(to: f.lease), lifecycle: other, store: f.disk.store, keyVault: f.vault)
        }
        #expect(await f.http.stub.requests.count == count)
    }

    @Test func lateOutcomeCannotConsumeNewerAuthoritativeGETPermission() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let barrier = ConversationControllerBarrier(), posts = ConversationControllerCounter()
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            if request.httpMethod == "POST", await posts.next() == 1 {
                await barrier.enter(); throw URLError(.networkConnectionLost)
            }
            return try f.wire.stateReply("pending")
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        defer { Task { await barrier.release(); await c.close() } }
        let old = Task {
            do { try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) }; await barrier.finish() }
            catch { await barrier.finish(); throw error }
        }
        try #require(await barrier.waitEnteredOrFinished())
        try await c.reconcile(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.states.last?.canResubmit == true)
        await barrier.release()
        if case .success = await old.result { Issue.record("Old superseded outcome must be refused") }
        try await c.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 2)
        #expect(await probe.saved.isEmpty)
        await c.close()
    }

    @Test func lateSessionReadCannotReplaceNewerSameAuthPatientMapping() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let barrier = ConversationControllerBarrier(), reads = ConversationControllerCounter(), nextOwner = UUID()
        await f.http.stub.respond { _, _ in
            let attempt = await reads.next()
            if attempt == 2 { await barrier.enter(); return try f.wire.sessionReply() }
            return try f.wire.sessionReply(owner: attempt >= 3 ? nextOwner : f.wire.ownerID)
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        defer { Task { await barrier.release(); await c.close() } }
        let old = Task {
            do { try await c.refreshSession { probe.events.append($0) }; await barrier.finish() }
            catch { await barrier.finish(); throw error }
        }
        try #require(await barrier.waitEnteredOrFinished())
        try await c.refreshSession { probe.events.append($0) }
        await barrier.release()
        if case .success = await old.result { Issue.record("Late session response must be refused") }
        try await c.publishSnapshot { probe.events.append($0) }
        #expect(await probe.snapshots.last?.entries.isEmpty == true)
        #expect(await probe.snapshots.last?.held.count == 1)
        #expect(await probe.saved.isEmpty)
        await c.close()
    }

    @Test func accountSwitchDuringPOSTCancelsLatePublicationAndPreservesOriginalUnknown() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let barrier = ConversationControllerBarrier()
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            await barrier.enter(); return try f.wire.savedReply()
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        defer { Task { await barrier.release(); await c.close() } }
        let old = Task {
            do { try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) }; await barrier.finish() }
            catch { await barrier.finish(); throw error }
        }
        try #require(await barrier.waitEnteredOrFinished())
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        await MainActor.run { probe.events.removeAll() }
        await f.http.lifecycle.replace(.init(userID: "90000000-0000-4000-8000-000000000002", generation: 8, bearer: "synthetic-B"))
        await barrier.release()
        if case .success = await old.result { Issue.record("Old account cannot finish as visible success") }
        #expect(await probe.saved.isEmpty)
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        #expect(try f.disk.store.load(owner: f.owner, key: f.disk.key).first?.state == .dispatchedUnknown)
        await c.close()
    }

    @Test func authoritativeAbsenceAllowsExactOriginalReplay() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let posts = ConversationControllerCounter()
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            if request.httpMethod == "GET" { return try f.wire.stateReply("absent") }
            if await posts.next() == 1 { throw URLError(.networkConnectionLost) }
            return try f.wire.savedReply()
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        await #expect(throws: MobileAPITransportError.network) { try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) } }
        try await c.reconcile(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.states.last?.value.status == .absent)
        try await c.resubmit(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.saved.count == 1)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 2)
        await c.close()
    }

    @Test func olderSuspensionCannotHideNewerVisiblePatientSnapshot() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let mapping = ConversationControllerMapping(owner: f.wire.ownerID), barrier = ConversationControllerBarrier()
        await f.http.stub.respond { _, _ in try f.wire.sessionReply(owner: await mapping.owner) }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        defer { Task { await barrier.release(); await c.close() } }
        await f.http.lifecycle.holdNextVisible(barrier)
        let old = Task {
            do { try await c.refreshSession { probe.events.append($0) }; await barrier.finish() }
            catch { await barrier.finish(); throw error }
        }
        try #require(await barrier.waitEnteredOrFinished())
        await mapping.replace(UUID())
        try await c.refreshSession { probe.events.append($0) }
        await barrier.release()
        if case .success = await old.result { Issue.record("Superseded refresh must fail") }
        let last = try #require(await probe.events.last)
        if case .scopeSuspended = last { Issue.record("Older suspension erased newer visible scope") }
        #expect(await probe.snapshots.last?.entries.isEmpty == true)
        #expect(await probe.snapshots.last?.held.count == 1)
        await c.close()
    }

    @Test func failedRefreshStillAllowsEncryptedOfflineEnqueueWithoutRawScopePublication() async throws {
        let f = try await Fixture.make(seed: false); defer { f.disk.remove() }
        await f.http.stub.respond { _, _ in try f.wire.sessionReply() }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        await f.http.stub.respond { _, _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: MobileAPITransportError.network) { try await c.refreshSession { probe.events.append($0) } }
        let id = try await c.enqueue(source: .text("offline preserved source")) { probe.events.append($0) }
        let row = try #require(f.disk.store.load(owner: f.owner, key: f.disk.key).first)
        #expect(row.commandID == id && row.originalServerEpoch == f.wire.epoch && row.originalPatientOwnerID == f.wire.ownerID)
        #expect(await probe.saved.isEmpty)
        let last = try #require(await probe.events.last)
        if case let .queued(queued) = last { #expect(queued == id) }
        else { Issue.record("Unverified scope may only publish queued metadata") }
        await c.close()
    }

    @Test func callerCancellationPreservesUnknownAndOnlyGETCanRecoverSavedOutcome() async throws {
        let f = try await Fixture.make(); defer { f.disk.remove() }
        let barrier = ConversationControllerBarrier()
        await f.http.stub.respond { request, _ in
            if request.url?.path.hasSuffix("/session") == true { return try f.wire.sessionReply() }
            if request.httpMethod == "POST" { await barrier.enter() }
            return try f.wire.savedReply()
        }
        let c = try await f.open(), probe = await MainActor.run { ConversationControllerProbe() }
        defer { Task { await barrier.release(); await c.close() } }
        let task = Task {
            do { try await c.send(commandID: f.wire.command.commandID) { probe.events.append($0) }; await barrier.finish() }
            catch { await barrier.finish(); throw error }
        }
        try #require(await barrier.waitEnteredOrFinished())
        let original = try Data(contentsOf: f.disk.store.fileURL(owner: f.owner))
        task.cancel(); await barrier.release()
        if case .success = await task.result { Issue.record("Cancelled POST must not publish success") }
        #expect(await probe.saved.isEmpty)
        #expect(try Data(contentsOf: f.disk.store.fileURL(owner: f.owner)) == original)
        try await c.reconcile(commandID: f.wire.command.commandID) { probe.events.append($0) }
        #expect(await probe.saved.count == 1)
        #expect(await f.http.stub.requests.filter { $0.httpMethod == "POST" }.count == 1)
        await c.close()
    }

    private struct Fixture: Sendable {
        let disk: OutboxDiskFixture
        let http: ConversationHTTPFixture
        let lease: SessionLease
        let owner: ConversationOutboxOwner
        let vault: ConversationOutboxKeyVault
        let wire: ConversationControllerWireFixture
        static func make(seed: Bool = true) async throws -> Self {
            let disk = try OutboxDiskFixture(), http = try ConversationHTTPFixture()
            let lease = await http.lifecycle.leaseForRequest(), owner = try ConversationOutboxOwner(lease: lease)
            let wire = try ConversationControllerWireFixture()
            let keys = OutboxKeychainFake(); await keys.seed(disk.key.withUnsafeBytes { Data($0) }, owner: owner.hash)
            let vault = ConversationOutboxKeyVault(service: "synthetic", security: keys)
            if seed { try disk.store.update(owner: owner, key: disk.key) { $0.append(.init(command: wire.command, originalServerEpoch: wire.epoch, originalPatientOwnerID: wire.ownerID)) } }
            return .init(disk: disk, http: http, lease: lease, owner: owner, vault: vault, wire: wire)
        }
        func open() async throws -> ConversationMealCommandController { try await .open(transport: http.transport, lifecycle: http.lifecycle, store: disk.store, keyVault: vault) }
    }
}

struct ConversationControllerWireFixture: Sendable {
    let command: ConversationMealCommand
    let ownerID: UUID
    let epoch: UUID
    private let packet: Data
    init() throws {
        #if SWIFT_PACKAGE
        let url = try #require(Bundle.module.url(forResource: "ConversationMealCommandResultFixtures", withExtension: "json"))
        #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/ConversationMealCommandResultFixtures.json")
        #endif
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let wire = try #require(root["wire_command"] as? [String: Any])
        command = try ConversationMealCommand(wireBody: JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys, .withoutEscapingSlashes]))
        let owner = try #require(root["owner_id"] as? String), epoch = try #require(root["epoch"] as? String)
        ownerID = try #require(UUID(uuidString: owner)); self.epoch = try #require(UUID(uuidString: epoch))
        packet = try JSONSerialization.data(withJSONObject: #require((root["cases"] as? [[String: Any]])?.first?["payload"]))
    }
    func sessionReply(owner: UUID? = nil, epoch: UUID? = nil, auth: UUID = UUID(uuidString: "90000000-0000-4000-8000-000000000001")!) throws -> ConversationHTTPReply {
        try envelope(["schema": "conversation.session.v1", "auth_user_id": auth.uuidString.lowercased(), "owner_id": (owner ?? ownerID).uuidString.lowercased(), "epoch": (epoch ?? self.epoch).uuidString.lowercased(), "observed_at": "2026-11-04T12:00:00.000000001Z", "meal_command_protocol": "conversation.command.v1"], status: 200)
    }
    func stateReply(_ status: String, httpStatus: Int? = nil) throws -> ConversationHTTPReply {
        var p: [String: Any] = ["schema": "conversation.meal-command-state.v1", "status": status, "owner_id": ownerID.uuidString.lowercased(), "command_id": command.commandID.uuidString.lowercased(), "input_hash": command.inputHash, "epoch": epoch.uuidString.lowercased()]
        if status == "not_recorded" { p["reason"] = "missing_quantity"; p["food_indexes"] = [0] }
        return try envelope(p, status: httpStatus ?? (status == "pending" ? 202 : 200))
    }
    func savedReply(status: Int = 200) throws -> ConversationHTTPReply {
        try envelope(#require(JSONSerialization.jsonObject(with: packet) as? [String: Any]), status: status)
    }
    private func envelope(_ p: [String: Any], status: Int) throws -> ConversationHTTPReply {
        .init(status: status, body: try JSONSerialization.data(withJSONObject: ["data": p, "meta": ["api_version": "v1", "request_id": "conversation-controlled-0001"]]))
    }
}
actor ConversationControllerMapping {
    private(set) var owner: UUID
    init(owner: UUID) { self.owner = owner }
    func replace(_ owner: UUID) { self.owner = owner }
}
@MainActor final class ConversationControllerProbe {
    var events: [ConversationMealCommandEvent] = []
    var contexts: [ConversationCommandContext] { events.compactMap { if case let .scopeAccepted(v) = $0 { v } else { nil } } }
    var saved: [ConversationOutboxSavedPublication] { events.compactMap { if case let .saved(v) = $0 { v } else { nil } } }
    var states: [(value: ConversationMealCommandStateSnapshot, canResubmit: Bool)] { events.compactMap { if case let .state(v, allowed) = $0 { (v, allowed) } else { nil } } }
    var snapshots: [ConversationOutboxViewSnapshot] { events.compactMap { if case let .snapshot(v) = $0 { v } else { nil } } }
}

actor ConversationControllerEpoch {
    private(set) var epoch: UUID
    init(epoch: UUID) { self.epoch = epoch }
    func replace(_ epoch: UUID) { self.epoch = epoch }
}

actor ConversationControllerCounter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}
actor ConversationControllerBarrier {
    private var entered = false, finished = false, opened = false
    private var observers: [CheckedContinuation<Bool, Never>] = []
    private var blocked: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        entered = true; let waiting = observers; observers.removeAll(); waiting.forEach { $0.resume(returning: true) }
        if !opened { await withCheckedContinuation { blocked.append($0) } }
    }
    func finish() {
        finished = true; let waiting = observers; observers.removeAll(); waiting.forEach { $0.resume(returning: entered) }
    }
    func waitEnteredOrFinished() async -> Bool {
        if entered { return true }; if finished { return false }
        return await withCheckedContinuation { observers.append($0) }
    }
    func release() { opened = true; let waiting = blocked; blocked.removeAll(); waiting.forEach { $0.resume() } }
}
