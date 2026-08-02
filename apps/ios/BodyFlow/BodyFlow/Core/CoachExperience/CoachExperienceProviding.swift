protocol CoachExperienceProviding: Sendable {
    func coachExperience() async throws -> CoachExperienceResponse
}
