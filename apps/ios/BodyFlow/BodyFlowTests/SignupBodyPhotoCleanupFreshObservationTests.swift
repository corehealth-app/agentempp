#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup cleanup fresh official result", .serialized)
struct SignupBodyPhotoCleanupFreshObservationTests {
    @Test("G3F01 pending accepted G uses no extra GET and retains its attempt",
        arguments: [false, true])
    func pendingFreshResultAvoidsSameGenerationRead(failObservationWrite: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(unbound: true, ackedG1: true)
        let model = Self.model(h)
        let official = OnboardingBodyPhotoCleanupScope(generation: CleanupProcessorHarness.g1, state: .pending)
        let before = try await h.queue()
        if failObservationWrite { h.writeFault.arm() }
        await model.observeOfficial(official)
        let observed = try await h.queue()
        if failObservationWrite { #expect(observed == before) }
        else { #expect(observed.scope(CleanupProcessorHarness.g1)?.pending == true) }
        h.writeFault.disarm()
        let eventID = UUID()
        await model.run(eventID: eventID, freshObservation: .init(currentScope: official))
        let first = await h.peer.snapshot()
        #expect(first.reads == [CleanupProcessorHarness.g2])
        #expect(first.repairs.count == 2)
        let repairedG1 = try #require(first.repairs.first { $0.payload.generation == CleanupProcessorHarness.g1 })
        #expect(repairedG1.operation == .mediaDelete)
        #expect(repairedG1.key.value == "cleanup-retained-key-g1")
        #expect(repairedG1.createdAt == CleanupProcessorHarness.retainedDate)
        #expect(repairedG1.payload.generation == CleanupProcessorHarness.g1)
        let finished = try await h.queue()
        #expect(finished.knownScopes.count == 2)
        #expect(finished.scope(CleanupProcessorHarness.g1)?.pending == false)
        #expect(finished.scope(CleanupProcessorHarness.g2)?.pending == false)
        #expect(finished.unboundCreates == [CleanupProcessorHarness.marker])
        #expect(h.inputs.counts == .init(keys: 1, dates: 1))
        // Event IDs remain finite even if another callback supplies the DTO again.
        await model.run(eventID: eventID, freshObservation: .init(currentScope: official))
        let duplicate = await h.peer.snapshot()
        #expect(duplicate.reads == first.reads && duplicate.repairs == first.repairs)
        // The next foreground has no fresh wrapper; ACK-false G is still known.
        await model.run(eventID: UUID())
        let later = await h.peer.snapshot()
        #expect(later.reads == [CleanupProcessorHarness.g2, nil, CleanupProcessorHarness.g2])
        #expect(later.repairs.count == 4)
        #expect(later.repairs.filter { $0.payload.generation == CleanupProcessorHarness.g1 } == [repairedG1, repairedG1])
        #expect(h.inputs.counts == .init(keys: 1, dates: 1))
    }

    @Test("G3F02 fresh unknown/negative is visited but has no negative CAS",
        arguments: [OnboardingBodyPhotoCleanupState.unknown, .notRequired])
    func nonPositiveFreshResultPreservesKnownAndUnbound(state: OnboardingBodyPhotoCleanupState) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(unbound: true, ackedG1: true)
        let before = try await h.queue()
        let official = OnboardingBodyPhotoCleanupScope(generation: CleanupProcessorHarness.g1, state: state)
        let model = Self.model(h)
        await model.observeOfficial(official)
        await model.run(eventID: UUID(), freshObservation: .init(currentScope: official))
        let peer = await h.peer.snapshot()
        #expect(peer.reads == [CleanupProcessorHarness.g2])
        #expect(peer.repairs.count == 1)
        #expect(peer.repairs.first?.payload.generation == CleanupProcessorHarness.g2)
        let after = try await h.queue()
        #expect(after.scope(CleanupProcessorHarness.g1) == before.scope(CleanupProcessorHarness.g1))
        #expect(after.unboundCreates == before.unboundCreates)
        #expect(after.scope(CleanupProcessorHarness.g2)?.pending == false)
    }

    @Test("G3F03 fresh absence differs from an ordinary event and invents no G")
    func acceptedResultWithoutScopeDoesNotRediscoverImmediately() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [], unbound: true)
        let model = Self.model(h)
        let before = try await h.queue()
        await model.run(eventID: UUID(), freshObservation: .init(currentScope: nil))
        let fresh = await h.peer.snapshot()
        #expect(fresh.reads.isEmpty && fresh.repairs.isEmpty)
        #expect(try await h.queue() == before)
        await model.run(eventID: UUID())
        let ordinary = await h.peer.snapshot()
        #expect(ordinary.reads == [nil])
        #expect(ordinary.repairs.count == 1)
        #expect(ordinary.repairs.first?.payload.generation == CleanupProcessorHarness.g1)
        let after = try await h.queue()
        #expect(after.knownScopes.count == 1)
        #expect(after.scope(CleanupProcessorHarness.g1)?.pending == false)
        #expect(after.unboundCreates == [CleanupProcessorHarness.marker])
    }

    @Test("G3F04 fresh pending preparation and ACK retain current revision CAS",
        arguments: [CleanupProcessorHold.prepare, .repair])
    func freshPendingStillRespectsLocalRevision(hold: CleanupProcessorHold) async throws {
        let h = try await CleanupProcessorHarness(hold: hold)
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1])
        let model = Self.model(h)
        let fresh = SignupBodyPhotoCleanupFreshObservation(currentScope:
            .init(generation: CleanupProcessorHarness.g1, state: .pending))
        let task = Task { await model.run(eventID: UUID(), freshObservation: fresh); await h.gate.operationFinished() }
        let entered = await h.gate.entryOrOperationEnd()
        if !entered {
            await h.gate.release(); await task.value
            try #require(entered)
        }
        do {
            let revision = UUID(), inputs = h.inputs
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
            #expect(try await h.queue() == expected)
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty)
            if hold == .prepare { #expect(peer.repairs.isEmpty) }
            else { #expect(peer.acknowledgementResults == [false]) }
        } catch {
            await h.gate.release(); await task.value
            throw error
        }
    }

    @Test("G3F05 fresh DTO never bypasses visible owner/epoch authority",
        arguments: [CleanupProcessorHold.prepare, .acknowledge], [false, true])
    func freshResultCannotCommitAfterInvalidation(hold: CleanupProcessorHold, invalidateEpoch: Bool) async throws {
        let h = try await CleanupProcessorHarness(hold: hold)
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1])
        let owner = CleanupFreshOwnerFlag()
        let model = SignupBodyPhotoCleanupCoordinator(scope: h.scope, isCurrentOwner: { owner.isCurrent })
        let fresh = SignupBodyPhotoCleanupFreshObservation(currentScope:
            .init(generation: CleanupProcessorHarness.g1, state: .pending))
        let task = Task { await model.run(eventID: UUID(), freshObservation: fresh); await h.gate.operationFinished() }
        let entered = await h.gate.entryOrOperationEnd()
        if !entered {
            await h.gate.release(); await task.value
            try #require(entered)
        }
        do {
            let expected = try await h.queue()
            let bytes = try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a))
            if invalidateEpoch { model.invalidate(); task.cancel() }
            else { owner.isCurrent = false }
            await h.gate.release(); await task.value
            #expect(try await h.queue() == expected)
            #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
            try await h.lifecycle.validate(h.lease)
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.acknowledgementResults.isEmpty)
            if hold == .prepare { #expect(peer.repairs.isEmpty) }
            #expect(await h.registry.activeCount == 0)
        } catch {
            await h.gate.release(); await task.value
            throw error
        }
    }

    private static func model(_ h: CleanupProcessorHarness) -> SignupBodyPhotoCleanupCoordinator {
        SignupBodyPhotoCleanupCoordinator(scope: h.scope, isCurrentOwner: { true })
    }
}

@MainActor
private final class CleanupFreshOwnerFlag { var isCurrent = true }
#endif
