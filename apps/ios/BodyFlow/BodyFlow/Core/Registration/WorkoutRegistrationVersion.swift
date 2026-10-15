import Foundation

enum WorkoutRegistrationProtocol: String, Codable, Hashable, Sendable {
    case uiV1 = "ui-v1"
}

/// The revision the patient actually reviewed. A missing version is legacy;
/// it is never replaced with revision zero or the latest server revision.
struct WorkoutRegistrationVersion: Hashable, Sendable {
    let contentRevision: Int

    init?(contentRevision: Int) {
        guard (0...2147483647).contains(contentRevision) else { return nil }
        self.contentRevision = contentRevision
    }

    private enum CodingKeys: String, CodingKey {
        case workoutProtocol = "workout_protocol"
        case expectedRevision = "expected_revision"
    }

    func encodeSelection(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(WorkoutRegistrationProtocol.uiV1, forKey: .workoutProtocol)
        try container.encode(contentRevision, forKey: .expectedRevision)
    }
}

/// An edit's durable receipt can be older than the projection accompanying it.
/// It does not change which revision a later patient action selects.
struct WorkoutRegistrationEditReceipt: Codable, Hashable, Sendable {
    let requestKey: String
    let expectedRevision: Int
    let resultRevision: Int

    private enum CodingKeys: String, CodingKey {
        case requestKey, expectedRevision, resultRevision
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestKey = try container.decode(String.self, forKey: .requestKey)
        expectedRevision = try container.decode(Int.self, forKey: .expectedRevision)
        resultRevision = try container.decode(Int.self, forKey: .resultRevision)
        guard requestKey.hasPrefix("wue1:"), requestKey.count == 41,
              UUID(uuidString: String(requestKey.dropFirst(5))) != nil,
              (0..<2147483647).contains(expectedRevision),
              resultRevision == expectedRevision + 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .requestKey, in: container,
                debugDescription: "Invalid workout edit receipt"
            )
        }
    }
}
