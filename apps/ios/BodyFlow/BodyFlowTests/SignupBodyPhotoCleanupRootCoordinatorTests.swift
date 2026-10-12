#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup cleanup authenticated activation", .serialized)
struct SignupBodyPhotoCleanupRootCoordinatorTests {
    @Test("G3R01 initial active and startup share an event; next active retains scope")
    func startupDedupAndForegroundKeepOneBoundScope() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(unbound: true, ackedG1: true)
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let root = SignupBodyPhotoCleanupRootCoordinator(capability: factory.capability)
        defer { root.invalidate() }
        let owner = cleanupRootOwner()
        #expect(root.setActive(true) == nil) // No normal restore result yet.
        await root.transition(to: owner)
        let startup = try #require(root.finishRestore(owner: owner, freshObservation: nil))
        await startup.value
        let first = await h.peer.snapshot()
        #expect(first.reads == [nil, CleanupProcessorHarness.g2])
        #expect(first.repairs.count == 2)
        #expect(root.setActive(true) == nil)
        #expect(root.finishRestore(owner: owner, freshObservation: nil) == nil)
        await root.transition(to: owner) // An onboarding retry keeps the scope.
        let duplicate = await h.peer.snapshot()
        #expect(duplicate.reads == first.reads && duplicate.repairs == first.repairs)
        #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
        #expect(root.setActive(false) == nil)
        let next = try #require(root.setActive(true))
        await next.value
        let later = await h.peer.snapshot()
        #expect(later.reads == [nil, CleanupProcessorHarness.g2, nil, CleanupProcessorHarness.g2])
        #expect(later.repairs.count == 4)
        for g in [CleanupProcessorHarness.g1, CleanupProcessorHarness.g2] {
            let attempts = later.repairs.filter { $0.payload.generation == g }
            #expect(attempts.count == 2 && attempts.first == attempts.last)
        }
        #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
        let queue = try await h.queue()
        #expect(queue.unboundCreates == [CleanupProcessorHarness.marker])
        #expect(queue.scope(CleanupProcessorHarness.g1)?.pending == false)
        #expect(queue.scope(CleanupProcessorHarness.g2)?.pending == false)
    }

    @Test("G3R02 completion after empty startup creates a new fresh event without network wait",
        arguments: [false, true])
    func completionEventDoesNotReuseEmptyStartup(failObservationWrite: Bool) async throws {
        let h = try await CleanupProcessorHarness(hold: .repair)
        defer { h.removeFolder() }
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let root = SignupBodyPhotoCleanupRootCoordinator(capability: factory.capability)
        defer { root.invalidate() }
        let owner = cleanupRootOwner()
        root.setActive(true)
        await root.transition(to: owner)
        let startup = try #require(root.finishRestore(owner: owner,
            freshObservation: .init(currentScope: nil)))
        await startup.value
        #expect(await h.peer.snapshot().reads.isEmpty)
        let official = OnboardingBodyPhotoCleanupScope(generation: CleanupProcessorHarness.g1, state: .pending)
        if failObservationWrite { h.writeFault.arm() }
        await root.observeOfficial(official, owner: owner)
        // Observation returns after its persistence attempt, without a repair wait.
        h.writeFault.disarm()
        let completion = try #require(root.completionObserved(owner: owner,
            freshObservation: .init(currentScope: official)))
        let finisher = Task { await completion.value; await h.gate.operationFinished() }
        let entered = await h.gate.entryOrOperationEnd()
        if !entered {
            await h.gate.release(); await finisher.value
            try #require(entered)
        }
        do {
            #expect(root.finishRestore(owner: owner, freshObservation: nil) == nil)
            let during = try await h.queue()
            #expect(during.scope(CleanupProcessorHarness.g1)?.pending == true)
            let pending = await h.peer.snapshot()
            #expect(pending.reads.isEmpty && pending.repairs.count == 1)
            await h.gate.release(); await finisher.value
            #expect(try await h.queue().scope(CleanupProcessorHarness.g1)?.pending == false)
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
        } catch {
            await h.gate.release(); await finisher.value
            throw error
        }
    }

    @Test("G3R03 inactive fences each operation and next active resweeps retained attempt",
        arguments: [CleanupProcessorHold.read, .prepare, .repair, .acknowledge])
    func inactiveCancelsWithoutRebinding(hold: CleanupProcessorHold) async throws {
        let h = try await CleanupProcessorHarness(hold: hold)
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1], ackedG1: true)
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let root = SignupBodyPhotoCleanupRootCoordinator(capability: factory.capability)
        defer { root.invalidate() }
        let owner = cleanupRootOwner()
        root.setActive(true)
        await root.transition(to: owner)
        let startup = try #require(root.finishRestore(owner: owner, freshObservation: nil))
        let finisher = Task { await startup.value; await h.gate.operationFinished() }
        let entered = await h.gate.entryOrOperationEnd()
        if !entered {
            await h.gate.release(); await finisher.value
            try #require(entered)
        }
        do {
            let before = try await h.queue()
            let bytes = try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a))
            #expect(root.setActive(false) == nil)
            await h.gate.release(); await finisher.value
            #expect(try await h.queue() == before)
            #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
            let cancelled = await h.peer.snapshot()
            #expect(cancelled.acknowledgementResults.isEmpty)
            let next = try #require(root.setActive(true))
            await next.value
            let later = await h.peer.snapshot()
            #expect(later.reads.count == cancelled.reads.count + 1)
            #expect(later.repairs.count == cancelled.repairs.count + 1)
            let retained = try #require(later.repairs.last)
            #expect(retained.key.value == "cleanup-retained-key-g1")
            #expect(retained.createdAt == CleanupProcessorHarness.retainedDate)
            #expect(retained.payload.generation == CleanupProcessorHarness.g1)
            if let earlier = cancelled.repairs.first { #expect(earlier == retained) }
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
            #expect(h.inputs.counts == .init(keys: 0, dates: 0))
            #expect(try await h.queue().scope(CleanupProcessorHarness.g1)?.pending == false)
            #expect(await h.registry.activeCount == 0)
        } catch {
            await h.gate.release(); await finisher.value
            throw error
        }
    }

    @Test("G3R04 obsolete delayed A factory and metadata cannot revive after A to B to A")
    func delayedFactoryIsBoundToActivationNotUserID() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [])
        let factory = CleanupRootFactoryPeer(scope: h.scope, holdsFirstBind: true)
        let root = SignupBodyPhotoCleanupRootCoordinator(capability: factory.capability)
        defer { root.invalidate() }
        root.setActive(true)
        let oldA = cleanupRootOwner(), b = cleanupRootOwner(CleanupProcessorHarness.b), newA = cleanupRootOwner()
        #expect(oldA.userID == newA.userID && oldA.activationID != newA.activationID)
        let oldBind = Task { await root.transition(to: oldA); await factory.firstBindBarrier.operationFinished() }
        let entered = await factory.firstBindBarrier.entryOrOperationEnd()
        if !entered {
            await factory.firstBindBarrier.release(); await oldBind.value
            try #require(entered)
        }
        do {
            // Old pending metadata may only be buffered while its bind is held.
            await root.observeOfficial(.init(generation: CleanupProcessorHarness.g1, state: .pending), owner: oldA)
            await root.transition(to: b) // Explicit fixture returns A scope: must fail closed for B.
            await root.transition(to: newA)
            await root.observeOfficial(.init(generation: CleanupProcessorHarness.g2, state: .pending), owner: newA)
            let newOwnerQueue = try await h.queue()
            #expect(newOwnerQueue.scope(CleanupProcessorHarness.g1) == nil)
            #expect(newOwnerQueue.scope(CleanupProcessorHarness.g2)?.pending == true)
            let bytes = try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a))
            await factory.firstBindBarrier.release(); await oldBind.value
            #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
            await root.observeOfficial(.init(generation: CleanupProcessorHarness.g1, state: .pending), owner: oldA)
            #expect(try await h.queue() == newOwnerQueue)
            #expect(root.finishRestore(owner: oldA, freshObservation: nil) == nil)
            let current = try #require(root.finishRestore(owner: newA,
                freshObservation: .init(currentScope: .init(generation: CleanupProcessorHarness.g2, state: .pending))))
            await current.value
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.repairs.count == 1)
            #expect(peer.repairs.first?.payload.generation == CleanupProcessorHarness.g2)
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a, CleanupProcessorHarness.b, CleanupProcessorHarness.a])
            try await h.lifecycle.validate(h.lease) // Same lease intentionally remains valid throughout.
        } catch {
            await factory.firstBindBarrier.release(); await oldBind.value
            throw error
        }
    }

    @Test("G3R05 missing capability and wrong scope cannot produce local or network authority")
    func nilAndWrongOwnerFactoriesStayUnavailable() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1], unbound: true)
        let before = try await h.queue()
        let nilRoot = SignupBodyPhotoCleanupRootCoordinator(capability: nil)
        defer { nilRoot.invalidate() }
        let a = cleanupRootOwner()
        nilRoot.setActive(true)
        await nilRoot.transition(to: a)
        await nilRoot.observeOfficial(.init(generation: CleanupProcessorHarness.g2, state: .pending), owner: a)
        #expect(nilRoot.finishRestore(owner: a, freshObservation: nil) == nil)
        #expect(nilRoot.completionObserved(owner: a, freshObservation: .init(currentScope: nil)) == nil)
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let wrongRoot = SignupBodyPhotoCleanupRootCoordinator(capability: factory.capability)
        defer { wrongRoot.invalidate() }
        let b = cleanupRootOwner(CleanupProcessorHarness.b)
        wrongRoot.setActive(true)
        await wrongRoot.transition(to: b)
        await wrongRoot.observeOfficial(.init(generation: CleanupProcessorHarness.g2, state: .pending), owner: b)
        #expect(wrongRoot.finishRestore(owner: b, freshObservation: nil) == nil)
        #expect(try await h.queue() == before)
        let peer = await h.peer.snapshot()
        #expect(peer.reads.isEmpty && peer.repairs.isEmpty)
        #expect(await factory.snapshot() == [CleanupProcessorHarness.b])
    }
}
#endif
