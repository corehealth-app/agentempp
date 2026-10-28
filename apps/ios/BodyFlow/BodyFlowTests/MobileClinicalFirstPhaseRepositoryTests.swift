import Foundation
import Testing
@testable import BodyFlow

@Suite("First phase network — original Auth scope and choice-only requests")
struct MobileClinicalFirstPhaseRepositoryTests {
    @Test func sendsNoClientCalculatedEffectsAndUsesTheOriginalKeys() async throws {
        let transport = FirstPhaseRecordingTransport(), lifecycle = FirstPhaseLifecycle()
        let source = MobileClinicalFirstPhaseRepository(transport: transport, lifecycle: lifecycle)
        let bound = try await source.scoped(for: "auth-A")
        _ = try await bound.choices()
        let key = try IdempotencyKey(validating: "b3b01000-0000-4000-8000-000000003971")
        let preview = try await bound.prepare(phase: .bodyRecomposition, key: key)
        _ = try await bound.confirm(preview: preview, key: key)
        let calls = await transport.calls
        #expect(calls.map(\.path) == ["/api/mobile/v1/protocol/first-phase", "/api/mobile/v1/protocol/first-phase/preview", "/api/mobile/v1/protocol/first-phase/confirm"])
        #expect(calls[0].body == nil && calls[0].idempotency == .notRequired)
        let first = try #require(calls[1].body), second = try #require(calls[2].body)
        let firstObject = try #require(try JSONSerialization.jsonObject(with: first) as? [String: String])
        let secondObject = try #require(try JSONSerialization.jsonObject(with: second) as? [String: String])
        #expect(firstObject == ["phase": "recomposicao"])
        #expect(secondObject == ["phase": "recomposicao", "preview_id": preview.previewID])
        #expect(calls[1].idempotency == .required(key) && calls[2].idempotency == .required(key))
        #expect(await lifecycle.finished == 3)
    }
    @Test func anOldScopedRepositoryCannotSendAsBOrAReplacementA() async throws {
        let transport = FirstPhaseRecordingTransport(), lifecycle = FirstPhaseLifecycle()
        let source = MobileClinicalFirstPhaseRepository(transport: transport, lifecycle: lifecycle)
        let old = try await source.scoped(for: "auth-A")
        await lifecycle.replace(user: "auth-B")
        await #expect(throws: (any Error).self) { try await old.choices() }
        await #expect(throws: (any Error).self) { try await old.scoped(for: "auth-B") }
        await lifecycle.replace(user: "auth-A")
        await #expect(throws: (any Error).self) { try await old.choices() }
        #expect(await transport.calls.isEmpty)
    }
}
private actor FirstPhaseRecordingTransport: MobileAPIExecuting {
    struct Call: Sendable { let path: String; let body: Data?; let idempotency: MobileAPIIdempotency }
    var calls: [Call] = []
    func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> Response {
        calls.append(Call(path: request.path, body: request.body, idempotency: request.idempotency))
        let text = request.path.hasSuffix("/preview") ? ClinicalFirstPhaseTests.previewJSON
            : request.path.hasSuffix("/confirm") ? ClinicalFirstPhaseTests.confirmationJSON : ClinicalFirstPhaseTests.choicesJSON
        return try JSONDecoder().decode(Response.self, from: Data(text.utf8))
    }
}
private actor FirstPhaseLifecycle: SessionLifecycleProviding {
    var user = "auth-A", generation: UInt64 = 1, finished = 0
    func currentBearerToken() async -> String? { "synthetic-only" }
    func leaseForRequest() async throws -> SessionLease { SessionLease(userID: user, generation: generation, bearer: "synthetic-only") }
    func validate(_ lease: SessionLease) async throws {
        guard lease.userID == user && lease.generation == generation else { throw SessionLifecycleError.sessionSuperseded }
    }
    func refreshAfterUnauthorized(lease: SessionLease) async throws -> SessionLease { try await validate(lease); return lease }
    func signOut() async -> RemoteRevocationOutcome { generation += 1; return .confirmed }
    func beginPatientWork(lease: SessionLease, cancel: @escaping @Sendable () -> Void) async throws -> UUID { try await validate(lease); return UUID() }
    func finishPatientWork(_ id: UUID) async { finished += 1 }
    func replace(user: String) { self.user = user; generation += 1 }
}
