protocol CoachExperienceProviding: Sendable {
    func coachExperience() async throws -> CoachExperienceResponse
}

struct CoachExperienceV1PresentationContract: Sendable {
    static let version = "bodyflow.coach-persona.v1"

    static func validatedSnapshot(
        from response: CoachExperienceResponse
    ) -> CoachExperienceSnapshot? {
        guard response.data.contractVersion == version else { return nil }
        return response.data
    }

    private init() {}
}
