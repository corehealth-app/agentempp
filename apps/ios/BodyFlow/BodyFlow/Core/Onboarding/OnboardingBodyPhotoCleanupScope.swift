import Foundation

/// An official G-local observation, never proof that all later uploads are gone.
enum OnboardingBodyPhotoCleanupState: String, Codable, Equatable, Sendable {
    case notRequired = "not_required"
    case pending
    case unknown
}

struct OnboardingBodyPhotoCleanupScope: Codable, Equatable, Sendable {
    let generation: String
    let state: OnboardingBodyPhotoCleanupState

    init(generation: String, state: OnboardingBodyPhotoCleanupState) {
        self.generation = generation
        self.state = state
    }

    init(from decoder: any Decoder) throws {
        let shape = try decoder.container(keyedBy: CleanupFieldKey.self)
        guard Set(shape.allKeys.map(\.stringValue)) == Set(["generation", "state"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unexpected cleanup metadata fields"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generation = try values.decode(String.self, forKey: .generation)
        guard SignupBodyPhotoCleanupQueue.validGeneration(generation) else {
            throw DecodingError.dataCorruptedError(forKey: .generation, in: values,
                debugDescription: "Invalid cleanup generation")
        }
        state = try values.decode(OnboardingBodyPhotoCleanupState.self, forKey: .state)
    }

    private enum CodingKeys: String, CodingKey { case generation, state }
}

private struct CleanupFieldKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
