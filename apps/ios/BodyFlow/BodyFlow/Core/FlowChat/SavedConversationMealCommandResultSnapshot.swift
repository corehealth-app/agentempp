import Foundation

/// Closed factual result from the trusted authenticated command transport.
/// A decoder is neither proof of database persistence nor an HTTP-status ACK.
struct SavedConversationMealCommandResultSnapshot: Decodable, Sendable {
    struct Receipt: Decodable, Equatable, Sendable {
        let ownerID: String
        let commandID: String
        let inputHash: String
        let registrationID: String
        let providerKey: String
        let mealType: ConversationMealCommand.MealType
        let localDate: String
        let timezone: String
        let consumedAt: String
        let logIDs: [String]
        let effectVersion: String

        private enum CodingKeys: String, CodingKey {
            case schema, ownerID = "owner_id", commandID = "command_id", inputHash = "input_hash"
            case registrationID = "registration_id", providerKey = "provider_key", mealType = "meal_type"
            case localDate = "local_date", timezone, consumedAt = "consumed_at", logIDs = "log_ids", effectVersion = "effect_version"
        }
        init(from decoder: any Decoder) throws {
            try savedKeys(decoder, ["schema", "owner_id", "command_id", "input_hash", "registration_id", "provider_key",
                "meal_type", "local_date", "timezone", "consumed_at", "log_ids", "effect_version"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try savedCheck(c.decode(String.self, forKey: .schema) == "conversation.meal-effect.v1")
            ownerID = try savedUUID(c.decode(String.self, forKey: .ownerID))
            commandID = try savedUUID(c.decode(String.self, forKey: .commandID))
            inputHash = try savedHash(c.decode(String.self, forKey: .inputHash))
            registrationID = try savedUUID(c.decode(String.self, forKey: .registrationID))
            providerKey = try c.decode(String.self, forKey: .providerKey)
            try savedCheck(providerKey == "conversation.meal/\(ownerID)/\(commandID)")
            guard let meal = ConversationMealCommand.MealType(rawValue: try c.decode(String.self, forKey: .mealType)) else { throw InvalidSavedPacket.value }
            mealType = meal
            localDate = try c.decode(String.self, forKey: .localDate)
            try savedCheck(savedCivilDate(localDate))
            timezone = try c.decode(String.self, forKey: .timezone)
            consumedAt = try c.decode(String.self, forKey: .consumedAt)
            guard let consumed = SavedPacketInstant(consumedAt), let zone = TimeZone(identifier: timezone) else { throw InvalidSavedPacket.value }
            var calendar = Calendar(identifier: .iso8601); calendar.timeZone = zone
            let day = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(consumed.seconds)))
            guard let year = day.year, let month = day.month, let date = day.day else { throw InvalidSavedPacket.value }
            try savedCheck(localDate == String(format: "%04d-%02d-%02d", year, month, date))
            logIDs = try c.decode([String].self, forKey: .logIDs)
            try savedCheck((1...30).contains(logIDs.count) && Set(logIDs).count == logIDs.count)
            for id in logIDs { _ = try savedUUID(id) }
            effectVersion = try c.decode(String.self, forKey: .effectVersion)
            try savedCheck(effectVersion.hasPrefix("cmeal1:") && effectVersion.count == 71)
            _ = try savedHash(String(effectVersion.dropFirst(7)))
        }
    }

    let ownerID: String
    let commandID: String
    let inputHash: String
    let epoch: String
    let admittedAt: String
    let receipt: Receipt
    let feedback: ConversationFeedbackPresentationSnapshot?

    private enum CodingKeys: String, CodingKey {
        case schema, status, ownerID = "owner_id", commandID = "command_id", inputHash = "input_hash"
        case epoch, admittedAt = "admitted_at", receipt, feedback
    }
    init(from decoder: any Decoder) throws {
        do {
            try savedKeys(decoder, ["schema", "status", "owner_id", "command_id", "input_hash", "epoch", "admitted_at", "receipt", "feedback"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try savedCheck(c.decode(String.self, forKey: .schema) == "conversation.meal-command-result.v1")
            try savedCheck(c.decode(String.self, forKey: .status) == "saved")
            ownerID = try savedUUID(c.decode(String.self, forKey: .ownerID))
            commandID = try savedUUID(c.decode(String.self, forKey: .commandID))
            inputHash = try savedHash(c.decode(String.self, forKey: .inputHash))
            epoch = try savedUUID(c.decode(String.self, forKey: .epoch))
            admittedAt = try c.decode(String.self, forKey: .admittedAt)
            receipt = try c.decode(Receipt.self, forKey: .receipt)
            guard let admitted = SavedPacketInstant(admittedAt), let consumed = SavedPacketInstant(receipt.consumedAt) else { throw InvalidSavedPacket.value }
            try savedCheck(receipt.ownerID == ownerID && receipt.commandID == commandID && receipt.inputHash == inputHash && admitted <= consumed)
            // The actual BFF drops malformed optional presentation. Do the same
            // without turning enrichment failure into lost factual success.
            if let raw = try? c.decode(SavedPacketValue.self, forKey: .feedback),
               let bytes = try? raw.data(), bytes.count <= 200_000,
               let candidate = try? JSONDecoder().decode(ConversationFeedbackPresentationSnapshot.self, from: bytes),
               Self.acceptsFeedback(candidate, receipt: receipt, commandID: commandID, epoch: epoch, admitted: admitted) {
                feedback = candidate
            } else { feedback = nil }
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Saved command result unavailable"))
        }
    }

    func boundFeedback(scope: ConversationFeedbackPresentationSnapshot.Scope) -> ConversationFeedbackPresentationSnapshot.Bound? {
        guard scope.ownerID == ownerID, scope.epoch == epoch else { return nil }
        return feedback?.bound(to: .init(scope: scope, commandID: commandID, registrationID: receipt.registrationID,
            localDate: receipt.localDate, mealKind: receipt.mealType.rawValue, logIDs: receipt.logIDs, admittedAt: admittedAt), current: scope)
    }

    private static func acceptsFeedback(_ value: ConversationFeedbackPresentationSnapshot, receipt: Receipt, commandID: String, epoch: String, admitted: SavedPacketInstant) -> Bool {
        guard value.original.registrationID == receipt.registrationID, value.original.localDate == receipt.localDate,
              value.provenance.commandID == commandID, value.provenance.epoch == epoch,
              let observed = SavedPacketInstant(value.provenance.observedAt), observed >= admitted else { return false }
        switch value.content {
        case let .sections(recorded, sections):
            return recorded.mealKind == receipt.mealType.rawValue && Set(recorded.items.map(\.logID)) == Set(receipt.logIDs) &&
                sections.allSatisfy { $0.text.utf16.count <= 64_000 }
        case let .placeholder(sections): return sections.allSatisfy { $0.text.utf16.count <= 64_000 }
        case .legacy: return true // The existing closed wrapper already checks restricted policy and v1 identity/day.
        }
    }
}

/// Published only through the actual visible-session gate after factual ACK.
struct ConversationOutboxSavedPublication: Sendable {
    let receipt: SavedConversationMealCommandResultSnapshot.Receipt
    let feedback: ConversationFeedbackPresentationSnapshot.Bound?
}

private enum InvalidSavedPacket: Error { case value }
private func savedCheck(_ condition: Bool) throws { if !condition { throw InvalidSavedPacket.value } }
private func savedUUID(_ value: String) throws -> String {
    try savedCheck(value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil && UUID(uuidString: value) != nil)
    return value
}
private func savedHash(_ value: String) throws -> String {
    try savedCheck(value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil); return value
}
private struct SavedPacketKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func savedKeys(_ decoder: any Decoder, _ expected: Set<String>) throws {
    try savedCheck(Set(decoder.container(keyedBy: SavedPacketKey.self).allKeys.map(\.stringValue)) == expected)
}
private indirect enum SavedPacketValue: Codable {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([Self].self) { self = .array(a) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .object(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .bool(v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    func data() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]; return try encoder.encode(self) }
}
private func savedCivilDate(_ s: String) -> Bool {
    let b = Array(s.utf8)
    guard b.count == 10, b[4] == 45, b[7] == 45,
          b.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }) else { return false }
    let p = s.split(separator: "-")
    guard let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), y > 0, (1...12).contains(m) else { return false }
    let leap = y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)
    return (1...[31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]).contains(d)
}
private struct SavedPacketInstant: Comparable {
    let seconds: Int64
    let nanos: Int
    init?(_ raw: String) {
        let pattern = #"^(\d{4}-\d{2}-\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.(\d{1,9}))?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#
        guard let re = try? NSRegularExpression(pattern: pattern), let match = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.range.length == raw.utf16.count else { return nil }
        func part(_ index: Int) -> String { guard let r = Range(match.range(at: index), in: raw) else { return "" }; return String(raw[r]) }
        guard savedCivilDate(part(1)) else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: "\(part(1))T\(part(2)):\(part(3)):\(part(4))\(part(6))") else { return nil }
        seconds = Int64(date.timeIntervalSince1970.rounded())
        let fraction = part(5); nanos = Int(fraction + String(repeating: "0", count: 9 - fraction.count)) ?? 0
    }
    static func < (a: Self, b: Self) -> Bool { a.seconds == b.seconds ? a.nanos < b.nanos : a.seconds < b.seconds }
}
