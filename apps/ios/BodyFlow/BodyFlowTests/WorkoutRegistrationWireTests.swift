import Foundation
import Testing

@testable import BodyFlow

@Suite("Versioned workout registration wire")
struct WorkoutRegistrationWireTests {
    private let id = "7c9c0c5e-1f6a-4a1a-9c0b-0f1d2e3a4b5c"
    private let keyString = "7C9C0C5E-1F6A-4A1A-9C0B-0F1D2E3A4B5C"
    private let instant = Date(timeIntervalSince1970: 1784589300)

    @Test("explicit ui-v1 creation carries only patient input and the literal UUID header")
    func proposeVersionedWorkout() async throws {
        let spy = WorkoutWireTransport(replies: [.json(reply(revision: 0))])
        let repository = MobileRegistrationRepository(transport: spy)
        let attempt = MutationAttempt(
            operation: .proposalCreate, key: try key(),
            payload: proposal(protocol: .uiV1), createdAt: instant
        )
        let response = try await repository.propose(attempt)
        let requests = await spy.requests
        let request = try #require(requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/registrations/propose")
        #expect(request.idempotency == .required(try key()))
        #expect(try object(request.body) == expectedProposal(versioned: true))
        #expect(response.data.workoutVersion?.contentRevision == 0)
        #expect(attempt.createdAt == instant)
    }

    @Test("edit freezes the selected revision and body through timeout then current projection replay")
    func editRetryPreservesOriginalIntent() async throws {
        let spy = WorkoutWireTransport(replies: [.failure(.timeout), .json(reply(revision: 2, receipt: true))])
        let repository = MobileRegistrationRepository(transport: spy)
        let version = try #require(WorkoutRegistrationVersion(contentRevision: 0))
        let attempt = MutationAttempt(
            operation: .proposalEdit, key: try key(),
            payload: RegistrationEditCommand(registrationID: id, proposal: proposal(), workoutVersion: version),
            createdAt: instant
        )
        await #expect(throws: BodyFlowCapabilityError.offline) { try await repository.edit(attempt) }
        let response = try await repository.edit(attempt)
        let requests = await spy.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.method == .patch)
            #expect(request.path == "/api/mobile/v1/registrations/\(id)")
            #expect(request.idempotency == .required(try key()))
            let expected = expectedProposal(versioned: true, expectedRevision: 0)
            #expect(try object(request.body) == expected)
        }
        #expect(response.data.workoutVersion?.contentRevision == 2)
        #expect(response.data.editReceipt?.expectedRevision == 0)
        #expect(response.data.editReceipt?.resultRevision == 1)
        #expect(attempt.payload.workoutVersion?.contentRevision == 0)
        #expect(attempt.createdAt == instant)
    }

    @Test("confirm response loss retries the same selection and decodes already-confirmed replay")
    func confirmRetryPreservesOriginalIntent() async throws {
        let spy = WorkoutWireTransport(replies: [.failure(.timeout), .json(reply(revision: 3, confirmed: true))])
        let repository = MobileRegistrationRepository(transport: spy)
        let version = try #require(WorkoutRegistrationVersion(contentRevision: 3))
        let attempt = MutationAttempt(
            operation: .proposalConfirm, key: try key(),
            payload: RegistrationIDCommand(
                registrationID: id, workoutVersion: version
            ), createdAt: instant
        )
        await #expect(throws: BodyFlowCapabilityError.offline) { try await repository.confirm(attempt) }
        let response = try await repository.confirm(attempt)
        let requests = await spy.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.method == .post)
            #expect(request.path == "/api/mobile/v1/registrations/\(id)/confirm")
            #expect(request.idempotency == .required(try key()))
            #expect(try object(request.body) == ["workout_protocol": "ui-v1", "expected_revision": 3] as NSDictionary)
        }
        #expect(response.data.alreadyConfirmed)
        #expect(response.data.registration.workoutVersion?.contentRevision == 3)
        #expect(attempt.payload.workoutVersion?.contentRevision == 3)
        #expect(attempt.createdAt == instant)
    }

    @Test("cancel sends the reviewed revision while legacy selection bodies remain absent")
    func cancelVersionedAndLegacyBodies() async throws {
        let spy = WorkoutWireTransport(replies: [
            .json(reply(revision: 4, status: "cancelled")),
            .json(reply(revision: nil, status: "cancelled")),
            .json(reply(revision: nil, confirmed: true)),
        ])
        let repository = MobileRegistrationRepository(transport: spy)
        let version = try #require(WorkoutRegistrationVersion(contentRevision: 4))
        _ = try await repository.cancel(MutationAttempt(
            operation: .proposalCancel, key: try key(),
            payload: RegistrationIDCommand(
                registrationID: id, workoutVersion: version
            ), createdAt: instant
        ))
        _ = try await repository.cancel(MutationAttempt(
            operation: .proposalCancel, key: try key(), payload: RegistrationIDCommand(registrationID: id), createdAt: instant
        ))
        _ = try await repository.confirm(MutationAttempt(
            operation: .proposalConfirm, key: try key(), payload: RegistrationIDCommand(registrationID: id), createdAt: instant
        ))
        let requests = await spy.requests
        #expect(requests.map(\.method) == [.delete, .delete, .post])
        #expect(try object(requests[0].body) == ["workout_protocol": "ui-v1", "expected_revision": 4] as NSDictionary)
        #expect(requests[1].body == nil)
        #expect(requests[2].body == nil)
    }

    @Test("owned recovery GET has neither mutation body nor idempotency key")
    func recoveryReadUsesGET() async throws {
        let spy = WorkoutWireTransport(replies: [.json(reply(revision: 5))])
        let repository = MobileRegistrationRepository(transport: spy)
        let response = try await repository.loadWorkoutRegistration(id: id)
        let request = try #require(await spy.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/registrations/\(id)")
        #expect(request.idempotency == .notRequired)
        #expect(request.body == nil)
        #expect(response.data.workoutVersion?.contentRevision == 5)
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.loadWorkoutRegistration(id: "../another-owner")
        }
        #expect(await spy.requests.count == 1)
    }

    @Test("invalid edit pairings fail before reaching transport")
    func invalidEditPairingsDoNotSend() async throws {
        let spy = WorkoutWireTransport(replies: [])
        let repository = MobileRegistrationRepository(transport: spy)
        let version = try #require(WorkoutRegistrationVersion(contentRevision: 0))
        let meal = RegistrationProposalRequest.meal(MealProposalRequest(mealType: .lunch, items: [], consumedAt: nil))
        let commands = [
            RegistrationEditCommand(registrationID: id, proposal: meal, workoutVersion: version),
            RegistrationEditCommand(registrationID: id, proposal: proposal(protocol: .uiV1)),
        ]
        for command in commands {
            await #expect(throws: BodyFlowCapabilityError.invalidInput) {
                try await repository.edit(MutationAttempt(
                    operation: .proposalEdit, key: try key(), payload: command, createdAt: instant
                ))
            }
        }
        #expect(await spy.requests.isEmpty)
    }

    @Test("legacy workout creation and edit preserve their original flat JSON")
    func legacyWorkoutWireIsUnchanged() async throws {
        let spy = WorkoutWireTransport(replies: [.json(reply(revision: nil)), .json(reply(revision: nil))])
        let repository = MobileRegistrationRepository(transport: spy)
        _ = try await repository.propose(MutationAttempt(
            operation: .proposalCreate, key: try key(), payload: proposal(), createdAt: instant
        ))
        _ = try await repository.edit(MutationAttempt(
            operation: .proposalEdit, key: try key(),
            payload: RegistrationEditCommand(registrationID: id, proposal: proposal()), createdAt: instant
        ))
        for request in await spy.requests {
            #expect(try object(request.body) == expectedProposal(versioned: false))
        }
    }

    private func key() throws -> IdempotencyKey { try IdempotencyKey(validating: keyString) }

    private func proposal(protocol value: WorkoutRegistrationProtocol? = nil) -> RegistrationProposalRequest {
        .workout(WorkoutProposalRequest(
            workoutType: "Natação", durationMin: 40, intensity: .moderate,
            performedAt: APITimestamp(value: instant), registrationProtocol: value
        ))
    }

    private func object(_ data: Data?) throws -> NSDictionary {
        let body = try #require(data)
        return try #require(JSONSerialization.jsonObject(with: body) as? NSDictionary)
    }

    private func expectedProposal(versioned: Bool, expectedRevision: Int? = nil) -> NSDictionary {
        var result: [String: Any] = [
            "kind": "workout", "workout_type": "Natação", "duration_min": 40,
            "intensity": "moderada", "performed_at": "2026-07-20T23:15:00Z",
        ]
        if versioned { result["workout_protocol"] = "ui-v1" }
        if let expectedRevision { result["expected_revision"] = expectedRevision }
        return result as NSDictionary
    }

    private func reply(
        revision: Int?, receipt: Bool = false, confirmed: Bool = false, status: String = "pending"
    ) -> Data {
        let metadata = revision.map { ",\"workout_protocol\":\"ui-v1\",\"content_revision\":\($0)" } ?? ""
        let receiptJSON = receipt
            ? ",\"receipt\":{\"requestKey\":\"wue1:\(keyString)\",\"expectedRevision\":0,\"resultRevision\":1}"
            : ""
        let flags = confirmed ? ",\"already_confirmed\":true,\"deduped\":false" : ""
        let actualStatus = confirmed ? "confirmed" : status
        let resolvedAt = actualStatus == "pending" ? "null" : "\"2026-07-20T12:30:00Z\""
        return Data("""
        {"data":{"id":"\(id)","status":"\(actualStatus)",
         "created_at":"2026-07-20T12:00:00Z","expires_at":"2026-07-21T12:00:00Z","resolved_at":\(resolvedAt),
         "proposal":{"kind":"workout","workout_type":"Natação","duration_min":40,"estimated_kcal":400,"intensity":"moderada"}
         \(metadata)\(receiptJSON)\(flags)},"meta":{"api_version":"v1","request_id":"workout-wire-test"}}
        """.utf8)
    }
}

private actor WorkoutWireTransport: MobileAPIEnvelopeExecuting {
    enum Reply: Sendable {
        case json(Data)
        case failure(MobileAPITransportError)
    }
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }
    private var replies: [Reply]
    private(set) var requests: [Recorded] = []

    init(replies: [Reply]) { self.replies = replies }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(method: request.method, path: request.path, body: request.body, idempotency: request.idempotency))
        guard !replies.isEmpty else { throw MobileAPITransportError.network }
        switch replies.removeFirst() {
        case let .failure(error): throw error
        case let .json(data): return try JSONDecoder().decode(MobileResponse<Response>.self, from: data)
        }
    }
}
