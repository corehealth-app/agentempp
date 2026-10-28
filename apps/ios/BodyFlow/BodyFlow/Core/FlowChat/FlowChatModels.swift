import Foundation

enum FlowMessageRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
}

enum FlowMessageState: String, Codable, Hashable, Sendable {
    case processing
    case completed
    case failed
}

struct FlowMessage: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let conversationID: String
    let role: FlowMessageRole
    let content: String
    let state: FlowMessageState
    let requestID: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, role, content, state
        case conversationID = "conversation_id"
        case requestID = "request_id"
        case createdAt = "created_at"
    }

    init(
        id: String,
        conversationID: String,
        role: FlowMessageRole,
        content: String,
        state: FlowMessageState,
        requestID: String,
        createdAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.state = state
        self.requestID = requestID
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        role = try container.decode(FlowMessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        state = try container.decode(FlowMessageState.self, forKey: .state)
        requestID = try container.decode(String.self, forKey: .requestID)
        createdAt = try container.decode(APITimestamp.self, forKey: .createdAt).value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(state, forKey: .state)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(APITimestamp(value: createdAt), forKey: .createdAt)
    }
}

struct FlowHistoryResponse: Codable, Equatable, Sendable {
    let conversationID: String
    let messages: [FlowMessage]
    let clinicalPolicy: CurrentClinicalPolicy?

    init(conversationID: String, messages: [FlowMessage], clinicalPolicy: CurrentClinicalPolicy? = nil) {
        self.conversationID = conversationID
        self.messages = messages
        self.clinicalPolicy = clinicalPolicy
    }
    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case messages
        case clinicalPolicy = "clinical_policy"
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try c.decode(String.self, forKey: .conversationID)
        messages = try c.decode([FlowMessage].self, forKey: .messages)
        clinicalPolicy = c.contains(.clinicalPolicy) ? try c.decode(CurrentClinicalPolicy.self, forKey: .clinicalPolicy) : nil
    }
}

/// The plan proposal a turn created, for the app to open its review. It is
/// a draft: nothing is the patient's plan until they confirm it.
struct FlowTurnDraft: Codable, Hashable, Sendable {
    let id: String
    let domain: PlanDraftDomain
}

struct FlowSendResponse: Codable, Equatable, Sendable {
    let conversationID: String
    let message: FlowMessage
    /// Absent from a server that does not propose plans.
    let draft: FlowTurnDraft?
    let clinicalPolicy: CurrentClinicalPolicy?

    init(conversationID: String, message: FlowMessage, draft: FlowTurnDraft? = nil, clinicalPolicy: CurrentClinicalPolicy? = nil) {
        self.conversationID = conversationID
        self.message = message
        self.draft = draft
        self.clinicalPolicy = clinicalPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case message
        case draft
        case clinicalPolicy = "clinical_policy"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        message = try container.decode(FlowMessage.self, forKey: .message)
        clinicalPolicy = container.contains(.clinicalPolicy) ? try container.decode(CurrentClinicalPolicy.self, forKey: .clinicalPolicy) : nil
        // A draft the app cannot read (unknown domain) is only a missing
        // shortcut, never a failed reply.
        draft = (try? container.decodeIfPresent(FlowTurnDraft.self, forKey: .draft)) ?? nil
    }
}
