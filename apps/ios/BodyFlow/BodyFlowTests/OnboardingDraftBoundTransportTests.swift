import Foundation
import Testing

@testable import BodyFlow

/// URLSession's real MobileAPITransport, with only the HTTP peer replaced.
/// This is not a physical SDK/server/account E2E claim.
@MainActor
@Suite("Onboarding session-bound mobile transport", .serialized)
struct OnboardingDraftBoundTransportTests {
    @Test("a retained transport sends nothing under a later session's bearer", arguments: [false, true], [false, true])
    func aRetainedTransportCannotSendForANewerSession(returnToA: Bool, largerBodyCopy: Bool) async throws {
        let h = try await DraftBoundTransportHarness()
        defer { h.removeFolder() }
        let lease = try await h.lifecycle.leaseForRequest()
        let original = h.transport.scoped(to: lease)
        let retained = largerBodyCopy ? original.withResponseBodyLimit(1_024 * 1_024) : original
        try await h.lifecycle.switch(to: DraftBoundTransportHarness.record(DraftBoundTransportHarness.b, marker: "B"))
        if returnToA {
            try await h.lifecycle.switch(to: DraftBoundTransportHarness.record(DraftBoundTransportHarness.a, marker: "New A"))
        }

        await #expect(throws: MobileAPITransportError.sessionSuperseded) {
            let _: OnboardingEligibilityDecision = try await retained.execute(Self.request())
        }

        #expect(await h.peer.requests.isEmpty)
    }

    @Test("a retained repository sends no eligibility request under B or a later A", arguments: [false, true])
    func aRetainedRepositoryCannotRenewItsTransportScope(returnToA: Bool) async throws {
        let h = try await DraftBoundTransportHarness()
        defer { h.removeFolder() }
        let old = try await h.repository.scoped(for: DraftBoundTransportHarness.a)
        try await h.lifecycle.switch(to: DraftBoundTransportHarness.record(DraftBoundTransportHarness.b, marker: "B"))
        if returnToA {
            try await h.lifecycle.switch(to: DraftBoundTransportHarness.record(DraftBoundTransportHarness.a, marker: "New A"))
        }

        var failed = false
        do {
            _ = try await old.checkEligibility(
                OnboardingEligibilityInput(draft: E3Fixtures.draft()), for: DraftBoundTransportHarness.a,
                idempotencyKey: IdempotencyKey(validating: "draft-bound-old-eligibility")
            )
        } catch { failed = true }

        #expect(failed)
        #expect(await h.peer.requests.isEmpty)
    }

    @Test("a legitimate 401 refresh retries once with the rotated bearer in the same generation")
    func aBoundRepositoryAllowsTheSameSession401Refresh() async throws {
        let h = try await DraftBoundTransportHarness(firstResponseIsUnauthorized: true)
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: DraftBoundTransportHarness.a)
        let before = try await h.lifecycle.leaseForRequest()

        let answer = try await repository.checkEligibility(
            OnboardingEligibilityInput(draft: E3Fixtures.draft()), for: DraftBoundTransportHarness.a,
            idempotencyKey: IdempotencyKey(validating: "draft-bound-live-eligibility")
        )

        #expect(answer == E3Fixtures.choice)
        #expect(await h.remote.refreshCount == 1)
        let after = try await h.lifecycle.leaseForRequest()
        #expect(before.userID == after.userID)
        #expect(before.generation == after.generation)
        let requests = await h.peer.requests
        #expect(requests.count == 2)
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer \(DraftBoundTransportHarness.token(subject: DraftBoundTransportHarness.a, marker: "Initial"))",
            "Bearer \(DraftBoundTransportHarness.token(subject: DraftBoundTransportHarness.a, marker: "Refreshed"))"
        ])
        #expect(requests.allSatisfy { $0.url?.path == "/api/mobile/v1/onboarding/eligibility" })
    }

    @Test("eligibility 401 then invalidGrant clears the draft and background cannot recreate it")
    func eligibilityInvalidGrantThenBackgroundCannotRecreateTheDraft() async throws {
        let h = try await DraftBoundTransportHarness(
            firstResponseIsUnauthorized: true, invalidGrant: true
        )
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: DraftBoundTransportHarness.a)
        var draft = E3Fixtures.draft(step: .routine)
        draft.consent = nil
        let model = OnboardingFlowModel(
            userID: DraftBoundTransportHarness.a, initialDraft: draft, repository: repository,
            personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements, onStepChanged: { _ in }, onCompleted: {}
        )
        await model.keepDraftOnDevice()
        try #require(FileManager.default.fileExists(atPath: h.draftStore.fileURL.path))
        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            _ = try await repository.checkEligibility(
                OnboardingEligibilityInput(draft: E3Fixtures.draft()), for: DraftBoundTransportHarness.a,
                idempotencyKey: IdempotencyKey(validating: "draft-bound-invalid-grant")
            )
        }
        #expect(await h.remote.refreshCount == 1)
        #expect(await h.peer.requests.count == 1)
        try #require(await h.authStore.currentRecord() == nil)
        try #require(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
        try #require(model.isActive)

        await model.keepDraftOnDevice()

        #expect(!FileManager.default.fileExists(atPath: h.draftStore.root.path))
    }

    private static func request() throws -> MobileAPIRequest<OnboardingEligibilityDecision> {
        try MobileAPIRequest(
            method: .post, path: "/api/mobile/v1/onboarding/eligibility",
            body: JSONEncoder().encode(OnboardingEligibilityInput(draft: E3Fixtures.draft())),
            idempotencyKey: IdempotencyKey(validating: "draft-bound-transport-eligibility")
        )
    }
}

private struct DraftBoundTransportHarness: Sendable {
    static let a = "00000000-0000-4000-8000-0000000000a1"
    static let b = "00000000-0000-4000-8000-0000000000b2"
    let folder: URL
    let draftStore: OnboardingDeviceDraftStore
    let authStore: AuthenticationSessionStore
    let remote: DraftBoundAuthRemote
    let lifecycle: SessionLifecycleCoordinator
    let peer: DraftBoundHTTPPeer
    let transport: MobileAPITransport
    let repository: MobileOnboardingRepository

    init(firstResponseIsUnauthorized: Bool = false, invalidGrant: Bool = false) async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("draft-bound-http-\(UUID().uuidString)", isDirectory: true)
        draftStore = OnboardingDeviceDraftStore(directory: folder)
        authStore = AuthenticationSessionStore(
            secureStore: InMemorySecureStore(), now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await authStore.replace(with: Self.record(DraftBoundTransportHarness.a, marker: "Initial"))
        remote = DraftBoundAuthRemote(invalidGrant: invalidGrant)
        lifecycle = SessionLifecycleCoordinator(
            store: authStore, remote: remote,
            sensitiveStateClearer: OnboardingDeviceDraftSessionClearer(store: draftStore),
            refreshPolicy: SessionRefreshPolicy(now: { Date(timeIntervalSince1970: 1_000) }, leeway: 60)
        )
        peer = DraftBoundHTTPPeer(firstResponseIsUnauthorized: firstResponseIsUnauthorized)
        await DraftBoundURLProtocol.install(peer)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DraftBoundURLProtocol.self]
        transport = MobileAPITransport(
            configuration: try MobileAPIConfiguration(originString: "https://mobile.example.test"),
            sessionLifecycle: lifecycle, session: URLSession(configuration: configuration),
            clock: ContinuousClock()
        )
        repository = MobileOnboardingRepository(
            transport: transport, deviceDraft: draftStore, sessionLifecycle: lifecycle
        )
    }

    static func record(_ userID: String, marker: String) -> AuthenticationSessionRecord {
        AuthenticationSessionRecord(
            userID: userID, email: "synthetic@example.invalid", isEmailConfirmed: true,
            isOnboardingCompleted: false, accessToken: token(subject: userID, marker: marker),
            refreshToken: "synthetic-refresh-\(marker)", expiresAt: Date(timeIntervalSince1970: 1_500)
        )
    }
    static func token(subject: String, marker: String) -> String {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payload = base64URL(Data(#"{"sub":"\#(subject)","marker":"\#(marker)"}"#.utf8))
        return "\(header).\(payload).synthetic"
    }
    func removeFolder() { try? FileManager.default.removeItem(at: folder) }
}

private actor DraftBoundAuthRemote: SupabaseAuthRemoteOperating {
    let invalidGrant: Bool
    private(set) var refreshCount = 0
    init(invalidGrant: Bool) { self.invalidGrant = invalidGrant }
    func signIn(email: String, password: String) throws -> AuthenticationSessionRecord {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func signUp(email: String, password: String) throws -> SupabaseRemoteSignUpResult {
        throw SupabaseAuthRemoteError.requestFailed
    }
    func requestPasswordRecovery(email: String) throws {}
    func refresh(record: AuthenticationSessionRecord) throws -> AuthenticationSessionRecord {
        refreshCount += 1
        if invalidGrant { throw SupabaseAuthRemoteError.invalidGrant }
        return DraftBoundTransportHarness.record(record.userID, marker: "Refreshed")
    }
    func revokeCurrentSession(accessToken: String) -> RemoteRevocationOutcome { .confirmed }
}

private actor DraftBoundHTTPPeer {
    let firstResponseIsUnauthorized: Bool
    private(set) var requests: [URLRequest] = []
    init(firstResponseIsUnauthorized: Bool) { self.firstResponseIsUnauthorized = firstResponseIsUnauthorized }

    func respond(to request: URLRequest) throws -> (Int, Data) {
        requests.append(request)
        if firstResponseIsUnauthorized, requests.count == 1 {
            return (401, Data("{\"error\":{\"code\":\"unauthorized\",\"message\":\"Synthetic refusal\",\"request_id\":\"draft-bound-401\"}}".utf8))
        }
        let answer = try JSONEncoder().encode(E3Fixtures.choice)
        return (200, Data("{\"data\":".utf8) + answer + Data(
            ",\"meta\":{\"api_version\":\"v1\",\"request_id\":\"draft-bound-ok\"}}".utf8
        ))
    }
}

private actor DraftBoundProtocolRegistry {
    var peer: DraftBoundHTTPPeer?
    func install(_ peer: DraftBoundHTTPPeer) { self.peer = peer }
}

private final class DraftBoundURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = DraftBoundProtocolRegistry()
    private let lock = NSLock()
    private var operation: Task<Void, Never>?
    private var cancelled = false
    static func install(_ peer: DraftBoundHTTPPeer) async { await registry.install(peer) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "mobile.example.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Match the existing URLProtocol fixtures: capture a Sendable value
        // instead of transferring the Foundation subclass directly.
        let box = DraftBoundURLProtocolBox(instance: self)
        let task = Task { await box.instance.load() }
        lock.withLock {
            if cancelled { task.cancel() }
            operation = task
        }
    }

    private func load() async {
        do {
            try Task.checkCancellation()
            guard let peer = await Self.registry.peer else { throw URLError(.badServerResponse) }
            let (status, body) = try await peer.respond(to: request)
            try Task.checkCancellation()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {
        lock.withLock {
            cancelled = true
            operation?.cancel()
        }
    }
}

// Foundation marks URLProtocol unavailable for checked Sendable. The box is
// private to one loader task; the only cross-thread mutation (cancel/task)
// stays behind the instance's lock, as in the existing CoverURLProtocolBox.
private struct DraftBoundURLProtocolBox: @unchecked Sendable {
    let instance: DraftBoundURLProtocol
}
