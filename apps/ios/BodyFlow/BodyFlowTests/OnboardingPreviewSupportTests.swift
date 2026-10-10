#if DEBUG
import CryptoKit
import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Server-owned Debug onboarding fixture", .serialized)
struct OnboardingPreviewSupportTests {
    @Test("A completed Debug fixture exposes an acknowledged server-shaped state")
    func completedFixtureExposesAcknowledgedState() async throws {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing", "--ui-testing-prompt13-loaded"],
            buildFlavor: .debug
        )
        let dependencies = AppDependencies.make(configuration: configuration)
        let session = try #require(await dependencies.authentication.restoreSession())
        let state = try await dependencies.onboarding.loadState(for: session.userID)

        #expect(configuration.startsWithCompletedFixture)
        #expect(state.completion.completed)
        #expect(state.completion.completedAt != nil)
        #expect(state.draft?.currentStep == .completion)
        #expect(state.acceptedActions.count == state.requirements.documents.count)
        #expect(Set(state.acceptedActions.map(\.action)) == [
            .acceptance, .acknowledgement, .consent,
        ])
    }

    @Test("Debug injection supplies current QA documents, not legacy consent IDs")
    func debugInjectionSuppliesCurrentDocuments() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        let state = try await dependencies.onboarding.loadState(for: session.userID)

        #expect(state.requirements.available)
        #expect(state.requirements.blockingReason == nil)
        #expect(state.requirements.documents.count == 3)
        #expect(state.requirements.documents.allSatisfy { $0.required })
        #expect(Set(state.requirements.documents.map(\.action)) == [
            .acceptance, .acknowledgement, .consent,
        ])
        #expect(state.acceptedActions.isEmpty)
        #expect(!state.completion.completed)
        #expect(state.completion.completedAt == nil)
        #expect(state.draft?.currentStep == .welcome)
        #expect(state.draft?.documentActions == nil)
        for document in state.requirements.documents {
            let body = try #require(document.body)
            #expect(body.contains("QA"))
            #expect(body.utf8.count > 1_000)
            #expect(document.contentURL == nil)
            #expect(document.version == "qa-local-v1")
            #expect(document.documentKey.hasPrefix("qa_onboarding_"))
            let hash = SHA256.hash(data: Data(body.utf8))
                .map { String(format: "%02x", $0) }.joined()
            #expect(document.contentHash == hash)
        }
    }

    @Test("Real model requires explicit current actions before acknowledging completion")
    func realModelRejectsUncheckedConsentAndCompletesExplicitly() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        let state = try await dependencies.onboarding.loadState(for: session.userID)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .consent)
        draft.consent = nil
        draft.documentActions = nil
        var completions = 0
        let model = OnboardingFlowModel(
            userID: session.userID,
            initialDraft: draft,
            repository: dependencies.onboarding,
            personaRepository: dependencies.coachPersona,
            developmentConsentAvailability: .unavailable,
            requirements: state.requirements,
            onStepChanged: { _ in },
            onCompleted: { completions += 1 }
        )

        await model.continueFromCurrentStep()
        #expect(model.step == .consent)
        #expect(model.validationIssues == [.consentRequired])
        #expect(completions == 0)
        let documents = try #require(
            state.requirements.available ? state.requirements.documents : nil
        )
        for document in documents {
            model.updateDocumentAction(document.explicitAction, selected: true)
        }
        await model.continueFromCurrentStep()
        #expect(model.step == .objective)
        await model.continueFromCurrentStep()
        #expect(model.step == .completion)
        #expect(completions == 0)
        #expect(try await dependencies.onboarding.loadState(for: session.userID)
            .completion.completed == false)

        await model.complete()
        #expect(completions == 1)
        #expect(model.operationState == .idle)
        let completed = try await dependencies.onboarding.loadState(for: session.userID)
        #expect(completed.completion.completed)
        #expect(completed.acceptedActions.count == 3)
        #expect(completed.draft == model.draft)
        await model.complete()
        #expect(completions == 1)
    }

    @Test("Saved local draft resumes unchanged without inventing acceptance or completion")
    func draftResumesWithoutInventingCompletion() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        draft.consent = nil
        draft.documentActions = nil
        draft.bodyFatPercent = nil
        try await dependencies.onboarding.saveDraft(draft, for: session.userID)

        let resumed = try await dependencies.onboarding.loadState(for: session.userID)
        #expect(resumed.draft == draft)
        #expect(resumed.requirements.available)
        #expect(resumed.acceptedActions.isEmpty)
        #expect(!resumed.completion.completed)
        #expect(resumed.completion.completedAt == nil)
        #expect(try await dependencies.authentication.restoreSession() == session)
    }

    private func debugDependencies() async throws -> AppDependencies {
        let dependencies = AppDependencies.make(configuration: fixtureConfiguration(
            arguments: ["--ui-testing-fresh-auth"],
            service: "qa-fixture-\(UUID().uuidString)"
        ))
        _ = try await dependencies.authentication.restoreSession()
        _ = try await dependencies.authentication.signIn(
            email: "qa-onboarding@example.com",
            password: UUID().uuidString
        )
        return dependencies
    }

    private func fixtureConfiguration(arguments: [String], service: String) -> AppLaunchConfiguration {
        let resolved = AppLaunchConfiguration.resolve(arguments: arguments, buildFlavor: .debug)
        // Preserve real launch selection/reset semantics; isolate the test-owned
        // backing service from other suites and the executable UI fixture.
        return AppLaunchConfiguration(
            mode: resolved.mode,
            shouldResetDemoState: resolved.shouldResetDemoState,
            startsWithCompletedFixture: resolved.startsWithCompletedFixture,
            preloadsSyntheticOnboardingValues: resolved.preloadsSyntheticOnboardingValues,
            authBehavior: resolved.authBehavior,
            demoStorageBoundary: resolved.demoStorageBoundary,
            demoKeychainService: service
        )
    }

    @Test("Rebuilding the local provider retains only an explicitly acknowledged finish")
    func explicitCompletionSurvivesProviderRebuild() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        let state = try await dependencies.onboarding.loadState(for: session.userID)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.consent = nil
        draft.documentActions = state.requirements.documents.map(\.explicitAction)
        let key = try IdempotencyKey(validating: "qa-rebuild-finish")
        let acknowledgement = try await dependencies.onboarding.completeOfficial(
            draft, for: session.userID, idempotencyKey: key
        )
        let provider = try #require(dependencies.onboarding as? OnboardingPreviewRepository)
        let namespace = await provider.receiptNamespace
        let rebuilt = OnboardingPreviewRepository(
            stateStore: DemoStateStore(secureStore: dependencies.secureStore),
            buildFlavor: .debug,
            preloadsSyntheticOnboardingValues: false,
            receiptNamespace: namespace
        )

        let resumed = try await rebuilt.loadState(for: session.userID)
        #expect(resumed.completion.completed)
        #expect(resumed.completion.completedAt == acknowledgement.completedAt)
        #expect(resumed.acceptedActions == acknowledgement.documentActions)
        #expect(resumed.draft == draft)
    }

    @Test("Fresh launch, preserve, and reset retain truthful server-shaped state")
    func launchResetDoesNotResurrectAnOldFinish() async throws {
        let service = "qa-fixture-reset-\(UUID().uuidString)"
        let fresh = AppDependencies.make(configuration: fixtureConfiguration(
            arguments: ["--ui-testing-fresh-auth"], service: service
        ))
        _ = try await fresh.authentication.restoreSession()
        _ = try await fresh.authentication.signIn(
            email: "qa-onboarding@example.com",
            password: UUID().uuidString
        )
        let session = try #require(await fresh.authentication.restoreSession())
        let state = try await fresh.onboarding.loadState(for: session.userID)
        var finished = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        finished.consent = nil
        finished.documentActions = state.requirements.documents.map(\.explicitAction)
        let acknowledgement = try await fresh.onboarding.completeOfficial(
            finished, for: session.userID,
            idempotencyKey: IdempotencyKey(validating: "qa-launch-preserve-finish")
        )
        let preserved = AppDependencies.make(configuration: fixtureConfiguration(
            arguments: ["--ui-testing-preserve-state"], service: service
        ))
        _ = try #require(await preserved.authentication.restoreSession())
        let completed = try await preserved.onboarding.loadState(for: session.userID)
        #expect(completed.completion.completed)
        #expect(completed.acceptedActions == acknowledgement.documentActions)
        #expect(completed.draft == finished)

        let reset = AppDependencies.make(configuration: fixtureConfiguration(
            arguments: ["--ui-testing-fresh-auth"], service: service
        ))
        _ = try await reset.authentication.restoreSession()
        _ = try await reset.authentication.signIn(
            email: "qa-onboarding@example.com",
            password: UUID().uuidString
        )
        _ = try #require(await reset.authentication.restoreSession())
        let resetState = try await reset.onboarding.loadState(for: session.userID)
        #expect(!resetState.completion.completed)
        #expect(resetState.acceptedActions.isEmpty)
        var unfinished = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        unfinished.consent = nil
        unfinished.documentActions = nil
        try await reset.onboarding.saveDraft(unfinished, for: session.userID)
        let restored = AppDependencies.make(configuration: fixtureConfiguration(
            arguments: ["--ui-testing-preserve-state"], service: service
        ))
        _ = try #require(await restored.authentication.restoreSession())
        let resumed = try await restored.onboarding.loadState(for: session.userID)
        #expect(!resumed.completion.completed)
        #expect(resumed.acceptedActions.isEmpty)
        #expect(resumed.draft == unfinished)
    }

    @Test("Synthetic cleanup remains usable after local sign out")
    func cleanupAfterSignOutRemainsUsable() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        try await dependencies.authentication.signOut()
        try await dependencies.onboarding.clear(for: session.userID)
    }

    @Test("Concurrent conflicting finishes acknowledge exactly one snapshot; replay is exact")
    func concurrentFinishesAndReplayRemainAtomic() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        let state = try await dependencies.onboarding.loadState(for: session.userID)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.consent = nil
        draft.documentActions = state.requirements.documents.map(\.explicitAction)
        let first = draft
        draft.displayName = "Second QA snapshot"
        let second = draft
        let candidates = [first, second]
        let repository = dependencies.onboarding
        let results = await withTaskGroup(of: Int?.self) { group in
            for index in candidates.indices {
                group.addTask {
                    do {
                        _ = try await repository.completeOfficial(
                            candidates[index], for: session.userID,
                            idempotencyKey: IdempotencyKey(validating: "qa-concurrent-\(index)")
                        )
                        return index
                    } catch OnboardingRepositoryError.alreadyCompleted {
                        return nil
                    } catch {
                        Issue.record("Unexpected local fixture error: \(error)")
                        return nil
                    }
                }
            }
            var winners: [Int] = []
            for await index in group { if let index { winners.append(index) } }
            return winners
        }
        #expect(results.count == 1)
        let winner = try #require(results.first)
        let acknowledged = try await repository.loadState(for: session.userID)
        #expect(acknowledged.draft == candidates[winner])
        #expect(acknowledged.completion.completed)
        let replay = try await repository.completeOfficial(
            candidates[winner], for: session.userID,
            idempotencyKey: IdempotencyKey(validating: "qa-concurrent-\(winner)")
        )
        #expect(replay.completedAt == acknowledged.completion.completedAt)
        #expect(replay.documentActions == acknowledged.acceptedActions)
        await #expect(throws: OnboardingRepositoryError.invalidDraft) {
            try await repository.loadState(for: "qa-not-active-user")
        }
    }

    @Test("Unknown action identity cannot create an acknowledged completion")
    func forgedActionsCannotComplete() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [OnboardingDocumentAction(
            documentKey: "qa_unknown", version: "qa-local-v1", locale: "pt-BR",
            contentHash: String(repeating: "0", count: 64), action: .acceptance
        )]
        let submitted = draft
        await #expect(throws: OnboardingRepositoryError.invalidDraft) {
            try await dependencies.onboarding.completeOfficial(
                submitted, for: session.userID,
                idempotencyKey: IdempotencyKey(validating: "qa-forged-finish")
            )
        }
        #expect(try await dependencies.onboarding.loadState(for: session.userID)
            .completion.completed == false)
    }

    @Test("scripted eligibility requires the active local account and never persists a decision")
    func eligibilityRequiresLocalOwnerWithoutSaving() async throws {
        let dependencies = try await debugDependencies()
        let session = try #require(await dependencies.authentication.restoreSession())
        let before = try await dependencies.onboarding.loadState(for: session.userID)
        let input = try OnboardingEligibilityInput(draft: E3Fixtures.draft())
        let key = try IdempotencyKey(validating: "e3-local-owner")
        #expect(try await dependencies.onboarding.checkEligibility(input, for: session.userID,
            idempotencyKey: key) == E3Fixtures.choice)
        #expect(try await dependencies.onboarding.loadState(for: session.userID) == before)
        await #expect(throws: OnboardingRepositoryError.invalidDraft) {
            try await dependencies.onboarding.checkEligibility(input, for: "another-local-account", idempotencyKey: key)
        }
        try await dependencies.authentication.signOut()
        await #expect(throws: OnboardingRepositoryError.invalidDraft) {
            try await dependencies.onboarding.checkEligibility(input, for: session.userID, idempotencyKey: key)
        }
    }

    /// First update (2026-10-10): the fixtures behind the load-error UI
    /// tests answer the read of the sign-up the way the real repository does.
    @Test("the two load-failure fixtures refuse the sign-up read with their own error")
    func loadFailureFixturesRefuseTheRead() async throws {
        let cases: [(String, OnboardingEligibilityPreviewScenario, OnboardingRepositoryError)] = [
            ("--ui-testing-onboarding-admin-conflict", .adminAccountConflict, .adminAccountConflict),
            ("--ui-testing-onboarding-load-failure", .loadFailure, .serviceUnavailable),
        ]
        for (flag, scenario, expected) in cases {
            let resolved = AppLaunchConfiguration.resolve(arguments: [flag], buildFlavor: .debug)
            #expect(resolved.mode == .demo)
            #expect(resolved.onboardingEligibilityScenario == scenario)
            let dependencies = try await debugDependencies()
            let session = try #require(await dependencies.authentication.restoreSession())
            let repository = OnboardingPreviewRepository(
                stateStore: DemoStateStore(secureStore: dependencies.secureStore),
                buildFlavor: .debug,
                preloadsSyntheticOnboardingValues: true,
                eligibilityScenario: scenario
            )
            await #expect(throws: expected) {
                try await repository.loadState(for: session.userID)
            }
        }
    }

    @Test("Release ignores all E3 UI fixture arguments and retains unavailable onboarding", arguments: [
        "--ui-testing-fresh-auth", "--ui-testing-onboarding-assigned", "--ui-testing-onboarding-gain-blocked",
        "--ui-testing-onboarding-welcome", "--ui-testing-onboarding-eligibility-failure",
        "--ui-testing-onboarding-completion-uncertain",
        // First update (2026-10-10): the two load-failure fixtures.
        "--ui-testing-onboarding-admin-conflict", "--ui-testing-onboarding-load-failure"])
    func releaseDoesNotSelectSyntheticOnboarding(flag: String) async {
        let configuration = AppLaunchConfiguration.resolve(
            arguments: ["--ui-testing", flag],
            buildFlavor: .release
        )
        let dependencies = AppDependencies.make(configuration: configuration)
        #expect(configuration.mode == .releaseUnavailable)
        #expect(configuration.onboardingEligibilityScenario == nil)
        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            try await dependencies.onboarding.loadState(for: "qa-release-boundary")
        }
    }
}
#endif
