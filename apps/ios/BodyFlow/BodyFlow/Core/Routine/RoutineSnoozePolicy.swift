import Foundation

enum RoutineSnoozeSelection: Hashable, Sendable {
    case minutes(Int)
    case custom(Date)
}

struct RoutineSnoozePolicy: Sendable {
    private static let supportedPresetMinutes: Set<Int> = [15, 30, 60]

    private let calendar: Calendar

    init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    init(context: PatientTimeZoneContext) throws {
        self.init(timeZone: try context.requireTimeZone())
    }

    func date(
        for selection: RoutineSnoozeSelection,
        scheduledFor: Date,
        occurredAt: Date
    ) -> Date? {
        guard calendar.isDate(scheduledFor, inSameDayAs: occurredAt) else {
            return nil
        }

        let candidate: Date
        switch selection {
        case let .minutes(minutes):
            guard Self.supportedPresetMinutes.contains(minutes) else {
                return nil
            }
            candidate = occurredAt.addingTimeInterval(TimeInterval(minutes * 60))
        case let .custom(customDate):
            candidate = customDate
        }

        guard candidate > occurredAt,
              calendar.isDate(scheduledFor, inSameDayAs: candidate) else {
            return nil
        }

        return candidate
    }
}
