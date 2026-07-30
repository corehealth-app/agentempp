import Foundation
import Testing

@testable import BodyFlow

@Suite("Routine Snooze Policy")
struct RoutineSnoozePolicyTests {
    @Test(
        "taken and skipped reject a snooze time",
        arguments: [RoutineActionStatus.taken, .skipped]
    )
    func terminalActionsRejectSnoozeTime(status: RoutineActionStatus) throws {
        #expect(throws: RoutineCommandValidationError.invalidSnoozeStructure) {
            try RoutineActionCommand(
                kind: .medication,
                itemID: "item-1",
                status: status,
                reminderRuleID: "rule-1",
                scheduledFor: timestamp("2026-07-22T11:00:00.000Z"),
                occurredAt: timestamp("2026-07-22T11:01:00.000Z"),
                snoozedUntil: timestamp("2026-07-22T11:16:00.000Z")
            )
        }
    }

    @Test("snoozed requires a snooze time")
    func snoozedRequiresSnoozeTime() throws {
        #expect(throws: RoutineCommandValidationError.invalidSnoozeStructure) {
            try RoutineActionCommand(
                kind: .supplement,
                itemID: "item-1",
                status: .snoozed,
                reminderRuleID: "rule-1",
                scheduledFor: timestamp("2026-07-22T11:00:00.000Z"),
                occurredAt: timestamp("2026-07-22T11:01:00.000Z"),
                snoozedUntil: nil
            )
        }
    }

    @Test(
        "presets add 15 30 or 60 minutes to the injected occurrence time",
        arguments: [
            PresetExpectation(minutes: 15, expected: "2026-07-22T14:35:00.000Z"),
            PresetExpectation(minutes: 30, expected: "2026-07-22T14:50:00.000Z"),
            PresetExpectation(minutes: 60, expected: "2026-07-22T15:20:00.000Z"),
        ]
    )
    func presetsAreBasedOnOccurredAt(expectation: PresetExpectation) throws {
        let time = RoutineTimeProviderStub(
            now: try date("2026-07-22T14:20:00.000Z")
        )
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())
        let expected = try date(expectation.expected)

        #expect(policy.date(
            for: .minutes(expectation.minutes),
            scheduledFor: try date("2026-07-22T11:00:00.000Z"),
            occurredAt: time.now
        ) == expected)
    }

    @Test("unsupported minute values are unavailable")
    func rejectsUnsupportedMinutePreset() throws {
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())

        #expect(policy.date(
            for: .minutes(14),
            scheduledFor: try date("2026-07-22T11:00:00.000Z"),
            occurredAt: try date("2026-07-22T11:01:00.000Z")
        ) == nil)
    }

    @Test("custom snooze must be strictly later than occurredAt")
    func customMustBeLater() throws {
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())
        let occurredAt = try date("2026-07-22T14:20:00.000Z")

        #expect(policy.date(
            for: .custom(occurredAt),
            scheduledFor: try date("2026-07-22T11:00:00.000Z"),
            occurredAt: occurredAt
        ) == nil)
        #expect(policy.date(
            for: .custom(try date("2026-07-22T14:19:59.000Z")),
            scheduledFor: try date("2026-07-22T11:00:00.000Z"),
            occurredAt: occurredAt
        ) == nil)
    }

    @Test("custom snooze later on the original patient-local date remains available")
    func acceptsLaterCustomTimeOnOriginalLocalDate() throws {
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())
        let custom = try date("2026-07-23T02:59:59.000Z")

        #expect(policy.date(
            for: .custom(custom),
            scheduledFor: try date("2026-07-22T23:00:00.000Z"),
            occurredAt: try date("2026-07-23T02:00:00.000Z")
        ) == custom)
    }

    @Test("occurredAt outside the original occurrence local date rejects snooze")
    func occurredAtOutsideOriginalDateIsUnavailable() throws {
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())

        #expect(policy.date(
            for: .minutes(15),
            scheduledFor: try date("2026-07-22T23:00:00.000Z"),
            occurredAt: try date("2026-07-23T03:00:00.000Z")
        ) == nil)
    }

    @Test("preset crossing the patient local date is unavailable")
    func crossingDatePresetIsUnavailable() throws {
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())

        #expect(policy.date(
            for: .minutes(60),
            scheduledFor: try date("2026-07-22T23:00:00.000Z"),
            occurredAt: try date("2026-07-23T02:30:00.000Z")
        ) == nil)
    }

    @Test("custom time crossing the patient local date is unavailable")
    func crossingDateCustomTimeIsUnavailable() throws {
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())

        #expect(policy.date(
            for: .custom(try date("2026-07-23T03:00:00.000Z")),
            scheduledFor: try date("2026-07-22T23:00:00.000Z"),
            occurredAt: try date("2026-07-23T02:30:00.000Z")
        ) == nil)
    }

    @Test("crossing-date preset is unavailable rather than clamped to the date edge")
    func crossingDatePresetNeverClamps() throws {
        let policy = RoutineSnoozePolicy(timeZone: try saoPaulo())
        let endOfOriginalLocalDate = try date("2026-07-23T02:59:59.999Z")

        let result = policy.date(
            for: .minutes(60),
            scheduledFor: try date("2026-07-22T23:00:00.000Z"),
            occurredAt: try date("2026-07-23T02:30:00.000Z")
        )

        #expect(result == nil)
        #expect(result != endOfOriginalLocalDate)
    }

    @Test("DST edge availability differs between the injected New York and UTC dates")
    func validatesDSTEdgeInInjectedTimeZone() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let utc = try #require(TimeZone(identifier: "Etc/UTC"))
        let newYorkPolicy = RoutineSnoozePolicy(timeZone: newYork)
        let utcPolicy = RoutineSnoozePolicy(timeZone: utc)
        let scheduledFor = try date("2026-11-01T03:30:00.000Z")
        let occurredAt = try date("2026-11-01T03:45:00.000Z")
        let expectedUTCResult = try date("2026-11-01T04:15:00.000Z")

        let newYorkResult = newYorkPolicy.date(
            for: .minutes(30),
            scheduledFor: scheduledFor,
            occurredAt: occurredAt
        )
        let utcResult = utcPolicy.date(
            for: .minutes(30),
            scheduledFor: scheduledFor,
            occurredAt: occurredAt
        )

        #expect(newYorkResult == nil)
        #expect(utcResult == expectedUTCResult)
    }

    @Test("documented patient timezone context resolves an explicit IANA identifier")
    func resolvesDocumentedPatientTimeZone() throws {
        let context = PatientTimeZoneContext(
            documentedIANAIdentifier: "Pacific/Auckland"
        )

        #expect(try context.requireTimeZone().identifier == "Pacific/Auckland")
    }

    @Test("missing invalid abbreviated or offset patient timezone fails closed")
    func unavailablePatientTimeZoneFailsClosed() {
        for context in [
            PatientTimeZoneContext(documentedIANAIdentifier: nil),
            PatientTimeZoneContext(documentedIANAIdentifier: "Not/A_Time_Zone"),
            PatientTimeZoneContext(documentedIANAIdentifier: "PST"),
            PatientTimeZoneContext(documentedIANAIdentifier: "GMT+03:00"),
        ] {
            #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try context.requireTimeZone()
            }
        }
    }

    @Test("snooze policy rejects unavailable timezone context before date validation")
    func policyRejectsUnavailableTimeZoneContext() {
        for context in [
            PatientTimeZoneContext(documentedIANAIdentifier: nil),
            PatientTimeZoneContext(documentedIANAIdentifier: "Not/A_Time_Zone"),
            PatientTimeZoneContext(documentedIANAIdentifier: "PST"),
            PatientTimeZoneContext(documentedIANAIdentifier: "GMT+03:00"),
        ] {
            #expect(throws: BodyFlowCapabilityError.operationUnavailable) {
                try RoutineSnoozePolicy(context: context)
            }
        }
    }

    #if DEBUG
    @Test("Debug installs a deterministic patient timezone instead of TimeZone.current")
    func debugPatientTimeZoneIsFixed() throws {
        #expect(PatientTimeZoneContext.appDefault.documentedIANAIdentifier == "America/Sao_Paulo")
        #expect(try PatientTimeZoneContext.appDefault.requireTimeZone().identifier == "America/Sao_Paulo")
    }
    #endif
}

struct PresetExpectation: Sendable, CustomTestStringConvertible {
    let minutes: Int
    let expected: String

    var testDescription: String {
        "\(minutes) minutes"
    }
}

private struct RoutineTimeProviderStub: TimeProviding {
    let now: Date
}

private func saoPaulo() throws -> TimeZone {
    try #require(TimeZone(identifier: "America/Sao_Paulo"))
}

private func timestamp(_ value: String) throws -> APITimestamp {
    try JSONDecoder().decode(
        APITimestamp.self,
        from: Data("\"\(value)\"".utf8)
    )
}

private func date(_ value: String) throws -> Date {
    try timestamp(value).value
}
