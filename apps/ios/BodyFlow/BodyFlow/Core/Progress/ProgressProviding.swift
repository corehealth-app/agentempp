protocol ProgressProviding: Sendable {
    func progress() async throws -> ProgressResponse
    func profileWeight() async throws -> ProfileWeightResponse?
}

extension ProgressProviding {
    /// Existing demo/preview providers have no separate profile capability.
    func profileWeight() async throws -> ProfileWeightResponse? { nil }
}
