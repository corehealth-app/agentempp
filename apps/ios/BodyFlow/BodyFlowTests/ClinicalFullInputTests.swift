import Foundation
import Testing
@testable import BodyFlow

@Suite("Clinical FULL — raw input is never silently skipped or truncated")
struct ClinicalFullInputTests {
    @Test func sessionDurationMustBePositiveEvenWithoutDescriptorBoundsAndOptOutRemainsExplicit() throws {
        let descriptor = #"{"key":"activity.sessionMinutes","label":"Minutos","input_kind":"decimal","unit":"minutes","opt_out_label":"Prefiro não responder","options":null,"min":null,"max":null,"preselected":null,"initially_confirmed":null,"hint":null},"#
        let form = try ClinicalFullFormTests.questionnaire(ClinicalFullFormTests.json.replacingOccurrences(of: "\"questions\":[", with: "\"questions\":[" + descriptor))
        let question = try #require(form.questions.first(where: { $0.key == .sessionMinutes }))
        var draft = ClinicalFullDraft(questionnaire: form), input = ClinicalFullInputState()
        input.setText("0,5", question: question, draft: &draft, language: .portugueseBrazil)
        #expect(!input.hasInvalidValues && draft.answers.activity?.sessionMinutes == Decimal(string: "0.5"))
        for raw in ["0", "0,0", "-1"] {
            input.setText(raw, question: question, draft: &draft, language: .portugueseBrazil)
            #expect(input.hasInvalidValues && input.text[.sessionMinutes] == raw)
            #expect(draft.answers.activity?.sessionMinutes == Decimal(string: "0.5"))
            input.refresh(form)
            #expect(input.hasInvalidValues && input.text[.sessionMinutes] == raw)
        }
        input.setText("", question: question, draft: &draft, language: .portugueseBrazil)
        #expect(!input.hasInvalidValues && draft.answers.activity?.sessionMinutes == nil)
    }
    @Test func invalidOrPartialWeightStaysVisibleAndCannotReplaceTheLastValidAnswer() throws {
        let form = try ClinicalFullFormTests.questionnaire(), question = try #require(form.questions.first)
        var draft = ClinicalFullDraft(questionnaire:form), input = ClinicalFullInputState()
        input.setText("70,5",question:question,draft:&draft,language:.portugueseBrazil)
        #expect(draft.answers.weightKg == Decimal(string:"70.5"))
        for text in ["70,", "1.000", "0", "301", "--"] {
            input.setText(text,question:question,draft:&draft,language:.portugueseBrazil)
            #expect(input.hasInvalidValues && input.text[.weightKg] == text)
            #expect(draft.answers.weightKg == Decimal(string:"70.5"))
            input.refresh(form)
            #expect(input.hasInvalidValues && input.text[.weightKg] == text)
        }
        input.setText("",question:question,draft:&draft,language:.portugueseBrazil)
        #expect(!input.hasInvalidValues && draft.answers.weightKg == nil)
    }
    @Test func zeroIsAnActualIntegerButFractionalSessionsAreNeverTruncated() throws {
        let question = ClinicalFullQuestion(key:.strengthSessions,label:"Treinos",inputKind:.integer,unit:"per_week",optOutLabel:"Pular",options:nil,min:0,max:7,preselected:nil,initiallyConfirmed:nil,hint:nil)
        var input = ClinicalFullInputState(), draft = ClinicalFullDraft(questionnaire:try ClinicalFullFormTests.questionnaire())
        input.setText("0",question:question,draft:&draft,language:.englishUnitedStates)
        #expect(!input.hasInvalidValues && draft.answers.strengthSessions == 0)
        input.setText("2.5",question:question,draft:&draft,language:.englishUnitedStates)
        #expect(input.hasInvalidValues && draft.answers.strengthSessions == 0)
        input.setText("7",question:question,draft:&draft,language:.englishUnitedStates)
        #expect(!input.hasInvalidValues && draft.answers.strengthSessions == 7)
    }
    @Test func explicitFalseRemainsDifferentFromAnUnansweredBoolean() throws {
        let question = ClinicalFullQuestion(key:.professionalConversationConfirmed,label:"Conversa",inputKind:.boolean,unit:nil,optOutLabel:"Pular",options:[ClinicalFullOption(value:.boolean(true),label:"Sim"),ClinicalFullOption(value:.boolean(false),label:"Não")],min:nil,max:nil,preselected:nil,initiallyConfirmed:nil,hint:nil)
        var draft = ClinicalFullDraft(questionnaire:try ClinicalFullFormTests.questionnaire())
        ClinicalFullInputState.select(.boolean(false),question:question,draft:&draft)
        #expect(draft.answers.professionalConversationConfirmed == false)
        ClinicalFullInputState.select(nil,question:question,draft:&draft)
        #expect(draft.answers.professionalConversationConfirmed == nil)
    }
    @Test func purposesAreOnlyTheServerOptionsAndMustIncludeTheSelectedBranch() throws {
        let base = ClinicalFullFormTests.json
        let valid = base.replacingOccurrences(of:"\"questions\":",with:"\"activity_purpose_options\":[\"normal\",\"consider_maintenance\",\"end_deficit\"],\"questions\":")
        #expect(try ClinicalFullFormTests.questionnaire(valid).purposeOptions?.count == 3)
        #expect(throws:(any Error).self) { try ClinicalFullFormTests.questionnaire(valid.replacingOccurrences(of:"[\"normal\",\"consider_maintenance\",\"end_deficit\"]",with:"[\"normal\"]")) }
    }
}
