import Foundation
import Testing

@testable import BodyFlow

@Suite("Routine Contract")
struct RoutineContractTests {
    @Test("supplement list decodes the documented nested item and nullable occurrence fields")
    func decodesSupplementList() throws {
        let response = try decode(
            RoutineListResponse.self,
            from: supplementListJSON
        )

        #expect(response.meta.apiVersion == "v1")
        #expect(response.meta.requestID == "request-routine-supplement-list-0001")
        #expect(response.data.localDate == "2026-07-22")
        #expect(response.data.items.count == 1)

        let item = try #require(response.data.items.first)
        #expect(item.id == "11111111-1111-4111-8111-111111111111")
        #expect(item.kind == .supplement)
        #expect(item.name == "Creatina")
        #expect(item.doseText == "3 g")
        #expect(item.origin == "professional")
        #expect(item.remindersEnabled)
        #expect(item.active)
        #expect(item.archivedAt == nil)
        #expect(item.version == 1)
        #expect(item.frequencySummary.timesPerWeek == 14)
        #expect(item.schedules.map(\.id) == [
            "11111111-1111-4111-8111-111111111112",
            "11111111-1111-4111-8111-111111111113",
        ])
        let expectedLastActionAt = try date("2026-07-22T11:03:00.000Z")
        #expect(item.schedules[0].occurrence?.status == "taken")
        #expect(item.schedules[0].occurrence?.lastActionAt?.value == expectedLastActionAt)
        #expect(item.schedules[0].occurrence?.snoozedUntil == nil)
        #expect(item.schedules[1].occurrence?.status == "pending")
        #expect(item.schedules[1].occurrence?.lastActionAt == nil)
    }

    @Test("medication list preserves its discriminator and an absent DST occurrence")
    func decodesMedicationList() throws {
        let response = try decode(
            RoutineListResponse.self,
            from: medicationListJSON
        )

        let item = try #require(response.data.items.first)
        #expect(response.data.localDate == "2026-11-01")
        #expect(item.kind == .medication)
        #expect(item.name == "Medicamento cadastrado")
        #expect(item.frequencySummary.timesPerWeek == 7)
        #expect(item.schedules[0].localTime == "02:30")
        #expect(item.schedules[0].weekdays == [0, 1, 2, 3, 4, 5, 6])
        #expect(item.schedules[0].occurrence == nil)
    }

    @Test("item history decodes append-only fields and preserves its opaque cursor byte for byte")
    func decodesRoutineHistoryAndOpaqueCursor() throws {
        let response = try decode(
            RoutineHistoryPage.self,
            from: historyJSON
        )

        #expect(response.meta.requestID == "request-routine-history-0001")
        #expect(response.nextCursor == opaqueCursor)
        #expect(response.items.map(\.status) == ["taken", "missed"])

        let correction = try #require(response.items.first)
        #expect(correction.routineItemID == "11111111-1111-4111-8111-111111111111")
        #expect(correction.kind == .supplement)
        #expect(correction.reminderRuleID == "11111111-1111-4111-8111-111111111112")
        #expect(correction.snoozedUntil == nil)
        #expect(correction.source == "patient")
        #expect(correction.supersedesLogID == "11111111-1111-4111-8111-111111111115")
    }

    @Test("routine provider receives the server cursor unchanged")
    func providerPassesOpaqueCursorUnchanged() async throws {
        let page = try decode(RoutineHistoryPage.self, from: historyJSON)
        let provider = RoutineProviderCursorSpy(page: page)

        let received = try await provider.history(
            kind: .supplement,
            itemID: "11111111-1111-4111-8111-111111111111",
            cursor: page.nextCursor,
            limit: 20
        )

        #expect(received.nextCursor == opaqueCursor)
        #expect(await provider.lastCursor() == opaqueCursor)
    }

    @Test("routine action command encodes the documented body without an internal occurrence key")
    func actionCommandEncodesOnlyDocumentedBody() throws {
        let command = try RoutineActionCommand(
            kind: .supplement,
            itemID: "11111111-1111-4111-8111-111111111111",
            status: .snoozed,
            reminderRuleID: "11111111-1111-4111-8111-111111111113",
            scheduledFor: timestamp("2026-07-22T23:00:00.000Z"),
            occurredAt: timestamp("2026-07-22T23:01:00.000Z"),
            snoozedUntil: timestamp("2026-07-22T23:31:00.000Z")
        )

        let object = try encodedObject(command)
        let expected: NSDictionary = [
            "status": "snoozed",
            "reminder_rule_id": "11111111-1111-4111-8111-111111111113",
            "scheduled_for": "2026-07-22T23:00:00Z",
            "occurred_at": "2026-07-22T23:01:00Z",
            "snoozed_until": "2026-07-22T23:31:00Z",
        ]

        #expect(command.kind == .supplement)
        #expect(command.itemID == "11111111-1111-4111-8111-111111111111")
        #expect(object == expected)
        #expect(object["item_type"] == nil)
        #expect(object["item_id"] == nil)
        #expect(object["occurrence_key"] == nil)
    }

    @Test("routine action receipt keeps the documented MobileResponse envelope")
    func decodesRoutineActionReceipt() throws {
        let response = try decode(
            RoutineActionResponse.self,
            from: """
            {
              "data": {
                "adherence_log_id": "11111111-1111-4111-8111-111111111114",
                "occurrence_key": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "item_type": "supplement",
                "status": "snoozed"
              },
              "meta": {"api_version": "v1", "request_id": "request-routine-log-0001"}
            }
            """
        )

        #expect(response.data.adherenceLogID == "11111111-1111-4111-8111-111111111114")
        #expect(response.data.occurrenceKey == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(response.data.kind == .supplement)
        #expect(response.data.status == "snoozed")
    }

    @Test(
        "hydration accepts its inclusive integer boundaries",
        arguments: [1, 5_000]
    )
    func hydrationAcceptsBoundaries(amountML: Int) throws {
        let command = try HydrationCommand(
            amountML: amountML,
            occurredAt: timestamp("2026-07-22T12:00:00.000Z")
        )

        #expect(command.amountML == amountML)
        #expect(try encodedObject(command)["amount_ml"] as? Int == amountML)
    }

    @Test(
        "hydration rejects values outside its literal integer boundaries",
        arguments: [0, 5_001]
    )
    func hydrationRejectsOutOfRange(amountML: Int) throws {
        #expect(throws: RoutineCommandValidationError.invalidHydrationAmount) {
            try HydrationCommand(
                amountML: amountML,
                occurredAt: timestamp("2026-07-22T12:00:00.000Z")
            )
        }
    }

    @Test(
        "hydration decoding rejects amounts outside the validated command boundary",
        arguments: [0, 5_001]
    )
    func hydrationDecodeRejectsOutOfRange(amountML: Int) {
        #expect(throws: RoutineCommandValidationError.invalidHydrationAmount) {
            try decode(
                HydrationCommand.self,
                from: """
                {
                  "amount_ml": \(amountML),
                  "occurred_at": "2026-07-22T12:00:00.000Z"
                }
                """
            )
        }
    }

    @Test(
        "hydration validated boundaries survive a Codable round trip",
        arguments: [1, 5_000]
    )
    func hydrationBoundariesRoundTrip(amountML: Int) throws {
        let original = try HydrationCommand(
            amountML: amountML,
            occurredAt: timestamp("2026-07-22T12:00:00.000Z")
        )

        let decoded = try JSONDecoder().decode(
            HydrationCommand.self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded == original)
        #expect(decoded.amountML == amountML)
    }

    @Test("hydration receipt keeps the documented MobileResponse envelope")
    func decodesHydrationReceipt() throws {
        let receipt = try decode(
            HydrationReceipt.self,
            from: """
            {
              "data": {
                "hydration_log_id": "33333333-3333-4333-8333-333333333333",
                "inserted": true,
                "water_consumed_ml": 850
              },
              "meta": {"api_version": "v1", "request_id": "hydration-request-0001"}
            }
            """
        )

        #expect(receipt.data.hydrationLogID == "33333333-3333-4333-8333-333333333333")
        #expect(receipt.data.inserted)
        #expect(receipt.data.waterConsumedML == 850)
    }

    @Test(
        "weight accepts the approved inclusive app-only boundaries",
        arguments: [30.0, 300.0]
    )
    func weightAcceptsBoundaries(weightKG: Double) throws {
        let recordedAt = try date("2026-07-22T12:00:00.000Z")
        let command = try WeightCommand(weightKG: weightKG, recordedAt: recordedAt)

        #expect(command.weightKG == weightKG)
        #expect(command.recordedAt == recordedAt)
    }

    @Test(
        "weight rejects values outside the approved app-only boundaries without clamping",
        arguments: [29.99, 300.01]
    )
    func weightRejectsOutOfRange(weightKG: Double) throws {
        #expect(throws: RoutineCommandValidationError.invalidWeight) {
            try WeightCommand(
                weightKG: weightKG,
                recordedAt: date("2026-07-22T12:00:00.000Z")
            )
        }
    }

    @Test("routine core surface contains no detail or request transport capability")
    func routineCoreHasNoDetailOrTransportSurface() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let routineDirectory = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "BodyFlow/Core/Routine", directoryHint: .isDirectory)
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: routineDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        #expect(!sourceFiles.isEmpty)

        let forbiddenPatterns = [
            #"\bRoutineDetail\w*\b"#,
            #"\bfunc\s+detail\s*\("#,
            #"\bAPIRequest\b"#,
            #"(?:supplements|medications)/[^\s\"]+/detail"#,
        ]

        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for pattern in forbiddenPatterns {
                let match = source.range(
                    of: pattern,
                    options: .regularExpression
                )
                #expect(match == nil, "Forbidden routine surface in \(sourceFile.lastPathComponent): \(pattern)")
            }
        }
    }
}

private actor RoutineProviderCursorSpy: RoutineProviding {
    private let page: RoutineHistoryPage
    private var cursor: String?

    init(page: RoutineHistoryPage) {
        self.page = page
    }

    func list(
        kind: RoutineItemKind,
        includeArchived: Bool
    ) async throws -> RoutineListResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func record(
        _ attempt: MutationAttempt<RoutineActionCommand>
    ) async throws -> RoutineActionResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func history(
        kind: RoutineItemKind,
        itemID: String,
        cursor: String?,
        limit: Int
    ) async throws -> RoutineHistoryPage {
        self.cursor = cursor
        return page
    }

    func lastCursor() -> String? {
        cursor
    }
}

private let opaqueCursor = "AbC_-09+/=.%2F?keep-byte-for-byte"

private let supplementListJSON = """
{
  "data": {
    "local_date": "2026-07-22",
    "items": [{
      "id": "11111111-1111-4111-8111-111111111111",
      "item_type": "supplement",
      "name": "Creatina",
      "dose_text": "3 g",
      "origin": "professional",
      "reminders_enabled": true,
      "active": true,
      "archived_at": null,
      "version": 1,
      "created_at": "2026-07-22T10:00:00.000Z",
      "updated_at": "2026-07-22T10:00:00.000Z",
      "frequency_summary": {"times_per_week": 14},
      "schedules": [
        {
          "id": "11111111-1111-4111-8111-111111111112",
          "local_time": "08:00",
          "weekdays": [0, 1, 2, 3, 4, 5, 6],
          "occurrence": {
            "scheduled_for": "2026-07-22T11:00:00.000Z",
            "status": "taken",
            "last_action_at": "2026-07-22T11:03:00.000Z",
            "snoozed_until": null
          }
        },
        {
          "id": "11111111-1111-4111-8111-111111111113",
          "local_time": "20:00",
          "weekdays": [0, 1, 2, 3, 4, 5, 6],
          "occurrence": {
            "scheduled_for": "2026-07-22T23:00:00.000Z",
            "status": "pending",
            "last_action_at": null,
            "snoozed_until": null
          }
        }
      ],
      "future_item_field": "ignored"
    }]
  },
  "meta": {"api_version": "v1", "request_id": "request-routine-supplement-list-0001"}
}
"""

private let medicationListJSON = """
{
  "data": {
    "local_date": "2026-11-01",
    "items": [{
      "id": "22222222-2222-4222-8222-222222222221",
      "item_type": "medication",
      "name": "Medicamento cadastrado",
      "dose_text": "1 comprimido",
      "origin": "professional",
      "reminders_enabled": true,
      "active": true,
      "archived_at": null,
      "version": 1,
      "created_at": "2026-07-22T10:15:00.000Z",
      "updated_at": "2026-07-22T10:15:00.000Z",
      "frequency_summary": {"times_per_week": 7},
      "schedules": [{
        "id": "22222222-2222-4222-8222-222222222222",
        "local_time": "02:30",
        "weekdays": [0, 1, 2, 3, 4, 5, 6],
        "occurrence": null
      }]
    }]
  },
  "meta": {"api_version": "v1", "request_id": "request-routine-medication-list-0001"}
}
"""

private let historyJSON = """
{
  "data": {
    "items": [
      {
        "id": "11111111-1111-4111-8111-111111111116",
        "routine_item_id": "11111111-1111-4111-8111-111111111111",
        "item_type": "supplement",
        "status": "taken",
        "reminder_rule_id": "11111111-1111-4111-8111-111111111112",
        "scheduled_for": "2026-07-22T11:00:00.000Z",
        "occurred_at": "2026-07-23T12:00:00.000Z",
        "snoozed_until": null,
        "source": "patient",
        "supersedes_log_id": "11111111-1111-4111-8111-111111111115",
        "created_at": "2026-07-23T12:00:01.000Z"
      },
      {
        "id": "11111111-1111-4111-8111-111111111115",
        "routine_item_id": "11111111-1111-4111-8111-111111111111",
        "item_type": "supplement",
        "status": "missed",
        "reminder_rule_id": "11111111-1111-4111-8111-111111111112",
        "scheduled_for": "2026-07-22T11:00:00.000Z",
        "occurred_at": "2026-07-23T03:00:00.000Z",
        "snoozed_until": null,
        "source": "system",
        "supersedes_log_id": null,
        "created_at": "2026-07-23T03:00:01.000Z"
      }
    ],
    "next_cursor": "AbC_-09+/=.%2F?keep-byte-for-byte"
  },
  "meta": {"api_version": "v1", "request_id": "request-routine-history-0001"}
}
"""

private func decode<Value: Decodable>(
    _ type: Value.Type,
    from json: String
) throws -> Value {
    try JSONDecoder().decode(Value.self, from: Data(json.utf8))
}

private func encodedObject<Value: Encodable>(
    _ value: Value
) throws -> NSDictionary {
    try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            as? NSDictionary
    )
}

private func timestamp(_ value: String) throws -> APITimestamp {
    try decode(APITimestamp.self, from: "\"\(value)\"")
}

private func date(_ value: String) throws -> Date {
    try timestamp(value).value
}
