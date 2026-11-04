import Foundation

enum MobileAPIUnauthorizedReplay: Sendable, Equatable { case standard, never }

/// Closed new-protocol headers, never arbitrary header overrides. They are
/// preconditions, not part of the immutable command body or source authority.
enum MobileConversationRequestHeaders: Sendable {
    case session
    case submit(epoch: UUID, ownerID: UUID)
    case reconciliation(epoch: UUID, ownerID: UUID, inputHash: String)

    func validate(method: HTTPMethod, path: String, query: [URLQueryItem], body: Data?, key: IdempotencyKey?, replay: MobileAPIUnauthorizedReplay) throws {
        let base = "/api/mobile/v1/conversation/meal-commands"
        guard query.isEmpty else { throw MobileAPIRequestError.invalidConversationHeaders }
        switch self {
        case .session:
            guard method == .get, path == "/api/mobile/v1/conversation/session", body == nil, key == nil else { throw MobileAPIRequestError.invalidConversationHeaders }
        case .submit:
            guard method == .post, path == base, let body, let key, replay == .never,
                  let command = try? ConversationMealCommand(wireBody: body), command.wireBody == body,
                  key.value == command.idempotencyKey else { throw MobileAPIRequestError.invalidConversationHeaders }
        case let .reconciliation(_, _, hash):
            let tail = String(path.dropFirst((base + "/").count))
            guard method == .get, body == nil, key == nil, path.hasPrefix(base + "/"),
                  let id = UUID(uuidString: tail), id.uuidString.lowercased() == tail,
                  hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw MobileAPIRequestError.invalidConversationHeaders }
        }
    }
    func apply(to request: inout URLRequest) {
        request.setValue("meal-command-v1", forHTTPHeaderField: "X-Conversation-Protocol")
        switch self {
        case .session: break
        case let .submit(epoch, owner):
            request.setValue(epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Epoch")
            request.setValue(owner.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Owner")
        case let .reconciliation(epoch, owner, hash):
            request.setValue(epoch.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Epoch")
            request.setValue(hash, forHTTPHeaderField: "X-Conversation-Input-Hash")
            request.setValue(owner.uuidString.lowercased(), forHTTPHeaderField: "X-Conversation-Owner")
        }
    }
}

struct MobileAPIHTTPResponse<Payload: Decodable & Sendable>: Sendable {
    let statusCode: Int
    let data: Payload
    let meta: MobileResponseMetadata
}

/// Opt-in envelope check only. Existing mobile consumers retain their additive
/// metadata compatibility; the new command protocol rejects private additions.
struct MobileConversationEnvelopeShape: Decodable {
    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: ConversationEnvelopeKey.self)
        guard Set(root.allKeys.map(\.stringValue)) == ["data", "meta"],
              let meta = ConversationEnvelopeKey(stringValue: "meta") else { throw MobileAPITransportError.invalidResponse }
        let child = try root.superDecoder(forKey: meta).container(keyedBy: ConversationEnvelopeKey.self)
        guard Set(child.allKeys.map(\.stringValue)) == ["api_version", "request_id"] else { throw MobileAPITransportError.invalidResponse }
    }
}
private struct ConversationEnvelopeKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
