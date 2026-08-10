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
