#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup cleanup model restore boundaries", .serialized)
struct SignupBodyPhotoCleanupModelOwnerTests {
    @Test("G3M06 cancellation at bind or normal GET cannot publish or remember stale official G",
        arguments: [false, true])
    func cancelledRestoreHasNoCleanupPublication(holdAtBind: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [], unbound: true)
        let expected = try await h.queue()
        let factory = CleanupRootFactoryPeer(scope: h.scope, holdsFirstBind: holdAtBind)
        let repository = CleanupModelReplyRepository(replies: [.success(cleanupModelEdgeState(CleanupProcessorHarness.g1))],
            holdFirstRead: !holdAtBind)
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        model.setCleanupActive(true)
        let barrier = holdAtBind ? factory.firstBindBarrier : repository.firstReadBarrier
        let start = Task { await model.start(); await barrier.operationFinished() }
        let entered = await barrier.entryOrOperationEnd()
        if !entered {
            await barrier.release(); await start.value
            try #require(entered)
        }
        do {
            _ = try #require(model.cleanupOwnerToken)
            let before = await repository.snapshot()
            #expect(before.stateReads == (holdAtBind ? 0 : 1))
            start.cancel()
            await barrier.release(); await start.value
            #expect(model.state == .launching && model.currentSession == nil)
            #expect(model.cleanupEventTask == nil)
            #expect(try await h.queue() == expected)
            let after = await repository.snapshot()
            #expect(after.stateReads == before.stateReads && after.technicalReads == 0 && after.completionPosts == 0)
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.repairs.isEmpty)
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
            try await h.lifecycle.validate(h.lease)
        } catch {
            await barrier.release(); await start.value
            throw error
        }
    }

    @Test("G3M07 late bind/GET from an earlier same-user activation cannot overwrite the newer restore",
        arguments: [false, true])
    func overlappingStartsRequireActivationAndRestoreGuards(holdAtBind: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [], unbound: true)
        let factory = CleanupRootFactoryPeer(scope: h.scope, holdsFirstBind: holdAtBind)
        let replies: [Result<OnboardingServerState, OnboardingRepositoryError>] = holdAtBind
            ? [.success(cleanupModelEdgeState(CleanupProcessorHarness.g2))]
            : [.success(cleanupModelEdgeState(CleanupProcessorHarness.g1)), .success(cleanupModelEdgeState(CleanupProcessorHarness.g2))]
        let repository = CleanupModelReplyRepository(replies: replies, holdFirstRead: !holdAtBind)
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        let barrier = holdAtBind ? factory.firstBindBarrier : repository.firstReadBarrier
        let older = Task { await model.start(); await barrier.operationFinished() }
        let entered = await barrier.entryOrOperationEnd()
        if !entered {
            await barrier.release(); await older.value
            try #require(entered)
        }
        do {
            let oldOwner = try #require(model.cleanupOwnerToken)
            await model.start()
            let newOwner = try #require(model.cleanupOwnerToken)
            #expect(newOwner.userID == oldOwner.userID && newOwner.activationID != oldOwner.activationID)
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            let current = try await h.queue()
            #expect(current.scope(CleanupProcessorHarness.g1) == nil)
            #expect(current.scope(CleanupProcessorHarness.g2)?.pending == true)
            let bytes = try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a))
            await barrier.release(); await older.value
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            #expect(model.cleanupOwnerToken == newOwner)
            #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
            let source = await repository.snapshot()
            #expect(source.stateReads == (holdAtBind ? 1 : 2))
            #expect(source.technicalReads == 0 && source.completionPosts == 0)
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a, CleanupProcessorHarness.a])
            #expect(model.cleanupEventTask == nil) // Inactive: do not cache fresh for a future active.
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.repairs.isEmpty)
            try await h.lifecycle.validate(h.lease) // Model nonce matters even with this lease still valid.
        } catch {
            await barrier.release(); await older.value
            throw error
        }
    }

    @Test("G3M08 failed normal GET is not a confirmed fresh absence")
    func failedGetLeavesOrdinaryDebtSweepAvailable() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [], unbound: true)
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let repository = CleanupModelReplyRepository(replies: [.failure(.serviceUnavailable)])
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        model.setCleanupActive(true)
        await model.start()
        _ = try #require(model.cleanupOwnerToken)
        #expect(model.onboardingLoadFailure == .temporary)
        let event = try #require(model.cleanupEventTask)
        await event.value
        let source = await repository.snapshot()
        #expect(source.stateReads == 1 && source.technicalReads == 0 && source.completionPosts == 0)
        let peer = await h.peer.snapshot()
        #expect(peer.reads == [nil])
        #expect(peer.repairs.count == 1 && peer.repairs.first?.payload.generation == CleanupProcessorHarness.g1)
        let queue = try await h.queue()
        #expect(queue.scope(CleanupProcessorHarness.g1)?.pending == false)
        #expect(queue.unboundCreates == [CleanupProcessorHarness.marker])
        #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
    }

    @Test("MC01 an older retry cannot begin a restore after a newer same-activation retry reached home")
    func overlappingRetriesFenceBeforeBinding() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let factory = CleanupModelRetryBindingFactory(scope: h.scope)
        // First restore is retryable; newer retry reaches home. A forbidden
        // third GET would fail and visibly undo the newer accepted restore.
        let repository = CleanupModelReplyRepository(replies: [
            .failure(.serviceUnavailable),
            .success(cleanupModelEdgeState(CleanupProcessorHarness.g2)),
            .failure(.serviceUnavailable)
        ])
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        await model.start()
        #expect(model.onboardingLoadFailure == .temporary)
        #expect(model.state == .onboarding(userID: CleanupProcessorHarness.a, step: .welcome))
        let activation = try #require(model.cleanupOwnerToken)
        #expect(await repository.snapshot().stateReads == 1)
        let barrier = factory.heldRetryBindingBarrier
        let older = Task {
            await model.retryOnboardingRestore()
            await barrier.operationFinished()
        }
        let entered = await barrier.entryOrOperationEnd()
        if !entered {
            await barrier.release(); await older.value
            try #require(entered)
        }
        do {
            #expect(model.cleanupOwnerToken == activation)
            #expect(await repository.snapshot().stateReads == 1)
            await model.retryOnboardingRestore()
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            #expect(model.cleanupOwnerToken == activation)
            #expect(model.onboardingLoadFailure == nil)
            let session = try #require(model.currentSession)
            #expect(session.isOnboardingCompleted)
            let source = await repository.snapshot()
            #expect(source.stateReads == 2 && source.technicalReads == 0 && source.completionPosts == 0)
            let expectedQueue = try await h.queue()
            #expect(expectedQueue.scope(CleanupProcessorHarness.g1) == nil)
            #expect(expectedQueue.scope(CleanupProcessorHarness.g2)?.pending == true)
            let bytes = try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a))
            #expect(model.cleanupEventTask == nil) // Inactive fixture: no network sweep.
            await barrier.release(); await older.value
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            #expect(model.currentSession == session && model.cleanupOwnerToken == activation)
            #expect(model.onboardingLoadFailure == nil && model.restoredOnboardingDraft == nil)
            let after = await repository.snapshot()
            #expect(after.stateReads == 2, "Superseded bind must not begin an extra restore GET")
            #expect(after.technicalReads == 0 && after.completionPosts == 0)
            #expect(try await h.queue() == expectedQueue)
            #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a, CleanupProcessorHarness.a, CleanupProcessorHarness.a])
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.repairs.isEmpty)
            try await h.lifecycle.validate(h.lease)
        } catch {
            await barrier.release(); await older.value
            throw error
        }
    }

    @Test("MC02 an old onboarding callback cannot attach its G to a new confirmed activation while binding")
    func oldOnboardingCallbackCannotCrossConfirmedActivation() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let factory = CleanupModelNextActivationFactory(scope: h.scope)
        let incomplete = OnboardingServerState(locale: "pt-BR",
            completion: .init(completed: false, completedAt: nil),
            requirements: .unavailable, acceptedActions: [],
            draft: BodyFlowTestFixtures.onboardingDraft(currentStep: .objective))
        let repository = CleanupModelReplyRepository(replies: [
            .success(incomplete),
            .success(cleanupModelEdgeState(CleanupProcessorHarness.g2))
        ])
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        await model.start()
        let oldOnboarding = try #require(model.onboardingOwnerToken)
        let oldActivation = try #require(model.cleanupOwnerToken)
        let initialQueue = try await h.queue()
        #expect(initialQueue.knownScopes.isEmpty && initialQueue.unboundCreates.isEmpty)
        #expect(await repository.snapshot().stateReads == 1)
        let barrier = factory.newActivationBindingBarrier
        let fresh = Task { await model.start(); await barrier.operationFinished() }
        let entered = await barrier.entryOrOperationEnd()
        if !entered {
            await barrier.release(); await fresh.value
            try #require(entered)
        }
        do {
            let newActivation = try #require(model.cleanupOwnerToken)
            #expect(newActivation.userID == oldActivation.userID)
            #expect(newActivation.activationID != oldActivation.activationID)
            #expect(model.onboardingOwnerToken != oldOnboarding,
                "The visible old state must not keep its callback authority during a new restore")
            #expect(await repository.snapshot().stateReads == 1)
            let event = await model.observeOnboardingCleanup(
                .init(generation: CleanupProcessorHarness.g1, state: .pending), ownerToken: oldOnboarding)
            #expect(event == nil)
            #expect(try await h.queue() == initialQueue)
            await barrier.release(); await fresh.value
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            #expect(model.cleanupOwnerToken == newActivation && model.onboardingOwnerToken == nil)
            let final = try await h.queue()
            #expect(final.scope(CleanupProcessorHarness.g1) == nil,
                "An old Flow callback must not become pending debt of the new activation")
            #expect(final.scope(CleanupProcessorHarness.g2)?.pending == true)
            #expect(final.knownScopes.count == 1 && final.unboundCreates.isEmpty)
            let source = await repository.snapshot()
            #expect(source.stateReads == 2 && source.technicalReads == 0 && source.completionPosts == 0)
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a, CleanupProcessorHarness.a])
            #expect(model.cleanupEventTask == nil)
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.repairs.isEmpty)
            try await h.lifecycle.validate(h.lease) // The unchanged lease cannot replace the Flow identity guard.
        } catch {
            await barrier.release(); await fresh.value
            throw error
        }
    }

    @Test("MC03 canceling a fresh activation cannot revive the preceding onboarding token or attach its G after retry")
    func cancelledFreshActivationCannotReviveOldOnboardingAuthority() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let factory = CleanupModelNextActivationFactory(scope: h.scope)
        let incomplete = OnboardingServerState(locale: "pt-BR",
            completion: .init(completed: false, completedAt: nil),
            requirements: .unavailable, acceptedActions: [],
            draft: BodyFlowTestFixtures.onboardingDraft(currentStep: .objective))
        let repository = CleanupModelReplyRepository(replies: [
            .success(incomplete),
            .success(cleanupModelEdgeState(CleanupProcessorHarness.g2))
        ])
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        await model.start()
        let oldOnboarding = try #require(model.onboardingOwnerToken)
        let oldActivation = try #require(model.cleanupOwnerToken)
        let oldState = model.state
        let initialQueue = try await h.queue()
        #expect(initialQueue.knownScopes.isEmpty && initialQueue.unboundCreates.isEmpty)
        #expect(await repository.snapshot().stateReads == 1)
        let barrier = factory.newActivationBindingBarrier
        let fresh = Task { await model.start(); await barrier.operationFinished() }
        let entered = await barrier.entryOrOperationEnd()
        if !entered {
            await barrier.release(); await fresh.value
            try #require(entered)
        }
        do {
            let nextActivation = try #require(model.cleanupOwnerToken)
            #expect(nextActivation.userID == oldActivation.userID)
            #expect(nextActivation.activationID != oldActivation.activationID)
            #expect(model.onboardingOwnerToken == nil)
            // Root's cancellation handler cancels the bound task. The peer
            // ignores cancellation until released; no second GET is performed.
            fresh.cancel()
            await barrier.release(); await fresh.value
            #expect(model.state == oldState && model.cleanupOwnerToken == nextActivation)
            #expect(await repository.snapshot().stateReads == 1)
            #expect(model.onboardingOwnerToken == nil,
                "Clearing active restore bookkeeping must not revive the preceding published token")
            let staleEvent = await model.observeOnboardingCleanup(
                .init(generation: CleanupProcessorHarness.g1, state: .pending), ownerToken: oldOnboarding)
            #expect(staleEvent == nil)
            #expect(try await h.queue() == initialQueue)
            // The obsolete G can be buffered without disk effect. A valid
            // retry bind then flushes it before the fresh authoritative GET.
            await model.retryOnboardingRestore()
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            #expect(model.cleanupOwnerToken == nextActivation && model.onboardingOwnerToken == nil)
            let final = try await h.queue()
            #expect(final.scope(CleanupProcessorHarness.g1) == nil,
                "The canceled activation must not let an old Flow callback become pending debt after rebind")
            #expect(final.scope(CleanupProcessorHarness.g2)?.pending == true)
            #expect(final.knownScopes.count == 1 && final.unboundCreates.isEmpty)
            let source = await repository.snapshot()
            #expect(source.stateReads == 2 && source.technicalReads == 0 && source.completionPosts == 0)
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a,
                CleanupProcessorHarness.a, CleanupProcessorHarness.a])
            #expect(model.cleanupEventTask == nil) // Inactive: no separate network sweep.
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.repairs.isEmpty)
            try await h.lifecycle.validate(h.lease)
        } catch {
            fresh.cancel()
            await barrier.release(); await fresh.value
            throw error
        }
    }

    private static func model(_ repository: CleanupModelReplyRepository,
        capability: SignupBodyPhotoCleanupCapability) -> AppFlowModel {
        AppFlowModel(authentication: CleanupModelAuthentication(session: cleanupModelSession()),
            onboarding: repository, persona: CleanupModelPersona(), telemetry: DisabledTelemetryClient(),
            signupBodyPhotoCleanup: capability)
    }
}
#endif
