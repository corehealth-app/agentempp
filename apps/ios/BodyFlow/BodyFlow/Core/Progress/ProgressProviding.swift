protocol ProgressProviding: Sendable {
    func progress() async throws -> ProgressResponse
}
