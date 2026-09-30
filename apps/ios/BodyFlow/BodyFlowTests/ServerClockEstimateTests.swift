import Foundation
import Testing

@testable import BodyFlow

@Suite("Server clock estimate")
struct ServerClockEstimateTests {
    // 2026-09-29 19:05:00 UTC = 16:05 BRT.
    private static let serverDue = Date(timeIntervalSince1970: 1_790_708_700)

    @Test("an IMF-fixdate header is read in GMT")
    func parsesTheHTTPDate() {
        #expect(ServerClockEstimate.parse("Tue, 29 Sep 2026 19:05:00 GMT") == Self.serverDue)
        #expect(ServerClockEstimate.parse("29/09/2026 19:05") == nil)
        #expect(ServerClockEstimate.parse("") == nil)
    }

    @Test("with no readable header the phone's clock is used unchanged")
    func noHeaderKeepsThePhoneClock() {
        let clock = ServerClockEstimate()
        let phone = Self.serverDue
        clock.record(dateHeader: nil, receivedAt: phone)
        clock.record(dateHeader: "not a date", receivedAt: phone)
        #expect(clock.offset == nil)
        #expect(clock.serverNow(deviceNow: phone) == phone)
    }

    // Finding (adversarial review, 2026-09-29): a phone 2 min ahead opened
    // Tomado at its 16:05 while the server was at 16:03 and refused it.
    @Test("a phone two minutes ahead does not open a 16:05 occurrence at the server's 16:03")
    func phoneAheadWaitsForTheServer() {
        let clock = ServerClockEstimate()
        let serverAt1603 = "Tue, 29 Sep 2026 19:03:00 GMT"
        let phoneAt1605 = Self.serverDue
        clock.record(dateHeader: serverAt1603, receivedAt: phoneAt1605)
        #expect(clock.offset == -120)

        let schedule = RoutineScheduleSnapshot(
            id: "rule-1605",
            localTime: "16:05",
            weekdays: [0, 1, 2, 3, 4, 5, 6],
            occurrence: RoutineOccurrenceSnapshot(
                scheduledFor: APITimestamp(value: Self.serverDue),
                status: "pending",
                lastActionAt: nil,
                snoozedUntil: nil
            )
        )
        let early = RoutineActionConfiguration(
            kind: .medication,
            itemID: "medication-1",
            schedules: [schedule],
            now: clock.serverNow(deviceNow: phoneAt1605)
        )
        #expect(early.context == nil)
        #expect(early.upcoming?.localTime == "16:05")

        let due = RoutineActionConfiguration(
            kind: .medication,
            itemID: "medication-1",
            schedules: [schedule],
            now: clock.serverNow(deviceNow: phoneAt1605.addingTimeInterval(120))
        )
        #expect(due.context?.reminderRuleID == "rule-1605")
    }

    @Test("the latest response replaces an older reading")
    func latestReadingWins() {
        let clock = ServerClockEstimate()
        clock.record(dateHeader: "Tue, 29 Sep 2026 19:03:00 GMT", receivedAt: Self.serverDue)
        clock.record(dateHeader: "Tue, 29 Sep 2026 19:05:10 GMT", receivedAt: Self.serverDue)
        #expect(clock.offset == 10)
    }
}
