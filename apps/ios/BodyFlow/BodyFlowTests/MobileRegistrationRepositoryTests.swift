import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile registration repository")
struct MobileRegistrationRepositoryTests {
    private static let registrationID = "7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c"

    private static let pendingJSON = Data("""
    {"data":{"id":"7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c","status":"pending",
      "created_at":"2026-07-20T15:04:05.123456+00:00","expires_at":"2026-07-21T15:04:05.123456+00:00",
      "resolved_at":null,
      "proposal":{"kind":"meal","meal_type":"almoco",
        "items":[{"name":"arroz","quantity_g":120,"kcal":155.4,"protein_g":3.1,"carbs_g":33,"fat_g":0.3}],
        "totals":{"kcal":155.4,"protein_g":3.1,"carbs_g":33,"fat_g":0.3},"warnings":[]}},
     "meta":{"api_version":"v1","request_id":"req-propose-1"}}
    """.utf8)

    private static let confirmedJSON = Data("""
    {"data":{"id":"7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c","status":"confirmed",
      "created_at":"2026-07-20T15:04:05.123456+00:00","expires_at":"2026-07-21T15:04:05.123456+00:00",
      "resolved_at":"2026-07-20T15:10:05.000001+00:00",
      "proposal":{"kind":"meal","meal_type":"almoco","items":[],"totals":null,"warnings":["x"]},
      "already_confirmed":false,"deduped":true},
     "meta":{"api_version":"v1","request_id":"req-confirm-1"}}
    """.utf8)

    private static let hydrationJSON = Data("""
    {"data":{"hydration_log_id":"0d0d0d0d-0000-4000-8000-000000000001","inserted":true,"water_consumed_ml":1250},
     "meta":{"api_version":"v1","request_id":"req-hydration-1"}}
    """.utf8)

    private func key(_ value: String) throws -> IdempotencyKey {
        try IdempotencyKey(validating: value)
    }

    private var mealRequest: RegistrationProposalRequest {
        .meal(MealProposalRequest(
            mealType: .lunch,
            items: [MealProposalItemRequest(foodName: "arroz", quantityG: 120, userKcal: nil)],
            consumedAt: nil
        ))
    }

    @Test("propose posts the structured proposal with the attempt's idempotency key")
    func proposeSendsProposal() async throws {
        let spy = RegistrationTransportSpy(responseJSON: Self.pendingJSON)
        let repository = MobileRegistrationRepository(transport: spy)
        let attempt = MutationAttempt(
            operation: .proposalCreate, key: try key("mobile-test-propose-1"),
            payload: mealRequest, createdAt: Date()
        )

        let response = try await repository.propose(attempt)

        let request = try #require(await spy.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/registrations/propose")
        #expect(request.idempotency == .required(try key("mobile-test-propose-1")))
        let body = try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["kind"] as? String == "meal")
        #expect(body["meal_type"] as? String == "almoco")
        #expect((body["items"] as? [[String: Any]])?.first?["food_name"] as? String == "arroz")
        #expect(body["user_kcal"] == nil)
        #expect(response.data.id == Self.registrationID)
        #expect(response.data.status == "pending")
        #expect(response.meta.requestID == "req-propose-1")
        if case let .meal(meal) = response.data.proposal {
            #expect(meal.items.first?.kcal == Decimal(string: "155.4"))
        } else {
            Issue.record("expected a meal proposal")
        }
    }

    @Test("edit, confirm and cancel address the registration by id with the right method")
    func editConfirmCancelAddressTheRegistration() async throws {
        let spy = RegistrationTransportSpy(responseJSON: Self.pendingJSON, confirmationJSON: Self.confirmedJSON)
        let repository = MobileRegistrationRepository(transport: spy)
        let id = Self.registrationID

        _ = try await repository.edit(MutationAttempt(
            operation: .proposalEdit, key: try key("mobile-test-edit-1"),
            payload: RegistrationEditCommand(registrationID: id, proposal: mealRequest), createdAt: Date()
        ))
        let confirmation = try await repository.confirm(MutationAttempt(
            operation: .proposalConfirm, key: try key("mobile-test-confirm-1"),
            payload: RegistrationIDCommand(registrationID: id), createdAt: Date()
        ))
        _ = try await repository.cancel(MutationAttempt(
            operation: .proposalCancel, key: try key("mobile-test-cancel-1"),
            payload: RegistrationIDCommand(registrationID: id), createdAt: Date()
        ))

        let requests = await spy.requests
        #expect(requests.map(\.method) == [.patch, .post, .delete])
        #expect(requests.map(\.path) == [
            "/api/mobile/v1/registrations/\(id)",
            "/api/mobile/v1/registrations/\(id)/confirm",
            "/api/mobile/v1/registrations/\(id)",
        ])
        #expect(requests[0].body != nil)
        #expect(requests[1].body == nil)
        #expect(requests[2].body == nil)
        #expect(confirmation.data.alreadyConfirmed == false)
        #expect(confirmation.data.deduped == true)
        #expect(confirmation.data.registration.status == "confirmed")
    }

    @Test("an id outside the UUID alphabet never reaches the transport")
    func invalidIdentifierFailsClosed() async throws {
        let spy = RegistrationTransportSpy(responseJSON: Self.pendingJSON)
        let repository = MobileRegistrationRepository(transport: spy)
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.confirm(MutationAttempt(
                operation: .proposalConfirm, key: try key("mobile-test-confirm-2"),
                payload: RegistrationIDCommand(registrationID: "../pending"), createdAt: Date()
            ))
        }
        #expect(await spy.requests.isEmpty)
    }

    @Test("hydration posts the command and decodes the receipt")
    func hydrationRecords() async throws {
        let spy = RegistrationTransportSpy(responseJSON: Self.hydrationJSON)
        let repository = MobileRegistrationRepository(transport: spy)
        let receipt = try await repository.record(MutationAttempt(
            operation: .hydration, key: try key("mobile-test-hydration-1"),
            payload: try HydrationCommand(amountML: 250, occurredAt: APITimestamp(value: Date(timeIntervalSince1970: 1_784_589_300))),
            createdAt: Date()
        ))
        let request = try #require(await spy.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/routine/hydration")
        let body = try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["amount_ml"] as? Int == 250)
        #expect((body["occurred_at"] as? String)?.hasPrefix("2026-07-20T23:15:00") == true)
        #expect(receipt.data.waterConsumedML == 1250)
        #expect(receipt.data.inserted)
    }

    @Test("transport failures land on the registration capability states")
    func transportFailuresMap() async throws {
        let cases: [(MobileAPITransportError, BodyFlowCapabilityError)] = [
            (.conflict(code: "registration_not_pending", requestID: nil), .registrationNotPending),
            (.http(status: 410, code: "registration_expired", requestID: nil), .registrationExpired),
            (.validation(code: "registration_rejected", requestID: nil), .invalidInput),
            (.conflict(code: "idempotency_key_conflict", requestID: nil), .idempotencyConflict),
            (.http(status: 402, code: "subscription_required", requestID: nil), .subscriptionRequired),
            (.network, .offline),
            (.timeout, .offline),
            (.unavailableConfiguration, .operationUnavailable),
            (.server(status: 500, code: "registration_lookup_failed", requestID: nil), .serviceUnavailable),
        ]
        for (failure, expected) in cases {
            let spy = RegistrationTransportSpy(responseJSON: Self.pendingJSON, failure: failure)
            let repository = MobileRegistrationRepository(transport: spy)
            await #expect(throws: expected) {
                try await repository.propose(MutationAttempt(
                    operation: .proposalCreate, key: try key("mobile-test-failure-1"),
                    payload: mealRequest, createdAt: Date()
                ))
            }
        }
    }
}

private actor RegistrationTransportSpy: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }

    private(set) var requests: [Recorded] = []
    private let responseJSON: Data
    private let confirmationJSON: Data?
    private let failure: MobileAPITransportError?

    init(responseJSON: Data, confirmationJSON: Data? = nil, failure: MobileAPITransportError? = nil) {
        self.responseJSON = responseJSON
        self.confirmationJSON = confirmationJSON
        self.failure = failure
    }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(
            method: request.method, path: request.path,
            body: request.body, idempotency: request.idempotency
        ))
        if let failure { throw failure }
        let data = request.path.hasSuffix("/confirm") ? (confirmationJSON ?? responseJSON) : responseJSON
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: data)
    }
}
