import Foundation
import Testing
@testable import BodyFlow

@Suite("Onboarding cleanup metadata models")
struct OnboardingCleanupMetadataModelTests {
    @Test("official cleanup metadata survives GET decode and encode with its literal generation",
          arguments: ["not_required", "pending", "unknown"])
    func retainsOfficialSignal(_ state: String) throws {
        let generation = "2026-10-12T11:22:33.123456+00:00"
        let bytes = Data("""
        {"locale":"pt-BR","completion":{"completed":false,"completed_at":null},
         "requirements":{"available":false,"blocking_reason":"documents_unavailable","documents":[]},
         "accepted_actions":[],"body_photo_cleanup":{"generation":"\(generation)","state":"\(state)"}}
        """.utf8)
        let decoded = try JSONDecoder().decode(OnboardingServerState.self, from: bytes)
        #expect(decoded.locale == "pt-BR")
        #expect(decoded.completion.completedAt == nil)
        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let signal = try #require(object["body_photo_cleanup"] as? [String: String])
        #expect(signal == ["generation": generation, "state": state])
    }
}
