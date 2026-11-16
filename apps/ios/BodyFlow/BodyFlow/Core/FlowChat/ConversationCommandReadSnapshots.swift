import Foundation

/// Authenticated read-only observation. It creates no command or registration.
struct ConversationSessionSnapshot: Decodable, Sendable {
    let authUserID: UUID
    let ownerID: UUID
    let epoch: UUID
    let observedAt: String
    private enum CodingKeys: String, CodingKey { case schema, authUserID = "auth_user_id", ownerID = "owner_id", epoch, observedAt = "observed_at", protocolVersion = "meal_command_protocol" }
    init(from decoder: any Decoder) throws {
        do {
            try conversationReadKeys(decoder, ["schema", "auth_user_id", "owner_id", "epoch", "observed_at", "meal_command_protocol"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try conversationReadCheck(c.decode(String.self, forKey: .schema) == "conversation.session.v1")
            try conversationReadCheck(c.decode(String.self, forKey: .protocolVersion) == "conversation.command.v1")
            authUserID = try conversationReadUUID(c.decode(String.self, forKey: .authUserID))
            ownerID = try conversationReadUUID(c.decode(String.self, forKey: .ownerID))
            epoch = try conversationReadUUID(c.decode(String.self, forKey: .epoch))
            observedAt = try c.decode(String.self, forKey: .observedAt)
            try conversationReadCheck(ConversationProtocolInstant(observedAt) != nil)
        } catch { throw conversationReadFailure(decoder) }
    }
}

struct ConversationMealCommandStateSnapshot: Decodable, Sendable {
    enum Status: String, Sendable { case absent, pending, notRecorded = "not_recorded" }
    let status: Status
    let ownerID: UUID
    let commandID: UUID
    let inputHash: String
    let epoch: UUID
    let reason: String?
    let foodIndexes: [Int]
    private enum CodingKeys: String, CodingKey { case schema, status, ownerID = "owner_id", commandID = "command_id", inputHash = "input_hash", epoch, reason, foodIndexes = "food_indexes" }
    init(from decoder: any Decoder) throws {
        do {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let status = Status(rawValue: try c.decode(String.self, forKey: .status)) else { throw ConversationReadInvalid.value }
            self.status = status
            let common: Set<String> = ["schema", "status", "owner_id", "command_id", "input_hash", "epoch"]
            try conversationReadKeys(decoder, status == .notRecorded ? common.union(["reason", "food_indexes"]) : common)
            try conversationReadCheck(c.decode(String.self, forKey: .schema) == "conversation.meal-command-state.v1")
            ownerID = try conversationReadUUID(c.decode(String.self, forKey: .ownerID))
            commandID = try conversationReadUUID(c.decode(String.self, forKey: .commandID))
            inputHash = try c.decode(String.self, forKey: .inputHash)
            try conversationReadCheck(inputHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil)
            epoch = try conversationReadUUID(c.decode(String.self, forKey: .epoch))
            if status == .notRecorded {
                let reason = try c.decode(String.self, forKey: .reason)
                try conversationReadCheck(reason.range(of: "^[a-z_]{1,80}$", options: .regularExpression) != nil)
                self.reason = reason
                foodIndexes = try c.decode([Int].self, forKey: .foodIndexes)
                try conversationReadCheck(foodIndexes.count <= 30 && Set(foodIndexes).count == foodIndexes.count && foodIndexes.allSatisfy { (0...29).contains($0) })
            } else { reason = nil; foodIndexes = [] }
        } catch { throw conversationReadFailure(decoder) }
    }
    func matches(_ ticket: ConversationOutboxTicket, server: ConversationOutboxServerObservation) -> Bool {
        ownerID == ticket.originalPatientOwnerID && ownerID == server.ownerID && commandID == ticket.commandID &&
            inputHash == ticket.inputHash && epoch == ticket.originalServerEpoch && epoch == server.epoch
    }
}

enum ConversationMealCommandReply: Decodable, Sendable {
    case saved(SavedConversationMealCommandResultSnapshot)
    case state(ConversationMealCommandStateSnapshot)
    private enum CodingKeys: String, CodingKey { case schema }
    init(from decoder: any Decoder) throws {
        switch try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .schema) {
        case "conversation.meal-command-result.v1": self = .saved(try SavedConversationMealCommandResultSnapshot(from: decoder))
        case "conversation.meal-command-state.v1": self = .state(try ConversationMealCommandStateSnapshot(from: decoder))
        default: throw conversationReadFailure(decoder)
        }
    }
    func acceptsHTTPStatus(_ code: Int) -> Bool {
        switch self {
        case .saved: code == 200
        case let .state(value): value.status == .pending ? code == 202 : code == 200
        }
    }
}

private enum ConversationReadInvalid: Error { case value }
private func conversationReadCheck(_ value: Bool) throws { if !value { throw ConversationReadInvalid.value } }
private func conversationReadUUID(_ raw: String) throws -> UUID {
    guard raw.range(of: "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", options: .regularExpression) != nil,
          let id = UUID(uuidString: raw) else { throw ConversationReadInvalid.value }; return id
}
private struct ConversationReadKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func conversationReadKeys(_ decoder: any Decoder, _ keys: Set<String>) throws {
    try conversationReadCheck(Set(decoder.container(keyedBy: ConversationReadKey.self).allKeys.map(\.stringValue)) == keys)
}
private func conversationReadFailure(_ decoder: any Decoder) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Conversation response unavailable"))
}

/// Nanosecond RFC3339 ordering, with no device-clock authority or UUID ordering.
struct ConversationProtocolInstant: Comparable, Sendable {
    let seconds: Int64
    let nanos: Int
    init?(_ raw: String) {
        let pattern = #"^(\d{4}-\d{2}-\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.(\d{1,9}))?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#
        guard let re = try? NSRegularExpression(pattern: pattern), let match = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)), match.range.length == raw.utf16.count else { return nil }
        func part(_ i: Int) -> String { guard let r = Range(match.range(at: i), in: raw) else { return "" }; return String(raw[r]) }
        let date = part(1), parts = date.split(separator: "-")
        guard date.utf8.allSatisfy({ $0 == 45 || (48...57).contains($0) }), let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), y > 0, (1...12).contains(m) else { return nil }
        let leap = y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)
        guard (1...[31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]).contains(d) else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        guard let instant = formatter.date(from: "\(date)T\(part(2)):\(part(3)):\(part(4))\(part(6))") else { return nil }
        seconds = Int64(instant.timeIntervalSince1970.rounded())
        let fraction = part(5); nanos = Int(fraction + String(repeating: "0", count: 9 - fraction.count)) ?? 0
    }
    static func < (a: Self, b: Self) -> Bool { a.seconds == b.seconds ? a.nanos < b.nanos : a.seconds < b.seconds }
}
