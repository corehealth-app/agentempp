import Testing

@testable import BodyFlow

@MainActor
@Suite("App flow model")
struct AppFlowModelTests {
    @Test("fresh launch restores into sign in")
    func freshLaunch() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: nil),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            initialAuthOperationState: .failed(.operationUnavailable)
        )

        await model.start()

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
        #expect(model.presentationError == nil)
        #expect(model.authOperationState == .idle)
    }

    @Test("confirmed incomplete session resumes its saved onboarding step")
    func resumesOnboarding() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(loadedDraft: draft),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(model.state == .onboarding(userID: "fixture-user", step: .objective))
        #expect(model.currentSession == session)
    }

    @Test("A to B to A rejects old generation callbacks even when the identity returns")
    func returnedAccountRejectsOldOwner() async throws {
        let a = AuthSession(userID: "qa-a", email: "a@example.invalid", isEmailConfirmed: true, isOnboardingCompleted: false)
        let b = AuthSession(userID: "qa-b", email: "b@example.invalid", isEmailConfirmed: true, isOnboardingCompleted: false)
        let model = AppFlowModel(authentication: AuthenticationServiceSpy(restoredSession: a, signedInSession: b),
            onboarding: OnboardingRepositorySpy(loadedDraft: BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)),
            persona: CoachPersonaRepositorySpy(), telemetry: DisabledTelemetryClient())
        await model.start()
        let firstA = try #require(model.onboardingOwnerToken)
        await model.signOut()
        #expect(model.onboardingOwnerToken == nil)
        await model.signIn(email: b.email, password: "synthetic")
        let ownerB = try #require(model.onboardingOwnerToken)
        await model.signOut()
        await model.start()
        let returnedA = try #require(model.onboardingOwnerToken)
        #expect(returnedA.userID == firstA.userID)
        #expect(returnedA.restoreGeneration != firstA.restoreGeneration)
        model.updateOnboardingStep(.completion, ownerToken: firstA)
        model.completeOnboarding(ownerToken: firstA)
        model.completeOnboarding(ownerToken: ownerB)
        #expect(model.state == .onboarding(userID: a.userID, step: .routine))
        #expect(model.currentSession?.isOnboardingCompleted == false)
        model.updateOnboardingStep(.completion, ownerToken: returnedA)
        #expect(model.state == .onboarding(userID: a.userID, step: .completion))
        model.completeOnboarding(ownerToken: returnedA)
        #expect(model.state == .authenticated(userID: a.userID))
    }

    @Test("a successful restore retains the authoritative draft without a second read")
    func successfulRestoreRetainsAuthoritativeDraft() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        let onboarding = SequencedOnboardingRepository(
            results: [
                .success(draft),
                .failure(.serviceUnavailable),
            ]
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()
        var rootCoordinator = OnboardingRootCoordinator()
        rootCoordinator.synchronize(
            activeUserID: session.userID,
            restoredDraft: model.restoredOnboardingDraft,
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: InMemoryTelemetryClient(),
            onStepChanged: { _ in },
            onCompleted: {}
        )

        #expect(model.state == .onboarding(userID: session.userID, step: .objective))
        #expect(model.restoredOnboardingDraft == draft)
        #expect(rootCoordinator.flowModel?.draft == draft)
        #expect(!rootCoordinator.loadFailed)
        #expect(await onboarding.loadCount() == 1)
    }

    @Test("a failed authoritative restore can retry into the next saved draft")
    func failedRestoreRetriesAuthoritativeDraft() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        let onboarding = SequencedOnboardingRepository(
            results: [
                .failure(.storageUnavailable),
                .success(draft),
            ]
        )
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            telemetry: telemetry,
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()
        var rootCoordinator = OnboardingRootCoordinator()
        rootCoordinator.synchronize(
            activeUserID: session.userID,
            restoredDraft: model.restoredOnboardingDraft,
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: InMemoryTelemetryClient(),
            onStepChanged: { _ in },
            onCompleted: {}
        )

        #expect(model.state == .onboarding(userID: session.userID, step: .welcome))
        #expect(model.restoredOnboardingDraft == nil)
        #expect(model.presentationError == .storageUnavailable)
        #expect(rootCoordinator.flowModel == nil)
        #expect(rootCoordinator.loadFailed)
        #expect(await onboarding.loadCount() == 1)
        #expect(await telemetry.snapshot().isEmpty)

        await model.retryOnboardingRestore()
        rootCoordinator.synchronize(
            activeUserID: session.userID,
            restoredDraft: model.restoredOnboardingDraft,
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: InMemoryTelemetryClient(),
            onStepChanged: { _ in },
            onCompleted: {}
        )

        #expect(model.state == .onboarding(userID: session.userID, step: .routine))
        #expect(model.restoredOnboardingDraft == draft)
        #expect(model.presentationError == nil)
        #expect(rootCoordinator.flowModel?.draft == draft)
        #expect(!rootCoordinator.loadFailed)
        #expect(await onboarding.loadCount() == 2)
        #expect(await telemetry.snapshot() == [
            .onboardingStepViewed(.routine),
        ])
    }

    @Test("an empty authoritative restore renders a new welcome draft")
    func emptyRestoreRendersNewWelcomeDraft() async {
        let session = incompleteSession()
        let telemetry = InMemoryTelemetryClient()
        let onboarding = OnboardingRepositorySpy(loadedDraft: nil)
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            telemetry: telemetry,
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()
        var rootCoordinator = OnboardingRootCoordinator()
        rootCoordinator.synchronize(
            activeUserID: session.userID,
            restoredDraft: model.restoredOnboardingDraft,
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            developmentConsentAvailability: .syntheticDevelopment,
            telemetry: telemetry,
            onStepChanged: { _ in },
            onCompleted: {}
        )

        #expect(model.state == .onboarding(userID: session.userID, step: .welcome))
        #expect(model.restoredOnboardingDraft?.currentStep == .welcome)
        #expect(rootCoordinator.flowModel?.step == .welcome)
        #expect(!rootCoordinator.loadFailed)
        #expect(await telemetry.snapshot() == [
            .onboardingStepViewed(.welcome),
        ])
    }

    @Test("a retry resumed after sign out cannot resurrect onboarding")
    func staleRetryAfterSignOutIsIgnored() async {
        let session = incompleteSession()
        let initialDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        let staleDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        let onboarding = SuspendedOnboardingRepository(initialDraft: initialDraft)
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            telemetry: telemetry,
            developmentConsentAvailability: .syntheticDevelopment
        )
        await model.start()

        let retry = Task {
            await model.retryOnboardingRestore()
        }
        await onboarding.waitForLoadCount(2)
        await model.signOut()
        await onboarding.resumeLoad(2, with: .success(staleDraft))
        await retry.value

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
        #expect(model.restoredOnboardingDraft == nil)
        #expect(model.presentationError == nil)
        #expect(await telemetry.snapshot() == [
            .onboardingStepViewed(.objective),
            TelemetryEvent(name: .signOutCompleted),
        ])
    }

    @Test("a cancelled retry cannot publish a late draft or telemetry")
    func cancelledRetryIsIgnored() async {
        let session = incompleteSession()
        let initialDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        let lateDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        let onboarding = SuspendedOnboardingRepository(initialDraft: initialDraft)
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            telemetry: telemetry,
            developmentConsentAvailability: .syntheticDevelopment
        )
        await model.start()

        let retry = Task {
            await model.retryOnboardingRestore()
        }
        await onboarding.waitForLoadCount(2)
        retry.cancel()
        await onboarding.resumeLoad(2, with: .success(lateDraft))
        await retry.value

        #expect(model.state == .onboarding(userID: session.userID, step: .objective))
        #expect(model.restoredOnboardingDraft == initialDraft)
        #expect(model.presentationError == nil)
        #expect(await telemetry.snapshot() == [
            .onboardingStepViewed(.objective),
        ])
    }

    @Test("the latest concurrent retry is the only result allowed to publish")
    func latestRetryWins() async {
        let session = incompleteSession()
        let initialDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        let staleDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        let latestDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .persona)
        let onboarding = SuspendedOnboardingRepository(initialDraft: initialDraft)
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            telemetry: telemetry,
            developmentConsentAvailability: .syntheticDevelopment
        )
        await model.start()

        let firstRetry = Task {
            await model.retryOnboardingRestore()
        }
        await onboarding.waitForLoadCount(2)
        let latestRetry = Task {
            await model.retryOnboardingRestore()
        }
        await onboarding.waitForLoadCount(3)

        await onboarding.resumeLoad(3, with: .success(latestDraft))
        await latestRetry.value
        await onboarding.resumeLoad(2, with: .success(staleDraft))
        await firstRetry.value

        #expect(model.state == .onboarding(userID: session.userID, step: .persona))
        #expect(model.restoredOnboardingDraft == latestDraft)
        #expect(model.presentationError == nil)
        #expect(await telemetry.snapshot() == [
            .onboardingStepViewed(.objective),
            .onboardingStepViewed(.persona),
        ])
    }

    @Test("confirmed complete session restores into the authenticated shell")
    func restoresAuthenticatedSession() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(serverCompleted: true),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(model.currentSession == session)
    }

    @Test("server completion overrides a stale incomplete authentication snapshot")
    func serverCompletionIsAuthoritative() async {
        let session = incompleteSession()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(serverCompleted: true),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(model.state == .authenticated(userID: session.userID))
        #expect(model.currentSession?.isOnboardingCompleted == true)
    }

    @Test("server incomplete state overrides a stale completed authentication snapshot")
    func staleLocalCompletionCannotBypassServer() async {
        let session = AuthSession.completedFixture
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(serverCompleted: false),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(model.state == .onboarding(userID: session.userID, step: .welcome))
        #expect(model.currentSession?.isOnboardingCompleted == false)
    }

    @Test("server requirements and authoritative locale replace the device locale")
    func serverRequirementsAreRestored() async {
        let session = incompleteSession()
        let document = OnboardingLegalDocument(
            documentKey: "terms_of_service",
            version: "2026-09-15.1",
            locale: "en-US",
            body: "Synthetic terms for tests only",
            contentURL: nil,
            contentHash: String(repeating: "a", count: 64),
            purpose: "synthetic_terms_test",
            action: .acceptance,
            required: true,
            effectiveAt: "2026-09-15T15:00:00.000Z"
        )
        let requirements = OnboardingRequirements(
            available: true,
            blockingReason: nil,
            documents: [document]
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(
                locale: "en-US",
                requirements: requirements
            ),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(model.restoredOnboardingRequirements == requirements)
        #expect(model.restoredOnboardingDraft?.localeIdentifier == "en-US")
        #expect(model.state == .onboarding(userID: session.userID, step: .welcome))
    }

    @Test("a previously completed profile resumes directly at current legal consent")
    func staleLegalCompletionResumesAtConsent() async {
        let session = AuthSession.completedFixture
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .completion)
        draft.documentActions = [
            OnboardingDocumentAction(
                documentKey: "old_terms",
                version: "1",
                locale: "pt-BR",
                contentHash: String(repeating: "b", count: 64),
                action: .acceptance
            ),
        ]
        let requirements = OnboardingRequirements(
            available: true,
            blockingReason: nil,
            documents: [OnboardingLegalDocument(
                documentKey: "terms_of_service",
                version: "2026-09-15.2",
                locale: "pt-BR",
                body: "Updated synthetic terms for tests only",
                contentURL: nil,
                contentHash: String(repeating: "a", count: 64),
                purpose: "synthetic_reconsent_test",
                action: .acceptance,
                required: true,
                effectiveAt: "2026-09-15T16:00:00.000Z"
            )]
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(
                loadedDraft: draft,
                serverCompleted: false,
                completedAt: "2026-09-15T15:00:00.000Z",
                requirements: requirements
            ),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(model.state == .onboarding(userID: session.userID, step: .consent))
        #expect(model.restoredOnboardingDraft?.currentStep == .consent)
        #expect(model.restoredOnboardingDraft?.documentActions == nil)
        #expect(model.restoredOnboardingDraft?.displayName == "Fixture User")
        #expect(model.currentSession?.isOnboardingCompleted == false)
    }

    @Test("unconfirmed session awaits email confirmation")
    func awaitsEmailConfirmation() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: AuthSession(
                    userID: "fixture-user",
                    email: "fixture@example.invalid",
                    isEmailConfirmed: false,
                    isOnboardingCompleted: false
                )
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(
            model.state == .awaitingEmailConfirmation(
                email: "fixture@example.invalid"
            )
        )
    }

    @Test("restoration failure returns to sign in with a recoverable error")
    func handlesRestorationFailure() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                restoreError: .serviceUnavailable
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()

        #expect(model.state == .signedOut(.signIn))
        #expect(model.presentationError == .serviceUnavailable)
        #expect(model.authOperationState == .failed(.serviceUnavailable))
        #expect(model.currentSession == nil)
    }

    @Test("successful sign out clears the session and returns to sign in")
    func successfulSignOutClearsSessionAndReturnsToSignIn() async {
        let session = AuthSession.completedFixture
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: session),
            onboarding: OnboardingRepositorySpy(serverCompleted: true),
            persona: CoachPersonaRepositorySpy(),
            telemetry: telemetry,
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()
        await model.signOut()

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
        #expect(model.presentationError == nil)
        #expect(model.authOperationState == .idle)
        #expect(await telemetry.snapshot() == [
            TelemetryEvent(name: .signOutCompleted),
        ])
    }

    @Test("failed sign out preserves the authenticated state and session")
    func failedSignOutPreservesAuthenticatedStateAndSession() async {
        let session = AuthSession.completedFixture
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: session,
                signOutError: .serviceUnavailable
            ),
            onboarding: OnboardingRepositorySpy(serverCompleted: true),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()
        await model.signOut()

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(model.currentSession == session)
        #expect(model.presentationError == .serviceUnavailable)
        #expect(model.authOperationState == .failed(.serviceUnavailable))
    }

    @Test("Keychain failure cannot publish a false signed-out state")
    func keychainFailurePreservesOnboardingStateAndSession() async {
        let session = incompleteSession()
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: session,
                signOutError: .storageUnavailable
            ),
            onboarding: OnboardingRepositorySpy(loadedDraft: draft),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.start()
        await model.signOut()

        #expect(model.state == .onboarding(userID: "fixture-user", step: .routine))
        #expect(model.currentSession == session)
        #expect(model.restoredOnboardingDraft == draft)
        #expect(model.presentationError == .storageUnavailable)
        #expect(model.authOperationState == .failed(.storageUnavailable))
    }

    @Test("failed sign out does not cancel an in-flight onboarding retry")
    func failedSignOutPreservesInFlightOnboardingRetry() async {
        let session = incompleteSession()
        let initialDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        let resumedDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        let onboarding = SuspendedOnboardingRepository(initialDraft: initialDraft)
        let telemetry = InMemoryTelemetryClient()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: session,
                signOutError: .serviceUnavailable
            ),
            onboarding: onboarding,
            persona: CoachPersonaRepositorySpy(),
            telemetry: telemetry,
            developmentConsentAvailability: .syntheticDevelopment
        )
        await model.start()

        let retry = Task {
            await model.retryOnboardingRestore()
        }
        await onboarding.waitForLoadCount(2)

        await model.signOut()

        #expect(model.state == .onboarding(userID: "fixture-user", step: .objective))
        #expect(model.currentSession == session)
        #expect(model.presentationError == .serviceUnavailable)

        await onboarding.resumeLoad(2, with: .success(resumedDraft))
        await retry.value

        #expect(model.state == .onboarding(userID: "fixture-user", step: .routine))
        #expect(model.currentSession == session)
        #expect(model.restoredOnboardingDraft == resumedDraft)
        #expect(await telemetry.snapshot() == [
            .onboardingStepViewed(.objective),
            .onboardingStepViewed(.routine),
        ])
    }

    @Test("cancelled restoration never publishes an authenticated destination")
    func cancelledRestorationDoesNotNavigate() async {
        let cancellation = CancellationCheckSpy()
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: AuthSession(
                    userID: "fixture-user",
                    email: "fixture@example.invalid",
                    isEmailConfirmed: true,
                    isOnboardingCompleted: true
                )
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            cancellationCheck: cancellation.isCancelled
        )

        await model.start()

        #expect(model.state == .launching)
        #expect(model.currentSession == nil)
    }

    @Test("authentication destinations are driven by explicit commands")
    func authenticationDestinations() async {
        let model = makeModel()
        await model.start()

        await model.showSignUp()
        #expect(model.state == .signedOut(.signUp))

        await model.showPasswordRecovery()
        #expect(model.state == .signedOut(.passwordRecovery))

        await model.showSignIn()
        #expect(model.state == .signedOut(.signIn))
    }

    @Test("sign in resumes onboarding for an incomplete session")
    func signInResumesOnboarding() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                signedInSession: session
            ),
            onboarding: OnboardingRepositorySpy(
                loadedDraft: BodyFlowTestFixtures.onboardingDraft(
                    currentStep: .routine
                )
            ),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.signIn(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(model.state == .onboarding(userID: "fixture-user", step: .routine))
        #expect(model.currentSession == session)
        #expect(model.authOperationState == .idle)
    }

    @Test("sign in opens the shell for a completed session")
    func signInOpensAuthenticatedShell() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: true
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                signedInSession: session
            ),
            onboarding: OnboardingRepositorySpy(serverCompleted: true),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.signIn(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(model.currentSession == session)
        #expect(model.authOperationState == .idle)
    }

    @Test("sign up success waits for email confirmation")
    func signUpAwaitsConfirmation() async {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                signUpResult: .confirmationRequired(
                    email: "fixture@example.invalid"
                )
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.signUp(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(
            model.state == .awaitingEmailConfirmation(
                email: "fixture@example.invalid"
            )
        )
        #expect(model.currentSession == nil)
        #expect(model.authOperationState == .idle)
    }

    @Test("development confirmation enters onboarding")
    func developmentConfirmationEntersOnboarding() async {
        let session = AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(
                restoredSession: nil,
                confirmedSession: session
            ),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )

        await model.confirmEmailForDevelopment()

        #expect(model.state == .onboarding(userID: "fixture-user", step: .welcome))
        #expect(model.currentSession == session)
        #expect(model.authOperationState == .idle)
    }

    @Test("a persisted onboarding step updates the root state for the same user")
    func updatesPersistedOnboardingStep() {
        let model = AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: nil),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            initialState: .onboarding(userID: "fixture-user", step: .welcome)
        )

        model.updateOnboardingStep(.bodyData)

        #expect(model.state == .onboarding(
            userID: "fixture-user",
            step: .bodyData
        ))
    }

    @Test("recovery success discloses no account state")
    func recoveryUsesNeutralConfirmation() async {
        let model = makeModel()
        await model.start()
        await model.showPasswordRecovery()

        await model.requestPasswordRecovery(
            email: "fixture@example.invalid"
        )

        #expect(model.state == .signedOut(.passwordRecovery))
        #expect(model.currentSession == nil)
        #expect(model.presentationError == nil)
        #expect(model.authOperationState == .recoveryConfirmation)
    }

    @Test("a second submit is suppressed while sign in is in flight")
    func suppressesDoubleTap() async {
        let authentication = SuspendedAuthenticationService()
        let model = AppFlowModel(
            authentication: authentication,
            onboarding: OnboardingRepositorySpy(serverCompleted: true),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )
        await model.start()

        let firstSubmission = Task {
            await model.signIn(
                email: "fixture@example.invalid",
                password: "local-pass"
            )
        }
        await authentication.waitUntilSignInSuspends()

        await model.signIn(
            email: "fixture@example.invalid",
            password: "local-pass"
        )

        #expect(await authentication.signInCount() == 1)
        #expect(model.authOperationState == .submitting)

        await authentication.resumeSignIn(returning: .completedFixture)
        await firstSubmission.value

        #expect(model.state == .authenticated(userID: "fixture-user"))
    }

    @Test("cancelled submission ignores a late successful response")
    func cancellationPreventsLateTransition() async {
        let authentication = SuspendedAuthenticationService()
        let model = AppFlowModel(
            authentication: authentication,
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )
        await model.start()

        let submission = Task {
            await model.signIn(
                email: "fixture@example.invalid",
                password: "local-pass"
            )
        }
        await authentication.waitUntilSignInSuspends()

        submission.cancel()
        await authentication.resumeSignIn(returning: .completedFixture)
        await submission.value

        #expect(model.state == .signedOut(.signIn))
        #expect(model.currentSession == nil)
        #expect(model.authOperationState == .idle)
    }

    private func makeModel() -> AppFlowModel {
        AppFlowModel(
            authentication: AuthenticationServiceSpy(restoredSession: nil),
            onboarding: OnboardingRepositorySpy(),
            persona: CoachPersonaRepositorySpy(),
            telemetry: InMemoryTelemetryClient(),
            developmentConsentAvailability: .syntheticDevelopment
        )
    }

    private func incompleteSession() -> AuthSession {
        AuthSession(
            userID: "fixture-user",
            email: "fixture@example.invalid",
            isEmailConfirmed: true,
            isOnboardingCompleted: false
        )
    }
}

private struct AuthenticationServiceSpy: AuthenticationService {
    let restoredSession: AuthSession?
    let restoreError: AuthenticationError?
    let signedInSession: AuthSession?
    let signUpResult: AuthSignUpResult?
    let confirmedSession: AuthSession?
    let recoveryError: AuthenticationError?
    let signOutError: AuthenticationError?

    init(
        restoredSession: AuthSession?,
        restoreError: AuthenticationError? = nil,
        signedInSession: AuthSession? = nil,
        signUpResult: AuthSignUpResult? = nil,
        confirmedSession: AuthSession? = nil,
        recoveryError: AuthenticationError? = nil,
        signOutError: AuthenticationError? = nil
    ) {
        self.restoredSession = restoredSession
        self.restoreError = restoreError
        self.signedInSession = signedInSession
        self.signUpResult = signUpResult
        self.confirmedSession = confirmedSession
        self.recoveryError = recoveryError
        self.signOutError = signOutError
    }

    func restoreSession() async throws -> AuthSession? {
        if let restoreError {
            throw restoreError
        }
        return restoredSession
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        guard let signedInSession else {
            throw AuthenticationError.operationUnavailable
        }
        return signedInSession
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        guard let signUpResult else {
            throw AuthenticationError.operationUnavailable
        }
        return signUpResult
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        guard let confirmedSession else {
            throw AuthenticationError.operationUnavailable
        }
        return confirmedSession
    }

    func requestPasswordRecovery(email: String) async throws {
        if let recoveryError {
            throw recoveryError
        }
    }

    func signOut() async throws {
        if let signOutError {
            throw signOutError
        }
    }
}

private actor SuspendedAuthenticationService: AuthenticationService {
    private var continuation: CheckedContinuation<AuthSession, any Error>?
    private var count = 0

    func restoreSession() async throws -> AuthSession? {
        nil
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        count += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        throw AuthenticationError.operationUnavailable
    }

    func confirmEmailForDevelopment() async throws -> AuthSession {
        throw AuthenticationError.operationUnavailable
    }

    func requestPasswordRecovery(email: String) async throws {
        throw AuthenticationError.operationUnavailable
    }

    func signOut() async throws {}

    func waitUntilSignInSuspends() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func signInCount() -> Int {
        count
    }

    func resumeSignIn(returning session: AuthSession) {
        continuation?.resume(returning: session)
        continuation = nil
    }
}

private extension AuthSession {
    static let completedFixture = AuthSession(
        userID: "fixture-user",
        email: "fixture@example.invalid",
        isEmailConfirmed: true,
        isOnboardingCompleted: true
    )
}

private struct OnboardingRepositorySpy: OnboardingRepository {
    let loadedDraft: OnboardingDraft?
    let locale: String
    let serverCompleted: Bool
    let completedAt: String?
    let requirements: OnboardingRequirements

    init(
        loadedDraft: OnboardingDraft? = nil,
        locale: String = "pt-BR",
        serverCompleted: Bool = false,
        completedAt: String? = nil,
        requirements: OnboardingRequirements = .unavailable
    ) {
        self.loadedDraft = loadedDraft
        self.locale = locale
        self.serverCompleted = serverCompleted
        self.completedAt = completedAt ?? (serverCompleted ? "2026-09-15T15:00:00.000Z" : nil)
        self.requirements = requirements
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        loadedDraft
    }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        OnboardingServerState(
            locale: locale,
            completion: OnboardingCompletionState(
                completed: serverCompleted,
                completedAt: completedAt
            ),
            requirements: requirements,
            acceptedActions: [],
            draft: loadedDraft
        )
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}

    func clear(for userID: String) async throws {}
}

private actor SequencedOnboardingRepository: OnboardingRepository {
    private var results: [Result<OnboardingDraft?, OnboardingRepositoryError>]
    private var loadCallCount = 0

    init(results: [Result<OnboardingDraft?, OnboardingRepositoryError>]) {
        self.results = results
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        loadCallCount += 1
        guard !results.isEmpty else {
            throw OnboardingRepositoryError.serviceUnavailable
        }
        return try results.removeFirst().get()
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}

    func clear(for userID: String) async throws {}

    func loadCount() -> Int {
        loadCallCount
    }
}

private actor SuspendedOnboardingRepository: OnboardingRepository {
    private let initialDraft: OnboardingDraft
    private var loadCallCount = 0
    private var continuations: [
        Int: CheckedContinuation<OnboardingDraft?, any Error>
    ] = [:]

    init(initialDraft: OnboardingDraft) {
        self.initialDraft = initialDraft
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        loadCallCount += 1
        let call = loadCallCount
        if call == 1 {
            return initialDraft
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}

    func clear(for userID: String) async throws {}

    func waitForLoadCount(_ expectedCount: Int) async {
        while loadCallCount < expectedCount {
            await Task.yield()
        }
    }

    func resumeLoad(
        _ call: Int,
        with result: Result<OnboardingDraft?, OnboardingRepositoryError>
    ) {
        guard let continuation = continuations.removeValue(forKey: call) else {
            return
        }
        continuation.resume(with: result)
    }
}

private struct CoachPersonaRepositorySpy: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? {
        nil
    }

    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}

@MainActor
private final class CancellationCheckSpy {
    private var callCount = 0

    func isCancelled() -> Bool {
        defer { callCount += 1 }
        return callCount > 0
    }
}
