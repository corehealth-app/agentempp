import Foundation
import Observation

@MainActor
@Observable
final class RoutineDetailViewModel {
    let kind: RoutineItemKind
    let itemID: String
    private let listModel: RoutineListViewModel

    var item: RoutineItemSnapshot? {
        listModel.snapshot?.items.first { $0.id == itemID && $0.kind == kind }
    }

    init(
        kind: RoutineItemKind,
        itemID: String,
        listModel: RoutineListViewModel
    ) {
        self.kind = kind
        self.itemID = itemID
        self.listModel = listModel
    }

    func resolveFromTodayIfNeeded() async {
        guard listModel.snapshot == nil else { return }
        await listModel.load(revision: 0)
    }
}

/// Captures the two allowed detail origins. A list-origin detail receives the
/// existing owner; a Today-origin detail creates exactly one list owner/read.
@MainActor
final class RoutineDetailEntry {
    let listModel: RoutineListViewModel
    let detailModel: RoutineDetailViewModel
    private let loadsFromToday: Bool

    init(
        kind: RoutineItemKind,
        itemID: String,
        listModel: RoutineListViewModel
    ) {
        self.listModel = listModel
        detailModel = RoutineDetailViewModel(
            kind: kind,
            itemID: itemID,
            listModel: listModel
        )
        loadsFromToday = false
    }

    init(
        kind: RoutineItemKind,
        itemID: String,
        provider: any RoutineProviding
    ) {
        let listModel = RoutineListViewModel(kind: kind, provider: provider)
        self.listModel = listModel
        detailModel = RoutineDetailViewModel(
            kind: kind,
            itemID: itemID,
            listModel: listModel
        )
        loadsFromToday = true
    }

    func loadFromToday(revision: Int) async {
        guard loadsFromToday else { return }
        await listModel.load(revision: revision)
    }
}
