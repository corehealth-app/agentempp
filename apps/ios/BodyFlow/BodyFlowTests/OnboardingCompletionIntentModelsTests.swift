import Foundation
import Testing

@testable import BodyFlow

@Suite("Signup completion intent models")
struct OnboardingCompletionIntentModelsTests {
    private let preparationID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let intentID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let keyUUID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    @Test("A present invalid capability cannot become legacy", arguments: [
        "null", "{}", "{\"protocol\":\"osc2\"}", "{\"protocol\":true}", "\"osc1\""
    ])
    func invalidCapabilityIsNotAbsence(_ capabilityJSON: String) throws {
        let state = OnboardingServerState(
            completion: .init(completed: false, completedAt: nil),
            requirements: .unavailable,
            acceptedActions: []
        )
        let base = try JSONEncoder().encode(state)
        var object = try #require(JSONSerialization.jsonObject(with: base) as? [String: Any])
        object["signup_completion"] = try JSONSerialization.jsonObject(
            with: Data(capabilityJSON.utf8), options: [.fragmentsAllowed]
        )
        let body = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OnboardingServerState.self, from: body)
        }
    }

    @Test("Absence remains legacy and a known capability survives round trip")
    func capabilityPresenceIsExplicit() throws {
        let absent = OnboardingServerState(
            completion: .init(completed: false, completedAt: nil),
            requirements: .unavailable, acceptedActions: []
        )
        let legacy = try JSONDecoder().decode(OnboardingServerState.self, from: JSONEncoder().encode(absent))
        #expect(legacy.signupCompletion == nil)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(absent)) as? [String: Any])
        object["signup_completion"] = ["protocol": "osc1"]
        let known = try JSONDecoder().decode(OnboardingServerState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(known.signupCompletion == .osc1)
        #expect(try JSONDecoder().decode(OnboardingServerState.self, from: JSONEncoder().encode(known)) == known)
    }

    @Test("Receipt Q, intent ID and key identity are independent")
    func independentReceiptIdentities() throws {
        let intent = try JSONDecoder().decode(OnboardingCompletionIntent.self, from: validReceipt())
        #expect(intent.preparationID == preparationID)
        #expect(intent.intentID == intentID)
        #expect(intent.requestKey.value == "osc1:\(keyUUID)")
        #expect(intent.matches(preparationID: preparationID))
        #expect(!intent.matches(preparationID: intentID))
    }

    @Test("Malformed receipt cannot be used as a completion identity", arguments: [
        "missingQ", "missingID", "unknownProtocol", "genericKey", "upperKey", "badUUID", "nullKey"
    ])
    func malformedReceipt(_ scenario: String) throws {
        var object = try #require(JSONSerialization.jsonObject(with: validReceipt()) as? [String: Any])
        switch scenario {
        case "missingQ": object.removeValue(forKey: "preparation_id")
        case "missingID": object.removeValue(forKey: "intent_id")
        case "unknownProtocol": object["protocol"] = "osc2"
        case "genericKey": object["request_key"] = keyUUID
        case "upperKey": object["request_key"] = "osc1:\(keyUUID.uppercased())"
        case "badUUID": object["intent_id"] = "not-an-id"
        default: object["request_key"] = NSNull()
        }
        let body = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(OnboardingCompletionIntent.self, from: body) }
    }

    @Test("Only explicit null means an absent resolution")
    func missingResolutionIsNotAbsence() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OnboardingCompletionIntentResponse.self, from: Data("{}".utf8))
        }
        let absent = try JSONDecoder().decode(OnboardingCompletionIntentResponse.self, from: Data("{\"completion_intent\":null}".utf8))
        #expect(absent.completionIntent == nil)
    }

    private func validReceipt() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocol": "osc1", "preparation_id": preparationID.uuidString.lowercased(),
            "intent_id": intentID.uuidString.lowercased(), "request_key": "osc1:\(keyUUID)"
        ])
    }
}
