protocol PlanProviding: Sendable {
    func plan() async throws -> PlanResponse
}
