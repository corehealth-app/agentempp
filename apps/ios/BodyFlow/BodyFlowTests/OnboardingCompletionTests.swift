import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Onboarding completion")
struct OnboardingCompletionTests {
    @Test("missing persona blocks every persistence side effect")
    func missingPersonaBlocksCompletion() async {
        var draft = completeDraft()
        draft.persona = nil
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        let model = makeModel(
            draft: draft,
            onboarding: onboarding,
            persona: persona
        )

        await model.complete()

        #expect(model.validationIssues.contains(.personaRequired))
        #expect(model.step == .completion)
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
    }

    @Test(arguments: [DevelopmentConsentDocumentID.terms, .privacy])
    func missingEitherConsentBlocksCompletion(
        _ missingDocument: DevelopmentConsentDocumentID
    ) async {
        var draft = completeDraft()
        draft.consent = DevelopmentConsentAcceptance(
            documentIDs: DevelopmentConsentDocumentID.allCases.filter {
                $0 != missingDocument
            },
            acceptedAt: fixtureDate
        )
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        let model = makeModel(
            draft: draft,
            onboarding: onboarding,
            persona: persona
        )

        await model.complete()

        #expect(model.validationIssues.contains(.consentRequired))
        #expect(model.step == .completion)
        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
    }

    @Test("persona is persisted before onboarding completion and root callback")
    func persistsInApprovedOrder() async {
        let events = CompletionEventRecorder()
        let onboarding = CompletionOnboardingRepository(events: events)
        let persona = CompletionPersonaRepository(events: events)
        var callbackCount = 0
        let model = makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: {
                callbackCount += 1
                events.record("callback")
            }
        )

        await model.complete()

        #expect(events.values == ["persona", "complete", "callback"])
        #expect(callbackCount == 1)
        #expect(model.operationState == .idle)
    }

    @Test("completion cannot start before the review step")
    func completionRequiresReviewStep() async {
        var draft = completeDraft()
        draft.currentStep = .consent
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        let model = makeModel(
            draft: draft,
            onboarding: onboarding,
            persona: persona
        )

        await model.complete()

        #expect(await persona.writes.isEmpty)
        #expect(await onboarding.completedDrafts.isEmpty)
    }

    @Test("persona failure keeps completion visible and never calls complete")
    func personaFailureStopsCompletion() async {
        let onboarding = CompletionOnboardingRepository()
        let persona = CompletionPersonaRepository(
            results: [.failure(.serviceUnavailable)]
        )
        var callbackCount = 0
        let model = makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )

        await model.complete()

        #expect(model.step == .completion)
        #expect(model.operationState == .failed(.serviceUnavailable))
        #expect(await persona.writes == [.focus])
        #expect(await onboarding.completedDrafts.isEmpty)
        #expect(callbackCount == 0)
    }

    @Test("complete failure preserves consent and retry repeats safe writes")
    func retriesPartialCompletion() async {
        let onboarding = CompletionOnboardingRepository(
            results: [.failure(.serviceUnavailable), .success(())]
        )
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )

        await model.complete()

        #expect(model.step == .completion)
        #expect(model.draft.consent?.documentIDs == [.terms, .privacy])
        #expect(model.operationState == .failed(.serviceUnavailable))
        #expect(callbackCount == 0)

        await model.complete()

        #expect(await persona.writes == [.focus, .focus])
        #expect(await onboarding.completedDrafts.count == 2)
        #expect(callbackCount == 1)
        #expect(model.operationState == .idle)
    }

    @Test("double tap starts one final submission")
    func suppressesConcurrentCompletion() async {
        let onboarding = SuspendedCompletionOnboardingRepository()
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )
        let first = Task { await model.complete() }
        await onboarding.waitUntilCompleteSuspends()

        await model.complete()

        #expect(await persona.writes == [.focus])
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
        let model = makeModel(
            onboarding: onboarding,
            persona: persona,
            onCompleted: { callbackCount += 1 }
        )

        await model.complete()
        await model.complete()

        #expect(await persona.writes == [.focus])
        #expect(await onboarding.completedDrafts.count == 1)
        #expect(callbackCount == 1)
    }

    @Test("cancellation after a repository response prevents late transition")
    func cancellationPreventsLateTransition() async {
        let onboarding = CancellationIgnoringCompletionRepository()
        let persona = CompletionPersonaRepository()
        var callbackCount = 0
        let model = makeModel(
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
        let model = makeModel(onboarding: onboarding, persona: persona)
        let submission = Task { await model.complete() }
        await onboarding.waitUntilCompleteSuspends()

        submission.cancel()
        await onboarding.resumeComplete()
        await submission.value

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

    @Test("root completion requires the current confirmed session and matching user")
    func rootCompletionRequiresCurrentMatchingUser() async {
        let model = makeAppFlowModel(session: incompleteSession())
        await model.start()

        model.completeOnboarding(for: "another-user")

        #expect(model.state == .onboarding(
            userID: "fixture-user",
            step: .completion
        ))
        #expect(model.currentSession?.isOnboardingCompleted == false)

        model.completeOnboarding(for: "fixture-user")

        #expect(model.state == .authenticated(userID: "fixture-user"))
        #expect(model.currentSession?.isOnboardingCompleted == true)
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
            step: .completion
        ))
        #expect(model.currentSession?.isOnboardingCompleted == false)
    }

    private func makeModel(
        draft: OnboardingDraft? = nil,
        onboarding: any OnboardingRepository = CompletionOnboardingRepository(),
        persona: any CoachPersonaRepository = CompletionPersonaRepository(),
        onCompleted: @escaping @MainActor () -> Void = {}
    ) -> OnboardingFlowModel {
        OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: draft ?? completeDraft(),
            repository: onboarding,
            personaRepository: persona,
            onStepChanged: { _ in },
            onCompleted: onCompleted,
            now: { fixtureDate }
        )
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
        return draft
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
    private let loadedDraft: OnboardingDraft?
    private let events: CompletionEventRecorder?
    private var results: [Result<Void, OnboardingRepositoryError>]
    private(set) var completedDrafts: [OnboardingDraft] = []

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

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        completedDrafts.append(draft)
        events?.record("complete")
        guard !results.isEmpty else { return }
        try results.removeFirst().get()
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
