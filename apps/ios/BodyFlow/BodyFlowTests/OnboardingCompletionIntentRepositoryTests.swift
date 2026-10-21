import Foundation
import Testing

@testable import BodyFlow

@Suite("Signup completion intent repository")
struct OnboardingCompletionIntentRepositoryTests {
    @Test("Begin carries only Q in its body and the same header")
    func beginWire() async throws {
        let peer = IntentRepositoryPeer(response: try F.intentResponse())
        let intent = try await MobileOnboardingRepository(transport: peer)
            .beginCompletionIntent(for: F.owner, preparationID: F.q)
        #expect(intent.matches(preparationID: F.q))
        let requests = await peer.requests
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/onboarding/completion-intent")
        #expect(request.queryItems.isEmpty)
        #expect(request.idempotency == .required(try IdempotencyKey(validating: F.q.uuidString.lowercased())))
        let body = try #require(request.body)
        let object = try JSONSerialization.jsonObject(with: body)
        #expect(object as? [String: String] == ["preparation_id": F.q.uuidString.lowercased()])
    }

    @Test("Resolve reads Q without a body, mutation key or automatic begin")
    func resolveWire() async throws {
        let peer = IntentRepositoryPeer(response: Data("{\"completion_intent\":null}".utf8))
        let intent = try await MobileOnboardingRepository(transport: peer)
            .resolveCompletionIntent(for: F.owner, preparationID: F.q)
        #expect(intent == nil)
        let requests = await peer.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/onboarding/completion-intent")
        #expect(request.queryItems == [URLQueryItem(name: "preparation_id", value: F.q.uuidString.lowercased())])
        #expect(request.body == nil)
        #expect(request.idempotency == .notRequired)
    }

    @Test("A positive receipt must belong to the requested Q", arguments: [false, true])
    func mismatchedPreparation(resolve: Bool) async throws {
        let peer = IntentRepositoryPeer(response: try F.intentResponse(q: F.id))
        let repo = MobileOnboardingRepository(transport: peer)
        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            if resolve { _ = try await repo.resolveCompletionIntent(for: F.owner, preparationID: F.q) }
            else { _ = try await repo.beginCompletionIntent(for: F.owner, preparationID: F.q) }
        }
        #expect(await peer.requests.count == 1)
    }

    @Test("An uncertain begin never repeats itself or resolves automatically", arguments: [
        MobileAPITransportError.timeout, .network, .server(status: 503, code: "unavailable", requestID: nil)
    ])
    func uncertainBeginDoesNotRetry(_ error: MobileAPITransportError) async throws {
        let peer = IntentRepositoryPeer(response: Data(), failure: error)
        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            _ = try await MobileOnboardingRepository(transport: peer).beginCompletionIntent(for: F.owner, preparationID: F.q)
        }
        #expect(await peer.requests.count == 1)
    }

    @Test("Versioned completion adds only its two markers to the original clinical body")
    func completionPreservesOriginalBody() async throws {
        let peer = IntentRepositoryPeer(response: try F.ack())
        let repo = MobileOnboardingRepository(transport: peer)
        let draft = E3Fixtures.draft(step: .completion)
        _ = try await repo.completeOfficial(draft, for: F.owner, idempotencyKey: IdempotencyKey(validating: "legacy-body-comparison"))
        let intent = try F.intent()
        _ = try await repo.completeOfficial(draft, for: F.owner, completionIntent: intent)
        let requests = await peer.requests
        #expect(requests.count == 2)
        let originalData = try #require(requests.first?.body)
        let versionedData = try #require(requests.last?.body)
        let originalObject = try JSONSerialization.jsonObject(with: originalData)
        let versionedObject = try JSONSerialization.jsonObject(with: versionedData)
        let original = try #require(originalObject as? [String: Any])
        var versioned = try #require(versionedObject as? [String: Any])
        #expect(requests.last?.idempotency == .required(intent.requestKey))
        #expect(versioned.removeValue(forKey: "signup_strength_protocol") as? String == "osc1")
        #expect(versioned.removeValue(forKey: "completion_intent_id") as? String == F.id.uuidString.lowercased())
        #expect(NSDictionary(dictionary: versioned) == NSDictionary(dictionary: original))
    }

    @Test("Reserved keys cannot be accidentally sent by the legacy method", arguments: [
        "osc1:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "OSC2:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    ])
    func legacyCannotStripReceipt(_ key: String) async throws {
        let peer = IntentRepositoryPeer(response: try F.ack())
        await #expect(throws: OnboardingRepositoryError.invalidDraft) {
            _ = try await MobileOnboardingRepository(transport: peer).completeOfficial(
                E3Fixtures.draft(step: .completion), for: F.owner, idempotencyKey: IdempotencyKey(validating: key)
            )
        }
        #expect(await peer.requests.isEmpty)
    }

    @Test("New authority conflicts remain typed for official reconciliation", arguments: [
        "mobile_signup_strength_stale_epoch", "mobile_signup_completion_invalid_intent"
    ])
    func authorityConflict(_ code: String) async throws {
        let peer = IntentRepositoryPeer(response: Data(), failure: .conflict(code: code, requestID: nil))
        await #expect(throws: OnboardingRepositoryError.completionIntentChanged) {
            _ = try await MobileOnboardingRepository(transport: peer).beginCompletionIntent(for: F.owner, preparationID: F.q)
        }
    }

    @Test("Resuming an on-device draft preserves the server capability")
    func resumedDraftKeepsCapability() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("intent-resume-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnboardingDeviceDraftStore(directory: directory)
        let kept = E3Fixtures.draft(step: .routine)
        store.save(kept, for: F.owner)
        let state = OnboardingServerState(completion: .init(completed: false, completedAt: nil),
            requirements: E3Fixtures.requirements, acceptedActions: [], signupCompletion: .osc1)
        let peer = IntentRepositoryPeer(response: try JSONEncoder().encode(state))
        let repo = try await MobileOnboardingRepository(transport: peer, deviceDraft: store,
            sessionLifecycle: IntentRepositoryLifecycle()).scoped(for: F.owner)
        let restored = try await repo.loadState(for: F.owner)
        #expect(restored.draft != nil)
        #expect(restored.signupCompletion == .osc1)
    }

    @Test("A retained repository cannot begin, resolve or complete under B or later A",
          arguments: ["begin", "resolve", "complete"], [false, true])
    func oldGenerationSendsNothing(_ operation: String, returnToA: Bool) async throws {
        let peer = IntentRepositoryPeer(response: try F.intentResponse())
        let life = IntentRepositoryLifecycle()
        let repo = try await MobileOnboardingRepository(transport: peer, sessionLifecycle: life).scoped(for: F.owner)
        await life.change(to: "other-synthetic-owner")
        if returnToA { await life.change(to: F.owner) }
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await F.invoke(operation, repo) }
        #expect(await peer.requests.isEmpty)
    }

    @Test("Late success and error cannot cross a session generation",
          arguments: ["begin", "resolve", "complete"], [false, true])
    func lateResultIsRejected(_ operation: String, fails: Bool) async throws {
        let life = IntentRepositoryLifecycle()
        let peer = IntentRepositoryPeer(response: try operation == "complete" ? F.ack() : F.intentResponse(),
            failure: fails ? .network : nil, effect: { await life.change(to: F.owner) })
        let repo = try await MobileOnboardingRepository(transport: peer, sessionLifecycle: life).scoped(for: F.owner)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await F.invoke(operation, repo) }
        #expect(await peer.requests.count == 1)
    }

    private typealias F = IntentRepositoryFixture
}

private enum IntentRepositoryFixture {
    static let owner = "00000000-0000-4000-8000-0000000000a1"
    static let q = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    static let id = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    static let key = "osc1:cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    static func intentResponse(q: UUID = IntentRepositoryFixture.q) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["completion_intent": ["protocol": "osc1",
            "preparation_id": q.uuidString.lowercased(), "intent_id": id.uuidString.lowercased(), "request_key": key]])
    }
    static func intent() throws -> OnboardingCompletionIntent {
        try JSONDecoder().decode(OnboardingCompletionIntentResponse.self, from: intentResponse()).completionIntent!
    }
    static func ack() throws -> Data {
        let draft = E3Fixtures.draft(step: .completion)
        return try JSONEncoder().encode(OnboardingCompletionAcknowledgement(onboardingCompleted: true,
            completedAt: "2026-10-21T14:00:00Z", objective: draft.objective!, persona: draft.persona!,
            documentActions: (draft.documentActions ?? []).map { .init(documentKey: $0.documentKey,
                version: $0.version, locale: $0.locale, contentHash: $0.contentHash, purpose: "synthetic_test",
                action: $0.action, actedAt: "2026-10-21T14:00:00Z") }))
    }
    static func invoke(_ operation: String, _ repo: any OnboardingRepository) async throws {
        switch operation {
        case "begin": _ = try await repo.beginCompletionIntent(for: owner, preparationID: q)
        case "resolve": _ = try await repo.resolveCompletionIntent(for: owner, preparationID: q)
        default: _ = try await repo.completeOfficial(E3Fixtures.draft(step: .completion), for: owner, completionIntent: intent())
        }
    }
}

private struct IntentRepositoryWireRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let queryItems: [URLQueryItem]
    let body: Data?
    let idempotency: MobileAPIIdempotency
}

private actor IntentRepositoryPeer: MobileAPIExecuting {
    let response: Data
    let failure: MobileAPITransportError?
    let effect: @Sendable () async -> Void
    private(set) var requests: [IntentRepositoryWireRequest] = []
    init(response: Data, failure: MobileAPITransportError? = nil, effect: @escaping @Sendable () async -> Void = {}) {
        self.response = response; self.failure = failure; self.effect = effect
    }
    func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> Response {
        requests.append(.init(method: request.method, path: request.path, queryItems: request.queryItems,
            body: request.body, idempotency: request.idempotency))
        await effect()
        if let failure { throw failure }
        return try JSONDecoder().decode(Response.self, from: response)
    }
}

private actor IntentRepositoryLifecycle: SessionLifecycleProviding {
    private var owner = IntentRepositoryFixture.owner
    private var generation: UInt64 = 1
    func change(to userID: String) { owner = userID; generation += 1 }
    func currentBearerToken() async -> String? { "synthetic-token" }
    func leaseForRequest() throws -> SessionLease { .init(userID: owner, generation: generation, bearer: "synthetic-token") }
    func validate(_ lease: SessionLease) throws {
        guard lease.userID == owner, lease.generation == generation else { throw SessionLifecycleError.sessionSuperseded }
    }
    func refreshAfterUnauthorized(lease: SessionLease) throws -> SessionLease { try validate(lease); return lease }
    func signOut() -> RemoteRevocationOutcome { .unconfirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) throws -> UUID { try validate(lease); return UUID() }
    func finishPatientWork(_ id: UUID) {}
    func performPatientStateOperation<Value: Sendable>(lease: SessionLease, operation: @Sendable () throws -> Value) throws -> Value {
        try validate(lease); return try operation()
    }
}
