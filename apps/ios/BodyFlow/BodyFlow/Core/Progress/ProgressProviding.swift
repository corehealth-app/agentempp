protocol ProgressProviding: Sendable {
    func progress() async throws -> ProgressResponse
    func profileWeight() async throws -> ProfileWeightResponse?
    /// The chart series for the last `days` days (direction v2, block G).
    func trends(days: Int) async throws -> TrendsResponse
}

extension ProgressProviding {
    /// Existing demo/preview providers have no separate profile capability.
    func profileWeight() async throws -> ProfileWeightResponse? { nil }

    /// Providers without a trends surface show the honest empty state.
    func trends(days: Int) async throws -> TrendsResponse {
        TrendsResponse(
            data: .empty(days: days),
            meta: MobileResponseMetadata(apiVersion: "v1", requestID: "trends-unavailable")
        )
    }
}
