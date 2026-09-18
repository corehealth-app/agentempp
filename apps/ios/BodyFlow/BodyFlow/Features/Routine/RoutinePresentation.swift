import Foundation

struct RoutineSchedulePresentation: Equatable, Sendable {
    let id: String
    let localTime: String
    let weekdays: [Int]
    let status: String?

    init(schedule: RoutineScheduleSnapshot) {
        id = schedule.id
        localTime = schedule.localTime
        weekdays = schedule.weekdays
        status = schedule.occurrence?.status
    }
}

struct RoutineItemPresentation: Equatable, Sendable {
    let id: String
    let kind: RoutineItemKind
    let name: String
    let schedules: [RoutineSchedulePresentation]

    init(item: RoutineItemSnapshot) {
        id = item.id
        kind = item.kind
        name = item.name
        schedules = item.schedules.map(RoutineSchedulePresentation.init)
    }
}

struct RoutineHistoryPresentation: Equatable, Sendable {
    let rows: [RoutineHistoryItem]
    let canLoadMore: Bool

    init(snapshot: RoutineHistorySnapshot) {
        rows = snapshot.items
        canLoadMore = snapshot.nextCursor != nil
    }
}

struct RoutineHistoryRowPresentation: Equatable, Sendable, Identifiable {
    let id: String
    let rawStatus: String
    let statusLabel: String
    let scheduledForLabel: String?

    init(
        row: RoutineHistoryItem,
        patientTimeZone: PatientTimeZoneContext,
        language: SupportedAppLanguage
    ) {
        id = row.id
        rawStatus = row.status
        statusLabel = RoutineCopy.status(row.status, language: language)
        scheduledForLabel = Self.scheduledForLabel(
            row.scheduledFor.value,
            patientTimeZone: patientTimeZone,
            language: language
        )
    }

    private static func scheduledForLabel(
        _ date: Date,
        patientTimeZone: PatientTimeZoneContext,
        language: SupportedAppLanguage
    ) -> String? {
        guard let timeZone = try? patientTimeZone.requireTimeZone() else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = language.formattingLocale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct RoutineListPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable { case content, empty, unavailable, unavailableError }

    static func state(for readState: FeatureReadState<RoutineListSnapshot>) -> State {
        switch readState {
        case .empty: .empty
        case .unavailable: .unavailable
        case .loaded: .content
        case .idle, .loading, .offline, .failed: .unavailableError
        }
    }
}

enum RoutineCopy {
    static func string(
        _ key: String.LocalizationValue,
        language: SupportedAppLanguage
    ) -> String {
        (try? AppLocalization.string(key, for: language)) ?? String(localized: key)
    }

    static func status(
        _ rawStatus: String,
        language: SupportedAppLanguage
    ) -> String {
        let key: String.LocalizationValue? = switch rawStatus {
        case "taken": "routine.status.taken"
        case "snoozed": "routine.status.snoozed"
        case "skipped": "routine.status.skipped"
        case "pending": "routine.status.pending"
        default: nil
        }
        guard let key else { return rawStatus }
        return string(key, language: language)
    }
}
