protocol HistoryProviding: Sendable {
    func history(_ query: HistoryQuery) async throws -> HistoryResponse
}
