import CryptoKit
import Foundation
import Testing
@testable import BodyFlow

@Suite("Conversation meal command wire contract")
struct ConversationMealCommandTests {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test func canonicalWirePreservesOriginalSourceAndIdentity() throws {
        let command = try ConversationMealCommand(
            commandID: id, source: .text("  arroz/feijão 😀 e\u{301}\n"), mealType: .almoco
        )
        let expected = "{\"command_id\":\"00000000-0000-0000-0000-000000000001\",\"command_protocol\":\"conversation.command.v1\",\"kind\":\"meal.report\",\"meal_type\":\"almoco\",\"source\":{\"channel\":\"text\",\"text\":\"  arroz/feijão 😀 e\u{301}\\n\"}}"
        #expect(command.wireBody == Data(expected.utf8))
        #expect(command.idempotencyKey == "cmsg1:00000000-0000-0000-0000-000000000001")
        #expect(command.inputHash == SHA256.hash(data: Data(expected.utf8)).map { String(format: "%02x", $0) }.joined())
        #expect(try ConversationMealCommand(wireBody: command.wireBody).wireBody == command.wireBody)
        #expect(!String(describing: command).contains("arroz"))
        #expect(Mirror(reflecting: command).children.isEmpty)
    }

    @Test func utf16LimitsAndECMAScriptWhitespaceMatchServer() throws {
        _ = try ConversationMealCommand(source: .text(String(repeating: "😀", count: 1_000)))
        #expect(throws: ConversationOutboxError.invalidCommand) {
            try ConversationMealCommand(source: .text(String(repeating: "😀", count: 1_001)))
        }
        _ = try ConversationMealCommand(source: .text("\u{85}")) // JS trim preserves NEL.
        for value in ["", " \t\r\n", "\u{feff}\u{a0}", "x\u{0}", "x\u{1f}", "x\u{7f}"] {
            #expect(throws: ConversationOutboxError.invalidCommand) {
                try ConversationMealCommand(source: .text(value))
            }
        }
        _ = try ConversationMealCommand(source: .text("x\t\r\n\u{2028}"))
    }

    @Test func canonicalHashesMatchActualTypeScriptBinderGoldens() throws {
        // Generated with bindConversationCommand in the pinned base f10efb91,
        // including canonically equivalent but byte-distinct Unicode source.
        let cases = [
            ("  arroz/feijão 😀 e\u{301}\n", "8c54698ade993c1642b56ede02de3778623ef80ca11036c97f4b6758340ae1a5"),
            ("x/\u{2028}\u{2029}\u{feff}", "42bb8b10225e5ff853270e9fa48ce05ff2e76c3e9d80053aa4de48180ef0453a"),
            ("\u{85}", "647cff6c31ea7c6a2a511d0bf4c558c74c6b2bb19b79f1ef09930d131c39b5ff"),
            ("é", "03efd6f9d5849300d49c48ccebfe7b2b40bd378db715840db167e6683512fe55"),
            ("e\u{301}", "f6f039fde6d21527c1c313ef825fb2a3528e61168529e4e7b3b3615269a31a84"),
            ("a\t\r\nb", "1f3d098832b361021a5c244555addd5697aafac6576af763d891e6bd143decfb"),
        ]
        for (source, hash) in cases {
            #expect(try ConversationMealCommand(commandID: id, source: .text(source)).inputHash == hash)
        }
    }

    @Test func mediaHasExplicitActionAndOmitsMissingOptionals() throws {
        let media = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let command = try ConversationMealCommand(commandID: id, source: .media(assetID: media, caption: nil))
        #expect(String(data: command.wireBody, encoding: .utf8) == "{\"command_id\":\"00000000-0000-0000-0000-000000000001\",\"command_protocol\":\"conversation.command.v1\",\"kind\":\"meal.report\",\"source\":{\"channel\":\"media\",\"media_asset_id\":\"00000000-0000-0000-0000-000000000002\",\"user_action\":\"register_consumed_meal\"}}")
        _ = try ConversationMealCommand(source: .media(assetID: media, caption: String(repeating: "😀", count: 500)))
        #expect(throws: ConversationOutboxError.invalidCommand) {
            try ConversationMealCommand(source: .media(assetID: media, caption: String(repeating: "😀", count: 501)))
        }
        #expect(throws: ConversationOutboxError.invalidCommand) {
            try ConversationMealCommand(source: .media(assetID: media, caption: " "))
        }
    }

    @Test func closedWireRejectsExtraNullAndSpoofedAuthority() throws {
        let valid = try ConversationMealCommand(commandID: id, source: .text("arroz"))
        let base = try #require(JSONSerialization.jsonObject(with: valid.wireBody) as? [String: Any])
        var cases: [[String: Any]] = []
        for key in ["owner_id", "nutrition", "epoch", "policy", "input_hash"] {
            var object = base; object[key] = "forged"; cases.append(object)
        }
        var nullMeal = base; nullMeal["meal_type"] = NSNull(); cases.append(nullMeal)
        var unknownMeal = base; unknownMeal["meal_type"] = "breakfast"; cases.append(unknownMeal)
        var workout = base; workout["kind"] = "workout.report"; cases.append(workout)
        var upper = base; upper["command_id"] = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"; cases.append(upper)
        for source: [String: Any] in [
            ["channel": "text", "text": "arroz", "url": "https://example.invalid"],
            ["channel": "media", "media_asset_id": id.uuidString.lowercased(), "user_action": "analyze"],
            ["channel": "media", "media_asset_id": id.uuidString.lowercased(), "user_action": "register_consumed_meal", "caption": NSNull()],
        ] { var object = base; object["source"] = source; cases.append(object) }
        for object in cases {
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: ConversationOutboxError.invalidCommand) { try ConversationMealCommand(wireBody: data) }
        }
    }
}
