import Foundation
import Testing
@testable import BodyFlow

@Suite("Clinical FULL — public adaptive form and unknown answers")
struct ClinicalFullFormTests {
    static let cycle = "b3b01000-0000-4000-8000-000000004700"
    static let candidate = String(repeating: "a", count: 64)
    static let json = #"{"version":1,"locale":"pt-BR","kind":"REGULAR","cycle_id":"b3b01000-0000-4000-8000-000000004700","activity_purpose":"consider_maintenance","questions":[{"key":"weightKg","label":"Qual é o seu peso hoje?","input_kind":"decimal","unit":"kg","opt_out_label":"Prefiro não responder","options":null,"min":30,"max":300,"preselected":null,"initially_confirmed":null,"hint":null},{"key":"activity.activityLevel","label":"Nível de atividade","input_kind":"single_choice","unit":null,"opt_out_label":"Prefiro não responder","options":[{"value":"moderado","label":"Moderado"}],"min":null,"max":null,"preselected":"moderado","initially_confirmed":false,"hint":null}],"preference_question":null,"support_text":null,"photo_requirement":{"required":true,"new_only":true,"poses":["front","side","back"]},"body_fat":{"status":"ready","percent":24,"candidate_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}"#
    static func questionnaire(_ text: String = json) throws -> ClinicalFullQuestionnaire {
        try JSONDecoder().decode(ClinicalFullQuestionnaire.self, from: Data(text.utf8)).validated()
    }
    @Test func transitionRequiresItsActualCycleAndThreeNewPhotosWithoutPublicLegacyAuthority() throws {
        let text = Self.json.replacingOccurrences(of: "\"kind\":\"REGULAR\"", with: "\"kind\":\"TRANSITION_FULL\"")
        let form = try Self.questionnaire(text)
        #expect(form.kind.rawValue == "TRANSITION_FULL" && form.kind.requiresCycle)
        #expect(form.photoRequirement.required && form.photoRequirement.newOnly)
        #expect(form.photoRequirement.poses == [.front, .side, .back])
        var draft = ClinicalFullDraft(questionnaire: form)
        draft.acceptBodyFat(from: form)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        #expect((object["bodyFat"] as? [String: Any])?["candidateId"] as? String == Self.candidate)
        for forbidden in ["legacyOrigin", "generation", "epoch", "meanHundredths", "targets", "phase", "kind"] {
            #expect(object[forbidden] == nil)
        }
        #expect(throws: (any Error).self) {
            try Self.questionnaire(text.replacingOccurrences(of: "\"required\":true", with: "\"required\":false"))
        }
        #expect(throws: (any Error).self) {
            try Self.questionnaire(text.replacingOccurrences(of: "\"cycle_id\":\"\(Self.cycle)\"", with: "\"cycle_id\":null"))
        }
    }
    @Test func officialReadingAndUnconfirmedPreselectionArePreserved() throws {
        let form = try Self.questionnaire()
        var draft = ClinicalFullDraft(questionnaire: form)
        #expect(form.bodyFat.percent == 24)
        #expect(draft.answers.weightKg == nil)
        #expect(draft.answers.activity?.activityLevel == .moderate)
        #expect(draft.answers.activity?.activityLevelConfirmed == false)
        draft.acceptBodyFat(from: form)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        #expect((object["bodyFat"] as? [String: Any])?["candidateId"] as? String == Self.candidate)
        for forbidden in ["phase", "kind", "noPlanOrigin", "sourceHash", "meanHundredths", "targets", "context_hash"] { #expect(object[forbidden] == nil) }
    }
    @Test func missingIsNullAndZeroFalseAreActualAnswers() throws {
        let draft = ClinicalFullDraft(questionnaire: try Self.questionnaire())
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        #expect(object["bodyFat"] is NSNull)
        var values = ClinicalFullAnswers()
        values.strengthSessions = 0; values.professionalConversationConfirmed = false
        let answers = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(values)) as? [String: Any])
        #expect(answers["weightKg"] is NSNull)
        #expect(answers["strengthSessions"] as? Int == 0)
        #expect(answers["professionalConversationConfirmed"] as? Bool == false)
    }
    @Test func healthNoneIsExplicitAndRemovingLastRiskNeverInventsNone() throws {
        var draft = ClinicalFullDraft(questionnaire: try Self.questionnaire())
        draft.selectNoHealthRisks()
        #expect(draft.answers.healthCheck == .noneReported)
        draft.setHealthRisk(.reducedIntake, selected: true)
        #expect(draft.answers.healthCheck == .risks([.reducedIntake]))
        draft.setHealthRisk(.reducedIntake, selected: false)
        #expect(draft.answers.healthCheck == nil)
    }
    @Test func aReplacementReadingInvalidatesAcceptanceWithoutRecomputingTheMean() throws {
        let original = try Self.questionnaire()
        var draft = ClinicalFullDraft(questionnaire: original)
        draft.acceptBodyFat(from: original)
        let replacement = try Self.questionnaire(Self.json.replacingOccurrences(of: Self.candidate, with: String(repeating: "b", count: 64)))
        try draft.refresh(from: replacement)
        #expect(draft.acceptedBodyFat == nil)
        #expect(replacement.bodyFat.percent == 24)
    }
    @Test func unknownKeysDuplicateQuestionsAndInvalidScopeFailClosed() throws {
        for input in [Self.json.replacingOccurrences(of: "weightKg", with: "privateClinicalOrigin"), Self.json.replacingOccurrences(of: "activity.activityLevel", with: "weightKg"), Self.json.replacingOccurrences(of: "\"kind\":\"REGULAR\"", with: "\"kind\":\"ROUTINE_REVIEW\"")] {
            #expect(throws: (any Error).self) { try Self.questionnaire(input) }
        }
    }
    @Test func aNewScopeCannotSilentlyRetainTheOldDraft() throws {
        var draft = ClinicalFullDraft(questionnaire: try Self.questionnaire())
        let other = try Self.questionnaire(Self.json.replacingOccurrences(of: Self.cycle, with: "b3b01000-0000-4000-8000-000000004701"))
        #expect(throws: ClinicalFullFailure.changed) { try draft.refresh(from: other) }
    }
    @Test func hiddenAnswersAndPreferenceNeverLeakIntoThePublicDraft() throws {
        var draft = ClinicalFullDraft(questionnaire: try Self.questionnaire())
        draft.answers.strengthSessions = 0; draft.answers.professionalConversationConfirmed = false
        draft.preference = .change(.weight(60))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        let answers = try #require(object["answers"] as? [String: Any])
        #expect(answers["strengthSessions"] is NSNull)
        #expect(answers["professionalConversationConfirmed"] is NSNull)
        #expect(object["preference"] is NSNull)
    }
    @Test func preferenceEncodesTheStatementWithoutCalculatingOrReplacingAnyTarget() throws {
        let input = ClinicalFullPreference.change(.weight(60))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        #expect(object["action"] as? String == "change")
        #expect((object["value"] as? [String: Any])?["kg"] as? Int == 60)
        let follow = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ClinicalFullPreference.change(.followApp))) as? [String: Any])
        let goal = try #require(follow["value"] as? [String: Any])
        #expect(goal.count == 1 && goal["kind"] as? String == "follow_app")
        #expect(throws: (any Error).self) { try JSONEncoder().encode(ClinicalFullPreference.change(.weight(0))) }
    }
}
