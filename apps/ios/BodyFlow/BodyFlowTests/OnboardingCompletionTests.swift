import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Onboarding completion")
struct OnboardingCompletionTests {
    @Test("A definitive photo refusal returns to body data only after an official read")
    func photoRefusalReconcilesBeforeEditing() async {
        let repository = CompletionOnboardingRepository(results: [.failure(.bodyPhotoConfirmationChanged)])
        let model = await makeModel(onboarding: repository)
        await prepareE3Review(model)
        await model.complete()
        #expect(model.step == .bodyData)
        #expect(!model.unresolvedCompletion)
        #expect(model.allowsDraftEditing)
        #expect(model.eligibilityDecision == nil)
        #expect(await repository.completedDrafts.count == 1)
    }
    @Test("missing persona blocks every persistence side effect")
    func missingPersonaBlocksCompletion() async {
        var draft = completeDraft()
        draft.persona = nil
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        let model = await makeModel(
            draft: draft,
            onboarding: onboarding,
            persona: persona
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.validationIssues.contains(.personaRequired))
        #expect(model.step == .persona)
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
    }

    @Test(arguments: [DevelopmentConsentDocumentID.terms, .privacy])
    func missingEitherConsentBlocksCompletion(
        _ missingDocument: DevelopmentConsentDocumentID
    ) async {
        var draft = completeDraft()
        let missingDocumentKey = missingDocument == .terms
            ? "terms_of_service"
            : "privacy_notice"
        draft.documentActions = completeDocumentActions.filter {
            $0.documentKey != missingDocumentKey
        }
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        let model = await makeModel(
            draft: draft,
            onboarding: onboarding,
            persona: persona
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.validationIssues.contains(.consentRequired))
        #expect(model.step == .consent)
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
    }

    @Test("unsupported locale blocks completion before every persistence side effect")
    func unsupportedLocaleBlocksCompletion() async {
        var draft = completeDraft()
        draft.localeIdentifier = "fr-FR"
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = await makeModel(
            draft: draft,
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.validationIssues == [.localeUnsupported])
        #expect(model.step == .welcome)
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
        #expect(callbackCount == 0)
    }

    @Test("the server-owned completion precedes the root callback without a separate persona write")
    func persistsInApprovedOrder() async {
        let events = CompletionEventRecorder()
        let onboarding = CompletionOnboardingRepository(events: events)
        let persona = CompletionPersonaRepository(events: events)
        var callbackCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: {
                callbackCount += 1
                events.record("callback")
            }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(events.values == ["complete", "callback"])
        #expect(await persona.writes.isEmpty)
        #expect(callbackCount == 1)
        #expect(model.operationState == .idle)
    }

    @Test("completion cannot start before the review step")
    func completionRequiresReviewStep() async {
        var draft = completeDraft()
        draft.currentStep = .consent
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        let model = await makeModel(
            draft: draft,
            onboarding: onboarding,
            persona: persona
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
    }

    @Test("unavailable synthetic consent blocks stale completion before every write")
    func unavailableSyntheticConsentBlocksCompletion() async {
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            persona: persona,
            developmentConsentAvailability: .unavailable,
            requirements: .unavailable,
            onCompleted: { callbackCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.validationIssues == [.developmentConsentUnavailable])
        #expect(model.step == .consent)
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
        #expect(callbackCount == 0)
    }

    @Test("official completion requires the exact current document action")
    func officialActionIsRequired() async {
        var draft = completeDraft()
        draft.consent = nil
        draft.documentActions = nil
        let onboarding = CompletionOnboardingRepository()
        let model = await makeModel(
            draft: draft,
            onboarding: onboarding,
            developmentConsentAvailability: .unavailable,
            requirements: officialRequirements
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.validationIssues.contains(.consentRequired))
        #expect(await onboarding.completedDrafts.isEmpty)
    }

    @Test("changed legal requirements return to consent and clear stale actions")
    func requirementsConflictReloadsAndClearsActions() async {
        let changedDocument = OnboardingLegalDocument(
            documentKey: "terms_of_service",
            version: "2026-09-15.2",
            locale: "pt-BR",
            body: "Updated synthetic terms for tests only",
            contentURL: nil,
            contentHash: String(repeating: "b", count: 64),
            purpose: "synthetic_terms_test",
            action: .acceptance,
            required: true,
            effectiveAt: "2026-09-15T16:00:00.000Z"
        )
        let onboarding = RequirementsChangingOnboardingRepository(
            changedRequirements: OnboardingRequirements(
                available: true,
                blockingReason: nil,
                documents: [changedDocument]
            )
        )
        var draft = completeDraft()
        draft.consent = nil
        draft.documentActions = completeDocumentActions
        var changedSteps: [OnboardingStep] = []
        var completionCount = 0
        let model = await makeModel(
            draft: draft,
            onboarding: onboarding,
            developmentConsentAvailability: .unavailable,
            requirements: officialRequirements,
            onStepChanged: { changedSteps.append($0) },
            onCompleted: { completionCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.step == .consent)
        #expect(model.draft.documentActions == nil)
        #expect(model.requirements.documents == [changedDocument])
        #expect(model.operationState == .failed(.operationUnavailable))
        #expect(changedSteps == [.consent])

        model.updateDocumentAction(changedDocument.explicitAction, selected: true)
        await model.continueFromCurrentStep()
        await prepareE3Review(model)
        await model.complete()

        #expect(Set(await onboarding.completionKeys).count == 2)
        #expect(completionCount == 1)
        #expect(model.operationState == .idle)
    }

    @Test("requirements reload honors a completion established by another device")
    func requirementsReloadHonorsConcurrentCompletion() async {
        let onboarding = ConcurrentlyCompletedOnboardingRepository()
        var completionCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            onCompleted: { completionCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(completionCount == 1)
        #expect(model.operationState == .idle)
        #expect(model.step == .completion)
    }

    @Test("already-completed conflict reconciles a completion established by another device")
    func alreadyCompletedConflictReconcilesConcurrentCompletion() async {
        let onboarding = ConcurrentlyCompletedOnboardingRepository(
            completionError: .alreadyCompleted
        )
        var completionCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            onCompleted: { completionCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(completionCount == 1)
        #expect(model.operationState == .idle)
        #expect(model.step == .completion)
    }

    @Test("historical completion conflict restores the authoritative draft for reconsent")
    func historicalCompletionConflictRestoresAuthoritativeDraft() async {
        let changedDocument = OnboardingLegalDocument(
            documentKey: "terms_of_service",
            version: "2026-09-15.2",
            locale: "pt-BR",
            body: "Updated synthetic terms for tests only",
            contentURL: nil,
            contentHash: String(repeating: "b", count: 64),
            purpose: "synthetic_terms_test",
            action: .acceptance,
            required: true,
            effectiveAt: "2026-09-15T16:00:00.000Z"
        )
        let changedRequirements = OnboardingRequirements(
            available: true,
            blockingReason: nil,
            documents: [changedDocument]
        )
        var authoritativeDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .consent)
        authoritativeDraft.displayName = "Authoritative Synthetic User"
        authoritativeDraft.objective = .maintenance
        authoritativeDraft.persona = .zen
        authoritativeDraft.documentActions = nil
        let onboarding = HistoricalReconsentOnboardingRepository(
            authoritativeDraft: authoritativeDraft,
            changedRequirements: changedRequirements
        )
        var localDraft = completeDraft()
        localDraft.displayName = "Stale Local User"
        localDraft.objective = .muscleGain
        localDraft.persona = .impulse
        var completionCount = 0
        let model = await makeModel(
            draft: localDraft,
            onboarding: onboarding,
            onCompleted: { completionCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.step == .consent)
        #expect(model.draft == authoritativeDraft)
        #expect(model.draft.documentActions == nil)
        #expect(model.requirements == changedRequirements)
        #expect(model.operationState == .failed(.operationUnavailable))
        #expect(completionCount == 0)
    }

    @Test("a transient requirements reload failure preserves a safe retry path")
    func transientRequirementsReloadCanRetry() async {
        let changedDocument = OnboardingLegalDocument(
            documentKey: "terms_of_service",
            version: "2026-09-15.2",
            locale: "pt-BR",
            body: "Updated synthetic terms for tests only",
            contentURL: nil,
            contentHash: String(repeating: "b", count: 64),
            purpose: "synthetic_terms_test",
            action: .acceptance,
            required: true,
            effectiveAt: "2026-09-15T16:00:00.000Z"
        )
        let onboarding = TransientReloadFailureOnboardingRepository(
            changedRequirements: OnboardingRequirements(
                available: true,
                blockingReason: nil,
                documents: [changedDocument]
            )
        )
        let model = await makeModel(onboarding: onboarding)

        await prepareE3Review(model)
        await model.complete()

        #expect(model.step == .completion)
        #expect(model.draft.documentActions == completeDocumentActions)
        #expect(model.requirements == officialRequirements)
        #expect(model.operationState == .failed(.serviceUnavailable))

        await prepareE3Review(model)
        await model.complete()

        #expect(model.step == .consent)
        #expect(model.draft.documentActions == nil)
        #expect(model.requirements.documents == [changedDocument])
        #expect(await onboarding.completionKeys.count == 2)
        #expect(Set(await onboarding.completionKeys).count == 1)
    }

    @Test("a legacy persona repository cannot intercept server-owned completion")
    func personaRepositoryCannotInterceptCompletion() async {
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository(
            results: [.failure(.serviceUnavailable)]
        )
        var callbackCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.step == .completion)
        #expect(model.draft.currentStep == .completion)
        #expect(model.draft.consent?.documentIDs == [.terms, .privacy])
        #expect(model.operationState == .idle)
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.count == 1)
        #expect(callbackCount == 1)
    }

    @Test("completion retry preserves the draft and reuses one idempotency key")
    func retriesPartialCompletion() async {
        let onboarding = CompletionOnboardingRepository(
            results: [.failure(.serviceUnavailable), .success(())]
        )
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        var changedSteps: [OnboardingStep] = []
        let model = await makeModel(
            onboarding: onboarding,
            persona: persona,
            onStepChanged: { changedSteps.append($0) },
            onCompleted: { callbackCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()

        #expect(model.step == .completion)
        #expect(model.draft.currentStep == .completion)
        #expect(model.draft.consent?.documentIDs == [.terms, .privacy])
        #expect(model.operationState == .failed(.serviceUnavailable))
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.count == 1)
        #expect(changedSteps.isEmpty)
        #expect(callbackCount == 0)

        await prepareE3Review(model)
        await model.complete()

        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.count == 2)
        #expect(Set(await onboarding.completionKeys).count == 1)
        #expect(callbackCount == 1)
        #expect(model.operationState == .idle)
    }

    @Test("double tap starts one final submission")
    func suppressesConcurrentCompletion() async {
        let onboarding = SuspendedCompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )
        let first = Task { await model.complete() }
        await onboarding.waitUntilCompleteSuspends()

        await prepareE3Review(model)
        await model.complete()

        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completeCount == 1)
        #expect(model.operationState == .saving)

        await onboarding.resumeComplete()
        await first.value

        #expect(callbackCount == 1)
    }

    @Test("a second call after success is idempotent")
    func successfulCompletionTransitionsOnce() async {
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )

        await prepareE3Review(model)
        await model.complete()
        await prepareE3Review(model)
        await model.complete()

        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.count == 1)
        #expect(callbackCount == 1)
    }

    @Test("cancellation after a repository response prevents late transition")
    func cancellationPreventsLateTransition() async {
        let onboarding = CancellationIgnoringCompletionRepository()
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = await makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )
        let submission = Task { await model.complete() }
        await onboarding.waitUntilCompleteSuspends()

        submission.cancel()
        await onboarding.resumeComplete()
        await submission.value

        #expect(model.step == .completion)
        #expect(model.operationState == .idle)
        #expect(callbackCount == 0)
    }

    @Test("a cancelled late failure does not replace state with an error")
    func cancellationPreventsLateError() async {
        let onboarding = CancellationIgnoringFailingCompletionRepository()
        let persona = CompletionPersonaRepository()
        let model = await makeModel(onboarding: onboarding, persona: persona)
        let submission = Task { await model.complete() }
        await onboarding.waitUntilCompleteSuspends()

        submission.cancel()
        await onboarding.resumeComplete()
        await submission.value

        #expect(model.step == .completion)
        #expect(model.draft.currentStep == .completion)
        #expect(model.operationState == .idle)
    }

    @Test("release rejects the two synthetic IDs without mutating state")
    func releaseRejectsDevelopmentConsentWithoutMutation() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        let originalSession = incompleteSession()
        try await store.saveSession(originalSession)
        let repository = DemoOnboardingRepository(
            stateStore: store,
            buildFlavor: .release
        )
        let draft = completeDraft()

        await #expect(throws: OnboardingRepositoryError.developmentConsentForbidden) {
            try await repository.complete(draft, for: originalSession.userID)
        }

        #expect(try await store.loadSession() == originalSession)
        #expect(try await store.loadOnboardingDraft() == nil)
    }

    @Test("release rejects saving synthetic consent before replacing persisted draft")
    func releaseRejectsDevelopmentConsentSaveWithoutMutation() async throws {
        let store = DemoStateStore(secureStore: InMemorySecureStore())
        var originalDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .persona)
        originalDraft.consent = nil
        try await store.saveOnboardingDraft(originalDraft)
        let repository = DemoOnboardingRepository(
            stateStore: store,
            buildFlavor: .release
        )
        let forbiddenDraft = completeDraft()

        await #expect(throws: OnboardingRepositoryError.developmentConsentForbidden) {
            try await repository.saveDraft(forbiddenDraft, for: "fixture-user")
        }

        #expect(try await store.loadOnboardingDraft() == originalDraft)
    }

    @Test("root completion requires the current confirmed session and matching user")
    func rootCompletionRequiresCurrentMatchingUser() async {
        let model = makeAppFlowModel(session: incompleteSession())
        await model.start()

        model.completeOnboarding(for: "another-user")

        #expect(model.state == .onboarding(
            userID: "fixture-user",
            step: .consent
        ))
        #expect(model.currentSession?.isOnboardingCompleted == false)
        #expect(model.restoredOnboardingDraft != nil)

        model.completeOnboarding(for: "fixture-user")

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(model.currentSession?.isOnboardingCompleted == true)
        #expect(model.restoredOnboardingDraft == nil)
    }

    @Test("an old callback after sign out cannot authenticate")
    func staleCompletionCallbackIsIgnored() async {
        let model = makeAppFlowModel(session: incompleteSession())
        await model.start()
        await model.signOut()

        model.completeOnboarding(for: "fixture-user")

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
    }

    @Test("a cancelled root callback cannot authenticate")
    func cancelledRootCompletionIsIgnored() async {
        let cancellation = CompletionCancellationCheck()
        let model = AppFlowModel(
            authentication: CompletionAuthenticationService(
                session: incompleteSession()
            ),
            onboarding: CompletionOnboardingRepository(
                loadedDraft: completeDraft()
            ),
            persona: CompletionPersonaRepository(),
            telemetry: InMemoryTelemetryClient(),
            cancellationCheck: cancellation.isCancelled
        )
        await model.start()
        cancellation.cancel()

        model.completeOnboarding(for: "fixture-user")

        #expect(model.state == .onboarding(
            userID: "fixture-user",
            step: .consent
        ))
        #expect(model.currentSession?.isOnboardingCompleted == false)
    }

    @Test("uncertain completion locks edits and retries the exact original body with its key")
    func uncertainCompletionPreservesImmutableAttempt() async throws {
        let repository = CompletionOnboardingRepository(results: [.failure(.serviceUnavailable), .success(())])
        let model = await makeModel(onboarding: repository)
        let original = model.draft
        await prepareE3Review(model)
        await model.complete()
        model.updateWeightKG(90)
        model.updateObjective(.muscleGain)
        model.updateDocumentAction(officialDocument.explicitAction, selected: false)
        await model.back()
        #expect(model.draft == original)
        #expect(model.step == .completion)
        await prepareE3Review(model)
        await model.complete()
        #expect(await repository.completedDrafts == [original, original])
        let keys = await repository.completionKeys
        #expect(keys.count == 2)
        #expect(Set(keys).count == 1)
    }

    #if DEBUG
    @Test("G31 confirmed ACK plus local persistence failure never repeats completion POST", arguments: [false, true])
    func confirmedACKCleanupFaultNeverReposts(welcome: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let events = CompletionEventRecorder()
        let repository = CompletionCleanupObservedRepository(mode: .acknowledged, signal: .pending,
            welcome: welcome, events: events)
        let telemetry = CompletionCleanupTelemetry()
        let cleanup = SignupBodyPhotoCleanupCoordinator(scope: h.scope, isCurrentOwner: { true })
        var observed: [OnboardingBodyPhotoCleanupScope?] = []
        var callbacks = 0
        let model = await makeModel(onboarding: repository, userID: CleanupProcessorHarness.a,
            telemetry: telemetry, onOfficialCleanupObserved: { observation in
                observed.append(observation); events.record("cleanup")
                await cleanup.observeOfficial(observation)
            }, onCompleted: { callbacks += 1; events.record("callback") })
        let original = model.draft
        let beforeTelemetry = await telemetry.snapshot()
        h.writeFault.arm()
        await model.complete()
        #expect(observed == [CompletionCleanupObservedRepository.pendingScope])
        #expect(!model.unresolvedCompletion && !model.allowsDraftEditing)
        #expect(model.operationState == .idle)
        if welcome {
            #expect(model.pendingProtocolWelcome != nil && callbacks == 0)
            model.finishProtocolWelcome(); model.finishProtocolWelcome()
        }
        #expect(callbacks == 1)
        #expect(events.values == ["complete", "cleanup", "callback"])
        let localBefore = try await h.queue()
        #expect(localBefore.knownScopes.isEmpty)
        await model.complete()
        let counts = await repository.counts()
        #expect(counts.drafts == [original] && counts.keys.count == 1 && counts.reads == 0)
        let accepted = Array((await telemetry.snapshot()).dropFirst(beforeTelemetry.count))
        let persona = try #require(original.persona)
        #expect(accepted == [.coachPersonaSelected(persona.telemetryValue),
            .onboardingStepCompleted(.completion), .onboardingCompleted])
        // The processor's retained official buffer, not another completion POST.
        await cleanup.run(eventID: UUID())
        let localAfter = try await h.queue()
        #expect(localAfter.scope(CompletionCleanupObservedRepository.g1)?.pending == false)
        let finalCounts = await repository.counts()
        #expect(finalCounts.drafts == [original] && finalCounts.keys == counts.keys && finalCounts.reads == 0)
    }

    @Test("G32 cancel/owner invalidation during the new hook preserves accepted state and telemetry", arguments: [false, true])
    func acceptedACKHookCancellationCannotRearmPOST(invalidateOwner: Bool) async throws {
        let h = try await CleanupProcessorHarness()
        defer { h.removeFolder() }
        let gate = CleanupProcessorBarrier(holds: true)
        let owner = CompletionCleanupOwnerFlag()
        let repository = CompletionCleanupObservedRepository(mode: .acknowledged, signal: .pending, welcome: true)
        let telemetry = CompletionCleanupTelemetry()
        let cleanup = SignupBodyPhotoCleanupCoordinator(scope: h.scope, isCurrentOwner: { owner.current })
        var callbacks = 0
        let model = await makeModel(onboarding: repository, userID: CleanupProcessorHarness.a,
            telemetry: telemetry, onOfficialCleanupObserved: { observation in
                await gate.enter()
                await cleanup.observeOfficial(observation)
            }, onCompleted: { callbacks += 1 })
        let beforeTelemetry = await telemetry.snapshot()
        let original = model.draft
        let task = Task { await model.complete(); await gate.operationFinished() }
        let entered = await gate.entryOrOperationEnd()
        if !entered {
            await gate.release(); await task.value
            try #require(entered)
        }
        #expect(!model.unresolvedCompletion && !model.allowsDraftEditing)
        let started = await repository.counts()
        #expect(started.drafts == [original] && started.keys.count == 1)
        if invalidateOwner { owner.current = false; model.invalidate() }
        else { task.cancel() }
        await gate.release(); await task.value
        #expect(callbacks == 0 && model.pendingProtocolWelcome == nil)
        await model.complete()
        let final = await repository.counts()
        #expect(final.drafts == [original] && final.keys == started.keys && final.reads == 0)
        let persona = try #require(original.persona)
        let accepted = Array((await telemetry.snapshot()).dropFirst(beforeTelemetry.count))
        #expect(accepted == [.coachPersonaSelected(persona.telemetryValue),
            .onboardingStepCompleted(.completion), .onboardingCompleted])
        if !invalidateOwner {
            await cleanup.run(eventID: UUID())
            let queued = try await h.queue()
            #expect(queued.scope(CompletionCleanupObservedRepository.g1)?.pending == false)
        }
    }

    @Test("G33 completed reconciliation observes only its already-returned current scope",
        arguments: [OnboardingRepositoryError.alreadyCompleted, .requirementsChanged, .bodyPhotoConfirmationChanged],
        [CompletionCleanupSignal.pending, .unknown, .mismatch, .missing])
    func reconciliationObservesReturnedMetadata(error: OnboardingRepositoryError, signal: CompletionCleanupSignal) async throws {
        let events = CompletionEventRecorder()
        let repository = CompletionCleanupObservedRepository(mode: .reconcile(error), signal: signal,
            welcome: false, events: events)
        let telemetry = CompletionCleanupTelemetry()
        var observed: [OnboardingBodyPhotoCleanupScope?] = []
        var callbacks = 0
        let model = await makeModel(onboarding: repository, userID: CleanupProcessorHarness.a,
            telemetry: telemetry, onOfficialCleanupObserved: { scope in
                observed.append(scope); events.record("cleanup")
            }, onCompleted: { callbacks += 1; events.record("callback") })
        let beforeTelemetry = await telemetry.snapshot()
        await model.complete()
        if let expected = CompletionCleanupObservedRepository.currentScope(signal) {
            #expect(observed == [expected])
            #expect(events.values == ["complete", "read", "cleanup", "callback"])
        } else {
            #expect(observed.allSatisfy { $0 == nil })
        }
        #expect(callbacks == 1 && !model.unresolvedCompletion && !model.allowsDraftEditing)
        let counts = await repository.counts()
        #expect(counts.drafts.count == 1 && counts.keys.count == 1 && counts.reads == 1)
        let accepted = Array((await telemetry.snapshot()).dropFirst(beforeTelemetry.count))
        #expect(accepted.isEmpty) // Reconciliation is not a manufactured accepted ACK.
        await model.complete()
        let final = await repository.counts()
        #expect(final.drafts == counts.drafts && final.keys == counts.keys && final.reads == 1)
    }

    @Test("G34 invalid ACK/uncertain POST retain the original completion contract", arguments: [false, true])
    func cleanupHookDoesNotAuthorizeInvalidOrUncertainCompletion(uncertain: Bool) async throws {
        let repository = CompletionCleanupObservedRepository(mode: uncertain ? .uncertain : .invalidACK,
            signal: .pending, welcome: false)
        let telemetry = CompletionCleanupTelemetry()
        var observed: [OnboardingBodyPhotoCleanupScope?] = []
        var callbacks = 0
        let model = await makeModel(onboarding: repository, userID: CleanupProcessorHarness.a,
            telemetry: telemetry, onOfficialCleanupObserved: { observed.append($0) },
            onCompleted: { callbacks += 1 })
        let original = model.draft
        let beforeTelemetry = await telemetry.snapshot()
        await model.complete()
        #expect(observed.isEmpty && callbacks == 0 && model.unresolvedCompletion)
        #expect(model.operationState == .failed(.serviceUnavailable))
        let first = await repository.counts()
        #expect(first.drafts == [original] && first.keys.count == 1 && first.reads == 0)
        let accepted = Array((await telemetry.snapshot()).dropFirst(beforeTelemetry.count))
        #expect(accepted.isEmpty)
        if uncertain {
            await model.complete()
            let retried = await repository.counts()
            #expect(retried.drafts == [original, original])
            #expect(retried.keys.count == 2 && Set(retried.keys).count == 1)
            #expect(observed == [CompletionCleanupObservedRepository.pendingScope] && callbacks == 1)
        }
    }
    #endif

    private func makeModel(
        draft: OnboardingDraft? = nil,
        onboarding: any OnboardingRepository = CompletionOnboardingRepository(),
        persona: any CoachPersonaRepository = CompletionPersonaRepository(),
        developmentConsentAvailability: DevelopmentConsentAvailability = .unavailable,
        requirements: OnboardingRequirements? = nil,
        userID: String = "fixture-user",
        telemetry: any TelemetryClient = DisabledTelemetryClient(),
        onOfficialCleanupObserved: @escaping @MainActor (OnboardingBodyPhotoCleanupScope?) async -> Void = { _ in },
        onStepChanged: @escaping @MainActor (OnboardingStep) -> Void = { _ in },
        onCompleted: @escaping @MainActor () -> Void = {}
    ) async -> OnboardingFlowModel {
        let setup = CompletionSetupState()
        let model = OnboardingFlowModel(
            userID: userID,
            initialDraft: draft ?? completeDraft(),
            repository: onboarding,
            personaRepository: persona,
            developmentConsentAvailability: developmentConsentAvailability,
            requirements: requirements ?? officialRequirements,
            telemetry: telemetry,
            onStepChanged: { if setup.finished { onStepChanged($0) } },
            onCompleted: onCompleted,
            onOfficialCleanupObserved: onOfficialCleanupObserved,
            now: { fixtureDate }
        )
        // Establish the current server decision before observing the completion operation.
        if (draft ?? completeDraft()).currentStep == .completion {
            await prepareE3Review(model)
        }
        setup.finished = true
        return model
    }

    private func makeAppFlowModel(session: AuthSession) -> AppFlowModel {
        AppFlowModel(
            authentication: CompletionAuthenticationService(session: session),
            onboarding: CompletionOnboardingRepository(
                loadedDraft: completeDraft()
            ),
            persona: CompletionPersonaRepository(),
            telemetry: InMemoryTelemetryClient()
        )
    }

    private func completeDraft() -> OnboardingDraft {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.consent = DevelopmentConsentAcceptance(
            documentIDs: [.terms, .privacy],
            acceptedAt: fixtureDate
        )
        draft.documentActions = completeDocumentActions
        return draft
    }

    private var officialDocument: OnboardingLegalDocument {
        OnboardingLegalDocument(
            documentKey: "terms_of_service",
            version: "2026-09-15.1",
            locale: "pt-BR",
            body: "Synthetic terms for tests only",
            contentURL: nil,
            contentHash: String(repeating: "a", count: 64),
            purpose: "synthetic_terms_test",
            action: .acceptance,
            required: true,
            effectiveAt: "2026-09-15T15:00:00.000Z"
        )
    }

    private var officialRequirements: OnboardingRequirements {
        OnboardingRequirements(
            available: true,
            blockingReason: nil,
            documents: [officialDocument, officialPrivacyDocument]
        )
    }

    private var officialPrivacyDocument: OnboardingLegalDocument {
        OnboardingLegalDocument(
            documentKey: "privacy_notice",
            version: "2026-09-15.1",
            locale: "pt-BR",
            body: "Synthetic privacy notice for tests only",
            contentURL: nil,
            contentHash: String(repeating: "c", count: 64),
            purpose: "synthetic_privacy_test",
            action: .acknowledgement,
            required: true,
            effectiveAt: "2026-09-15T15:00:00.000Z"
        )
    }

    private var completeDocumentActions: [OnboardingDocumentAction] {
        [officialDocument.explicitAction, officialPrivacyDocument.explicitAction]
    }

    private func incompleteSession() -> AuthSession {
        AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
    }

    private var fixtureDate: Date {
        Date(timeIntervalSince1970: 946_684_800)
    }
}

private actor RequirementsChangingOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    let changedRequirements: OnboardingRequirements
    private var hasRejected = false
    private(set) var completionKeys: [IdempotencyKey] = []

    init(changedRequirements: OnboardingRequirements) {
        self.changedRequirements = changedRequirements
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        OnboardingServerState(
            completion: OnboardingCompletionState(completed: false, completedAt: nil),
            requirements: changedRequirements,
            acceptedActions: []
        )
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.requirementsChanged
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        completionKeys.append(idempotencyKey)
        if !hasRejected {
            hasRejected = true
            throw OnboardingRepositoryError.requirementsChanged
        }
        guard let objective = draft.objective, let persona = draft.persona else {
            throw OnboardingRepositoryError.invalidDraft
        }
        return OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: "2026-09-15T16:00:00.000Z",
            objective: objective,
            persona: persona,
            documentActions: (draft.documentActions ?? []).map { action in
                OnboardingAcceptedAction(
                    documentKey: action.documentKey,
                    version: action.version,
                    locale: action.locale,
                    contentHash: action.contentHash,
                    purpose: "synthetic_changed_requirement_test",
                    action: action.action,
                    actedAt: "2026-09-15T16:00:00.000Z"
                )
            }
        )
    }

    func clear(for userID: String) async throws {}
}

private actor ConcurrentlyCompletedOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    let completionError: OnboardingRepositoryError

    init(completionError: OnboardingRepositoryError = .requirementsChanged) {
        self.completionError = completionError
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        OnboardingServerState(
            completion: OnboardingCompletionState(
                completed: true,
                completedAt: "2026-09-15T16:00:00.000Z"
            ),
            requirements: .unavailable,
            acceptedActions: []
        )
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.requirementsChanged
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        throw completionError
    }

    func clear(for userID: String) async throws {}
}

private actor HistoricalReconsentOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    let authoritativeDraft: OnboardingDraft
    let changedRequirements: OnboardingRequirements

    init(
        authoritativeDraft: OnboardingDraft,
        changedRequirements: OnboardingRequirements
    ) {
        self.authoritativeDraft = authoritativeDraft
        self.changedRequirements = changedRequirements
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        OnboardingServerState(
            completion: OnboardingCompletionState(
                completed: false,
                completedAt: "2026-09-15T15:00:00.000Z"
            ),
            requirements: changedRequirements,
            acceptedActions: [],
            draft: authoritativeDraft
        )
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.alreadyCompleted
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        throw OnboardingRepositoryError.alreadyCompleted
    }

    func clear(for userID: String) async throws {}
}

private actor TransientReloadFailureOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    let changedRequirements: OnboardingRequirements
    private var loadCount = 0
    private(set) var completionKeys: [IdempotencyKey] = []

    init(changedRequirements: OnboardingRequirements) {
        self.changedRequirements = changedRequirements
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        loadCount += 1
        if loadCount == 1 {
            throw OnboardingRepositoryError.serviceUnavailable
        }
        return OnboardingServerState(
            completion: OnboardingCompletionState(completed: false, completedAt: nil),
            requirements: changedRequirements,
            acceptedActions: []
        )
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.requirementsChanged
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        completionKeys.append(idempotencyKey)
        throw OnboardingRepositoryError.requirementsChanged
    }

    func clear(for userID: String) async throws {}
}

private final class CompletionEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private actor CompletionOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    private let loadedDraft: OnboardingDraft?
    private let events: CompletionEventRecorder?
    private var results: [Result<Void, OnboardingRepositoryError>]
    private(set) var savedDrafts: [OnboardingDraft] = []
    private(set) var completedDrafts: [OnboardingDraft] = []
    private(set) var completionKeys: [IdempotencyKey] = []

    init(
        loadedDraft: OnboardingDraft? = nil,
        events: CompletionEventRecorder? = nil,
        results: [Result<Void, OnboardingRepositoryError>] = []
    ) {
        self.loadedDraft = loadedDraft
        self.events = events
        self.results = results
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        loadedDraft
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        savedDrafts.append(draft)
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        completedDrafts.append(draft)
        events?.record("complete")
        guard !results.isEmpty else { return }
        try results.removeFirst().get()
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        completionKeys.append(idempotencyKey)
        try await complete(draft, for: userID)
        guard let objective = draft.objective, let persona = draft.persona else {
            throw OnboardingRepositoryError.invalidDraft
        }
        return OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: "2026-09-15T15:00:00.000Z",
            objective: objective,
            persona: persona,
            documentActions: (draft.documentActions ?? []).map { action in
                OnboardingAcceptedAction(
                    documentKey: action.documentKey,
                    version: action.version,
                    locale: action.locale,
                    contentHash: action.contentHash,
                    purpose: "synthetic_completion_test",
                    action: action.action,
                    actedAt: "2026-09-15T15:00:00.000Z"
                )
            }
        )
    }

    func clear(for userID: String) async throws {}
}

private actor CompletionPersonaRepository: CoachPersonaRepository {
    private let events: CompletionEventRecorder?
    private var results: [Result<Void, CoachPersonaRepositoryError>]
    private(set) var writes: [CoachPersona] = []

    init(
        events: CompletionEventRecorder? = nil,
        results: [Result<Void, CoachPersonaRepositoryError>] = []
    ) {
        self.events = events
        self.results = results
    }

    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        writes.last
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {
        writes.append(persona)
        events?.record("persona")
        guard !results.isEmpty else { return }
        try results.removeFirst().get()
    }
}

private actor SuspendedCompletionOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var completeCount = 0

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        completeCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func clear(for userID: String) async throws {}

    func waitUntilCompleteSuspends() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeComplete() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CancellationIgnoringCompletionRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    private var continuation: CheckedContinuation<Void, Never>?

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func clear(for userID: String) async throws {}

    func waitUntilCompleteSuspends() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeComplete() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CancellationIgnoringFailingCompletionRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        E3Fixtures.choice
    }

    private var continuation: CheckedContinuation<Void, Never>?

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func clear(for userID: String) async throws {}

    func waitUntilCompleteSuspends() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeComplete() {
        continuation?.resume()
        continuation = nil
    }
}

private struct CompletionAuthenticationService: AuthenticationService {
    let session: AuthSession

    func restoreSession() async throws -> AuthSession? { session }
    func signIn(email: String, password: String) async throws -> AuthSession { session }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        .authenticated(session)
    }
    func confirmEmailForDevelopment() async throws -> AuthSession { session }
    func requestPasswordRecovery(email: String) async throws {}
    func signOut() async throws {}
}

@MainActor
private final class CompletionCancellationCheck {
    private var cancelled = false

    func cancel() {
        cancelled = true
    }

    func isCancelled() -> Bool {
        cancelled
    }
}

@MainActor
private final class CompletionSetupState {
    var finished = false
}

#if DEBUG
private enum CompletionCleanupMode: Sendable {
    case acknowledged, reconcile(OnboardingRepositoryError), invalidACK, uncertain
}
enum CompletionCleanupSignal: Sendable { case pending, unknown, mismatch, missing }
private struct CompletionCleanupCounts: Sendable {
    let drafts: [OnboardingDraft]
    let keys: [IdempotencyKey]
    let reads: Int
}
private actor CompletionCleanupObservedRepository: OnboardingRepository {
    nonisolated static let g1 = "2026-10-12T12:34:56.123456+03:00"
    nonisolated static let g2 = "2026-10-12T12:35:00.654321Z"
    nonisolated static var pendingScope: OnboardingBodyPhotoCleanupScope { .init(generation: g1, state: .pending) }
    private let mode: CompletionCleanupMode
    private let signal: CompletionCleanupSignal
    private let welcome: Bool
    private let events: CompletionEventRecorder?
    private let base: CompletionOnboardingRepository
    private var reads = 0

    init(mode: CompletionCleanupMode, signal: CompletionCleanupSignal, welcome: Bool,
        events: CompletionEventRecorder? = nil) {
        self.mode = mode; self.signal = signal; self.welcome = welcome; self.events = events
        let results: [Result<Void, OnboardingRepositoryError>]
        switch mode {
        case .reconcile(let error): results = [.failure(error)]
        case .uncertain: results = [.failure(.serviceUnavailable)]
        default: results = []
        }
        base = CompletionOnboardingRepository(events: events, results: results)
    }
    nonisolated static func currentScope(_ signal: CompletionCleanupSignal) -> OnboardingBodyPhotoCleanupScope? {
        switch signal {
        case .pending: pendingScope
        case .unknown: .init(generation: g1, state: .unknown)
        case .mismatch, .missing: nil
        }
    }
    private func rawScope() -> OnboardingBodyPhotoCleanupScope? {
        if case .mismatch = signal { return .init(generation: Self.g2, state: .pending) }
        return Self.currentScope(signal)
    }
    func counts() async -> CompletionCleanupCounts {
        .init(drafts: await base.completedDrafts, keys: await base.completionKeys, reads: reads)
    }
    func scoped(for userID: String) async throws -> any OnboardingRepository { self }
    func loadBodyPhotoCleanupScope(generation: String?) async throws -> OnboardingBodyPhotoCleanupScope? {
        // This callback packet must never create a new technical GET.
        throw OnboardingRepositoryError.serviceUnavailable
    }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { try await base.loadDraft(for: userID) }
    func loadState(for userID: String) async throws -> OnboardingServerState {
        reads += 1; events?.record("read")
        return OnboardingServerState(locale: "pt-BR",
            completion: .init(completed: true, completedAt: Self.g1), requirements: .unavailable,
            acceptedActions: [], draft: nil, bodyPhotoCleanup: rawScope())
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws { try await base.saveDraft(draft, for: userID) }
    func keepDraftOnDevice(_ draft: OnboardingDraft, for userID: String) async { await base.keepDraftOnDevice(draft, for: userID) }
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.serviceUnavailable // No synthetic default-ACK fallback.
    }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String,
        idempotencyKey: IdempotencyKey) async throws -> OnboardingCompletionAcknowledgement {
        let accepted = try await base.completeOfficial(draft, for: userID, idempotencyKey: idempotencyKey)
        let completed: Bool
        if case .invalidACK = mode { completed = false } else { completed = accepted.onboardingCompleted }
        return OnboardingCompletionAcknowledgement(onboardingCompleted: completed, completedAt: Self.g1,
            objective: accepted.objective, persona: accepted.persona, documentActions: accepted.documentActions,
            protocolWelcome: welcome ? ProtocolWelcome(protocol: try #require(accepted.objective), paragraphs: ["Synthetic original welcome"]) : nil,
            bodyPhotoCleanup: rawScope())
    }
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        try await base.checkEligibility(input, for: userID, idempotencyKey: idempotencyKey)
    }
    func clear(for userID: String) async throws { try await base.clear(for: userID) }
}
private actor CompletionCleanupTelemetry: TelemetryClient {
    private var events: [TelemetryEvent] = []
    func record(_ event: TelemetryEvent) async { events.append(event) }
    func snapshot() -> [TelemetryEvent] { events }
}
@MainActor
private final class CompletionCleanupOwnerFlag { var current = true }
#endif
