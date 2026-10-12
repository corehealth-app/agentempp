#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

enum SignupCaptureUnavailableGraph: CaseIterable, Sendable {
    case tokenOnly, missingTransport, missingStorageOrigin, unavailable, demoTransport
}

@MainActor
@Suite("Signup capture has only a real authenticated dependency graph", .serialized)
struct SignupBodyPhotoCaptureGraphTests {
    @Test("Real transport/lifecycle/storage bind one scope; old scope cannot renew after A-B-A")
    func realGraphBindsOneImmutableScope() async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        try await h.seed(generations: [CleanupProcessorHarness.g1], unbound: true)
        let queueBefore = try h.store.load(for: h.lease.userID)
        let counted = CleanupProcessorCountingLifecycle(base: h.lifecycle)
        let dependencies = try makeDependencies(h, lifecycle: counted)
        try #require(dependencies.apiClient is MobileAPITransport)
        try #require(dependencies.authentication is SupabaseAuthenticationService)
        let capability = try #require(dependencies.signupBodyPhotoCapture)
        let scope = try await capability.scoped(h.lease.userID)
        #expect(scope.userID == h.lease.userID)
        #expect(scope.photos is MobileSignupBodyPhotoRepository)
        #expect(scope.uploader is SignupSessionBoundUploader)
        #expect(scope.camera.origin == .device)
        try await scope.validateSession()
        #expect(await counted.leaseRequests == 1)
        #expect(try h.store.load(for: h.lease.userID) == queueBefore)
        try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.b))
        try await h.lifecycle.switch(to: CleanupProcessorHarness.record(CleanupProcessorHarness.a))
        var rejected = false
        do { try await scope.validateSession() } catch { rejected = true }
        #expect(rejected)
        #expect(await counted.leaseRequests == 1)
        // No request, stage, permission or upload is dispatched by construction.
        #expect(try h.store.load(for: h.lease.userID) == queueBefore)
    }

    @Test("Missing components and demo never install real capture",
        arguments: SignupCaptureUnavailableGraph.allCases)
    func unavailableGraphsDoNotBind(_ graph: SignupCaptureUnavailableGraph) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let counted = CleanupProcessorCountingLifecycle(base: h.lifecycle)
        let mobile = try MobileAPIConfiguration(originString: "https://mobile.example.test")
        let dependencies: AppDependencies
        switch graph {
        case .tokenOnly:
            dependencies = AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
                mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(configuration: mobile),
                sessionTokenProvider: SignupCaptureGraphTokenProvider(), signupBodyPhotoCleanupStore: h.store)
            #expect(dependencies.apiClient is MobileAPITransport)
        case .missingTransport:
            dependencies = try makeDependencies(h, lifecycle: counted, hasTransport: false)
            #expect(dependencies.authentication is SupabaseAuthenticationService)
        case .missingStorageOrigin:
            dependencies = AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
                mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(configuration: mobile),
                sessionLifecycleOverride: counted, signupBodyPhotoCleanupStore: h.store)
            #expect(dependencies.apiClient is MobileAPITransport)
        case .unavailable:
            dependencies = AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
                signupBodyPhotoCleanupStore: h.store)
        case .demoTransport:
            let transport = MobileAPITransport(configuration: mobile, sessionLifecycle: counted,
                session: URLSession(configuration: .ephemeral), clock: ContinuousClock())
            dependencies = AppDependencies.make(configuration: .resolve(arguments: ["--ui-testing"], buildFlavor: .debug),
                apiClientOverride: transport, sessionLifecycleOverride: counted,
                signupBodyPhotoCleanupStore: h.store)
        }
        #expect(dependencies.signupBodyPhotoCapture == nil)
        #expect(await counted.leaseRequests == 0)
    }

    private func makeDependencies(_ h: CleanupProcessorHarness,
        lifecycle: any SessionLifecycleProviding, hasTransport: Bool = true) throws -> AppDependencies {
        let mobile = try MobileAPIConfiguration(originString: "https://mobile.example.test")
        let auth = try SupabaseAuthConfiguration(originString: "https://auth.example.test", key: "sb_publishable_synthetic")
        return AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: hasTransport ? StaticMobileAPIConfigurationProvider(configuration: mobile) : nil,
            supabaseAuthConfiguration: auth,
            authenticationSessionStore: AuthenticationSessionStore(secureStore: InMemorySecureStore()),
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) },
            sessionLifecycleOverride: lifecycle,
            signupBodyPhotoCleanupStore: h.store)
    }
}

private struct SignupCaptureGraphTokenProvider: SessionTokenProviding {
    func currentBearerToken() async -> String? { "synthetic-token-only-fixture" }
}
#endif
