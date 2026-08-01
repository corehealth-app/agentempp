import Foundation
import Testing

@testable import BodyFlow

@Suite("Routine presentation")
struct RoutinePresentationTests {
    @Test("item presentation keeps response schedule order, local times and textual statuses")
    func itemPresentationIsLiteral() {
        let item = RoutineItemSnapshot(id: "supplement-1", kind: .supplement, name: "Creatina", doseText: "3 g", origin: "professional", remindersEnabled: true, active: true, archivedAt: nil, version: 1, createdAt: Self.timestamp, updatedAt: Self.timestamp, frequencySummary: RoutineFrequencySummary(timesPerWeek: 6), schedules: [
            RoutineScheduleSnapshot(id: "rule-evening", localTime: "20:15", weekdays: [1, 3, 5], occurrence: RoutineOccurrenceSnapshot(scheduledFor: Self.timestamp, status: "snoozed", lastActionAt: Self.timestamp, snoozedUntil: Self.timestamp)),
            RoutineScheduleSnapshot(id: "rule-morning", localTime: "07:30", weekdays: [0, 2, 4], occurrence: nil),
        ])

        let presentation = RoutineItemPresentation(item: item)
        #expect(presentation.name == "Creatina")
        #expect(presentation.schedules.map(\.localTime) == ["20:15", "07:30"])
        #expect(presentation.schedules.map(\.status) == ["snoozed", nil])
        #expect(presentation.schedules.map(\.weekdays) == [[1, 3, 5], [0, 2, 4]])
    }

    @Test("history presentation exposes exact response rows in response order")
    func historyRowsAreLiteral() {
        let newest = Self.history(id: "newest", status: "skipped")
        let older = Self.history(id: "older", status: "taken")
        let presentation = RoutineHistoryPresentation(snapshot: RoutineHistorySnapshot(items: [newest, older], nextCursor: nil))
        #expect(presentation.rows == [newest, older])
        #expect(!presentation.canLoadMore)
    }

    @Test("empty and unavailable presentation stay different")
    func emptyAndUnavailableStayDifferent() {
        #expect(RoutineListPresentation.state(for: .empty) == .empty)
        #expect(RoutineListPresentation.state(for: .unavailable) == .unavailable)
    }

    private static func history(id: String, status: String) -> RoutineHistoryItem {
        RoutineHistoryItem(id: id, routineItemID: "supplement-1", kind: .supplement, status: status, reminderRuleID: "rule-1", scheduledFor: timestamp, occurredAt: timestamp, snoozedUntil: nil, source: "patient", supersedesLogID: nil, createdAt: timestamp)
    }

    private static let timestamp = APITimestamp(value: Date(timeIntervalSince1970: 1_784_588_460))
}
