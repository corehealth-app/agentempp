#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Signup cleanup model-owned activation", .serialized)
struct SignupBodyPhotoCleanupModelTests {
    @Test("G3M01 normal restore persists official G before home and repairs without extra GET",
        arguments: [false, true])
    func officialRestoreHasAuthorityBeforeHome(failWrite: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [], unbound: true)
        let observeGate = CleanupProcessorBarrier(holds: true)
        let factory = CleanupRootFactoryPeer(scope: cleanupModelScope(h.scope, observationGate: observeGate))
        let official = OnboardingBodyPhotoCleanupScope(generation: CleanupProcessorHarness.g1, state: .pending)
        let repository = CleanupModelRepository(completed: true, scope: official)
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        #expect(model.setCleanupActive(true) == nil)
        let start = Task { await model.start(); await observeGate.operationFinished() }
        let entered = await observeGate.entryOrOperationEnd()
        if !entered {
            await observeGate.release(); await start.value
            try #require(entered)
        }
        do {
            let owner = try #require(model.cleanupOwnerToken)
            #expect(owner.userID == CleanupProcessorHarness.a)
            #expect(model.state == .launching)
            #expect(model.onboardingOwnerToken == nil)
            let before = try await h.queue()
            #expect(before.knownScopes.isEmpty)
            let beforeSource = await repository.snapshot()
            #expect(beforeSource.stateReads == 1 && beforeSource.technicalReads == 0 && beforeSource.completionPosts == 0)
            let beforePeer = await h.peer.snapshot()
            #expect(beforePeer.reads.isEmpty && beforePeer.repairs.isEmpty)
            if failWrite { h.writeFault.arm() }
            await observeGate.release(); await start.value
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            #expect(model.onboardingOwnerToken == nil && model.cleanupOwnerToken == owner)
            let event = try #require(model.cleanupEventTask)
            await event.value
            let finalSource = await repository.snapshot()
            #expect(finalSource.stateReads == 1 && finalSource.technicalReads == 0 && finalSource.completionPosts == 0)
            let peer = await h.peer.snapshot()
            #expect(peer.reads.isEmpty && peer.repairs.count == 1)
            #expect(peer.repairs.first?.payload.generation == CleanupProcessorHarness.g1)
            let queue = try await h.queue()
            #expect(queue.scope(CleanupProcessorHarness.g1)?.pending == false)
            #expect(queue.unboundCreates == [CleanupProcessorHarness.marker])
            #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
        } catch {
            await observeGate.release(); await start.value
            throw error
        }
    }

    @Test("G3M02 normal GET missing/unknown/mismatch never manufactures current debt",
        arguments: CleanupModelSignal.allCases)
    func metadataControlsPreserveUnbound(signal: CleanupModelSignal) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [], unbound: true)
        let before = try await h.queue()
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let repository = CleanupModelRepository(completed: true, scope: signal.scope)
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        model.setCleanupActive(true)
        await model.start()
        _ = try #require(model.cleanupOwnerToken)
        let startup = try #require(model.cleanupEventTask)
        await startup.value
        #expect(try await h.queue() == before)
        let initial = await h.peer.snapshot()
        #expect(initial.reads.isEmpty && initial.repairs.isEmpty)
        let source = await repository.snapshot()
        #expect(source.stateReads == 1 && source.technicalReads == 0 && source.completionPosts == 0)
        model.setCleanupActive(false)
        let next = try #require(model.setCleanupActive(true))
        await next.value
        let later = await h.peer.snapshot()
        #expect(later.reads == [nil] && later.repairs.count == 1)
        #expect(try await h.queue().unboundCreates == [CleanupProcessorHarness.marker])
        #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
    }

    @Test("G3M03 retries reject old onboarding callbacks while activation survives home")
    func cleanupLifetimeIsIndependentOfOnboardingPresentation() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let repository = CleanupModelRepository(completed: false)
        let model = Self.model(repository, capability: factory.capability)
        defer { model.setCleanupActive(false) }
        await model.start() // Inactive restore binds, but does not sweep.
        let activation = try #require(model.cleanupOwnerToken)
        let firstOnboarding = try #require(model.onboardingOwnerToken)
        await model.retryOnboardingRestore()
        let currentOnboarding = try #require(model.onboardingOwnerToken)
        #expect(currentOnboarding != firstOnboarding && model.cleanupOwnerToken == activation)
        #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
        let before = try await h.queue()
        _ = await model.observeOnboardingCleanup(.init(generation: CleanupProcessorHarness.g2, state: .pending), ownerToken: firstOnboarding)
        #expect(try await h.queue() == before)
        _ = await model.observeOnboardingCleanup(.init(generation: CleanupProcessorHarness.g1, state: .pending), ownerToken: currentOnboarding)
        #expect(try await h.queue().scope(CleanupProcessorHarness.g1)?.pending == true)
        model.completeOnboarding(ownerToken: currentOnboarding)
        #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
        #expect(model.onboardingOwnerToken == nil && model.cleanupOwnerToken == activation)
        let next = try #require(model.setCleanupActive(true))
        await next.value
        let peer = await h.peer.snapshot()
        #expect(peer.reads == [CleanupProcessorHarness.g1] && peer.repairs.count == 1)
        #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
        _ = await model.observeOnboardingCleanup(.init(generation: CleanupProcessorHarness.g2, state: .pending), ownerToken: currentOnboarding)
        #expect(try await h.queue().scope(CleanupProcessorHarness.g2) == nil)
        let source = await repository.snapshot()
        #expect(source.stateReads == 2 && source.technicalReads == 0 && source.completionPosts == 0)
        #expect(model.cleanupEventTask != nil) // Keep the actual completed handle until the next event/teardown.
    }

    @Test("G3M04 presentation-only and unconfirmed session do not create cleanup authority",
        arguments: [false, true])
    func presentationCannotInstallAuthenticatedActivation(hasUnconfirmedSession: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let repository = CleanupModelRepository(completed: true,
            scope: .init(generation: CleanupProcessorHarness.g1, state: .pending))
        let session = hasUnconfirmedSession ? cleanupModelSession(confirmed: false) : nil
        let model = AppFlowModel(authentication: CleanupModelAuthentication(session: session),
            onboarding: repository, persona: CleanupModelPersona(), telemetry: DisabledTelemetryClient(),
            signupBodyPhotoCleanup: factory.capability,
            initialState: .authenticated(userID: CleanupProcessorHarness.a))
        #expect(model.cleanupOwnerToken == nil && model.cleanupEventTask == nil)
        #expect(model.setCleanupActive(true) == nil)
        await model.start()
        #expect(model.cleanupOwnerToken == nil && model.cleanupEventTask == nil)
        #expect(await factory.snapshot().isEmpty)
        let source = await repository.snapshot()
        #expect(source.stateReads == 0 && source.technicalReads == 0 && source.completionPosts == 0)
        let peer = await h.peer.snapshot()
        #expect(peer.reads.isEmpty && peer.repairs.isEmpty)
    }

    @Test("G3M05 failed sign out preserves activation; success tears down without erasing debt",
        arguments: [false, true])
    func signOutPreservesExistingFailureContract(failSignOut: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(unbound: true, ackedG1: true)
        let before = try await h.queue()
        let factory = CleanupRootFactoryPeer(scope: h.scope)
        let repository = CleanupModelRepository(completed: true)
        let model = Self.model(repository, capability: factory.capability, signOutFails: failSignOut)
        await model.start()
        let owner = try #require(model.cleanupOwnerToken)
        #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
        await model.signOut()
        if failSignOut {
            #expect(model.state == .authenticated(userID: CleanupProcessorHarness.a))
            #expect(model.cleanupOwnerToken == owner)
        } else {
            #expect(model.state == .signedOut(.signIn))
            #expect(model.cleanupOwnerToken == nil && model.cleanupEventTask == nil)
        }
        #expect(try await h.queue() == before)
        #expect(await factory.snapshot() == [CleanupProcessorHarness.a])
        model.setCleanupActive(false)
    }

    private static func model(_ repository: CleanupModelRepository,
        capability: SignupBodyPhotoCleanupCapability?, signOutFails: Bool = false) -> AppFlowModel {
        AppFlowModel(authentication: CleanupModelAuthentication(session: cleanupModelSession(), signOutFails: signOutFails),
            onboarding: repository, persona: CleanupModelPersona(), telemetry: DisabledTelemetryClient(),
            signupBodyPhotoCleanup: capability)
    }
}
#endif
