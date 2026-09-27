import Foundation
import Testing

@testable import BodyFlow

@Suite("Mobile routine repository")
struct MobileRoutineRepositoryTests {
    private static let itemID = "0a1b2c3d-0000-4000-8000-000000000010"
    private static let ruleID = "0a1b2c3d-0000-4000-8000-000000000020"

    private static let listJSON = Data("""
    {"data":{"local_date":"2026-07-20","items":[{"id":"0a1b2c3d-0000-4000-8000-000000000010",
      "item_type":"supplement","name":"Creatina","dose_text":"5 g","origin":"user",
      "reminders_enabled":true,"active":true,"archived_at":null,"version":1,
      "created_at":"2026-07-01T12:00:00.000000+00:00","updated_at":"2026-07-01T12:00:00.000000+00:00",
      "frequency_summary":{"times_per_week":7},
      "schedules":[{"id":"0a1b2c3d-0000-4000-8000-000000000020","local_time":"08:00","weekdays":[0,1,2,3,4,5,6],
        "occurrence":{"scheduled_for":"2026-07-20T11:00:00+00:00","status":"pending","last_action_at":null,"snoozed_until":null}}]}]},
     "meta":{"api_version":"v1","request_id":"req-routine-list-1"}}
    """.utf8)

    private static let receiptJSON = Data("""
    {"data":{"adherence_log_id":"0a1b2c3d-0000-4000-8000-000000000030",
      "occurrence_key":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "item_type":"medication","status":"snoozed"},
     "meta":{"api_version":"v1","request_id":"req-routine-log-1"}}
    """.utf8)

    private static let historyJSON = Data("""
    {"data":{"items":[{"id":"0a1b2c3d-0000-4000-8000-000000000040",
      "routine_item_id":"0a1b2c3d-0000-4000-8000-000000000010","item_type":"supplement","status":"missed",
      "reminder_rule_id":"0a1b2c3d-0000-4000-8000-000000000020",
      "scheduled_for":"2026-07-19T11:00:00+00:00","occurred_at":"2026-07-20T03:00:00.000001+00:00",
      "snoozed_until":null,"source":"system","supersedes_log_id":null,"created_at":"2026-07-20T03:00:00+00:00"}],
      "next_cursor":"eyJwIjoxfQ"},
     "meta":{"api_version":"v1","request_id":"req-routine-history-1"}}
    """.utf8)

    private static let scheduledFor = APITimestamp(value: Date(timeIntervalSince1970: 1_784_545_200))
    private static let occurredAt = APITimestamp(value: Date(timeIntervalSince1970: 1_784_589_300))

    private func key(_ value: String) throws -> IdempotencyKey {
        try IdempotencyKey(validating: value)
    }

    private func attempt(
        _ command: RoutineActionCommand,
        key value: String
    ) throws -> MutationAttempt<RoutineActionCommand> {
        MutationAttempt(
            operation: .routineAction,
            key: try key(value),
            payload: command,
            createdAt: Date()
        )
    }

    @Test("list reads the kind's collection with the archived flag")
    func listReadsCollection() async throws {
        let spy = RoutineTransportSpy(responseJSON: Self.listJSON)
        let repository = MobileRoutineRepository(transport: spy)

        let response = try await repository.list(kind: .supplement, includeArchived: false)

        let request = try #require(await spy.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/api/mobile/v1/supplements")
        #expect(request.queryItems == [URLQueryItem(name: "include_archived", value: "false")])
        #expect(request.idempotency == .notRequired)
        #expect(response.data.localDate == "2026-07-20")
        #expect(response.data.items.first?.kind == .supplement)
        #expect(response.data.items.first?.schedules.first?.occurrence?.status == "pending")
        #expect(response.meta.requestID == "req-routine-list-1")

        _ = try await repository.list(kind: .medication, includeArchived: true)
        let second = try #require(await spy.requests.last)
        #expect(second.path == "/api/mobile/v1/medications")
        #expect(second.queryItems == [URLQueryItem(name: "include_archived", value: "true")])
    }

    @Test("record posts the action under the item's log path with the attempt's key")
    func recordPostsAction() async throws {
        let spy = RoutineTransportSpy(responseJSON: Self.receiptJSON)
        let repository = MobileRoutineRepository(transport: spy)
        let snoozedUntil = APITimestamp(value: Date(timeIntervalSince1970: 1_784_590_200))
        let command = try RoutineActionCommand(
            kind: .medication,
            itemID: Self.itemID,
            status: .snoozed,
            reminderRuleID: Self.ruleID,
            scheduledFor: Self.scheduledFor,
            occurredAt: Self.occurredAt,
            snoozedUntil: snoozedUntil
        )

        let receipt = try await repository.record(try attempt(command, key: "mobile-test-routine-1"))

        let request = try #require(await spy.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "/api/mobile/v1/medications/\(Self.itemID)/log")
        #expect(request.idempotency == .required(try key("mobile-test-routine-1")))
        let body = try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["status"] as? String == "snoozed")
        #expect(body["reminder_rule_id"] as? String == Self.ruleID)
        #expect((body["scheduled_for"] as? String)?.hasPrefix("2026-07-20T11:00:00") == true)
        #expect((body["occurred_at"] as? String)?.hasPrefix("2026-07-20T23:15:00") == true)
        #expect((body["snoozed_until"] as? String)?.hasPrefix("2026-07-20T23:30:00") == true)
        // The kind and the item travel in the path, never in the body.
        #expect(body["kind"] == nil)
        #expect(body["item_type"] == nil)
        #expect(body["item_id"] == nil)
        #expect(receipt.data.status == "snoozed")
        #expect(receipt.data.kind == .medication)
        #expect(receipt.data.occurrenceKey.count == 64)
    }

    @Test("a taken action omits snoozed_until instead of sending null")
    func takenOmitsSnooze() async throws {
        let spy = RoutineTransportSpy(responseJSON: Self.receiptJSON)
        let repository = MobileRoutineRepository(transport: spy)
        let command = try RoutineActionCommand(
            kind: .supplement,
            itemID: Self.itemID,
            status: .taken,
            reminderRuleID: Self.ruleID,
            scheduledFor: Self.scheduledFor,
            occurredAt: Self.occurredAt,
            snoozedUntil: nil
        )

        _ = try await repository.record(try attempt(command, key: "mobile-test-routine-2"))

        let request = try #require(await spy.requests.first)
        #expect(request.path == "/api/mobile/v1/supplements/\(Self.itemID)/log")
        let body = try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["status"] as? String == "taken")
        #expect(body.keys.contains("snoozed_until") == false)
    }

    @Test("history reads the item's page with limit and cursor")
    func historyReadsPage() async throws {
        let spy = RoutineTransportSpy(responseJSON: Self.historyJSON)
        let repository = MobileRoutineRepository(transport: spy)

        let first = try await repository.history(
            kind: .supplement, itemID: Self.itemID, cursor: nil, limit: 20
        )
        let second = try await repository.history(
            kind: .supplement, itemID: Self.itemID, cursor: first.nextCursor, limit: 20
        )

        let requests = await spy.requests
        #expect(requests.count == 2)
        #expect(requests[0].method == .get)
        #expect(requests[0].path == "/api/mobile/v1/supplements/\(Self.itemID)/history")
        #expect(requests[0].queryItems == [URLQueryItem(name: "limit", value: "20")])
        #expect(requests[1].queryItems == [
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "cursor", value: "eyJwIjoxfQ"),
        ])
        #expect(first.items.first?.status == "missed")
        #expect(first.items.first?.source == "system")
        #expect(second.nextCursor == "eyJwIjoxfQ")
    }

    @Test("ids, cursors and limits outside the contract never reach the transport")
    func invalidInputsFailClosed() async throws {
        let spy = RoutineTransportSpy(responseJSON: Self.historyJSON)
        let repository = MobileRoutineRepository(transport: spy)

        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.history(kind: .supplement, itemID: "../supplements", cursor: nil, limit: 20)
        }
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.history(kind: .supplement, itemID: Self.itemID, cursor: "AbC_-09+/=", limit: 20)
        }
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.history(kind: .supplement, itemID: Self.itemID, cursor: nil, limit: 51)
        }
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.history(kind: .supplement, itemID: Self.itemID, cursor: nil, limit: 0)
        }
        await #expect(throws: BodyFlowCapabilityError.invalidInput) {
            try await repository.record(try attempt(try RoutineActionCommand(
                kind: .supplement, itemID: "supplement/1", status: .taken,
                reminderRuleID: Self.ruleID, scheduledFor: Self.scheduledFor,
                occurredAt: Self.occurredAt, snoozedUntil: nil
            ), key: "mobile-test-routine-3"))
        }
        #expect(await spy.requests.isEmpty)
    }

    @Test("transport failures land on the routine capability states")
    func transportFailuresMap() async throws {
        let cases: [(MobileAPITransportError, BodyFlowCapabilityError)] = [
            (.conflict(code: "routine_transition_invalid", requestID: nil), .routineTransitionInvalid),
            (.validation(code: "routine_snooze_invalid", requestID: nil), .routineSnoozeInvalid),
            (.validation(code: "occurred_at_out_of_range", requestID: nil), .invalidInput),
            (.conflict(code: "idempotency_key_conflict", requestID: nil), .idempotencyConflict),
            (.conflict(code: "idempotency_request_in_progress", requestID: nil), .idempotencyRequestInProgress),
            (.http(status: 404, code: "routine_item_not_found", requestID: nil), .serviceUnavailable),
            (.http(status: 402, code: "subscription_required", requestID: nil), .subscriptionRequired),
            (.network, .offline),
            (.missingSession, .operationUnavailable),
            (.server(status: 500, code: "internal_error", requestID: nil), .serviceUnavailable),
        ]
        for (failure, expected) in cases {
            let spy = RoutineTransportSpy(responseJSON: Self.receiptJSON, failure: failure)
            let repository = MobileRoutineRepository(transport: spy)
            await #expect(throws: expected) {
                try await repository.record(try attempt(try RoutineActionCommand(
                    kind: .supplement, itemID: Self.itemID, status: .taken,
                    reminderRuleID: Self.ruleID, scheduledFor: Self.scheduledFor,
                    occurredAt: Self.occurredAt, snoozedUntil: nil
                ), key: "mobile-test-routine-4"))
            }
        }
    }
}

private actor RoutineTransportSpy: MobileAPIEnvelopeExecuting {
    struct Recorded: Sendable {
        let method: HTTPMethod
        let path: String
        let queryItems: [URLQueryItem]
        let body: Data?
        let idempotency: MobileAPIIdempotency
    }

    private(set) var requests: [Recorded] = []
    private let responseJSON: Data
    private let failure: MobileAPITransportError?

    init(responseJSON: Data, failure: MobileAPITransportError? = nil) {
        self.responseJSON = responseJSON
        self.failure = failure
    }

    func executeEnvelope<Response: Codable & Sendable>(
        _ request: MobileAPIRequest<Response>
    ) async throws -> MobileResponse<Response> {
        requests.append(Recorded(
            method: request.method, path: request.path, queryItems: request.queryItems,
            body: request.body, idempotency: request.idempotency
        ))
        if let failure { throw failure }
        return try JSONDecoder().decode(MobileResponse<Response>.self, from: responseJSON)
    }
}
