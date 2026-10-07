import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Onboarding eligibility operation boundaries")
struct OnboardingEligibilityBoundaryTests {
    @Test("no request leaves the device before every preceding field and document action is valid")
    func invalidPrerequisiteNeverSendsBody() async {
        var missingSex = E3Fixtures.draft(); missingSex.biologicalSex = nil
        var missingRoutine = E3Fixtures.draft(); missingRoutine.trainingFrequency = nil
        var missingPersona = E3Fixtures.draft(); missingPersona.persona = nil
        var missingDocuments = E3Fixtures.draft(); missingDocuments.documentActions = nil
        for draft in [missingSex, missingRoutine, missingPersona, missingDocuments] {
            let repo = E3Repository()
            let model = await E3Fixtures.model(draft: draft, repository: repo)
            await model.continueFromCurrentStep()
            #expect(await repo.inputs.isEmpty)
            #expect(model.step != .objective)
        }
    }

    @Test("unavailable choice is cleared and the model cannot select it")
    func unavailableOptionCannotBeSelected() async {
        let blocked = OnboardingEligibilityDecision(decision: .choice, basis: .bodyFat, objective: nil, notice: nil,
            options: [.init(objective: .bodyRecomposition, status: .available, reasons: [], message: []),
                      .init(objective: .muscleGain, status: .blocked, reasons: [.training], message: ["Server reason\nexact newline"]),
                      .init(objective: .maintenance, status: .available, reasons: [], message: [])])
        var draft = E3Fixtures.draft(); draft.objective = .muscleGain
        let repo = E3Repository(decision: blocked)
        let model = await E3Fixtures.model(draft: draft, repository: repo)
        await model.continueFromCurrentStep()
        #expect(model.step == .objective)
        #expect(model.draft.objective == nil)
        model.updateObjective(.muscleGain)
        await model.continueFromCurrentStep()
        #expect(model.draft.objective == nil)
        #expect(model.step == .objective)
        #expect(model.validationIssues == [.objectiveRequired])
        #expect(model.eligibilityDecision?.options[1].message == ["Server reason\nexact newline"])
    }

    @Test("earlier success cannot overwrite a newer decision for changed body data")
    func invertedEligibilityRepliesKeepNewDecision() async {
        let repo = E3SuspendedEligibilityRepository()
        let model = await E3Fixtures.model(repository: repo)
        let first = Task { await model.continueFromCurrentStep() }
        await repo.waitForRequests(1)
        model.updateWeightKG(90)
        let second = Task { await model.continueFromCurrentStep() }
        await repo.waitForRequests(2)
        await repo.respond(1, with: .success(E3Fixtures.assigned))
        await second.value
        await repo.respond(0, with: .success(E3Fixtures.choice))
        await first.value
        #expect(model.step == .objective)
        #expect(model.draft.weightKG == 90)
        #expect(model.eligibilityDecision == E3Fixtures.assigned)
        #expect(model.draft.objective == .bodyRecomposition)
        #expect(await repo.inputs.map(\.weightKG) == [65, 90])
    }

    @Test("cancelled old failure cannot replace a new result")
    func cancelledEligibilityFailureCannotReplaceNewResult() async {
        let repo = E3SuspendedEligibilityRepository()
        let model = await E3Fixtures.model(repository: repo)
        let first = Task { await model.continueFromCurrentStep() }
        await repo.waitForRequests(1)
        first.cancel(); model.cancelActiveSubmission()
        let second = Task { await model.continueFromCurrentStep() }
        await repo.waitForRequests(2)
        await repo.respond(1, with: .success(E3Fixtures.choice))
        await second.value
        await repo.respond(0, with: .failure(.serviceUnavailable))
        await first.value
        #expect(model.step == .objective)
        #expect(model.operationState == .idle)
        #expect(model.eligibilityDecision == E3Fixtures.choice)
    }

    @Test("editing an eligibility input makes the old selection unusable until refreshed")
    func inputChangeRequiresNewDecision() async {
        let repo = E3Repository()
        let model = await E3Fixtures.model(repository: repo)
        await model.continueFromCurrentStep()
        model.updateWeightKG(81)
        #expect(!model.hasCurrentEligibilityDecision)
        await model.continueFromCurrentStep()
        #expect(model.step == .objective)
        #expect(await repo.inputs.map(\.weightKG) == [65, 81])
        await model.continueFromCurrentStep()
        #expect(model.step == .completion)
    }

    @Test("historical completion skips eligibility, locks objective and suppresses welcome")
    func historicalReacceptanceDoesNotReenterProtocol() async {
        let repo = E3Repository(welcome: true)
        var callbacks = 0
        let model = OnboardingFlowModel(userID: "qa-a", initialDraft: E3Fixtures.draft(), repository: repo,
            personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements, historicalCompletedAt: "2026-09-15T15:00:00Z",
            onStepChanged: { _ in }, onCompleted: { callbacks += 1 })
        #expect(model.visibleSteps == [.consent, .completion])
        model.updateObjective(.muscleGain)
        await model.back()
        #expect(model.step == .consent)
        #expect(model.draft.objective == .bodyRecomposition)
        await model.continueFromCurrentStep()
        await model.complete()
        #expect(await repo.inputs.isEmpty)
        #expect(model.pendingProtocolWelcome == nil)
        #expect(callbacks == 1)
    }

    @Test("definitive objective refusal fetches a new decision and uses a new completion key")
    func objectiveRefusalUsesNewDecisionAndKey() async {
        let repo = E3Repository(completionErrors: [.objectiveNotEligible])
        var callbacks = 0
        let model = await E3Fixtures.model(draft: E3Fixtures.draft(step: .completion), repository: repo,
                                          onCompleted: { callbacks += 1 })
        await model.complete()
        #expect(model.step == .objective)
        #expect(model.hasCurrentEligibilityDecision)
        #expect(await repo.inputs.count == 2)
        #expect(!model.unresolvedCompletion)
        await model.continueFromCurrentStep()
        await model.complete()
        #expect(Set(await repo.completionKeys).count == 2)
        #expect(callbacks == 1)
    }

    @Test("cancelled completion keeps immutable key and body for a retry; late welcome cannot publish")
    func cancelledCompletionRetryUsesOriginalBodyAndKey() async {
        let repo = E3SuspendedCompletionRepository()
        var callbacks = 0
        let model = await E3Fixtures.model(draft: E3Fixtures.draft(step: .completion), repository: repo,
                                          onCompleted: { callbacks += 1 })
        let original = model.draft
        let first = Task { await model.complete() }
        await repo.waitForRequests(1)
        first.cancel(); model.cancelActiveSubmission()
        model.updateWeightKG(90); model.updateObjective(.muscleGain)
        model.updateDocumentAction(E3Fixtures.document.explicitAction, selected: false)
        await model.back()
        #expect(model.draft == original)
        #expect(model.unresolvedCompletion)
        let second = Task { await model.complete() }
        await repo.waitForRequests(2)
        await repo.respond(1)
        await second.value
        await repo.respond(0)
        await first.value
        #expect(await repo.drafts == [original, original])
        #expect(Set(await repo.keys).count == 1)
        #expect(model.pendingProtocolWelcome?.protocol == .bodyRecomposition)
        #expect(model.pendingProtocolWelcome?.paragraphs == ["Original server text"])
        #expect(callbacks == 0)
        model.finishProtocolWelcome(); model.finishProtocolWelcome()
        #expect(callbacks == 1)
    }

    @Test("teardown drops a late pending eligibility result and its error")
    func invalidatedOwnerCannotPublishResult() async {
        let repo = E3SuspendedEligibilityRepository()
        let model = await E3Fixtures.model(repository: repo)
        let request = Task { await model.continueFromCurrentStep() }
        await repo.waitForRequests(1)
        model.invalidate()
        await repo.respond(0, with: .success(E3Fixtures.assigned))
        await request.value
        #expect(!model.isActive)
        #expect(model.eligibilityDecision == nil)
        #expect(model.step == .consent)
        #expect(model.operationState == .idle)
    }
}

actor E3SuspendedEligibilityRepository: OnboardingRepository {
    private(set) var inputs: [OnboardingEligibilityInput] = []
    private var continuations: [Int: CheckedContinuation<OnboardingEligibilityDecision, any Error>] = [:]
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        let index = inputs.count; inputs.append(input)
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func waitForRequests(_ count: Int) async { while continuations.count < count { await Task.yield() } }
    func respond(_ index: Int, with result: Result<OnboardingEligibilityDecision, OnboardingRepositoryError>) {
        continuations.removeValue(forKey: index)?.resume(with: result.mapError { $0 as any Error })
    }
}

actor E3SuspendedCompletionRepository: OnboardingRepository {
    private(set) var drafts: [OnboardingDraft] = []
    private(set) var keys: [IdempotencyKey] = []
    private var continuations: [Int: CheckedContinuation<OnboardingCompletionAcknowledgement, any Error>] = [:]
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision { E3Fixtures.choice }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingCompletionAcknowledgement {
        let index = drafts.count; drafts.append(draft); keys.append(idempotencyKey)
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func waitForRequests(_ count: Int) async { while continuations.count < count { await Task.yield() } }
    func respond(_ index: Int) {
        let draft = drafts[index]
        let ack = OnboardingCompletionAcknowledgement(onboardingCompleted: true, completedAt: "2026-10-07T15:00:00Z",
            objective: draft.objective!, persona: draft.persona!, documentActions: (draft.documentActions ?? []).map {
                .init(documentKey: $0.documentKey, version: $0.version, locale: $0.locale, contentHash: $0.contentHash,
                      purpose: "synthetic_test", action: $0.action, actedAt: "2026-10-07T15:00:00Z")
            }, protocolWelcome: ProtocolWelcome(protocol: draft.objective!, paragraphs: ["Original server text"]))
        continuations.removeValue(forKey: index)?.resume(returning: ack)
    }
}
