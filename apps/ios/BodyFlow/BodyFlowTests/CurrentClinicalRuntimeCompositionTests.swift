import Foundation
import Testing
@testable import BodyFlow

@Suite("Complete current clinical runtime composition", .serialized)
struct CurrentClinicalRuntimeCompositionTests {
    #if DEBUG
    @Test("Current-clinical build flags do not replace the isolated demo family", arguments: [CurrentClinicalRuntimeMode.currentV1, .unavailable])
    func clinicalBuildFlagsPreserveDemo(_ mode: CurrentClinicalRuntimeMode) async throws {
        let dependencies = AppDependencies.make(
            configuration: AppLaunchConfiguration(mode: .demo, shouldResetDemoState: true,
                startsWithCompletedFixture: true, preloadsSyntheticOnboardingValues: true,
                authBehavior: .succeed(after: nil), demoStorageBoundary: .memory,
                prompt13Scenario: .loaded),
            currentClinicalRuntimeMode: mode
        )
        #expect(dependencies.onboarding is OnboardingPreviewRepository)
        #expect(try await dependencies.today.today() == DemoBodyFlowFixtures.loadedToday)
        #expect(try await dependencies.progress.progress() == DemoBodyFlowFixtures.loadedProgress)
        #expect(dependencies.flowChat is DemoFlowChatRepository)
        let session = try #require(await dependencies.authentication.restoreSession())
        let state = try await dependencies.onboarding.loadState(for: session.userID)
        #expect(state.requirements.available && state.completion.completed)
        #expect(!state.acceptedActions.isEmpty)
        #expect(dependencies.currentClinicalReadSessions == nil)
        #expect(dependencies.clinicalFirstPhase == nil && dependencies.clinicalFull == nil && dependencies.reevaluationPhotoCapture == nil)
    }
    #endif

    @Test("Explicit current mode installs the whole native family without starting Auth or network work")
    func completeCompositionIsConstructedTogether() async throws {
        let lifecycle = ClinicalAssemblyLifecycle()
        let dependencies = try Self.dependencies(lifecycle: lifecycle)
        #expect(dependencies.currentClinicalReadSessions != nil)
        #expect(dependencies.clinicalFirstPhase != nil)
        #expect(dependencies.clinicalFull != nil)
        #expect(dependencies.reevaluationPhotoCapture != nil)
        #expect((dependencies.onboarding as? MobileOnboardingRepository)?.clinicalRepresentation == .currentV1)
        #expect((dependencies.flowChat as? MobileFlowChatRepository)?.clinicalRepresentation == .currentV1)
        // The only numerical read capability is bound by the shell coordinator;
        // a process-wide caller cannot accidentally bypass that boundary.
        #expect(dependencies.today is UnavailableBodyFlowCapabilities)
        #expect(dependencies.plan is UnavailableBodyFlowCapabilities)
        #expect(dependencies.progress is UnavailableBodyFlowCapabilities)
        #expect(dependencies.currentObjective == nil)
        #expect(await lifecycle.leaseCalls == 0)
    }

    @Test("The same build binding reaches the complete native composition without Auth work")
    func previewCompositionIsBoundAsOneFamily() async throws {
        let binding = CurrentClinicalQABinding.load(from: [
            "origin": "https://candidate-qa.vercel.app",
            "deployment_id": "dpl_syntheticCandidate",
            "project_id": CurrentClinicalQABinding.projectID,
            "source_manifest_sha256": String(repeating: "a", count: 64),
            "receipt_sha256": String(repeating: "b", count: 64),
            "region": "gru1",
        ])
        let lifecycle = ClinicalAssemblyLifecycle()
        let bound = try Self.dependencies(lifecycle: lifecycle, apiOrigin: "https://candidate-qa.vercel.app", qaBinding: binding)
        #expect(bound.clinicalFirstPhase != nil && bound.clinicalFull != nil && bound.reevaluationPhotoCapture != nil)
        #expect((bound.flowChat as? MobileFlowChatRepository)?.clinicalRepresentation == .currentV1)
        #expect((bound.onboarding as? MobileOnboardingRepository)?.clinicalRepresentation == .currentV1)
        #expect(bound.currentClinicalReadSessions != nil)
        let other = try Self.dependencies(lifecycle: lifecycle, apiOrigin: "https://another-qa.vercel.app", qaBinding: binding)
        #expect(other.clinicalFirstPhase == nil && other.clinicalFull == nil && other.reevaluationPhotoCapture == nil)
        #expect(other.onboarding is UnavailableOnboardingRepository)
        #expect(other.flowChat is UnavailableFlowChatRepository)
        let wrongDatabase = try Self.dependencies(lifecycle: lifecycle, project: "other-project",
            apiOrigin: "https://candidate-qa.vercel.app", qaBinding: binding)
        #expect(wrongDatabase.clinicalFull == nil && wrongDatabase.reevaluationPhotoCapture == nil)
        let invalid = try Self.dependencies(lifecycle: lifecycle, qaBinding: .invalid)
        #expect(invalid.clinicalFull == nil && invalid.onboarding is UnavailableOnboardingRepository)
        #expect(await lifecycle.leaseCalls == 0)
    }

    @Test("Missing scope or wrong project makes the entire requested family unavailable", arguments: [0, 1, 2])
    func cannotInstallPartialFamily(_ mismatch: Int) async throws {
        let dependencies: AppDependencies
        if mismatch == 1 { dependencies = try Self.dependencies(lifecycle: ClinicalAssemblyLifecycle(), project: "other-project") }
        else if mismatch == 2 { dependencies = try Self.dependencies(lifecycle: ClinicalAssemblyLifecycle(), apiOrigin: "https://other-mobile.example.invalid") }
        else {
            dependencies = AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
                mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(configuration:
                    try MobileAPIConfiguration(originString: "https://performe-ai-staging-bff.vercel.app")),
                sessionTokenProvider: ClinicalAssemblyTokenOnly(), currentClinicalRuntimeMode: .currentV1)
        }
        #expect(dependencies.clinicalFirstPhase == nil && dependencies.clinicalFull == nil && dependencies.reevaluationPhotoCapture == nil)
        #expect(dependencies.onboarding is UnavailableOnboardingRepository)
        #expect(dependencies.flowChat is UnavailableFlowChatRepository)
        #expect(dependencies.today is UnavailableBodyFlowCapabilities)
        let factory = try #require(dependencies.currentClinicalReadSessions)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { _ = try await factory.bind("auth-A") }
    }

    @Test("An explicitly unavailable mode never installs a subset")
    func invalidModeIsUnavailable() throws {
        let dependencies = try Self.dependencies(lifecycle: ClinicalAssemblyLifecycle(), mode: .unavailable)
        #expect(dependencies.clinicalFirstPhase == nil && dependencies.clinicalFull == nil && dependencies.reevaluationPhotoCapture == nil)
        #expect(dependencies.onboarding is UnavailableOnboardingRepository)
        #expect(dependencies.flowChat is UnavailableFlowChatRepository)
        #expect(dependencies.currentClinicalReadSessions != nil)
    }

    @Test("Existing builds remain on their established legacy composition")
    func omittedModePreservesLegacy() throws {
        let dependencies = try Self.dependencies(lifecycle: ClinicalAssemblyLifecycle(), mode: .legacy)
        #expect(dependencies.currentClinicalReadSessions == nil)
        #expect(dependencies.clinicalFirstPhase == nil && dependencies.clinicalFull == nil && dependencies.reevaluationPhotoCapture == nil)
        #expect((dependencies.onboarding as? MobileOnboardingRepository)?.clinicalRepresentation == .legacy)
        #expect((dependencies.flowChat as? MobileFlowChatRepository)?.clinicalRepresentation == .legacy)
        #expect(dependencies.today is MobileBodyFlowRepository)
    }

    private static func dependencies(lifecycle: any SessionLifecycleProviding,
                                     project: String = "xitugspwfxkcluxvrdeg",
                                     apiOrigin: String = "https://performe-ai-staging-bff.vercel.app",
                                     mode: CurrentClinicalRuntimeMode = .currentV1,
                                     qaBinding: CurrentClinicalQABinding = .absent) throws -> AppDependencies {
        AppDependencies.make(configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(configuration:
                try MobileAPIConfiguration(originString: apiOrigin)),
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(originString: "https://" + project + ".supabase.co", key: "sb_publishable_synthetic"),
            authenticationSessionStore: AuthenticationSessionStore(secureStore: InMemorySecureStore()),
            sessionLifecycleOverride: lifecycle, currentClinicalRuntimeMode: mode,
            currentClinicalQABinding: qaBinding)
    }
}

private struct ClinicalAssemblyTokenOnly: SessionTokenProviding {
    func currentBearerToken() async -> String? { "synthetic" }
}
private actor ClinicalAssemblyLifecycle: SessionLifecycleProviding {
    private(set) var leaseCalls = 0
    func currentBearerToken() async -> String? { "synthetic" }
    func leaseForRequest() async throws -> SessionLease { leaseCalls += 1; throw SessionLifecycleError.missingSession }
    func validate(_ lease: SessionLease) async throws { throw SessionLifecycleError.missingSession }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { throw SessionLifecycleError.missingSession }
    func signOut() async -> RemoteRevocationOutcome { .confirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID { throw SessionLifecycleError.missingSession }
    func finishPatientWork(_ id: UUID) async {}
}
