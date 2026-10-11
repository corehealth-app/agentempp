import Foundation
import Testing

@testable import BodyFlow

/// Regression of the A4 HIGH: a user ID is not a live-session capability.
/// Every suspension below is continuation-controlled; no sleeps/retries.
@MainActor
@Suite("Device onboarding draft belongs to one session generation")
struct OnboardingDraftSessionOwnershipTests {
    private static let a = "00000000-0000-4000-8000-0000000000a1"
    private static let b = "00000000-0000-4000-8000-0000000000b2"

    @Test("invalidGrant clears the draft and a still-active model going to background cannot recreate it")
    func invalidGrantThenBackgroundDoesNotRecreateTheDraft() async throws {
        let h = try await DraftSessionHarness(userID: Self.a, refresh: .invalidGrant)
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: Self.a)
        let model = Self.model(userID: Self.a, repository: repository, name: "Before invalid grant")
        await model.keepDraftOnDevice()
        try #require(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))
        let lease = try await h.lifecycle.leaseForRequest()

        await #expect(throws: SessionLifecycleError.missingSession) {
            _ = try await h.lifecycle.refreshAfterUnauthorized(lease: lease)
        }
        try #require(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
        // AppFlowModel has not rendered the signed-out state yet.
        try #require(model.isActive)
        model.updateDisplayName("Old model entering background")
        await model.keepDraftOnDevice()

        #expect(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
        #expect(await h.authStore.currentRecord() == nil)
    }

    @Test("A to B to A does not give the first model the later session's capability")
    func aToBToADoesNotReviveTheFirstModel() async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let oldRepository = try await h.repository.scoped(for: Self.a)
        let old = Self.model(userID: Self.a, repository: oldRepository, name: "First A")
        await old.keepDraftOnDevice()
        try #require(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))

        try await h.lifecycle.switch(to: Self.record(Self.b, marker: "B"))
        try await h.lifecycle.switch(to: Self.record(Self.a, marker: "New A"))
        let newRepository = try await h.repository.scoped(for: Self.a)
        let fresh = Self.model(userID: Self.a, repository: newRepository, name: "Second A")
        await fresh.keepDraftOnDevice()
        let before = try Data(contentsOf: h.draftStore.fileURL)
        try #require(h.draftStore.load(for: Self.a)?.displayName == "Second A")

        old.updateDisplayName("Retired A overwrote the draft")
        await old.keepDraftOnDevice()

        #expect(try Data(contentsOf: h.draftStore.fileURL) == before)
        #expect(h.draftStore.load(for: Self.a)?.displayName == "Second A")
        await #expect(throws: SessionLifecycleError.sessionSuperseded) {
            _ = try await oldRepository.scoped(for: Self.a)
        }
    }

    @Test("an A load suspended in the server cannot remove a later draft", arguments: [false, true], [DraftSessionRead.unfinished, .finished, .serverDraft])
    func delayedLoadPreservesTheLaterDraft(returnToA: Bool, reply: DraftSessionRead) async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let old = try await h.repository.scoped(for: Self.a)
        await h.transport.suspendNextRead(reply)
        let read = Task { try await old.loadState(for: Self.a) }
        await h.transport.readGate.waitUntilEntered()
        let laterUser = returnToA ? Self.a : Self.b
        try await h.lifecycle.switch(to: Self.record(Self.b, marker: "B"))
        if returnToA { try await h.lifecycle.switch(to: Self.record(Self.a, marker: "New A")) }
        let later = try await h.repository.scoped(for: laterUser)
        await later.keepDraftOnDevice(Self.draft(name: "Later session"), for: laterUser)
        let before = try Data(contentsOf: h.draftStore.fileURL)

        await h.transport.readGate.open()
        _ = try? await read.value

        #expect(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))
        #expect((try? Data(contentsOf: h.draftStore.fileURL)) == before)
        #expect(h.draftStore.load(for: laterUser)?.displayName == "Later session")
    }

    @Test("an A completion suspended in the server cannot clear a later draft", arguments: [false, true])
    func delayedCompletionPreservesTheLaterDraft(returnToA: Bool) async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let old = try await h.repository.scoped(for: Self.a)
        await h.transport.suspendNextCompletion()
        let completion = Task {
            try await old.completeOfficial(
                E3Fixtures.draft(step: .completion), for: Self.a,
                idempotencyKey: try IdempotencyKey(validating: "draft-session-old-completion")
            )
        }
        await h.transport.completionGate.waitUntilEntered()
        let laterUser = returnToA ? Self.a : Self.b
        try await h.lifecycle.switch(to: Self.record(Self.b, marker: "B"))
        if returnToA { try await h.lifecycle.switch(to: Self.record(Self.a, marker: "New A")) }
        let later = try await h.repository.scoped(for: laterUser)
        await later.keepDraftOnDevice(Self.draft(name: "Later session"), for: laterUser)
        let before = try Data(contentsOf: h.draftStore.fileURL)

        await h.transport.completionGate.open()
        _ = try? await completion.value

        #expect(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))
        #expect((try? Data(contentsOf: h.draftStore.fileURL)) == before)
        #expect(h.draftStore.load(for: laterUser)?.displayName == "Later session")
    }

    @Test("an A clear scheduled before a switch cannot clear a later draft", arguments: [false, true])
    func delayedClearPreservesTheLaterDraft(returnToA: Bool) async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let old = try await h.repository.scoped(for: Self.a)
        let scheduled = DraftSessionContinuationGate()
        let clear = Task {
            await scheduled.enterAndWait()
            try await old.clear(for: Self.a)
        }
        await scheduled.waitUntilEntered()
        let laterUser = returnToA ? Self.a : Self.b
        try await h.lifecycle.switch(to: Self.record(Self.b, marker: "B"))
        if returnToA { try await h.lifecycle.switch(to: Self.record(Self.a, marker: "New A")) }
        let later = try await h.repository.scoped(for: laterUser)
        await later.keepDraftOnDevice(Self.draft(name: "Later session"), for: laterUser)
        let before = try Data(contentsOf: h.draftStore.fileURL)

        await scheduled.open()
        _ = try? await clear.value

        #expect(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))
        #expect((try? Data(contentsOf: h.draftStore.fileURL)) == before)
        #expect(h.draftStore.load(for: laterUser)?.displayName == "Later session")
    }

    @Test("a signed-out real graph cannot keep a draft just because a caller supplies a user ID")
    func theRealGraphRequiresAnAuthenticatedScope() async throws {
        let folder = DraftSessionHarness.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        let authStore = AuthenticationSessionStore(secureStore: InMemorySecureStore())
        let dependencies = try Self.realDependencies(authStore: authStore, draftStore: store)

        await dependencies.onboarding.keepDraftOnDevice(Self.draft(name: "Unauthenticated"), for: Self.a)

        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }

    @Test("the root hands its once-scoped repository to the model, which cannot revive after sign-out")
    func theRootPublishesItsScopedRepository() async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let root = AppFlowModel(
            authentication: DraftSessionAuthentication(lifecycle: h.lifecycle),
            onboarding: h.repository, persona: E3Persona(), telemetry: DisabledTelemetryClient()
        )
        await root.start()
        try #require(root.state == .onboarding(userID: Self.a, step: .welcome))
        let model = Self.model(
            userID: Self.a, repository: root.onboardingRepositoryForCurrentOwner, name: "Root owner"
        )
        await model.keepDraftOnDevice()
        try #require(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))
        _ = await h.lifecycle.signOut()

        await model.keepDraftOnDevice()

        #expect(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
    }

    @Test("a same-session refresh preserves the scope and the draft, including foreground editing")
    func refreshPreservesTheLiveScope() async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: Self.a)
        let model = Self.model(userID: Self.a, repository: repository, name: "Before refresh")
        await model.keepDraftOnDevice()
        let lease = try await h.lifecycle.leaseForRequest()
        let refreshed = try await h.lifecycle.refreshAfterUnauthorized(lease: lease)
        #expect(refreshed.generation == lease.generation)

        model.updateDisplayName("After refresh in foreground")
        await model.keepDraftOnDevice()

        #expect(h.draftStore.load(for: Self.a)?.displayName == "After refresh in foreground")
        #expect(try await repository.loadState(for: Self.a).draft?.displayName == "After refresh in foreground")
    }

    @Test("a cold relaunch with the persisted session resumes the draft and its kept step")
    func coldRelaunchWithSessionPreservesTheDraft() async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let first = try await h.repository.scoped(for: Self.a)
        await first.keepDraftOnDevice(Self.draft(name: "Cold relaunch"), for: Self.a)
        let before = try Data(contentsOf: h.draftStore.fileURL)
        let relaunched = SessionLifecycleCoordinator(
            store: h.authStore, remote: h.remote,
            sensitiveStateClearer: OnboardingDeviceDraftSessionClearer(store: h.draftStore),
            refreshPolicy: DraftSessionHarness.policy
        )
        let reopened = try await MobileOnboardingRepository(
            transport: DraftSessionTransport(), deviceDraft: h.draftStore,
            sessionLifecycle: relaunched
        ).scoped(for: Self.a)

        let state = try await reopened.loadState(for: Self.a)

        #expect(state.draft?.displayName == "Cold relaunch")
        #expect(state.draft?.currentStep == .routine)
        #expect(try Data(contentsOf: h.draftStore.fileURL) == before)
    }

    @Test("a cold relaunch after the durable invalidation marker clears the orphan", arguments: [false, true])
    func coldRelaunchAfterMarkerClearsTheOrphan(firstCallIsSwitch: Bool) async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let first = try await h.repository.scoped(for: Self.a)
        await first.keepDraftOnDevice(Self.draft(name: "Process ended before clearer"), for: Self.a)
        try #require(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))
        // Process ended after this durable marker, before any sensitive hook.
        _ = try await h.authStore.beginLocalInvalidation()
        let relaunched = SessionLifecycleCoordinator(
            store: h.authStore, remote: h.remote,
            sensitiveStateClearer: OnboardingDeviceDraftSessionClearer(store: h.draftStore),
            refreshPolicy: DraftSessionHarness.policy
        )

        if firstCallIsSwitch {
            try await relaunched.switch(to: Self.record(Self.a, marker: "New after marker"))
        } else {
            #expect(try await relaunched.restorePublicSession() == nil)
        }

        #expect(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
    }

    @Test("a failed completion and read preserve the current session's exact draft bytes")
    func failuresPreserveTheLiveDraft() async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: Self.a)
        await repository.keepDraftOnDevice(Self.draft(name: "Preserve on failure"), for: Self.a)
        let before = try Data(contentsOf: h.draftStore.fileURL)
        await h.transport.failReadAndCompletion()

        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            _ = try await repository.loadState(for: Self.a)
        }
        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            _ = try await repository.completeOfficial(
                E3Fixtures.draft(step: .completion), for: Self.a,
                idempotencyKey: try IdempotencyKey(validating: "draft-session-failed-completion")
            )
        }

        #expect(try Data(contentsOf: h.draftStore.fileURL) == before)
    }

    @Test("a live completion clears the draft, and the foreground model does not recreate it")
    func liveCompletionClearsTheDraft() async throws {
        let h = try await DraftSessionHarness(userID: Self.a)
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: Self.a)
        var draft = E3Fixtures.draft(step: .completion)
        draft.consent = nil
        let model = OnboardingFlowModel(
            userID: Self.a, initialDraft: draft, repository: repository,
            personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements, onStepChanged: { _ in }, onCompleted: {}
        )
        await prepareE3Review(model)
        try #require(model.step == .completion)
        try #require(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))

        await model.complete()
        #expect(!model.allowsDraftEditing)
        #expect(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
        await model.keepDraftOnDevice()
        #expect(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
    }

    private static func model(
        userID: String, repository: any OnboardingRepository, name: String
    ) -> OnboardingFlowModel {
        OnboardingFlowModel(
            userID: userID, initialDraft: draft(name: name), repository: repository,
            personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements, onStepChanged: { _ in }, onCompleted: {}
        )
    }

    private static func draft(name: String) -> OnboardingDraft {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        draft.displayName = name
        draft.consent = nil
        return draft
    }

    private static func record(_ userID: String, marker: String) -> AuthenticationSessionRecord {
        DraftSessionHarness.record(userID, marker: marker)
    }

    private static func realDependencies(
        authStore: AuthenticationSessionStore, draftStore: OnboardingDeviceDraftStore
    ) throws -> AppDependencies {
        AppDependencies.make(
            configuration: .resolve(arguments: [], buildFlavor: .release),
            mobileAPIConfigurationProvider: StaticMobileAPIConfigurationProvider(
                configuration: try MobileAPIConfiguration(originString: "https://mobile.example.test")
            ),
            supabaseAuthConfiguration: try SupabaseAuthConfiguration(
                originString: "https://project.example.test", key: "sb_publishable_synthetic"
            ),
            authenticationSessionStore: authStore,
            supabaseAuthFetch: { _ in throw URLError(.notConnectedToInternet) },
            onboardingDeviceDraft: draftStore
        )
    }
}

private struct DraftSessionHarness: Sendable {
    enum Refresh: Sendable, Equatable { case success, invalidGrant }
    let folder: URL
    let draftStore: OnboardingDeviceDraftStore
    let authStore: AuthenticationSessionStore
    let remote: DraftSessionAuthRemote
    let lifecycle: SessionLifecycleCoordinator
    let transport: DraftSessionTransport
    let repository: MobileOnboardingRepository

    static var policy: SessionRefreshPolicy {
        SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1_000) }, leeway: 60)
    }

    init(userID: String, refresh: Refresh = .success) async throws {
        folder = Self.makeFolder()
        draftStore = OnboardingDeviceDraftStore(directory: folder)
        authStore = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(), now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await authStore.replace(with: Self.record(userID, marker: "Initial"))
        remote = DraftSessionAuthRemote(outcome: refresh)
        lifecycle = SessionLifecycleCoordinator(
            store: authStore, remote: remote,
            sensitiveStateClearer: OnboardingDeviceDraftSessionClearer(store: draftStore),
            refreshPolicy: Self.policy
        )
        transport = DraftSessionTransport()
        repository = MobileOnboardingRepository(
            transport: transport, deviceDraft: draftStore, sessionLifecycle: lifecycle
        )
    }

    static func makeFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-session-ownership-\(UUID().uuidString)", isDirectory: true)
    }

    static func record(_ userID: String, marker: String) -> AuthenticationSessionRecord {
        AuthenticationSessionRecord(
            userID: userID, email: "synthetic@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: false, accessToken: token(subject: userID, marker: marker),
            refreshToken: "synthetic-refresh-\(marker)", expiresAt: Date(timeIntervalSince1970: 1_500)
        )
    }

    private static func token(subject: String, marker: String) -> String {
        let header = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8).base64EncodedString()
        let payload = Data(#"{"sub":"\#(subject)","marker":"\#(marker)"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload).synthetic-signature"
    }

    func removeFolder() { try? FileManager.default.removeItem(at: folder) }
}

enum DraftSessionRead: Sendable, Equatable { case unfinished, finished, serverDraft }

private actor DraftSessionTransport: MobileAPIExecuting {
    let readGate = DraftSessionContinuationGate()
    let completionGate = DraftSessionContinuationGate()
    private var nextRead: DraftSessionRead?
    private var nextCompletionIsSuspended = false
    private var fails = false

    func suspendNextRead(_ reply: DraftSessionRead) { nextRead = reply }
    func suspendNextCompletion() { nextCompletionIsSuspended = true }
    func failReadAndCompletion() { fails = true }

    func execute<Response: Decodable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> Response {
        if request.path.hasSuffix("/eligibility") { return E3Fixtures.choice as! Response }
        if fails { throw MobileAPITransportError.network }
        if request.method == .get {
            let reply = nextRead ?? .unfinished
            if nextRead != nil {
                nextRead = nil
                await readGate.enterAndWait()
            }
            let completed = reply == .finished
            return OnboardingServerState(
                completion: OnboardingCompletionState(
                    completed: completed, completedAt: completed ? "2026-10-11T15:00:00Z" : nil
                ),
                requirements: E3Fixtures.requirements, acceptedActions: [],
                draft: reply == .serverDraft ? E3Fixtures.draft(step: .consent) : nil
            ) as! Response
        }
        if nextCompletionIsSuspended {
            nextCompletionIsSuspended = false
            await completionGate.enterAndWait()
        }
        let draft = E3Fixtures.draft(step: .completion)
        let actedAt = "2026-10-11T15:00:00Z"
        return OnboardingCompletionAcknowledgement(
            onboardingCompleted: true, completedAt: actedAt,
            objective: draft.objective!, persona: draft.persona!,
            documentActions: (draft.documentActions ?? []).map {
                OnboardingAcceptedAction(
                    documentKey: $0.documentKey, version: $0.version, locale: $0.locale,
                    contentHash: $0.contentHash, purpose: E3Fixtures.document.purpose,
                    action: $0.action, actedAt: actedAt
                )
            }
        ) as! Response
    }
}

private actor DraftSessionContinuationGate {
    private var entered = false
    private var isOpen = false
    private var started: [CheckedContinuation<Void, Never>] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let listeners = started
        started.removeAll()
        listeners.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { started.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = waiting
        waiting.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor DraftSessionAuthRemote: SupabaseAuthRemoteOperating {
    let outcome: DraftSessionHarness.Refresh
    init(outcome: DraftSessionHarness.Refresh) { self.outcome = outcome }
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord {
        if outcome == .invalidGrant { throw SupabaseAuthRemoteError.invalidGrant }
        return DraftSessionHarness.record(record.userID, marker: "Refreshed")
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}

private struct DraftSessionAuthentication: AuthenticationService {
    let lifecycle: SessionLifecycleCoordinator
    func restoreSession() async throws -> AuthSession? { try await lifecycle.restorePublicSession() }
    func signIn(email: String, password: String) async throws -> AuthSession {
        throw AuthenticationError.serviceUnavailable
    }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult {
        throw AuthenticationError.serviceUnavailable
    }
    func confirmEmailForDevelopment() async throws -> AuthSession {
        throw AuthenticationError.serviceUnavailable
    }
    func requestPasswordRecovery(email: String) async throws {}
    func signOut() async throws { _ = await lifecycle.signOut() }
}
