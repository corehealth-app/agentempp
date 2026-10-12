#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup photo cleanup processor", .serialized)
struct SignupBodyPhotoCleanupCoordinatorTests {
    @Test("C01 known ACKed G is re-read once per event with its retained attempt")
    func retainedGenerationResweepsOncePerEvent() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(ackedG1: true)
        let model = Self.model(h)
        let first = UUID()
        await model.run(eventID: first)
        await model.run(eventID: first)
        await model.run(eventID: UUID())
        let snapshot = await h.peer.snapshot()
        #expect(snapshot.reads.count == 4)
        #expect(snapshot.repairs.count == 4)
        for generation in [CleanupProcessorHarness.g1, CleanupProcessorHarness.g2] {
            #expect(snapshot.reads.filter { $0 == generation }.count == 2)
            let attempts = snapshot.repairs.filter { $0.payload.generation == generation }
            #expect(attempts.count == 2)
            let firstAttempt = try #require(attempts.first)
            let lastAttempt = try #require(attempts.last)
            #expect(firstAttempt == lastAttempt)
            #expect(firstAttempt.operation == .mediaDelete)
        }
        let queue = try await h.queue()
        #expect(queue.knownScopes.count == 2)
        let g1 = try #require(queue.scope(CleanupProcessorHarness.g1))
        let g2 = try #require(queue.scope(CleanupProcessorHarness.g2))
        #expect(!g1.pending && !g2.pending)
        #expect(g1.repair?.key == "cleanup-retained-key-g1")
        #expect(g1.repair?.createdAt == CleanupProcessorHarness.retainedDate)
        #expect(h.inputs.counts == .init(keys: 1, dates: 1))
    }

    @Test("C02 nil discovery is one official G read and never erases unbound",
        arguments: [CleanupProcessorMode.pending, .currentUnknown, .currentNotRequired, .currentAbsent])
    func currentDiscoveryDoesNotDuplicateGeneration(mode: CleanupProcessorMode) async throws {
        let h = try await CleanupProcessorHarness(mode: mode)
        defer { h.removeFolder() }
        try await h.seed(unbound: true)
        await Self.model(h).run(eventID: UUID())
        let snapshot = await h.peer.snapshot()
        #expect(snapshot.reads.filter { $0 == nil }.count == 1)
        #expect(snapshot.reads.filter { $0 == CleanupProcessorHarness.g2 }.count == 1)
        if case .currentAbsent = mode {
            #expect(snapshot.reads.filter { $0 == CleanupProcessorHarness.g1 }.count == 1)
        } else {
            #expect(snapshot.reads.filter { $0 == CleanupProcessorHarness.g1 }.isEmpty)
        }
        let queue = try await h.queue()
        #expect(queue.unboundCreates == [CleanupProcessorHarness.marker])
        switch mode {
        case .currentNotRequired:
            #expect(queue.scope(CleanupProcessorHarness.g1) == nil)
            #expect(snapshot.repairs.filter { $0.payload.generation == CleanupProcessorHarness.g1 }.isEmpty)
        case .currentUnknown:
            #expect(queue.scope(CleanupProcessorHarness.g1)?.pending == true)
            #expect(snapshot.repairs.filter { $0.payload.generation == CleanupProcessorHarness.g1 }.isEmpty)
        default:
            #expect(queue.scope(CleanupProcessorHarness.g1)?.pending == false)
        }
    }

    @Test("C03 unknown/fault ends the event and preserves debt for the next event",
        arguments: [CleanupProcessorMode.unknown, .absent, .readFailure, .repairFailure, .invalidRepair], [false, true])
    func unknownAndFaultsPreserveDebt(mode: CleanupProcessorMode, failWrite: Bool) async throws {
        let h = try await CleanupProcessorHarness(mode: mode)
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1], unbound: true)
        if failWrite { h.writeFault.arm() }
        let model = Self.model(h)
        await model.run(eventID: UUID())
        let first = await h.peer.snapshot()
        #expect(!first.reads.isEmpty)
        #expect(first.reads.count <= 2)
        #expect(first.repairs.count <= 1)
        let beforeRetry = try await h.queue()
        #expect(beforeRetry.unboundCreates == [CleanupProcessorHarness.marker])
        #expect(beforeRetry.scope(CleanupProcessorHarness.g1)?.pending == true)
        await h.peer.setMode(.pending)
        // A fault not reached by the first mode must not poison the second event.
        h.writeFault.disarm()
        await model.run(eventID: UUID())
        let final = await h.peer.snapshot()
        #expect(final.repairs.count == first.repairs.count + 1)
        let after = try await h.queue()
        #expect(after.scope(CleanupProcessorHarness.g1)?.pending == false)
        #expect(after.unboundCreates == [CleanupProcessorHarness.marker])
        if first.repairs.count == 1 {
            #expect(first.repairs.first == final.repairs.last)
        }
    }

    @Test("C04 stale read/ACK cannot overwrite a later revision or adjacent work",
        arguments: [CleanupProcessorHold.read, .repair])
    func staleReadAndAcknowledgementRespectCAS(hold: CleanupProcessorHold) async throws {
        let h = try await CleanupProcessorHarness(hold: hold)
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1])
        let model = Self.model(h)
        let task = Task { await model.run(eventID: UUID()); await h.gate.operationFinished() }
        let entered = await h.gate.entryOrOperationEnd()
        if !entered {
            await h.gate.release(); await task.value
            try #require(entered)
        }
        let revision = UUID()
        let inputs = h.inputs
        do {
            try await h.mutate { current in
                _ = try current.observePending(CleanupProcessorHarness.g1, newRevision: revision)
                if hold == .repair {
                    _ = try current.prepareRepair(CleanupProcessorHarness.g1, expectedRevision: revision,
                        newRevision: UUID(), operationID: UUID(),
                        takeKey: { try inputs.nextKey() }, takeDate: { inputs.now })
                }
                _ = try current.observePending(CleanupProcessorHarness.g2, newRevision: UUID())
                _ = current.rememberUnbound(CleanupProcessorHarness.marker)
            }
            let expected = try await h.queue()
            await h.gate.release(); await task.value
            let final = try await h.queue()
            #expect(final == expected)
            let peer = await h.peer.snapshot()
            if hold == .read { #expect(peer.repairs.isEmpty) }
            else { #expect(peer.acknowledgementResults == [false]) }
        } catch {
            await h.gate.release(); await task.value
            throw error
        }
    }

    @Test("C05 all suspension points fence A to B and a later A",
        arguments: CleanupProcessorHold.allCases, [false, true])
    func retainedLeaseCannotReviveAfterOwnerSwitch(hold: CleanupProcessorHold, returnToA: Bool) async throws {
        let h = try await CleanupProcessorHarness(hold: hold)
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1], unbound: true)
        let model = Self.model(h)
        let task = Task { await model.run(eventID: UUID()); await h.gate.operationFinished() }
        let entered = await h.gate.entryOrOperationEnd()
        if !entered {
            await h.gate.release(); await task.value
            try #require(entered)
        }
        do {
            try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.b))
            if returnToA { try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.a)) }
            let later = returnToA ? CleanupProcessorHarness.a : CleanupProcessorHarness.b
            let bytes = try await h.seedLaterOwner(later)
            await h.gate.release(); await task.value
            #expect(try Data(contentsOf: h.store.fileURL(for: later)) == bytes)
            let count = await h.registry.activeCount
            #expect(count == 0)
            model.invalidate()
        } catch {
            await h.gate.release(); await task.value
            throw error
        }
    }

    @Test("C06 live factory binds once and an old scope cannot obtain a later A lease")
    func liveFactoryRequiresOneRetainedLease() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1])
        let counted = CleanupProcessorCountingLifecycle(base: h.lifecycle)
        let transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://mobile.example.test"),
            sessionLifecycle: counted, session: URLSession(configuration: .ephemeral), clock: ContinuousClock())
        let factory = SignupBodyPhotoCleanupCapability.live(transport: transport, lifecycle: counted,
            store: h.store, keyProvider: h.inputs, timeProvider: h.inputs)
        let scope: SignupBodyPhotoCleanupScope
        do { scope = try await factory.scoped(CleanupProcessorHarness.a) }
        catch {
            Issue.record("Authenticated cleanup factory did not produce its retained scope")
            return
        }
        #expect(scope.userID == CleanupProcessorHarness.a)
        try await scope.validateSession()
        let loaded = try await scope.loadQueue()
        #expect(loaded.scope(CleanupProcessorHarness.g1) != nil)
        let ticket = try #require(try await scope.prepareRepair(CleanupProcessorHarness.g1,
            loaded.scope(CleanupProcessorHarness.g1)?.revision,
            SignupBodyPhotoCleanupAuthorization(validate: {})))
        #expect(ticket.generation == CleanupProcessorHarness.g1)
        let prepared = try await scope.loadQueue()
        #expect(prepared.scope(CleanupProcessorHarness.g1)?.operationID == ticket.operationID)
        let calls = await counted.leaseRequests
        #expect(calls == 1)
        try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.b))
        try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.a))
        let before = try await h.seedLaterOwner(CleanupProcessorHarness.a)
        var rejected = false
        do { _ = try await scope.prepareRepair(CleanupProcessorHarness.g1, loaded.scope(CleanupProcessorHarness.g1)?.revision,
            SignupBodyPhotoCleanupAuthorization(validate: {})) }
        catch { rejected = true }
        #expect(rejected)
        #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == before)
        let finalCalls = await counted.leaseRequests
        #expect(finalCalls == 1)
    }

    @Test("C06b official pending is known without capture; manual/unknown never invent debt")
    func officialObservationHasIndependentAuthority() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let model = Self.model(h)
        for value in [nil, OnboardingBodyPhotoCleanupScope(generation: CleanupProcessorHarness.g1, state: .unknown),
                      .init(generation: CleanupProcessorHarness.g1, state: .notRequired)] {
            await model.observeOfficial(value)
        }
        let empty = try await h.queue()
        #expect(empty.knownScopes.isEmpty && empty.unboundCreates.isEmpty)
        await model.observeOfficial(.init(generation: CleanupProcessorHarness.g1, state: .pending))
        let known = try await h.queue()
        #expect(known.scope(CleanupProcessorHarness.g1)?.pending == true)
        let snapshot = await h.peer.snapshot()
        #expect(snapshot.reads.isEmpty && snapshot.repairs.isEmpty)
    }

    @Test("an official observation survives failed persistence and the next event keeps its repair identity")
    func officialObservationRemainsBufferedAfterWriteFailure() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let model = Self.model(h)
        h.writeFault.arm()
        await model.observeOfficial(.init(generation: CleanupProcessorHarness.g1, state: .pending))
        #expect(try await h.queue().knownScopes.isEmpty)
        h.writeFault.disarm()
        await model.run(eventID: UUID())
        let first = await h.peer.snapshot()
        #expect(first.reads == [CleanupProcessorHarness.g1])
        #expect(first.repairs.count == 1)
        let persisted = try await h.queue()
        #expect(persisted.scope(CleanupProcessorHarness.g1)?.pending == false)
        await model.run(eventID: UUID())
        let final = await h.peer.snapshot()
        #expect(final.reads == [CleanupProcessorHarness.g1, CleanupProcessorHarness.g1])
        #expect(final.repairs.count == 2)
        #expect(first.repairs.first == final.repairs.last)
        #expect(h.inputs.counts == .init(keys: 1, dates: 1))
    }

    @Test("the visible-state gate releases on throw and cancellation without allowing local effects")
    func visibleGateFailureAndCancellationReleaseAuthority() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        var rejected = false
        do {
            _ = try await h.lifecycle.performVisiblePatientStateOperation(lease: h.lease) {
                throw CleanupProcessorFailure.scripted
            }
        } catch { rejected = true }
        #expect(rejected)
        let owner = CleanupProcessorGateCounter()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await h.lifecycle.performVisiblePatientStateOperation(lease: h.lease) { owner.calls += 1 }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        #expect(await cancelled.value)
        #expect(owner.calls == 0)
        let valid = try await h.lifecycle.performVisiblePatientStateOperation(lease: h.lease) {
            owner.calls += 1
            return true
        }
        #expect(valid && owner.calls == 1)
        let oldGate = try await h.lifecycle.performPatientStateOperation(lease: h.lease) { true }
        #expect(oldGate)
    }

    private static func model(_ h: CleanupProcessorHarness) -> SignupBodyPhotoCleanupCoordinator {
        SignupBodyPhotoCleanupCoordinator(scope: h.scope, isCurrentOwner: { true })
    }
}

@MainActor
private final class CleanupProcessorGateCounter { var calls = 0 }
#endif
