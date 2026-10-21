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

    @Test("begin refreshes once without changing Q, body or session generation")
    func beginRefreshKeepsOriginalPreparation() async throws {
        let qText = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let q = try #require(UUID(uuidString: qText))
        let id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let key = "osc1:cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let reply = try JSONSerialization.data(withJSONObject: [
            "data": ["completion_intent": ["protocol": "osc1", "preparation_id": qText,
                "intent_id": id, "request_key": key]],
            "meta": ["api_version": "v1", "request_id": "intent-ok"]
        ])
        let h = try await DraftBoundTransportHarness(script: [
            .http(401, Data(#"{"error":{"code":"unauthorized","message":"Synthetic refusal","request_id":"intent-401"}}"#.utf8)),
            .http(200, reply)
        ])
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: DraftBoundTransportHarness.a)
        let before = try await h.lifecycle.leaseForRequest()

        let result = try await repository.beginCompletionIntent(for: DraftBoundTransportHarness.a, preparationID: q)

        #expect(result.preparationID == q)
        #expect(result.intentID.uuidString.lowercased() == id)
        #expect(result.requestKey == (try IdempotencyKey(validating: key)))
        #expect(await h.remote.refreshCount == 1)
        let after = try await h.lifecycle.leaseForRequest()
        #expect(before.userID == after.userID)
        #expect(before.generation == after.generation)
        let requests = await h.peer.requests
        let bodies = await h.peer.bodies
        try #require(requests.count == 2)
        try #require(bodies.count == 2)
        let first = try #require(bodies[0])
        let second = try #require(bodies[1])
        #expect(first == second)
        let object = try JSONSerialization.jsonObject(with: first)
        #expect(object as? [String: String] == ["preparation_id": qText])
        #expect(requests.allSatisfy {
            $0.httpMethod == "POST"
                && $0.url?.absoluteString == "https://mobile.example.test/api/mobile/v1/onboarding/completion-intent"
                && $0.value(forHTTPHeaderField: "Idempotency-Key") == qText
        })
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer \(DraftBoundTransportHarness.token(subject: DraftBoundTransportHarness.a, marker: "Initial"))",
            "Bearer \(DraftBoundTransportHarness.token(subject: DraftBoundTransportHarness.a, marker: "Refreshed"))"
        ])
        let requestID = try #require(requests[0].value(forHTTPHeaderField: "X-Request-Id"))
        #expect(!requestID.isEmpty)
        #expect(requests[1].value(forHTTPHeaderField: "X-Request-Id") == requestID)
    }

    @Test("uncertain begin neither retries nor resolves", arguments: [false, true])
    func uncertainBeginSendsOnce(timeout: Bool) async throws {
        let qText = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let q = try #require(UUID(uuidString: qText))
        let outcome: DraftBoundOutcome = timeout ? .timeout : .http(503,
            Data(#"{"error":{"code":"unavailable","message":"Synthetic refusal","request_id":"intent-503"}}"#.utf8))
        let h = try await DraftBoundTransportHarness(script: [outcome])
        defer { h.removeFolder() }
        let repository = try await h.repository.scoped(for: DraftBoundTransportHarness.a)
        let before = try await h.lifecycle.leaseForRequest()

        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            _ = try await repository.beginCompletionIntent(for: DraftBoundTransportHarness.a, preparationID: q)
        }

        let requests = await h.peer.requests
        let bodies = await h.peer.bodies
        try #require(requests.count == 1)
        try #require(bodies.count == 1)
        let body = try #require(bodies[0])
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/api/mobile/v1/onboarding/completion-intent")
        #expect(requests[0].value(forHTTPHeaderField: "Idempotency-Key") == qText)
        let object = try JSONSerialization.jsonObject(with: body)
        #expect(object as? [String: String] == ["preparation_id": qText])
        #expect(await h.remote.refreshCount == 0)
        let after = try await h.lifecycle.leaseForRequest()
        #expect(before.userID == after.userID)
        #expect(before.generation == after.generation)
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

    init(firstResponseIsUnauthorized: Bool = false, invalidGrant: Bool = false,
         script: [DraftBoundOutcome]? = nil) async throws {
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
        peer = DraftBoundHTTPPeer(firstResponseIsUnauthorized: firstResponseIsUnauthorized, script: script)
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

private enum DraftBoundOutcome: Sendable {
    case http(Int, Data)
    case timeout
}
private enum DraftBoundPeerError: Error { case scriptExhausted, bodyReadFailed, bodyTooLarge }

private actor DraftBoundHTTPPeer {
    let firstResponseIsUnauthorized: Bool
    let script: [DraftBoundOutcome]?
    private(set) var requests: [URLRequest] = []
    private(set) var bodies: [Data?] = []
    init(firstResponseIsUnauthorized: Bool, script: [DraftBoundOutcome]? = nil) {
        self.firstResponseIsUnauthorized = firstResponseIsUnauthorized
        self.script = script
    }

    func respond(to request: URLRequest) throws -> (Int, Data) {
        requests.append(request)
        if let script {
            bodies.append(try Self.captureBody(request))
            guard requests.count <= script.count else { throw DraftBoundPeerError.scriptExhausted }
            switch script[requests.count - 1] {
            case let .http(status, body): return (status, body)
            case .timeout: throw URLError(.timedOut)
            }
        }
        if firstResponseIsUnauthorized, requests.count == 1 {
            return (401, Data("{\"error\":{\"code\":\"unauthorized\",\"message\":\"Synthetic refusal\",\"request_id\":\"draft-bound-401\"}}".utf8))
        }
        let answer = try JSONEncoder().encode(E3Fixtures.choice)
        return (200, Data("{\"data\":".utf8) + answer + Data(
            ",\"meta\":{\"api_version\":\"v1\",\"request_id\":\"draft-bound-ok\"}}".utf8
        ))
    }

    private static func captureBody(_ request: URLRequest) throws -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw DraftBoundPeerError.bodyReadFailed }
            if count == 0 { break }
            guard result.count + count <= 8192 else { throw DraftBoundPeerError.bodyTooLarge }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
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
