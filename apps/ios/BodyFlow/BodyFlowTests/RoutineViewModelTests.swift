import Foundation
import Testing

@testable import BodyFlow

@Suite("Routine read models")
@MainActor
struct RoutineViewModelTests {
    @Test("list loads the provider order and excludes archived rows")
    func listLoadsProviderOrder() async throws {
        let first = Self.item(id: "supplement-z", name: "Zinco")
        let second = Self.item(id: "supplement-a", name: "Ácido fólico")
        let provider = RoutineReadProvider(
            lists: [.success(Self.list(items: [first, second]))]
        )
        let model = RoutineListViewModel(kind: .supplement, provider: provider)

        await model.load(revision: 0)

        #expect(model.state == .loaded(Self.list(items: [first, second]).data))
        #expect(await provider.listRequests == [
            RoutineListRequest(kind: .supplement, includeArchived: false),
        ])
    }

    @Test("empty, offline, error and unavailable list results stay distinct")
    func listStatesStayDistinct() async throws {
        let empty = RoutineListViewModel(
            kind: .supplement,
            provider: RoutineReadProvider(lists: [.success(Self.list(items: []))])
        )
        await empty.load(revision: 0)
        #expect(empty.state == .empty)

        let offline = RoutineListViewModel(
            kind: .supplement,
            provider: RoutineReadProvider(lists: [.failure(.offline)])
        )
        await offline.load(revision: 0)
        #expect(offline.state == .offline(previousValue: nil))

        let failed = RoutineListViewModel(
            kind: .supplement,
            provider: RoutineReadProvider(lists: [.failure(.serviceUnavailable)])
        )
        await failed.load(revision: 0)
        #expect(failed.state == .failed(previousValue: nil, error: .serviceUnavailable))

        let unavailable = RoutineListViewModel(
            kind: .supplement,
            provider: RoutineReadProvider(lists: [.failure(.operationUnavailable)])
        )
        await unavailable.load(revision: 0)
        #expect(unavailable.state == .unavailable)
    }

    @Test("a completed list revision reloads once and unrelated revisions do nothing")
    func listDeduplicatesRevisions() async throws {
        let provider = RoutineReadProvider(lists: [
            .success(Self.list(items: [Self.item(id: "first")])),
            .success(Self.list(items: [Self.item(id: "second")])),
        ])
        let model = RoutineListViewModel(kind: .supplement, provider: provider)

        await model.load(revision: 0)
        await model.load(revision: 0)
        await model.load(revision: -1)
        await model.load(revision: 1)

        #expect(await provider.listRequests == [
            RoutineListRequest(kind: .supplement, includeArchived: false),
            RoutineListRequest(kind: .supplement, includeArchived: false),
        ])
        #expect(model.state == .loaded(Self.list(items: [Self.item(id: "second")]).data))
    }

    @Test("detail resolves the loaded list snapshot without another provider call")
    func detailUsesLoadedListSnapshot() async throws {
        let listed = Self.item(id: "supplement-1", name: "Creatina")
        let provider = RoutineReadProvider(lists: [.success(Self.list(items: [listed]))])
        let list = RoutineListViewModel(kind: .supplement, provider: provider)
        await list.load(revision: 0)
        let detail = RoutineDetailViewModel(
            kind: .supplement,
            itemID: listed.id,
            listModel: list
        )

        #expect(detail.item == listed)
        #expect(await provider.listRequests == [
            RoutineListRequest(kind: .supplement, includeArchived: false),
        ])
    }

    @Test("detail entered from Today performs one active list read and selects its item")
    func detailFromTodayLoadsOnlyList() async throws {
        let listed = Self.item(id: "medication-1", kind: .medication)
        let provider = RoutineReadProvider(lists: [.success(Self.list(items: [listed]))])
        let list = RoutineListViewModel(kind: .medication, provider: provider)
        let detail = RoutineDetailViewModel(
            kind: .medication,
            itemID: listed.id,
            listModel: list
        )

        await detail.resolveFromTodayIfNeeded()

        #expect(detail.item == listed)
        #expect(await provider.listRequests == [
            RoutineListRequest(kind: .medication, includeArchived: false),
        ])
    }

    @Test("detail route composition reuses its list snapshot while Today owns one list read")
    func detailRouteCompositionSharesLoadedListAndLoadsTodayOnce() async throws {
        let listed = Self.item(id: "supplement-1", name: "Creatina")
        let provider = RoutineReadProvider(lists: [
            .success(Self.list(items: [listed])),
            .success(Self.list(items: [listed])),
        ])
        let list = RoutineListViewModel(kind: .supplement, provider: provider)
        await list.load(revision: 0)

        let fromList = RoutineDetailEntry(
            kind: .supplement,
            itemID: listed.id,
            listModel: list
        )
        #expect(fromList.detailModel.item == listed)
        #expect(await provider.listRequests.count == 1)
        await fromList.loadFromToday(revision: 1)
        #expect(await provider.listRequests.count == 1)

        let fromToday = RoutineDetailEntry(
            kind: .supplement,
            itemID: listed.id,
            provider: provider
        )
        await fromToday.loadFromToday(revision: 0)

        #expect(fromToday.detailModel.item == listed)
        #expect(await provider.listRequests == [
            RoutineListRequest(kind: .supplement, includeArchived: false),
            RoutineListRequest(kind: .supplement, includeArchived: false),
        ])
    }

    @Test("history appends only the second response after forwarding its opaque cursor")
    func historyAppendsUsingExactOpaqueCursor() async throws {
        let first = Self.history(id: "newest")
        let second = Self.history(id: "older")
        let cursor = "opaque::cursor/+=="
        let provider = RoutineReadProvider(histories: [
            .success(Self.page(items: [first], cursor: cursor)),
            .success(Self.page(items: [second], cursor: nil)),
        ])
        let model = RoutineHistoryViewModel(
            kind: .supplement,
            itemID: "supplement-1",
            provider: provider
        )

        await model.load(revision: 0)
        await model.loadMore()

        #expect(model.items == [first, second])
        #expect(model.nextCursor == nil)
        #expect(await provider.historyRequests == [
            RoutineHistoryRequest(kind: .supplement, itemID: "supplement-1", cursor: nil, limit: 20),
            RoutineHistoryRequest(kind: .supplement, itemID: "supplement-1", cursor: cursor, limit: 20),
        ])
    }

    @Test("history with nil cursor has no load more operation")
    func historyWithoutCursorDoesNotLoadMore() async throws {
        let provider = RoutineReadProvider(histories: [
            .success(Self.page(items: [Self.history(id: "only")], cursor: nil)),
        ])
        let model = RoutineHistoryViewModel(
            kind: .medication,
            itemID: "medication-1",
            provider: provider
        )

        await model.load(revision: 0)
        await model.loadMore()

        #expect(model.nextCursor == nil)
        #expect(await provider.historyRequests == [
            RoutineHistoryRequest(kind: .medication, itemID: "medication-1", cursor: nil, limit: 20),
        ])
    }

    @Test("history revisions reload once for that kind and item")
    func historyDeduplicatesRevisions() async throws {
        let provider = RoutineReadProvider(histories: [
            .success(Self.page(items: [Self.history(id: "first")], cursor: nil)),
            .success(Self.page(items: [Self.history(id: "second")], cursor: nil)),
        ])
        let model = RoutineHistoryViewModel(
            kind: .supplement,
            itemID: "supplement-1",
            provider: provider
        )

        await model.load(revision: 4)
        await model.load(revision: 4)
        await model.load(revision: 5)

        #expect(model.items.map(\.id) == ["second"])
        #expect(await provider.historyRequests.count == 2)
    }

    @Test("cancelled list and first history page suppress their late complete snapshots")
    func cancelledReadLoadsSuppressLatePublication() async throws {
        let provider = LateRoutineReadProvider(
            list: Self.list(items: [Self.item(id: "late-list")]),
            history: Self.page(items: [Self.history(id: "late-history")], cursor: "late")
        )
        let list = RoutineListViewModel(kind: .supplement, provider: provider)
        let history = RoutineHistoryViewModel(kind: .supplement, itemID: "supplement-1", provider: provider)

        let listTask = Task { await list.load(revision: 0) }
        let historyTask = Task { await history.load(revision: 0) }
        try? await Task.sleep(for: .milliseconds(20))
        listTask.cancel()
        historyTask.cancel()
        await listTask.value
        await historyTask.value

        #expect(list.state == .idle)
        #expect(history.state == .idle)
        #expect(history.items.isEmpty)
        #expect(history.nextCursor == nil)
    }

    @Test("cancelled load more cannot append late rows or replace the opaque cursor")
    func cancelledLoadMoreSuppressesLateAppend() async throws {
        let first = Self.history(id: "first")
        let provider = PagingLateRoutineReadProvider(first: Self.page(items: [first], cursor: "opaque"), second: Self.page(items: [Self.history(id: "late")], cursor: nil))
        let model = RoutineHistoryViewModel(kind: .supplement, itemID: "supplement-1", provider: provider)
        await model.load(revision: 0)

        let more = Task { await model.loadMore() }
        try? await Task.sleep(for: .milliseconds(20))
        more.cancel()
        await more.value

        #expect(model.items == [first])
        #expect(model.nextCursor == "opaque")
    }

    @Test("newer list and history revisions supersede late older snapshots")
    func newerRevisionsSuppressOlderLatePublication() async throws {
        let oldItem = Self.item(id: "old")
        let newItem = Self.item(id: "new")
        let oldHistory = Self.history(id: "old-history")
        let newHistory = Self.history(id: "new-history")
        let provider = RevisionSupersedingRoutineProvider(
            oldList: Self.list(items: [oldItem]),
            newList: Self.list(items: [newItem]),
            oldHistory: Self.page(items: [oldHistory], cursor: "old-cursor"),
            newHistory: Self.page(items: [newHistory], cursor: "new-cursor")
        )
        let list = RoutineListViewModel(kind: .supplement, provider: provider)
        let history = RoutineHistoryViewModel(kind: .supplement, itemID: "supplement-1", provider: provider)
        let oldListTask = Task { await list.load(revision: 0) }
        let oldHistoryTask = Task { await history.load(revision: 0) }
        try? await Task.sleep(for: .milliseconds(20))
        await list.load(revision: 1)
        await history.load(revision: 1)
        await oldListTask.value
        await oldHistoryTask.value

        #expect(list.snapshot?.items.map(\.id) == ["new"])
        #expect(history.items.map(\.id) == ["new-history"])
        #expect(history.nextCursor == "new-cursor")
    }

    private static func list(items: [RoutineItemSnapshot]) -> RoutineListResponse {
        RoutineListResponse(
            data: RoutineListSnapshot(localDate: "2026-07-20", items: items),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "test-list")
        )
    }

    private static func page(
        items: [RoutineHistoryItem],
        cursor: String?
    ) -> RoutineHistoryPage {
        RoutineHistoryPage(
            data: RoutineHistorySnapshot(items: items, nextCursor: cursor),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "test-history")
        )
    }

    private static func item(
        id: String,
        name: String = "Creatina",
        kind: RoutineItemKind = .supplement
    ) -> RoutineItemSnapshot {
        RoutineItemSnapshot(
            id: id,
            kind: kind,
            name: name,
            doseText: "3 g",
            origin: "professional",
            remindersEnabled: true,
            active: true,
            archivedAt: nil,
            version: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            frequencySummary: RoutineFrequencySummary(timesPerWeek: 7),
            schedules: []
        )
    }

    private static func history(id: String) -> RoutineHistoryItem {
        RoutineHistoryItem(
            id: id,
            routineItemID: "supplement-1",
            kind: .supplement,
            status: "taken",
            reminderRuleID: "rule-1",
            scheduledFor: timestamp,
            occurredAt: timestamp,
            snoozedUntil: nil,
            source: "patient",
            supersedesLogID: nil,
            createdAt: timestamp
        )
    }

    private static let timestamp = APITimestamp(
        value: Date(timeIntervalSince1970: 1_784_588_460)
    )
}

actor LateRoutineReadProvider: RoutineProviding {
    let listResponse: RoutineListResponse
    let historyResponse: RoutineHistoryPage

    init(list: RoutineListResponse, history: RoutineHistoryPage) {
        listResponse = list
        historyResponse = history
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse {
        try? await Task.sleep(for: .milliseconds(100))
        return listResponse
    }

    func history(kind: RoutineItemKind, itemID: String, cursor: String?, limit: Int) async throws -> RoutineHistoryPage {
        try? await Task.sleep(for: .milliseconds(100))
        return historyResponse
    }

    func record(_ attempt: MutationAttempt<RoutineActionCommand>) async throws -> RoutineActionResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

actor RevisionSupersedingRoutineProvider: RoutineProviding {
    let oldList: RoutineListResponse
    let newList: RoutineListResponse
    let oldHistory: RoutineHistoryPage
    let newHistory: RoutineHistoryPage
    private var listCalls = 0
    private var historyCalls = 0

    init(oldList: RoutineListResponse, newList: RoutineListResponse, oldHistory: RoutineHistoryPage, newHistory: RoutineHistoryPage) {
        self.oldList = oldList
        self.newList = newList
        self.oldHistory = oldHistory
        self.newHistory = newHistory
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse {
        listCalls += 1
        if listCalls == 1 { try? await Task.sleep(for: .milliseconds(100)); return oldList }
        return newList
    }

    func history(kind: RoutineItemKind, itemID: String, cursor: String?, limit: Int) async throws -> RoutineHistoryPage {
        historyCalls += 1
        if historyCalls == 1 { try? await Task.sleep(for: .milliseconds(100)); return oldHistory }
        return newHistory
    }

    func record(_ attempt: MutationAttempt<RoutineActionCommand>) async throws -> RoutineActionResponse { throw BodyFlowCapabilityError.operationUnavailable }
}

actor PagingLateRoutineReadProvider: RoutineProviding {
    let first: RoutineHistoryPage
    let second: RoutineHistoryPage
    private var historyCall = 0

    init(first: RoutineHistoryPage, second: RoutineHistoryPage) {
        self.first = first
        self.second = second
    }

    func history(kind: RoutineItemKind, itemID: String, cursor: String?, limit: Int) async throws -> RoutineHistoryPage {
        historyCall += 1
        if historyCall == 1 { return first }
        try? await Task.sleep(for: .milliseconds(100))
        return second
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }

    func record(_ attempt: MutationAttempt<RoutineActionCommand>) async throws -> RoutineActionResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

actor RoutineReadProvider: RoutineProviding {
    enum ListResult: Sendable {
        case success(RoutineListResponse)
        case failure(BodyFlowCapabilityError)
    }

    enum HistoryResult: Sendable {
        case success(RoutineHistoryPage)
        case failure(BodyFlowCapabilityError)
    }

    private var lists: [ListResult]
    private var histories: [HistoryResult]
    private(set) var listRequests: [RoutineListRequest] = []
    private(set) var historyRequests: [RoutineHistoryRequest] = []

    init(lists: [ListResult] = [], histories: [HistoryResult] = []) {
        self.lists = lists
        self.histories = histories
    }

    func list(kind: RoutineItemKind, includeArchived: Bool) async throws -> RoutineListResponse {
        listRequests.append(RoutineListRequest(
            kind: kind,
            includeArchived: includeArchived
        ))
        guard !lists.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch lists.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }

    func history(
        kind: RoutineItemKind,
        itemID: String,
        cursor: String?,
        limit: Int
    ) async throws -> RoutineHistoryPage {
        historyRequests.append(RoutineHistoryRequest(
            kind: kind,
            itemID: itemID,
            cursor: cursor,
            limit: limit
        ))
        guard !histories.isEmpty else { throw BodyFlowCapabilityError.serviceUnavailable }
        switch histories.removeFirst() {
        case let .success(response): return response
        case let .failure(error): throw error
        }
    }

    func record(
        _ attempt: MutationAttempt<RoutineActionCommand>
    ) async throws -> RoutineActionResponse {
        throw BodyFlowCapabilityError.operationUnavailable
    }
}

struct RoutineListRequest: Equatable, Sendable {
    let kind: RoutineItemKind
    let includeArchived: Bool
}

struct RoutineHistoryRequest: Equatable, Sendable {
    let kind: RoutineItemKind
    let itemID: String
    let cursor: String?
    let limit: Int
}
