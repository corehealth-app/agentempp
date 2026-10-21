import Foundation

enum OnboardingCompletionProtocol: String, Codable, Sendable {
    case osc1
}

struct OnboardingCompletionCapability: Codable, Equatable, Sendable {
    let protocolVersion: OnboardingCompletionProtocol
    static let osc1 = Self(protocolVersion: .osc1)

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
    }
}

/// A server-issued identity. Q, intentID and the UUID in K are independent.
/// No domain owner, epoch, hash or server clock is accepted from the client.
struct OnboardingCompletionIntent: Decodable, Equatable, Sendable {
    let protocolVersion: OnboardingCompletionProtocol
    let preparationID: UUID
    let intentID: UUID
    let requestKey: IdempotencyKey

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(OnboardingCompletionProtocol.self, forKey: .protocolVersion)
        preparationID = try values.decode(UUID.self, forKey: .preparationID)
        intentID = try values.decode(UUID.self, forKey: .intentID)
        let key = try values.decode(String.self, forKey: .requestKey)
        let prefix = "osc1:"
        let suffix = String(key.dropFirst(prefix.count))
        guard key.hasPrefix(prefix),
              let uuid = UUID(uuidString: suffix), uuid.uuidString.lowercased() == suffix,
              let parsedKey = try? IdempotencyKey(validating: key) else {
            throw DecodingError.dataCorruptedError(
                forKey: .requestKey, in: values, debugDescription: "Invalid signup completion key"
            )
        }
        requestKey = parsedKey
    }

    func matches(preparationID: UUID) -> Bool { self.preparationID == preparationID }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case preparationID = "preparation_id"
        case intentID = "intent_id"
        case requestKey = "request_key"
    }
}

struct OnboardingCompletionIntentResponse: Decodable, Sendable {
    let completionIntent: OnboardingCompletionIntent?

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // A missing field is malformed; only a literal null means absent.
        completionIntent = try values.decode(OnboardingCompletionIntent?.self, forKey: .completionIntent)
    }

    private enum CodingKeys: String, CodingKey {
        case completionIntent = "completion_intent"
    }
}
