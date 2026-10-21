import Foundation
import Testing

@testable import BodyFlow

@Suite("Workout strength clarification transport")
struct MobileWorkoutStrengthClarificationRepositoryTests {
    private let workout = "b2800000-0000-4000-8000-000000000001"
    private let lifecycle = "c3900000-0000-4000-8000-000000000001"
    private let question = "d4a00000-0000-4000-8000-000000000001"
    private let key = "e5b00000-0000-4000-8000-000000000001"
    private let other = "f6c00000-0000-4000-8000-000000000001"

    @Test("GET carries no body, query, idempotency or owner authority")
    func readIsOwnedGET() async throws {
        let transport = StrengthClarificationTransport(replies: [.json(reply("unanswered"))])
        let repository = MobileWorkoutStrengthClarificationRepository(transport: transport)
        let response = try await repository.load(workoutID: workout.uppercased())
        let request = try #require(await transport.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/workouts/\(workout)/strength-clarification")
        #expect(request.queryItems.isEmpty)
        #expect(request.body == nil)
        #expect(request.idempotency == .notRequired)
        #expect(response.data == .unanswered(try authoredQuestion()))
    }

    @Test("POST uses exact four fields and explicit UUID; timeout retry preserves original revision0", arguments: [WorkoutStrengthAnswer.yes, .no])
    func lostResponseRetriesTheOriginalAttempt(answer: WorkoutStrengthAnswer) async throws {
        let transport = StrengthClarificationTransport(replies: [.failure(.timeout), .json(reply("answered", answer: answer))])
        let repository = MobileWorkoutStrengthClarificationRepository(transport: transport)
        let original = try attempt(key: key.uppercased(), answer: answer)
        await #expect(throws: BodyFlowCapabilityError.offline) { try await repository.answer(original) }
        let response = try await repository.answer(original)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.map(\.method) == [.post, .post])
        #expect(requests[0].body == requests[1].body)
        for request in requests {
            #expect(request.path == "/api/mobile/v1/workouts/\(workout)/strength-clarification")
            #expect(request.queryItems.isEmpty)
            #expect(request.idempotency == .required(original.key))
            let data = try #require(request.body)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
            #expect(object == ["expected_lifecycle_key": lifecycle, "expected_fact_revision": 0, "question_key": question, "answer": answer.rawValue] as NSDictionary)
        }
        guard case let .answered(receipt) = response.data else { Issue.record("Expected official answer"); return }
        #expect(receipt.acceptedAt == "2026-10-21T01:02:03.123456Z")
        #expect(receipt.answer == answer)
        #expect(original.payload.question.factRevision == 0)
        #expect(original.key.value == key.uppercased())
        #expect(original.createdAt == Date(timeIntervalSince1970: 1_792_500_000))
    }

    @Test("a lost POST response can be recovered by one separate GET without repeating the write")
    func separateReadCanRecoverAnswered() async throws {
        let transport = StrengthClarificationTransport(replies: [.failure(.timeout), .json(reply("answered"))])
        let repository = MobileWorkoutStrengthClarificationRepository(transport: transport)
        await #expect(throws: BodyFlowCapabilityError.offline) { try await repository.answer(attempt()) }
        let response = try await repository.load(workoutID: workout)
        guard case .answered = response.data else { Issue.record("Expected stored answer"); return }
        #expect(await transport.requests.map(\.method) == [.post, .get])
    }

    @Test("unknown workout/classification absence is not a fabricated question")
    func distinctReadStates() async throws {
        for state in ["not_applicable", "unavailable"] {
            let transport = StrengthClarificationTransport(replies: [.json(reply(state))])
            let response = try await MobileWorkoutStrengthClarificationRepository(transport: transport).load(workoutID: workout)
            if state == "unavailable" { #expect(response.data == .unavailable) }
            else { #expect(response.data == .notApplicable(try #require(WorkoutStrengthScope(workoutID: workout, lifecycleKey: lifecycle)))) }
        }
    }

    @Test("new local conflict states survive the generic capability mapping")
    func localErrorsPrecedeGenericFallback() async throws {
        for (error, expected) in [
            (MobileAPITransportError.conflict(code: "workout_strength_unavailable", requestID: nil), WorkoutStrengthClarificationError.contextUnavailable),
            (.conflict(code: "workout_strength_answer_conflict", requestID: nil), .answerConflict),
            (.server(status: 503, code: "workout_strength_clarification_unavailable", requestID: nil), .disabled),
        ] {
            let transport = StrengthClarificationTransport(replies: [.failure(error)])
            let repository = MobileWorkoutStrengthClarificationRepository(transport: transport)
            await #expect(throws: expected) { try await repository.answer(attempt()) }
            #expect(await transport.requests.count == 1)
        }
        #expect(MobileAPITransportError.conflict(code: "workout_strength_unavailable", requestID: nil).capabilityError == .serviceUnavailable)
    }

    @Test("unknown errors keep existing capability states and cancellation remains cancellation")
    func fallbackAndCancellation() async throws {
        let transport = StrengthClarificationTransport(replies: [
            .failure(.network), .failure(.conflict(code: "unknown", requestID: nil)), .failure(.sessionSuperseded), .cancelled,
        ])
        let repository = MobileWorkoutStrengthClarificationRepository(transport: transport)
        await #expect(throws: BodyFlowCapabilityError.offline) { try await repository.load(workoutID: workout) }
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await repository.load(workoutID: workout) }
        await #expect(throws: CancellationError.self) { try await repository.load(workoutID: workout) }
        await #expect(throws: CancellationError.self) { try await repository.load(workoutID: workout) }
    }

    @Test("non-UUID path never reaches transport", arguments: ["pending-id", "../x", "b2800000000040008000000000000001"])
    func invalidPath(_ id: String) async throws {
        let transport = StrengthClarificationTransport(replies: [])
        await #expect(throws: BodyFlowCapabilityError.invalidInput) { try await MobileWorkoutStrengthClarificationRepository(transport: transport).load(workoutID: id) }
        #expect(await transport.requests.isEmpty)
    }

    @Test("non-UUID keys and wrong operation never reach transport")
    func invalidAttemptDoesNotSend() async throws {
        let transport = StrengthClarificationTransport(replies: [])
        let repository = MobileWorkoutStrengthClarificationRepository(transport: transport)
        for value in ["mobile-\(key)", "synthetic-key"] {
            await #expect(throws: BodyFlowCapabilityError.invalidIdempotencyKey) { try await repository.answer(attempt(key: value)) }
        }
        let invalid = MutationAttempt(operation: .proposalConfirm, key: try IdempotencyKey(validating: key), payload: WorkoutStrengthAnswerCommand(question: try authoredQuestion(), answer: .yes), createdAt: Date())
        await #expect(throws: BodyFlowCapabilityError.invalidInput) { try await repository.answer(invalid) }
        #expect(await transport.requests.isEmpty)
    }

    @Test("POST accepts only the same official answered tuple, not another status", arguments: [
        "unanswered", "not_applicable", "unavailable", "wrong_workout", "wrong_lifecycle", "wrong_question", "wrong_answer", "extra_receipt",
    ])
    func rejectsIncoherentWriteReply(_ variant: String) async throws {
        let transport = StrengthClarificationTransport(replies: [.json(reply(variant))])
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await MobileWorkoutStrengthClarificationRepository(transport: transport).answer(attempt()) }
        #expect(await transport.requests.count == 1)
    }

    @Test("GET refuses a valid wire anchored to a different workout")
    func rejectsForeignRead() async throws {
        let transport = StrengthClarificationTransport(replies: [.json(reply("wrong_workout"))])
        await #expect(throws: BodyFlowCapabilityError.serviceUnavailable) { try await MobileWorkoutStrengthClarificationRepository(transport: transport).load(workoutID: workout) }
    }

    @MainActor
    @Test("invalid optional identity leaves a valid confirmation finished without retry or question I/O", arguments: ["null", "true", "{}", "\"bad-id\""])
    func confirmationDoesNotFailBecauseOfOptionalIdentity(_ identity: String) async throws {
        func registration(status: String, extra: String) -> Data {
            Data("""
            {"data":{"id":"a1700000-0000-4000-8000-000000000001","status":"\(status)",
             "created_at":"2026-10-21T12:00:00Z","expires_at":"2026-10-22T12:00:00Z","resolved_at":null,
             "proposal":{"kind":"workout","workout_type":"Natação","duration_min":40,"estimated_kcal":400,"intensity":"moderada"},
             "workout_protocol":"ui-v1","content_revision":0\(extra)},"meta":{"api_version":"v1","request_id":"identity-model-control"}}
            """.utf8)
        }
        let transport = StrengthClarificationTransport(replies: [
            .json(registration(status: "pending", extra: "")),
            .json(registration(status: "confirmed", extra: ",\"already_confirmed\":false,\"confirmed_workout_id\":\(identity)")),
        ])
        let model = WorkoutRegistrationModel(registration: MobileRegistrationRepository(transport: transport),
            timeProvider: SystemTimeProvider(), keyProvider: RandomIdempotencyKeyProvider(),
            invalidationCenter: FeatureInvalidationCenter(), registrationProtocol: .uiV1)
        await model.submit(WorkoutProposalRequest(workoutType: "Natação", durationMin: 40, intensity: .moderate, performedAt: nil))
        #expect(model.phase == .proposal)
        await model.confirm()
        #expect(model.phase == .confirmed)
        #expect(model.confirmedRegistration?.status == "confirmed")
        #expect(model.confirmedRegistration?.confirmedWorkoutID == nil)
        #expect(model.retainedFailedAttempt == nil)
        #expect(model.captureError == nil)
        await model.retry()
        #expect(await transport.requests.map(\.path) == ["/api/mobile/v1/registrations/propose", "/api/mobile/v1/registrations/a1700000-0000-4000-8000-000000000001/confirm"])
    }

    private func authoredQuestion() throws -> WorkoutStrengthQuestion {
        try #require(WorkoutStrengthQuestion(workoutID: workout, lifecycleKey: lifecycle, factRevision: 0, questionKey: question))
    }
    private func attempt(key value: String? = nil, answer: WorkoutStrengthAnswer = .yes) throws -> MutationAttempt<WorkoutStrengthAnswerCommand> {
        MutationAttempt(operation: .workoutStrengthAnswer, key: try IdempotencyKey(validating: value ?? key), payload: WorkoutStrengthAnswerCommand(question: try authoredQuestion(), answer: answer), createdAt: Date(timeIntervalSince1970: 1_792_500_000))
    }
    private func reply(_ variant: String, answer: WorkoutStrengthAnswer = .yes) -> Data {
        let status = ["unanswered", "not_applicable", "unavailable"].contains(variant) ? variant : "answered"
        var value: [String: Any] = status == "unavailable" ? ["status": status, "reason": "provenance_gap"] : ["status": status, "workout_id": variant == "wrong_workout" ? other : workout, "lifecycle_key": variant == "wrong_lifecycle" ? other : lifecycle, "fact_revision": status == "answered" ? 1 : 0]
        if status == "unanswered" || status == "answered" { value["question_key"] = variant == "wrong_question" ? other : question }
        if status == "answered" {
            var receipt = ["answer": variant == "wrong_answer" ? (answer == .yes ? "no" : "yes") : answer.rawValue, "accepted_at": "2026-10-21T01:02:03.123456Z"]
            if variant == "extra_receipt" { receipt["owner_id"] = other }
            value["receipt"] = receipt
        }
        return try! JSONSerialization.data(withJSONObject: ["data": value, "meta": ["api_version": "v1", "request_id": "synthetic-clarification"]])
    }
}

private actor StrengthClarificationTransport: MobileAPIEnvelopeExecuting {
    enum Reply: Sendable { case json(Data); case failure(MobileAPITransportError); case cancelled }
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let queryItems: [URLQueryItem]
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }
    private var replies: [Reply]
    private(set) var requests: [Recorded] = []
    init(replies: [Reply]) { self.replies = replies }
    func executeEnvelope<Response: Codable & Sendable>(_ request: MobileAPIRequest<Response>) async throws -> MobileResponse<Response> {
        requests.append(Recorded(method: request.method, path: request.path, queryItems: request.queryItems, body: request.body, idempotency: request.idempotency))
        guard !replies.isEmpty else { throw MobileAPITransportError.network }
        switch replies.removeFirst() {
        case let .json(data): return try JSONDecoder().decode(MobileResponse<Response>.self, from: data)
        case let .failure(error): throw error
        case .cancelled: throw CancellationError()
        }
    }
}
