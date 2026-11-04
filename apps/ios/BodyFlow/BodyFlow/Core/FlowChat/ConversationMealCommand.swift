import CryptoKit
import Foundation

enum ConversationOutboxError: Error, Equatable, Sendable {
    case invalidCommand
    case invalidOwner
    case keyUnavailable
    case storageUnavailable
    case integrityFailure
    case queueFull
    case commandNotFound
    case reconciliationRequired
    case invalidTransition
    case sessionClosed
    case invalidServerObservation
    case originalEpochUnavailable
    case originalOwnerUnavailable
    case staleObservation
}

/// The closed candidate wire contract. No owner, nutrition, URL, epoch or
/// authority is supplied by the client. Original source bytes are preserved.
struct ConversationMealCommand: Sendable, CustomStringConvertible, CustomReflectable {
    enum MealType: String, Sendable, CaseIterable {
        case cafe, almoco, lanche, jantar, ceia, outro
    }

    enum Source: Sendable {
        case text(String)
        case media(assetID: UUID, caption: String?)
    }

    let commandID: UUID
    let wireBody: Data
    let inputHash: String
    var idempotencyKey: String { "cmsg1:\(commandID.uuidString.lowercased())" }

    init(commandID: UUID = UUID(), source: Source, mealType: MealType? = nil) throws {
        var object: [String: Any] = [
            "command_protocol": "conversation.command.v1",
            "command_id": commandID.uuidString.lowercased(),
            "kind": "meal.report",
        ]
        switch source {
        case .text(let text):
            guard Self.valid(text, limit: 2_000) else { throw ConversationOutboxError.invalidCommand }
            object["source"] = ["channel": "text", "text": text]
        case .media(let assetID, let caption):
            var media = ["channel": "media", "media_asset_id": assetID.uuidString.lowercased(),
                         "user_action": "register_consumed_meal"]
            if let caption {
                guard Self.valid(caption, limit: 1_000) else { throw ConversationOutboxError.invalidCommand }
                media["caption"] = caption
            }
            object["source"] = media
        }
        if let mealType { object["meal_type"] = mealType.rawValue }
        self.commandID = commandID
        // ASCII field names sort identically to the server's recursive canonical
        // JSON. Foundation's unescaped Unicode and slash output matches JSON.stringify.
        wireBody = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        inputHash = Self.digest(wireBody)
    }

    init(wireBody: Data) throws {
        do {
            guard wireBody.count <= 16_384,
                  let object = try JSONSerialization.jsonObject(with: wireBody) as? [String: Any],
                  Set(object.keys).isSubset(of: ["command_protocol", "command_id", "kind", "meal_type", "source"]),
                  object["command_protocol"] as? String == "conversation.command.v1",
                  object["kind"] as? String == "meal.report",
                  let idString = object["command_id"] as? String,
                  let id = Self.lowercaseUUID(idString),
                  let source = object["source"] as? [String: Any]
            else { throw ConversationOutboxError.invalidCommand }
            let mealType: MealType?
            if let value = object["meal_type"] {
                guard let raw = value as? String, let type = MealType(rawValue: raw) else {
                    throw ConversationOutboxError.invalidCommand
                }
                mealType = type
            } else { mealType = nil }
            let parsed: Source
            switch source["channel"] as? String {
            case "text":
                guard Set(source.keys) == ["channel", "text"], let text = source["text"] as? String else {
                    throw ConversationOutboxError.invalidCommand
                }
                parsed = .text(text)
            case "media":
                guard Set(source.keys).isSubset(of: ["channel", "media_asset_id", "user_action", "caption"]),
                      source["user_action"] as? String == "register_consumed_meal",
                      let raw = source["media_asset_id"] as? String, let assetID = Self.lowercaseUUID(raw)
                else { throw ConversationOutboxError.invalidCommand }
                let caption: String?
                if let value = source["caption"] {
                    guard let text = value as? String else { throw ConversationOutboxError.invalidCommand }
                    caption = text
                } else { caption = nil }
                parsed = .media(assetID: assetID, caption: caption)
            default: throw ConversationOutboxError.invalidCommand
            }
            try self.init(commandID: id, source: parsed, mealType: mealType)
        } catch { throw ConversationOutboxError.invalidCommand }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func lowercaseUUID(_ raw: String) -> UUID? {
        guard raw.utf8.count == 36,
              raw.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil
        else { return nil }
        return UUID(uuidString: raw)
    }

    private static func valid(_ text: String, limit: Int) -> Bool {
        guard !text.isEmpty, text.utf16.count <= limit,
              !text.unicodeScalars.contains(where: { ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127 })
        else { return false }
        // ECMAScript trim's exact set. This only checks blank input; it does
        // not trim, normalize Unicode, transcribe or rewrite the saved source.
        return text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 9...13, 32, 160, 5_760, 8_192...8_202, 8_232, 8_233, 8_239, 8_287, 12_288, 65_279: false
            default: true
            }
        }
    }

    var description: String { "ConversationMealCommand(redacted)" }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .struct) }
}
