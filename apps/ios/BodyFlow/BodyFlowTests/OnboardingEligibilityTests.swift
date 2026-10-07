import Foundation
import Testing
@testable import BodyFlow

@MainActor
@Suite("Server-authoritative onboarding eligibility")
struct OnboardingEligibilityTests {
    @Test("documents advance only after the server decision")
    func consentRequestsDecisionBeforeAdvance() async {
        let repository = E3Repository()
        let model = await E3Fixtures.model(repository: repository)
        await model.continueFromCurrentStep()
        #expect(model.step == .objective)
        #expect(await repository.inputs.count == 1)
    }

    @Test("server failure keeps documents visible with no transition")
    func eligibilityFailureKeepsDocuments() async {
        let repository = E3Repository(checkError: .serviceUnavailable)
        let model = await E3Fixtures.model(repository: repository)
        await model.continueFromCurrentStep()
        #expect(model.step == .consent)
        #expect(model.operationState == .failed(.serviceUnavailable))
        #expect(await repository.savedDrafts.isEmpty)
    }

    @Test("assigned response replaces an earlier unavailable objective")
    func assignedResponseSelectsRecomposition() async {
        let repository = E3Repository(decision: E3Fixtures.assigned)
        var draft = E3Fixtures.draft()
        draft.objective = .muscleGain
        let model = await E3Fixtures.model(draft: draft, repository: repository)
        await model.continueFromCurrentStep()
        #expect(model.draft.objective == .bodyRecomposition)
    }

    @Test("welcome from confirmed record delays the root")
    func welcomeDefersRoot() async {
        let repository = E3Repository(welcome: true)
        var callbacks = 0
        let model = await E3Fixtures.model(draft: E3Fixtures.draft(step: .completion), repository: repository,
                                    onCompleted: { callbacks += 1 })
        await model.complete()
        #expect(await repository.completionDrafts.count == 1)
        #expect(callbacks == 0)
    }

    @Test("new generation of the same account replaces stale flow")
    func sameUserNewGenerationReplacesModel() {
        var coordinator = OnboardingRootCoordinator()
        let repo = E3Repository()
        coordinator.synchronize(activeUserID: "qa-a", restoredDraft: E3Fixtures.draft(), restoreGeneration: 1,
            requirements: E3Fixtures.requirements, onboarding: repo, persona: E3Persona(),
            developmentConsentAvailability: .unavailable, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: {})
        let first = coordinator.flowModel
        var authoritative = E3Fixtures.draft()
        authoritative.objective = .maintenance
        coordinator.synchronize(activeUserID: "qa-a", restoredDraft: authoritative, restoreGeneration: 2,
            requirements: E3Fixtures.requirements, onboarding: repo, persona: E3Persona(),
            developmentConsentAvailability: .unavailable, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: {})
        #expect(coordinator.flowModel !== first)
        #expect(coordinator.flowModel?.draft.objective == .maintenance)
    }

    @Test("accepted success still records its telemetry when root tears down the flow")
    func rootTeardownKeepsAcceptedCompletionTelemetry() async {
        let repository = E3Repository()
        let telemetry = InMemoryTelemetryClient()
        let holder = E3ModelHolder()
        let model = OnboardingFlowModel(userID: "qa-a", initialDraft: E3Fixtures.draft(), repository: repository,
            personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements, historicalCompletedAt: "2026-09-15T15:00:00Z",
            telemetry: telemetry, onStepChanged: { _ in }, onCompleted: { holder.model?.invalidate() })
        holder.model = model
        await model.continueFromCurrentStep()
        let before = await telemetry.snapshot().count
        await model.complete()
        #expect(Array((await telemetry.snapshot()).dropFirst(before)).map(\.name) == [
            .coachPersonaSelected, .onboardingStepCompleted, .onboardingCompleted])
    }

    @Test("eligibility default repository implementation fails closed")
    func defaultCheckFailsClosed() async throws {
        let repo = E3DefaultRepository()
        await #expect(throws: OnboardingRepositoryError.serviceUnavailable) {
            try await repo.checkEligibility(OnboardingEligibilityInput(draft: E3Fixtures.draft()),
                for: "qa-a", idempotencyKey: IdempotencyKey(validating: "qa-eligibility-key"))
        }
    }
}

enum E3Fixtures {
    static let document = OnboardingLegalDocument(
        documentKey: "terms_of_service", version: "e3-qa-v1", locale: "pt-BR",
        body: "Synthetic test document", contentURL: nil, contentHash: String(repeating: "a", count: 64),
        purpose: "synthetic_test", action: .acceptance, required: true, effectiveAt: "2026-10-07T15:00:00Z")
    static let requirements = OnboardingRequirements(available: true, blockingReason: nil, documents: [document])
    static func draft(step: OnboardingStep = .consent) -> OnboardingDraft {
        var value = BodyFlowTestFixtures.onboardingDraft(currentStep: step)
        value.documentActions = [document.explicitAction]
        return value
    }
    static let choice = OnboardingEligibilityDecision(decision: .choice, basis: .bodyFat, objective: nil, notice: nil,
        options: [.init(objective: .bodyRecomposition, status: .available, reasons: [], message: []),
                  .init(objective: .muscleGain, status: .available, reasons: [], message: []),
                  .init(objective: .maintenance, status: .available, reasons: [], message: [])])
    static let assigned = OnboardingEligibilityDecision(decision: .assigned, basis: .bodyFat,
        objective: .bodyRecomposition, notice: ["Server assigned notice"], options: [
            .init(objective: .bodyRecomposition, status: .available, reasons: [], message: []),
            .init(objective: .muscleGain, status: .blocked, reasons: [.composition], message: ["Server gain blocked"]),
            .init(objective: .maintenance, status: .notOffered, reasons: [], message: [])])
    @MainActor static func model(draft: OnboardingDraft = E3Fixtures.draft(), repository: any OnboardingRepository,
        onCompleted: @escaping @MainActor () -> Void = {}) async -> OnboardingFlowModel {
        let model = OnboardingFlowModel(userID: "qa-a", initialDraft: draft, repository: repository,
            personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: requirements, onStepChanged: { _ in }, onCompleted: onCompleted)
        if draft.currentStep == .completion, model.step == .objective {
            await model.prepareObjectiveIfNeeded()
            await model.continueFromCurrentStep()
        }
        return model
    }
}

actor E3Repository: OnboardingRepository {
    var decision: OnboardingEligibilityDecision
    private var completionErrors: [OnboardingRepositoryError]
    let checkError: OnboardingRepositoryError?
    let welcome: Bool
    private(set) var inputs: [OnboardingEligibilityInput] = []
    private(set) var savedDrafts: [OnboardingDraft] = []
    private(set) var completionDrafts: [OnboardingDraft] = []
    private(set) var completionKeys: [IdempotencyKey] = []
    init(decision: OnboardingEligibilityDecision = E3Fixtures.choice,
        checkError: OnboardingRepositoryError? = nil, welcome: Bool = false,
        completionErrors: [OnboardingRepositoryError] = []) {
        self.completionErrors = completionErrors
        self.decision = decision; self.checkError = checkError; self.welcome = welcome
    }
    func setDecision(_ value: OnboardingEligibilityDecision) { decision = value }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws { savedDrafts.append(draft) }
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        inputs.append(input)
        if let checkError { throw checkError }
        return decision
    }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingCompletionAcknowledgement {
        completionDrafts.append(draft); completionKeys.append(idempotencyKey)
        if !completionErrors.isEmpty { throw completionErrors.removeFirst() }
        return OnboardingCompletionAcknowledgement(onboardingCompleted: true, completedAt: "2026-10-07T15:00:00Z",
            objective: draft.objective!, persona: draft.persona!, documentActions: (draft.documentActions ?? []).map {
                .init(documentKey: $0.documentKey, version: $0.version, locale: $0.locale, contentHash: $0.contentHash,
                      purpose: "synthetic_test", action: $0.action, actedAt: "2026-10-07T15:00:00Z")
            }, protocolWelcome: welcome ? ProtocolWelcome(protocol: draft.objective!, paragraphs: ["First server paragraph\nPreserved newline", "Second server paragraph"]) : nil)
    }
    func clear(for userID: String) async throws {}
}
struct E3Persona: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}
struct E3DefaultRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}
}

@MainActor
func prepareE3Review(_ model: OnboardingFlowModel) async {
    guard model.step == .objective else { return }
    await model.prepareObjectiveIfNeeded()
    await model.continueFromCurrentStep()
}

@MainActor
private final class E3ModelHolder {
    weak var model: OnboardingFlowModel?
}
