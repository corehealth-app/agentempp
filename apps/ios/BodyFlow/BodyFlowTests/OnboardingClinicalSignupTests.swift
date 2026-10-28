import Foundation
import Testing
@testable import BodyFlow

@Suite("Current clinical signup public contracts")
struct OnboardingClinicalSignupTests {
    static let noPlan = #"{"version":2,"decision":"no_plan","objective":null,"notice":["No plan now","Professional assessment"],"options":[],"professional_assessment_recommended":true,"pause_weight_loss_guidance":true}"#
    @Test func noPlanIsExplicitVersionedAndNeverAnIncompleteLegacyDecision() throws {
        let value = try JSONDecoder().decode(OnboardingEligibilityDecision.self, from: Data(Self.noPlan.utf8)).validated()
        #expect(value.version == 2 && value.decision == .noPlan && value.permits(nil))
        #expect(value.objective == nil && value.options.isEmpty)
        #expect(!E3Fixtures.choice.permits(nil))
        for text in [Self.noPlan.replacingOccurrences(of: "\"version\":2,", with: ""),
                     Self.noPlan.replacingOccurrences(of: "\"objective\":null,", with: ""),
                     Self.noPlan.replacingOccurrences(of: "\"professional_assessment_recommended\":true", with: "\"professional_assessment_recommended\":false")] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(OnboardingEligibilityDecision.self, from: Data(text.utf8)).validated()
            }
        }
    }
    @Test func currentInputSendsBirthDateAndTimezoneWithoutHealthOrAuthority() throws {
        var draft = E3Fixtures.draft(); draft.bodyFatPercent = nil
        let input = try OnboardingEligibilityInput(draft:draft, clinicalSignup:.current)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String:Any])
        #expect(Set(object.keys) == ["version","locale","timezone","birth_date","sex","height_cm","weight_kg","training_frequency"])
        #expect(object["version"] as? Int == 2)
        #expect(object["birth_date"] as? String == OnboardingCivilDate.string(from:try #require(draft.birthDate),timeZoneIdentifier:draft.timeZoneIdentifier))
        let old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(OnboardingEligibilityInput(draft:draft))) as? [String:Any])
        #expect(old["version"] == nil && old["birth_date"] == nil && old["timezone"] == nil)
    }
    @Test func nullableServerDraftNeedsKnownCapabilityAndLiteralObjectiveKey() throws {
        var draft=E3Fixtures.draft();draft.objective=nil
        let state=OnboardingServerState(completion:.init(completed:false,completedAt:"2026-10-27T12:00:00.000001Z"),requirements:E3Fixtures.requirements,acceptedActions:[],draft:draft,signupCompletion:.osc1,clinicalSignup:.current)
        let bytes=try JSONEncoder().encode(state)
        let decoded=try JSONDecoder().decode(OnboardingServerState.self,from:bytes)
        #expect(decoded.clinicalSignup == .current && decoded.draft?.objective == nil)
        var object=try #require(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        let raw=try #require(object["draft"] as? [String:Any]);#expect(raw["objective"] is NSNull)
        object.removeValue(forKey:"clinical_signup")
        #expect(throws:(any Error).self) {try JSONDecoder().decode(OnboardingServerState.self,from:JSONSerialization.data(withJSONObject:object))}
        object["clinical_signup"]=["representation":"current_clinical_v2"]
        var missing=raw;missing.removeValue(forKey:"objective");object["draft"]=missing
        #expect(throws:(any Error).self) {try JSONDecoder().decode(OnboardingServerState.self,from:JSONSerialization.data(withJSONObject:object))}
    }
    @Test func malformedCapabilityCannotSilentlyDowngrade() throws {
        let state=OnboardingServerState(completion:.init(completed:false,completedAt:nil),requirements:.unavailable,acceptedActions:[])
        for value:Any in [NSNull(),["representation":"unknown"],[:]] {
            var object=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as? [String:Any])
            object["clinical_signup"]=value
            #expect(throws:(any Error).self) {try JSONDecoder().decode(OnboardingServerState.self,from:JSONSerialization.data(withJSONObject:object))}
        }
    }
    @Test func nullableAcknowledgementNeedsClinicalObservationAndNoWelcome() throws {
        var draft=E3Fixtures.draft();draft.objective=nil
        let ack=OnboardingCompletionAcknowledgement(onboardingCompleted:true,completedAt:"2026-10-27T12:00:00.000001Z",objective:nil,persona:.focus,documentActions:[],clinicalSafety:try safety())
        let bytes=try JSONEncoder().encode(ack)
        let decoded=try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self,from:bytes)
        #expect(decoded.objective == nil && decoded.clinicalSafety?.noPlan == true)
        var object=try #require(JSONSerialization.jsonObject(with:bytes) as? [String:Any])
        object.removeValue(forKey:"clinical_safety")
        #expect(throws:(any Error).self) {try JSONDecoder().decode(OnboardingCompletionAcknowledgement.self,from:JSONSerialization.data(withJSONObject:object))}
    }
    private func safety() throws -> OnboardingClinicalSafety {
        try JSONDecoder().decode(OnboardingClinicalSafety.self,from:Data(#"{"version":1,"no_plan":true,"hold_active":false,"loss_guard":false,"hide_protein":true,"recording_allowed":true,"date":"2026-10-27","timezone":"America/Sao_Paulo","observed_at":"2026-10-27T12:00:00.000001Z"}"#.utf8))
    }
}
