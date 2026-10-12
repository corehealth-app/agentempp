#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

// Internal argument type, never private inside a parameterized @Test.
enum CleanupGraphUnavailableCase: CaseIterable, Sendable {
    case tokenOnly, missingTransport, unavailable, demoWithRealTransport
}

@MainActor
@Suite("Signup cleanup real root graph", .serialized)
struct SignupBodyPhotoCleanupGraphTests {
    @Test("G3G01 onboarding root forwards the exact shared scope callback",
        arguments: [false, true])
    func rootForwardsOfficialScopeHook(hasScope: Bool) async throws {
        var coordinator = OnboardingRootCoordinator()
        let repository = CleanupModelRepository(completed: false)
        var received: [OnboardingBodyPhotoCleanupScope?] = []
        coordinator.synchronize(activeUserID: CleanupProcessorHarness.a,
            restoredDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .objective),
            requirements: .unavailable, onboarding: repository, persona: CleanupModelPersona(),
            developmentConsentAvailability: .unavailable, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: {},
            onOfficialCleanupObserved: { received.append($0) })
        let flow = try #require(coordinator.flowModel)
        let observation = hasScope
            ? OnboardingBodyPhotoCleanupScope(generation: CleanupProcessorHarness.g1, state: .pending) : nil
        await flow.onOfficialCleanupObserved(observation)
        #expect(received == [observation])
        let source = await repository.snapshot()
        #expect(source.stateReads == 0 && source.technicalReads == 0 && source.completionPosts == 0)
        // This is a wiring test; committed ACK tests prove the accepted origin.
    }

    @Test("G3G02 real DI supplies a protected retained scope with an explicit temporary ledger")
    func actualTransportAndLifecycleProduceCleanupCapability() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g2], unbound: true)
        let counted = CleanupProcessorCountingLifecycle(base: h.lifecycle)
        let dependencies = try Self.dependencies(h, lifecycle: counted)
        #expect(dependencies.apiClient is MobileAPITransport)
        #expect(dependencies.authentication is SupabaseAuthenticationService)
        let capability = try #require(dependencies.signupBodyPhotoCleanup)
        let scope = try await capability.scoped(CleanupProcessorHarness.a)
        #expect(scope.userID == CleanupProcessorHarness.a)
        try await scope.validateSession()
        try await scope.observePending(CleanupProcessorHarness.g1,
            SignupBodyPhotoCleanupAuthorization(validate: {}))
        let loaded = try await scope.loadQueue()
        #expect(loaded.scope(CleanupProcessorHarness.g1)?.pending == true)
        #expect(loaded.scope(CleanupProcessorHarness.g2)?.pending == true)
        #expect(loaded.unboundCreates == [CleanupProcessorHarness.marker])
        let ticket = try #require(try await scope.prepareRepair(CleanupProcessorHarness.g1,
            loaded.scope(CleanupProcessorHarness.g1)?.revision, SignupBodyPhotoCleanupAuthorization(validate: {})))
        #expect(ticket.generation == CleanupProcessorHarness.g1)
        _ = try ticket.mutationAttempt()
        #expect(await counted.leaseRequests == 1)
        try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.b))
        try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.a))
        let bytes = try await h.seedLaterOwner(CleanupProcessorHarness.a)
        var rejected = false
        do {
            try await scope.observePending(CleanupProcessorHarness.g1,
                SignupBodyPhotoCleanupAuthorization(validate: {}))
        } catch { rejected = true }
        #expect(rejected)
        #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
        #expect(await counted.leaseRequests == 1)
    }

    @Test("G3G03 demo, token-only and unavailable graphs cannot install cleanup authority",
        arguments: CleanupGraphUnavailableCase.allCases)
    func unsupportedGraphHasNoCleanupCapability(graph: CleanupGraphUnavailableCase) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1], unbound: true)
        let bytes = try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a))
        let mobile = try MobileAPIConfiguration(originString: "https://mobile.example.test")
        let counted = CleanupProcessorCountingLifecycle(base: h.lifecycle)
        let dependencies: AppDependencies
        switch graph {
        case .tokenOnly:
            dependencies = AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
                mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(configuration: mobile),
                sessionTokenProvider: CleanupGraphTokenProvider(), signupBodyPhotoCleanupStore: h.store)
            #expect(dependencies.apiClient is MobileAPITransport)
        case .missingTransport:
            dependencies = try Self.dependencies(h, lifecycle: counted, installsMobileOrigin: false)
            #expect(dependencies.authentication is SupabaseAuthenticationService)
            #expect(dependencies.apiClient is UnavailableAPIClient)
        case .unavailable:
            dependencies = AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
                signupBodyPhotoCleanupStore: h.store)
            #expect(dependencies.apiClient is UnavailableAPIClient)
        case .demoWithRealTransport:
            let transport = MobileAPITransport(configuration: mobile, sessionLifecycle: counted,
                session: URLSession(configuration: .ephemeral), clock: ContinuousClock())
            dependencies = AppDependencies.make(configuration: .resolve(arguments: ["--ui-testing"], buildFlavor: .debug),
                apiClientOverride: transport, sessionLifecycleOverride: counted,
                signupBodyPhotoCleanupStore: h.store)
        }
        #expect(dependencies.signupBodyPhotoCleanup == nil)
        #expect(try Data(contentsOf: h.store.fileURL(for: CleanupProcessorHarness.a)) == bytes)
        #expect(await counted.leaseRequests == 0)
    }

    private static func dependencies(_ h: CleanupProcessorHarness,
        lifecycle: any SessionLifecycleProviding, installsMobileOrigin: Bool = true) throws -> AppDependencies {
        let mobile = try MobileAPIConfiguration(originString: "https://mobile.example.test")
        let auth = try SupabaseAuthConfiguration(originString: "https://auth.example.test", key: "sb_publishable_synthetic")
        return AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: installsMobileOrigin ? StaticMobileAPIConfigurationProvider(configuration: mobile) : nil,
            supabaseAuthConfiguration: auth,
            authenticationSessionStore: AuthenticationSessionStore(secureStore: InMemorySecureStore()),
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) },
            sessionLifecycleOverride: lifecycle,
            signupBodyPhotoCleanupStore: h.store)
    }
}

private struct CleanupGraphTokenProvider: SessionTokenProviding {
    func currentBearerToken() async -> String? { "synthetic-token-only-fixture" }
}
#endif
