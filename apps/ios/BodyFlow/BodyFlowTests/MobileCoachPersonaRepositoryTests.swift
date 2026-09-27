import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile coach persona repository")
struct MobileCoachPersonaRepositoryTests {
    private static func experienceJSON(selected: String) -> Data {
        Data("""
        {"data":{"selected":\(selected),"effective":"zen",
          "options":[{"code":"focus","name":"Foco","description":"Direto e objetivo."},
                     {"code":"impulse","name":"Impulso","description":"Positivo e energético."},
                     {"code":"zen","name":"Zen","description":"Calmo e acolhedor."}],
          "mascot":{"state":"active","changed_at":null},
          "contract_version":"bodyflow.coach-persona.v1"},
         "meta":{"api_version":"v1","request_id":"req-coach-1"}}
        """.utf8)
    }

    @Test("the coach experience is one GET on the persona route")
    func coachExperienceReads() async throws {
        let spy = CoachTransportSpy(responseJSON: Self.experienceJSON(selected: "\"zen\""))
        let repository = MobileCoachPersonaRepository(transport: spy)

        let response = try await repository.coachExperience()

        let request = try #require(await spy.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/coach/persona")
        #expect(request.idempotency == .notRequired)
        #expect(response.data.selected == .zen)
        #expect(response.data.effective == .zen)
        #expect(response.data.mascot.changedAt == nil)
        #expect(response.data.options.map(\.name) == ["Foco", "Impulso", "Zen"])
        #expect(CoachExperienceV1PresentationContract.validatedSnapshot(from: response) != nil)
    }

    @Test("the selected persona comes from the server, nil when none was chosen")
    func selectedPersonaMaps() async throws {
        let zen = MobileCoachPersonaRepository(
            transport: CoachTransportSpy(responseJSON: Self.experienceJSON(selected: "\"zen\""))
        )
        #expect(try await zen.selectedPersona(for: "user-a") == .zen)

        let none = MobileCoachPersonaRepository(
            transport: CoachTransportSpy(responseJSON: Self.experienceJSON(selected: "null"))
        )
        #expect(try await none.selectedPersona(for: "user-a") == nil)
    }

    @Test("setting the persona PATCHes the documented body with an idempotency key")
    func setPersonaPatches() async throws {
        let spy = CoachTransportSpy(responseJSON: Self.experienceJSON(selected: "\"impulse\""))
        let repository = MobileCoachPersonaRepository(transport: spy)

        try await repository.setPersona(.impulse, for: "user-a")

        let request = try #require(await spy.requests.first)
        #expect(request.method == .patch)
        #expect(request.path == "/api/mobile/v1/coach/persona")
        if case .required = request.idempotency {} else {
            Issue.record("a PATCH needs an idempotency key")
        }
        let body = try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["persona"] as? String == "impulse")
        #expect(body.count == 1)
    }

    @Test("failures surface as the repository's service-unavailable error, cancellation passes through")
    func failuresMap() async throws {
        for failure in [
            MobileAPITransportError.network,
            .conflict(code: "coach_locale_unsupported", requestID: nil),
            .server(status: 500, code: "internal_error", requestID: nil),
            .missingSession,
        ] {
            let repository = MobileCoachPersonaRepository(
                transport: CoachTransportSpy(responseJSON: Self.experienceJSON(selected: "null"), failure: failure)
            )
            await #expect(throws: CoachPersonaRepositoryError.serviceUnavailable) {
                try await repository.selectedPersona(for: "user-a")
            }
            await #expect(throws: CoachPersonaRepositoryError.serviceUnavailable) {
                try await repository.setPersona(.focus, for: "user-a")
            }
        }

        let cancelling = MobileCoachPersonaRepository(
            transport: CoachTransportSpy(responseJSON: Self.experienceJSON(selected: "null"), cancels: true)
        )
        await #expect(throws: CancellationError.self) {
            try await cancelling.setPersona(.focus, for: "user-a")
        }
    }

    @Test("the session factory hands the transport-backed provider to every user")
    func factoryBuildsProvider() {
        let provider = MobileCoachExperienceSessionFactory(
            transport: CoachTransportSpy(responseJSON: Self.experienceJSON(selected: "null"))
        ).makeCoachExperience(userID: "user-a")
        #expect(provider is MobileCoachPersonaRepository)
    }
}

private actor CoachTransportSpy: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }

    private(set) var requests: [Recorded] = []
    private let responseJSON: Data
    private let failure: MobileAPITransportError?
    private let cancels: Bool

    init(responseJSON: Data, failure: MobileAPITransportError? = nil, cancels: Bool = false) {
        self.responseJSON = responseJSON
        self.failure = failure
        self.cancels = cancels
    }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(
            method: request.method, path: request.path,
            body: request.body, idempotency: request.idempotency
        ))
        if cancels { throw CancellationError() }
        if let failure { throw failure }
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: responseJSON)
    }
}
