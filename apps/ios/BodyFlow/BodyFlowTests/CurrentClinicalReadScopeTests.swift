import Foundation
import Testing

@testable import BodyFlow

@Suite("Current clinical readers retain original Auth scope", .serialized)
struct CurrentClinicalReadScopeTests {
    @Test("A manually bound legacy token transport cannot claim current Auth authority")
    func tokenOnlyBindingIsNotClinicalAuthority() async throws {
        let configuration = try MobileAPIConfiguration(originString: "https://clinical-scope.example.invalid")
        let transport = MobileAPITransport(configuration: configuration, sessionTokenProvider: ClinicalReadTokenOnly(),
            session: URLSession(configuration: .ephemeral), clock: ContinuousClock())
            .scoped(to: SessionLease(userID: "auth-A", generation: 1, bearer: "synthetic"))
        await #expect(throws: SessionLifecycleError.sessionSuperseded) {
            try await transport.validateCurrentClinicalSession()
        }
    }
    @Test("Current readers refuse a generic transport before dispatch or numerical publication")
    func refusesTokenOnlyCurrentReaders() async throws {
        let transport = try ClinicalReadSuccessTransport()
        let reads = MobileBodyFlowRepository(transport: transport, clinicalRepresentation: .currentV1)
        let objective = MobileCurrentObjectiveRepository(transport: transport, clinicalRepresentation: .currentV1)
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await reads.today() }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await objective.currentObjective() }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Legacy constructors preserve the existing payload and transport contract")
    func legacyTransportRemainsCompatible() async throws {
        let transport = try ClinicalReadSuccessTransport()
        let reads = MobileBodyFlowRepository(transport: transport)
        let response = try await reads.today()
        let expected = try BodyFlowTestFixtures.decodeInconsistentToday()
        #expect(response.data.localDate == expected.data.localDate)
        let objective = try await MobileCurrentObjectiveRepository(transport: transport).currentObjective()
        #expect(objective.targets?.calories == 2300)
        #expect(await transport.requests.count == 2)
    }

    @Test("Current numerical responses require policy", arguments: [0, 1, 2, 3, 4])
    func missingPolicyIsNotLegacyFallback(_ kind: Int) async throws {
        let base = try ClinicalReadSuccessTransport()
        let transport = AuthorizedClinicalReadTransport(base: base, scope: ClinicalReadSessionScope())
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) {
            try await Self.read(kind, transport)
        }
        #expect(await base.requests.count == 1)
    }

    @Test("Current official policy is retained", arguments: [0, 1, 2, 3, 4])
    func acceptsCurrentPolicy(_ kind: Int) async throws {
        let base = try ClinicalReadSuccessTransport(withPolicy: true)
        try await Self.read(kind, AuthorizedClinicalReadTransport(base: base, scope: ClinicalReadSessionScope()))
        #expect(await base.requests.count == 1)
    }

    @Test("Official absence of progress stays absent without invented points")
    func emptyProgressRemainsAbsent() async throws {
        let base = try ClinicalReadSuccessTransport(emptyProgress: true)
        let transport = AuthorizedClinicalReadTransport(base: base, scope: ClinicalReadSessionScope())
        let response = try await MobileBodyFlowRepository(transport: transport, clinicalRepresentation: .currentV1).progress()
        #expect(response.data == nil)
        #expect(await base.requests.count == 1)
    }

    @Test("Late success cannot cross B or a new A", arguments: [0, 1, 2, 3, 4], [false, true])
    func lateSuccessIsRefused(_ kind: Int, _ returnToA: Bool) async throws {
        let base = try ClinicalReadSuccessTransport(withPolicy: true)
        let scope = ClinicalReadSessionScope()
        let transport = AuthorizedClinicalReadTransport(base: base, scope: scope)
        await base.holdNext()
        let task = Task { try await Self.read(kind, transport) }
        await base.waitForRequest()
        await scope.replace("auth-B")
        if returnToA { await scope.replace("auth-A") }
        await base.release(failure: false)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await task.value }
        #expect(await base.requests.count == 1)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await Self.read(kind, transport) }
        #expect(await base.requests.count == 1)
    }

    @Test("Late failure does not become a retry in a new session", arguments: [0, 1, 2, 3, 4])
    func lateFailureIsRefused(_ kind: Int) async throws {
        let base = try ClinicalReadSuccessTransport(withPolicy: true)
        let scope = ClinicalReadSessionScope()
        let transport = AuthorizedClinicalReadTransport(base: base, scope: scope)
        await base.holdNext()
        let task = Task { try await Self.read(kind, transport) }
        await base.waitForRequest()
        await scope.replace("auth-B")
        await scope.replace("auth-A")
        await base.release(failure: true)
        await #expect(throws: SessionLifecycleError.sessionSuperseded) { try await task.value }
        #expect(await base.requests.count == 1)
    }

    private static func read(_ kind: Int, _ transport: AuthorizedClinicalReadTransport) async throws {
        let repo = MobileBodyFlowRepository(transport: transport, clinicalRepresentation: .currentV1)
        switch kind {
        case 0: _ = try await repo.today()
        case 1: _ = try await repo.plan()
        case 2: _ = try await repo.progress()
        case 3: _ = try await repo.trends(days: 7)
        default: _ = try await MobileCurrentObjectiveRepository(transport: transport, clinicalRepresentation: .currentV1).currentObjective()
        }
    }
}

private struct ClinicalReadTokenOnly: SessionTokenProviding {
    func currentBearerToken() async -> String? { "synthetic" }
}

private actor ClinicalReadSuccessTransport: MobileAPIEnvelopeExecuting, MobileAPIExecuting {
    let payloads: [String: Data]
    private(set) var requests: [String] = []
    private var holdsNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var failure = false
    init(withPolicy: Bool = false, emptyProgress: Bool = false) throws {
        func data<T: Encodable>(_ value: T) throws -> Data {
            let raw = try JSONEncoder().encode(value)
            guard withPolicy else { return raw }
            var object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            object["clinical_policy"] = try JSONSerialization.jsonObject(with: Data(CurrentClinicalPolicyTests.policy.utf8))
            return try JSONSerialization.data(withJSONObject: object)
        }
        let objective = CurrentObjectiveSnapshot(currentProtocol: .maintenance,
            targets: .init(calories: 2300, proteinG: 144), welcome: nil)
        payloads = try [
            "/api/mobile/v1/today": data(BodyFlowTestFixtures.decodeInconsistentToday().data),
            "/api/mobile/v1/plan": data(PlanSnapshot(training: nil, nutrition: [])),
            "/api/mobile/v1/progress": emptyProgress ? Data("null".utf8) : data(BodyFlowTestFixtures.progressSnapshot),
            "/api/mobile/v1/trends": data(TrendsSnapshot.empty(days: 7)),
            "/api/mobile/v1/protocol": data(objective),
        ]
    }
    func holdNext() { holdsNext = true }
    func waitForRequest() async {
        if !requests.isEmpty { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release(failure: Bool) {
        self.failure = failure
        held?.resume(); held = nil
    }
    private func payload(_ path: String) async throws -> Data {
        requests.append(path)
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { continuation in
                held = continuation
                waiters.forEach { $0.resume() }; waiters.removeAll()
            }
        }
        if failure { throw URLError(.notConnectedToInternet) }
        return try #require(payloads[path])
    }
    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        let bytes = try await payload(request.path)
        return try MobileResponse(data: JSONDecoder().decode(Response.self, from: bytes),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "clinical-reader-qa"))
    }
    func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> Response {
        try await JSONDecoder().decode(Response.self, from: payload(request.path))
    }
}

private actor ClinicalReadSessionScope {
    private var userID = "auth-A"
    private var generation = 1
    func replace(_ user: String) { userID = user; generation += 1 }
    func validate() throws {
        guard userID == "auth-A", generation == 1 else { throw SessionLifecycleError.sessionSuperseded }
    }
}

private struct AuthorizedClinicalReadTransport: MobileAPIEnvelopeExecuting, MobileAPIExecuting, CurrentClinicalSessionAuthorizing {
    let base: ClinicalReadSuccessTransport
    let scope: ClinicalReadSessionScope
    func validateCurrentClinicalSession() async throws { try await scope.validate() }
    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        try await base.executeEnvelope(request)
    }
    func execute<Response: Decodable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> Response {
        try await base.execute(request)
    }
}
