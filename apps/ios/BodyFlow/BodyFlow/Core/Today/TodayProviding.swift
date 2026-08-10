protocol TodayProviding: Sendable {
    func today() async throws -> TodayResponse
}
