import Foundation
import Testing
import SwiftUI
@testable import BodyFlow

@MainActor @Suite("Current signup intent and health flow")
struct OnboardingClinicalSignupFlowTests {
    @Test func noPlanAdvancesAndUsesOnlyVersionedClinicalCompletion() async throws {
        let repo=ClinicalSignupSpy(),model=make(repo)
        await model.continueFromCurrentStep()
        #expect(model.step == .objective && model.draft.objective == nil && model.hasCurrentEligibilityDecision)
        await model.continueFromCurrentStep();#expect(model.step == .completion)
        await model.complete()
        #expect(repo.clinicalCompletions == 1 && repo.legacyCompletions == 0 && repo.begins.count == 1)
    }
    @Test func selectedRisksAreOnlyAdmittedOnContinueAndRetryKeepsExactTuple() async throws {
        let repo=ClinicalSignupSpy();repo.failAdmission=true
        let model=make(repo);model.updateHealthRisk(.reducedIntake,selected:true)
        #expect(repo.health.isEmpty && repo.begins.isEmpty)
        let before=model.draft
        await model.continueFromCurrentStep()
        #expect(model.step == .consent && !model.allowsDraftEditing && repo.health.count == 1 && repo.inputs.isEmpty)
        model.updateWeightKG(42);model.updateHealthRisk(.pregnantOrBreastfeeding,selected:true)
        #expect(model.draft == before)
        await model.continueFromCurrentStep()
        #expect(model.step == .objective && model.allowsDraftEditing && repo.begins.count == 1)
        #expect(repo.health.count == 2 && repo.health[0].0 == repo.health[1].0 && repo.health[0].1 == repo.health[1].1)
        await model.continueFromCurrentStep();await model.complete()
        #expect(repo.begins.count == 1 && repo.clinicalCompletions == 1)
    }
    @Test func uncertainPreparationResolvesOriginalQBeforeAdmission() async throws {
        let repo=ClinicalSignupSpy();repo.failBegin=true
        let model=make(repo);model.updateHealthRisk(.reducedIntake,selected:true)
        await model.continueFromCurrentStep()
        #expect(repo.begins.count == 1 && repo.health.isEmpty && !model.allowsDraftEditing)
        await model.continueFromCurrentStep()
        #expect(repo.resolves == repo.begins && repo.begins.count == 1 && repo.health.count == 1)
    }
    @Test func absentRiskDoesNotFabricateDeclarationOrBeginBeforeChoice() async throws {
        let repo=ClinicalSignupSpy(),model=make(repo)
        await model.continueFromCurrentStep()
        #expect(repo.health.isEmpty && repo.begins.isEmpty && repo.inputs.first?.version == 2)
    }
    @Test func capabilityCannotAcceptLegacyDecisionAsFallback() async throws {
        let repo=ClinicalSignupSpy();repo.legacyDecision=true
        let model=make(repo);await model.continueFromCurrentStep()
        #expect(model.step == .consent && !model.hasCurrentEligibilityDecision && repo.clinicalCompletions == 0)
    }
    @Test func hostedHealthQuestionsDoNotSendAndNoPlanNeverInvitesAnObjective() async throws {
        let repo=ClinicalSignupSpy(),model=make(repo)
        let nodes=SignUpRenderingProbe.nodes(SignupHealthQuestionsView(model:model),width:393,height:3000)
        #expect(nodes.filter{$0.identifier.hasPrefix("onboarding.health.") && $0.isButton}.count == 8)
        #expect(repo.health.isEmpty && repo.begins.isEmpty)
        await model.continueFromCurrentStep()
        let objective=SignUpRenderingProbe.nodes(ObjectiveStepView(model:model),width:393,height:2000)
        #expect(objective.contains{$0.identifier == "onboarding.objective.no-plan"})
        let choiceIDs:Set<String>=["onboarding.objective.recomposicao","onboarding.objective.ganho-massa","onboarding.objective.manutencao"]
        #expect(!objective.contains{$0.isButton && choiceIDs.contains($0.identifier)})
    }
    @Test func definitiveConflictRequiresFreshOfficialReadBeforeEditingOrNewIntent() async throws {
        let repo=ClinicalSignupSpy();repo.admissionError = .requirementsChanged
        let model=make(repo);model.updateHealthRisk(.reducedIntake,selected:true)
        await model.continueFromCurrentStep()
        #expect(model.canReviewClinicalHealth && !model.canRetryHealthAdmission && !model.allowsDraftEditing)
        await model.continueFromCurrentStep();#expect(repo.health.count == 1)
        await model.reviewClinicalHealthDeclaration()
        #expect(repo.stateReads == 1 && model.allowsDraftEditing && !model.canReviewClinicalHealth)
        #expect(model.step == .consent && model.draft.documentActions == nil && repo.health.count == 1)
    }
    @Test func lateHealthResponseCannotAdvanceAnInvalidatedOwner() async throws {
        let repo=ClinicalSignupSpy(),gate=ClinicalSignupGate();repo.healthGate=gate
        let model=make(repo);model.updateHealthRisk(.reducedIntake,selected:true)
        let task=Task {await model.continueFromCurrentStep()}
        await gate.entered();model.invalidate();gate.release();await task.value
        #expect(model.step == .consent && repo.inputs.isEmpty && !model.hasCurrentEligibilityDecision)
    }
    @Test func officialCompletionObservedDuringHealthRecoveryKeepsCleanupBeforeRoot() async throws {
        let repo=ClinicalSignupSpy();repo.admissionError = .completionIntentChanged;repo.reportCompleted=true
        var events:[String]=[]
        let model=make(repo,onCompleted:{events.append("root")},onCleanup:{_ in events.append("cleanup")})
        model.updateHealthRisk(.reducedIntake,selected:true)
        await model.continueFromCurrentStep();await model.reviewClinicalHealthDeclaration()
        #expect(events == ["cleanup","root"] && repo.health.count == 1 && repo.clinicalCompletions == 0)
    }
    private func make(_ repo:ClinicalSignupSpy,onCompleted:@escaping @MainActor ()->Void = {},
                      onCleanup:@escaping @MainActor (OnboardingBodyPhotoCleanupScope?) async->Void = {_ in})->OnboardingFlowModel {
        OnboardingFlowModel(userID:"clinical-qa",initialDraft:E3Fixtures.draft(),repository:repo,
            personaRepository:E3Persona(),developmentConsentAvailability:.unavailable,requirements:E3Fixtures.requirements,
            signupCompletion:.osc1,clinicalSignup:.current,onStepChanged:{_ in},onCompleted:onCompleted,onOfficialCleanupObserved:onCleanup)
    }
}
@MainActor private final class ClinicalSignupSpy:OnboardingRepository {
    var begins:[UUID]=[],resolves:[UUID]=[],health:[(OnboardingSignupHealthDeclaration,IdempotencyKey)]=[],inputs:[OnboardingEligibilityInput]=[]
    var failAdmission=false,failBegin=false,legacyDecision=false,clinicalCompletions=0,legacyCompletions=0
    var admissionError:OnboardingRepositoryError?,stateReads=0,healthGate:ClinicalSignupGate?,reportCompleted=false
    func loadDraft(for userID:String) async throws->OnboardingDraft? {nil}
    func loadState(for userID:String) async throws->OnboardingServerState {
        stateReads+=1
        return .init(completion:.init(completed:reportCompleted,completedAt:reportCompleted ? "2026-10-27T12:00:00.000001Z" : nil),requirements:E3Fixtures.requirements,acceptedActions:[],signupCompletion:.osc1,clinicalSignup:.current)
    }
    func saveDraft(_ draft:OnboardingDraft,for userID:String) async throws {}
    func complete(_ draft:OnboardingDraft,for userID:String) async throws {legacyCompletions+=1;throw OnboardingRepositoryError.serviceUnavailable}
    func checkEligibility(_ input:OnboardingEligibilityInput,for userID:String,idempotencyKey:IdempotencyKey) async throws->OnboardingEligibilityDecision {
        inputs.append(input)
        return legacyDecision ? E3Fixtures.choice : try JSONDecoder().decode(OnboardingEligibilityDecision.self,from:Data(OnboardingClinicalSignupTests.noPlan.utf8))
    }
    func beginCompletionIntent(for userID:String,preparationID:UUID) async throws->OnboardingCompletionIntent {
        begins.append(preparationID);if failBegin {failBegin=false;throw OnboardingRepositoryError.serviceUnavailable};return try receipt(preparationID)
    }
    func resolveCompletionIntent(for userID:String,preparationID:UUID) async throws->OnboardingCompletionIntent? {resolves.append(preparationID);return try receipt(preparationID)}
    private func receipt(_ preparation:UUID)throws->OnboardingCompletionIntent {
        try JSONDecoder().decode(OnboardingCompletionIntent.self,from:JSONSerialization.data(withJSONObject:["protocol":"osc1","preparation_id":preparation.uuidString.lowercased(),"intent_id":"b3b01000-0000-4000-8000-000000005901","request_key":"osc1:b3b01000-0000-4000-8000-000000005902"]))
    }
    func admitSignupHealth(_ declaration:OnboardingSignupHealthDeclaration,for userID:String,key:IdempotencyKey) async throws->OnboardingSignupHealthAcknowledgement {
        health.append((declaration,key));if failAdmission {failAdmission=false;throw OnboardingRepositoryError.serviceUnavailable}
        if let healthGate {await healthGate.block()}
        if let error=admissionError {throw error}
        var value=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(declaration)) as? [String:Any])
        value["id"]="b3b01000-0000-4000-8000-000000005903";value["requirement_set_id"]="b3b01000-0000-4000-8000-000000005904";value["admitted_at"]="2026-10-27T12:00:00.000001Z"
        return try JSONDecoder().decode(OnboardingSignupHealthAcknowledgement.self,from:JSONSerialization.data(withJSONObject:["version":1,"availability":"available","operation_key":key.value,"receipt":value]))
    }
    func completeOfficial(_ draft:OnboardingDraft,for userID:String,completionIntent:OnboardingCompletionIntent,clinicalSignup:OnboardingClinicalSignupCapability) async throws->OnboardingCompletionAcknowledgement {
        clinicalCompletions+=1
        let at="2026-10-27T12:00:00.000001Z"
        let safety=try JSONDecoder().decode(OnboardingClinicalSafety.self,from:Data(#"{"version":1,"no_plan":true,"hold_active":false,"loss_guard":false,"hide_protein":true,"recording_allowed":true,"date":"2026-10-27","timezone":"America/Sao_Paulo","observed_at":"2026-10-27T12:00:00.000001Z"}"#.utf8))
        return OnboardingCompletionAcknowledgement(onboardingCompleted:true,completedAt:at,objective:draft.objective,persona:try #require(draft.persona),documentActions:(draft.documentActions ?? []).map{.init(documentKey:$0.documentKey,version:$0.version,locale:$0.locale,contentHash:$0.contentHash,purpose:"synthetic",action:$0.action,actedAt:at)},clinicalSafety:safety)
    }
    func clear(for userID:String) async throws {}
}
@MainActor private final class ClinicalSignupGate {
    private var started=false,entry:CheckedContinuation<Void,Never>?,waiter:CheckedContinuation<Void,Never>?
    func block() async {started=true;entry?.resume();entry=nil;await withCheckedContinuation{waiter=$0}}
    func entered() async {if !started {await withCheckedContinuation{entry=$0}}}
    func release() {waiter?.resume();waiter=nil}
}
