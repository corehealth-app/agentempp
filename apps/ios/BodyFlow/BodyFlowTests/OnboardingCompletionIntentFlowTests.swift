import Foundation
import Testing
import SwiftUI
import UIKit
import XCTest
@testable import BodyFlow

@MainActor
@Suite("Signup completion intent flow")
struct OnboardingCompletionIntentFlowTests {
    @Test("An advertised protocol begins once then completes with its positive receipt")
    func advertisedProtocolUsesReceipt() async throws {
        let repository = IntentFlowRepository()
        let model = await makeModel(repository)
        let original = model.draft

        await model.complete()

        #expect(repository.begins == [F.q0])
        #expect(repository.resolves.isEmpty)
        #expect(repository.legacyDrafts.isEmpty)
        #expect(repository.versionedDrafts == [original])
        #expect(repository.receipts == [try F.receipt(F.q0)])
    }

    @Test("An uncertain begin keeps Q and resolves only after the next gesture")
    func uncertainPreparationResolvesSameQ() async throws {
        let repository = IntentFlowRepository()
        repository.beginResults = [.failure(.serviceUnavailable)]
        var callbacks = 0
        let model = await makeModel(repository, onCompleted: { callbacks += 1 })

        await model.complete()

        #expect(repository.begins == [F.q0])
        #expect(repository.resolves.isEmpty)
        #expect(repository.legacyDrafts.isEmpty && repository.versionedDrafts.isEmpty)
        #expect(callbacks == 0 && model.unresolvedCompletion && !model.allowsDraftEditing)
        await model.complete()
        #expect(repository.begins == [F.q0])
        #expect(repository.resolves == [F.q0])
        #expect(repository.receipts == [try F.receipt(F.q0)])
        #expect(callbacks == 1)
    }

    @Test("Absent capability preserves the original legacy key across a retry")
    func absentCapabilityKeepsLegacy() async {
        let repository = IntentFlowRepository()
        repository.completionErrors = [.serviceUnavailable]
        let model = await makeModel(repository, capability: nil)
        let original = model.draft
        await model.complete()
        await model.complete()
        #expect(repository.begins.isEmpty && repository.resolves.isEmpty && repository.receipts.isEmpty)
        #expect(repository.legacyDrafts == [original, original])
        #expect(repository.legacyKeys.count == 2 && Set(repository.legacyKeys).count == 1)
    }

    @Test("An absent or unavailable resolve never issues a new preparation", arguments: [false, true])
    func missingResolveKeepsUncertainty(unavailable: Bool) async {
        let repository = IntentFlowRepository()
        repository.beginResults = [.failure(.serviceUnavailable)]
        repository.resolveResults = unavailable
            ? [.failure(.serviceUnavailable), .failure(.serviceUnavailable)] : [.success(nil), .success(nil)]
        var ids = 0
        let model = await makeModel(repository, preparationID: { ids += 1; return F.q0 })
        await model.complete()
        await model.complete()
        await model.complete()
        #expect(repository.begins == [F.q0] && repository.resolves == [F.q0, F.q0] && ids == 1)
        #expect(repository.receipts.isEmpty && repository.legacyDrafts.isEmpty)
        #expect(model.unresolvedCompletion && !model.allowsDraftEditing && model.canReviewCompletion)
        #expect(model.checksCompletionOnly)
    }

    @Test("A receipt from another preparation cannot authorize completion", arguments: [false, true])
    func mismatchedReceiptStaysClosed(resolve: Bool) async throws {
        let repository = IntentFlowRepository()
        repository.beginResults = resolve ? [.failure(.serviceUnavailable)] : [.success(try F.receipt(F.q1))]
        repository.resolveResults = [.success(try F.receipt(F.q1))]
        let model = await makeModel(repository)
        await model.complete()
        if resolve { await model.complete() }
        #expect(repository.receipts.isEmpty && repository.legacyDrafts.isEmpty)
        #expect(model.unresolvedCompletion && !model.allowsDraftEditing)
    }

    @Test("Draft, documents, photos, back and persistence freeze before begin's first await")
    func preparationFreezesEveryEditAndDoubleTap() async throws {
        let repository = IntentFlowRepository()
        let gate = IntentFlowGate()
        repository.gates[.begin] = gate
        let model = await makeModel(repository)
        let original = model.draft
        let savedBefore = repository.savedDrafts
        let keptBefore = repository.keptDrafts
        let task = Task { await model.complete(); await gate.finish() }
        let entered = await gate.entryOrFinish()
        if !entered { await gate.release(); await task.value; try #require(entered) }
        model.updateDisplayName("Do not overwrite")
        model.updateWeightKG(42)
        model.updateBodyFatPercent(50)
        model.updateDocumentAction(E3Fixtures.document.explicitAction, selected: false)
        let deletion = model.beginBodyPhotoDeletion(for: OnboardingOwnerToken(userID: model.userID, restoreGeneration: 0))
        await model.back()
        await model.keepDraftOnDevice()
        await model.complete()
        #expect(model.draft == original && !model.canGoBack && deletion == nil)
        #expect(repository.savedDrafts == savedBefore && repository.keptDrafts == keptBefore)
        #expect(repository.begins == [F.q0] && repository.receipts.isEmpty)
        await gate.release(); await task.value
        let expected = try F.receipt(F.q0)
        #expect(repository.versionedDrafts == [original] && repository.receipts == [expected])
    }

    @Test("An uncertain completion retains draft, ID and K; preparation review cannot discard it")
    func uncertainCompletionKeepsExactTuple() async throws {
        let repository = IntentFlowRepository()
        repository.completionErrors = [.serviceUnavailable]
        let model = await makeModel(repository)
        let original = model.draft
        await model.complete()
        #expect(!model.canReviewCompletion && !model.checksCompletionOnly)
        model.reviewCompletionBeforeRetry()
        model.updateWeightKG(42)
        await model.complete()
        #expect(repository.begins == [F.q0] && repository.resolves.isEmpty)
        #expect(repository.versionedDrafts == [original, original])
        let expected = try F.receipt(F.q0)
        #expect(repository.receipts == [expected, expected] && model.draft == original)
    }

    @Test("A 409 with failed GET retries only GET, and official completion closes once")
    func authorityConflictNeverRepostsAfterReadFailure() async {
        let repository = IntentFlowRepository()
        repository.completionErrors = [.completionIntentChanged]
        repository.states = [.failure(.serviceUnavailable), .success(F.state(completed: true))]
        let telemetry = InMemoryTelemetryClient()
        var callbacks = 0
        let model = await makeModel(repository, telemetry: telemetry, onCompleted: { callbacks += 1 })
        let before = await telemetry.snapshot().count
        await model.complete()
        #expect(repository.reads == 1 && repository.receipts.count == 1)
        #expect(model.unresolvedCompletion && !model.canReviewCompletion && model.checksCompletionOnly)
        await model.complete()
        await model.complete()
        #expect(repository.reads == 2 && repository.receipts.count == 1 && repository.begins == [F.q0])
        #expect(callbacks == 1 && !model.unresolvedCompletion && !model.allowsDraftEditing)
        #expect(Array((await telemetry.snapshot()).dropFirst(before)).isEmpty)
    }

    @Test("An incomplete conflict needs explicit review before a new Q may be issued")
    func incompleteConflictRequiresReviewAndNewGesture() async throws {
        let repository = IntentFlowRepository()
        repository.completionErrors = [.completionIntentChanged]
        let state = F.state()
        repository.states = [.success(state), .success(state)]
        var issued = 0
        let model = await makeModel(repository, preparationID: { issued += 1; return issued == 1 ? F.q0 : F.q1 })
        await model.complete()
        #expect(model.step == .completion && model.canReviewCompletion && !model.allowsDraftEditing)
        await model.complete()
        #expect(repository.reads == 2 && repository.receipts.count == 1 && issued == 1)
        model.reviewCompletionBeforeRetry()
        #expect(model.step == .bodyData && model.allowsDraftEditing && !model.unresolvedCompletion)
        #expect(model.draft.documentActions == nil && issued == 1)
        await advanceToReview(model)
        await model.complete()
        #expect(repository.begins == [F.q0, F.q1] && issued == 2)
        #expect(repository.receipts == [try F.receipt(F.q0), try F.receipt(F.q1)])
    }

    @Test("A historical timestamp without an authoritative draft cannot unlock review")
    func inconsistentOfficialStateStaysClosed() async {
        let repository = IntentFlowRepository()
        repository.completionErrors = [.completionIntentChanged]
        repository.states = [.success(F.state(historical: true, includeDraft: false)), .failure(.serviceUnavailable)]
        let model = await makeModel(repository)
        await model.complete()
        #expect(!model.canReviewCompletion && !model.allowsDraftEditing)
        model.reviewCompletionBeforeRetry()
        await model.complete()
        #expect(repository.reads == 2 && repository.receipts.count == 1 && repository.begins == [F.q0])
    }

    @Test("Late begin or resolve success/error cannot overwrite a newer operation",
          arguments: [false, true], [false, true])
    func latePreparationDoesNotReplaceNewOperation(resolve: Bool, fails: Bool) async throws {
        let repository = IntentFlowRepository()
        let oldGate = IntentFlowGate()
        let nextGate = IntentFlowGate()
        let outcome: Result<OnboardingCompletionIntent, OnboardingRepositoryError> = fails
            ? .failure(.serviceUnavailable) : .success(try F.receipt(F.q0))
        if resolve {
            repository.beginResults = [.failure(.serviceUnavailable)]
            repository.resolveResults = [outcome.map(Optional.some), .success(try F.receipt(F.q0))]
        } else { repository.beginResults = [outcome] }
        let model = await makeModel(repository)
        if resolve { await model.complete() }
        repository.gates[resolve ? .resolve : .begin] = oldGate
        let old = Task { await model.complete(); await oldGate.finish() }
        let entered = await oldGate.entryOrFinish()
        if !entered { await oldGate.release(); await old.value; try #require(entered) }
        model.cancelActiveSubmission()
        repository.gates[.resolve] = nextGate
        let next = Task { await model.complete(); await nextGate.finish() }
        let nextEntered = await nextGate.entryOrFinish()
        if !nextEntered { await nextGate.release(); await oldGate.release(); await old.value; await next.value; try #require(nextEntered) }
        await oldGate.release(); await old.value
        #expect(model.operationState == .saving && repository.receipts.isEmpty)
        await nextGate.release(); await next.value
        #expect(repository.receipts == [try F.receipt(F.q0)])
        #expect(repository.begins == [F.q0] && repository.resolves.count == (resolve ? 2 : 1))
    }

    @Test("Explicit preparation review invalidates late Q0 while Q1 is pending", arguments: [false, true])
    func reviewAbandonsOnlyPreparation(fails: Bool) async throws {
        let repository = IntentFlowRepository()
        repository.beginResults = [fails ? .failure(.serviceUnavailable) : .success(try F.receipt(F.q0)),
            .success(try F.receipt(F.q1))]
        let oldGate = IntentFlowGate(); let newGate = IntentFlowGate()
        repository.gates[.begin] = oldGate
        var issued = 0
        let model = await makeModel(repository, preparationID: { issued += 1; return issued == 1 ? F.q0 : F.q1 })
        let old = Task { await model.complete(); await oldGate.finish() }
        let entered = await oldGate.entryOrFinish()
        if !entered { await oldGate.release(); await old.value; try #require(entered) }
        model.cancelActiveSubmission()
        #expect(model.canReviewCompletion)
        model.reviewCompletionBeforeRetry()
        model.updateDisplayName("Reviewed synthetic name")
        repository.gates[.begin] = newGate
        let next = Task { await model.complete(); await newGate.finish() }
        let newEntered = await newGate.entryOrFinish()
        if !newEntered { await newGate.release(); await oldGate.release(); await old.value; await next.value; try #require(newEntered) }
        await oldGate.release(); await old.value
        #expect(model.operationState == .saving && repository.receipts.isEmpty)
        await newGate.release(); await next.value
        let expected = try F.receipt(F.q1)
        #expect(repository.begins == [F.q0, F.q1] && repository.receipts == [expected])
        #expect(repository.versionedDrafts.first?.displayName == "Reviewed synthetic name")
    }

    @Test("422 after uncertainty reviews the objective without automatically issuing another Q")
    func objectiveRefusalPreservesOriginalRetry() async throws {
        let repository = IntentFlowRepository()
        repository.completionErrors = [.serviceUnavailable, .objectiveNotEligible]
        var issued = 0
        let model = await makeModel(repository, preparationID: { issued += 1; return issued == 1 ? F.q0 : F.q1 })
        let original = model.draft
        await model.complete()
        await model.complete()
        #expect(model.step == .objective && model.allowsDraftEditing && issued == 1)
        #expect(repository.versionedDrafts == [original, original])
        #expect(repository.receipts == [try F.receipt(F.q0), try F.receipt(F.q0)])
        await model.continueFromCurrentStep()
        await model.complete()
        #expect(repository.begins == [F.q0, F.q1] && issued == 2)
        #expect(repository.receipts.last == (try F.receipt(F.q1)))
    }

    @Test("An accepted versioned ACK survives cleanup cancellation without rearming POST", arguments: [false, true])
    func acceptedACKCannotRearm(invalidate: Bool) async throws {
        let repository = IntentFlowRepository()
        let gate = IntentFlowGate(); let telemetry = InMemoryTelemetryClient()
        var callbacks = 0
        let model = await makeModel(repository, telemetry: telemetry,
            onCleanup: { _ in await gate.pause() }, onCompleted: { callbacks += 1 })
        let before = await telemetry.snapshot().count
        let task = Task { await model.complete(); await gate.finish() }
        let entered = await gate.entryOrFinish()
        if !entered { await gate.release(); await task.value; try #require(entered) }
        #expect(!model.unresolvedCompletion && !model.allowsDraftEditing && repository.receipts.count == 1)
        if invalidate { model.invalidate() } else { task.cancel() }
        await gate.release(); await task.value
        await model.complete()
        #expect(callbacks == 0 && repository.receipts.count == 1)
        let events = Array((await telemetry.snapshot()).dropFirst(before)).map(\.name)
        #expect(events == [.coachPersonaSelected, .onboardingStepCompleted, .onboardingCompleted])
    }

    @Test("Root restore publishes the capability and clears it on failure, logout and completion")
    func rootCapabilityHasNoStaleFallback() async {
        let repository = IntentFlowRepository()
        repository.states = [.success(F.state()), .failure(.serviceUnavailable),
            .success(F.state(capability: nil)), .success(F.state(completed: true))]
        let root = AppFlowModel(authentication: CleanupModelAuthentication(session: F.session),
            onboarding: repository, persona: E3Persona(), telemetry: DisabledTelemetryClient())
        await root.start()
        #expect(root.restoredSignupCompletion == .osc1)
        await root.retryOnboardingRestore()
        #expect(root.restoredSignupCompletion == nil)
        await root.signOut()
        #expect(root.restoredSignupCompletion == nil && root.restoredOnboardingDraft == nil)
        await root.start()
        #expect(root.restoredSignupCompletion == nil && root.restoredOnboardingDraft != nil)
        await root.start()
        #expect(root.state == .authenticated(userID: F.session.userID) && root.restoredSignupCompletion == nil)
    }

    @Test("An old same-account restore cannot install its capability after a newer restore")
    func lateRootReadCannotPublishCapability() async throws {
        let repository = IntentFlowRepository()
        let gate = IntentFlowGate()
        repository.gates[.read] = gate
        repository.states = [.success(F.state()), .success(F.state(capability: nil))]
        let root = AppFlowModel(authentication: CleanupModelAuthentication(session: F.session),
            onboarding: repository, persona: E3Persona(), telemetry: DisabledTelemetryClient())
        let old = Task { await root.start(); await gate.finish() }
        let entered = await gate.entryOrFinish()
        if !entered { await gate.release(); await old.value; try #require(entered) }
        await root.start()
        let generation = root.onboardingRestoreGeneration
        #expect(root.restoredSignupCompletion == nil)
        await gate.release(); await old.value
        #expect(root.restoredSignupCompletion == nil && root.onboardingRestoreGeneration == generation)
    }

    @Test("A to B to A invalidates the old model and its late receipt", arguments: [false, true])
    func replacedOwnerCannotComplete(fails: Bool) async throws {
        let repository = IntentFlowRepository()
        repository.beginResults = [fails ? .failure(.serviceUnavailable) : .success(try F.receipt(F.q0)),
            .success(try F.receipt(F.q1))]
        let gate = IntentFlowGate(); repository.gates[.begin] = gate
        var coordinator = OnboardingRootCoordinator()
        var callbacks = 0
        coordinator.synchronize(activeUserID: F.session.userID, restoredDraft: E3Fixtures.draft(step: .completion),
            restoreGeneration: 1, signupCompletion: .osc1, requirements: E3Fixtures.requirements,
            onboarding: repository, persona: E3Persona(), developmentConsentAvailability: .unavailable,
            preparationIDProvider: { F.q0 }, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: { callbacks += 1 })
        let first = try #require(coordinator.flowModel)
        await prepareE3Review(first)
        let old = Task { await first.complete(); await gate.finish() }
        let entered = await gate.entryOrFinish()
        if !entered { await gate.release(); await old.value; try #require(entered) }
        coordinator.synchronize(activeUserID: "intent-flow-b", restoredDraft: E3Fixtures.draft(),
            restoreGeneration: 2, requirements: E3Fixtures.requirements, onboarding: repository,
            persona: E3Persona(), developmentConsentAvailability: .unavailable,
            telemetry: DisabledTelemetryClient(), onStepChanged: { _ in }, onCompleted: {})
        coordinator.synchronize(activeUserID: F.session.userID, restoredDraft: E3Fixtures.draft(step: .completion),
            restoreGeneration: 3, signupCompletion: .osc1, requirements: E3Fixtures.requirements,
            onboarding: repository, persona: E3Persona(), developmentConsentAvailability: .unavailable,
            preparationIDProvider: { F.q1 }, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: { callbacks += 1 })
        let current = try #require(coordinator.flowModel)
        #expect(current !== first && !first.isActive)
        await gate.release(); await old.value
        #expect(repository.receipts.isEmpty && callbacks == 0 && current.operationState == .idle)
        await prepareE3Review(current)
        await current.complete()
        #expect(repository.receipts == [try F.receipt(F.q1)] && callbacks == 1)
    }

    private func advanceToReview(_ model: OnboardingFlowModel) async {
        for _ in 0..<8 {
            if model.step == .completion { return }
            if model.step == .consent {
                for document in model.requirements.documents { model.updateDocumentAction(document.explicitAction, selected: true) }
            }
            if model.step == .objective { await model.prepareObjectiveIfNeeded() }
            await model.continueFromCurrentStep()
        }
    }

    fileprivate func makeModel(_ repository: IntentFlowRepository,
        capability: OnboardingCompletionCapability? = .osc1,
        preparationID: @escaping @MainActor () -> UUID = { F.q0 },
        telemetry: any TelemetryClient = DisabledTelemetryClient(),
        onCleanup: @escaping @MainActor (OnboardingBodyPhotoCleanupScope?) async -> Void = { _ in },
        onCompleted: @escaping @MainActor () -> Void = {}
    ) async -> OnboardingFlowModel {
        let model = OnboardingFlowModel(userID: "intent-flow-a", initialDraft: E3Fixtures.draft(step: .completion),
            repository: repository, personaRepository: E3Persona(), developmentConsentAvailability: .unavailable,
            requirements: E3Fixtures.requirements, signupCompletion: capability,
            preparationIDProvider: preparationID, telemetry: telemetry,
            onStepChanged: { _ in }, onCompleted: onCompleted, onOfficialCleanupObserved: onCleanup)
        await prepareE3Review(model)
        return model
    }
    private typealias F = IntentFlowFixture
}

private enum IntentFlowFixture {
    static let q0 = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    static let q1 = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
    static func receipt(_ q: UUID) throws -> OnboardingCompletionIntent {
        let id = q == q0 ? "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" : "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let key = q == q0 ? "osc1:cccccccc-cccc-4ccc-8ccc-cccccccccccc" : "osc1:ffffffff-ffff-4fff-8fff-ffffffffffff"
        let data = try JSONSerialization.data(withJSONObject: ["protocol": "osc1",
            "preparation_id": q.uuidString.lowercased(), "intent_id": id, "request_key": key])
        return try JSONDecoder().decode(OnboardingCompletionIntent.self, from: data)
    }
    static func ack(_ draft: OnboardingDraft) -> OnboardingCompletionAcknowledgement {
        OnboardingCompletionAcknowledgement(onboardingCompleted: true, completedAt: "2026-10-21T15:00:00Z",
            objective: draft.objective!, persona: draft.persona!, documentActions: (draft.documentActions ?? []).map {
                .init(documentKey: $0.documentKey, version: $0.version, locale: $0.locale,
                    contentHash: $0.contentHash, purpose: "synthetic_test", action: $0.action,
                    actedAt: "2026-10-21T15:00:00Z") })
    }
    static let session = AuthSession(userID: "intent-flow-a", email: "synthetic@example.invalid",
        isEmailConfirmed: true, isOnboardingCompleted: false)
    static func state(completed: Bool = false, historical: Bool = false, includeDraft: Bool = true,
        capability: OnboardingCompletionCapability? = .osc1) -> OnboardingServerState {
        OnboardingServerState(completion: .init(completed: completed,
            completedAt: completed || historical ? "2026-10-21T15:00:00Z" : nil),
            requirements: E3Fixtures.requirements, acceptedActions: [],
            draft: includeDraft ? E3Fixtures.draft(step: .bodyData) : nil, signupCompletion: capability)
    }
}

@MainActor
private final class IntentFlowRepository: OnboardingRepository {
    enum Call: Hashable { case begin, resolve, completion, read }
    var gates: [Call: IntentFlowGate] = [:]
    var beginResults: [Result<OnboardingCompletionIntent, OnboardingRepositoryError>] = []
    var resolveResults: [Result<OnboardingCompletionIntent?, OnboardingRepositoryError>] = []
    var completionErrors: [OnboardingRepositoryError] = []
    var states: [Result<OnboardingServerState, OnboardingRepositoryError>] = []
    private(set) var begins: [UUID] = []
    private(set) var resolves: [UUID] = []
    private(set) var legacyDrafts: [OnboardingDraft] = []
    private(set) var legacyKeys: [IdempotencyKey] = []
    private(set) var versionedDrafts: [OnboardingDraft] = []
    private(set) var receipts: [OnboardingCompletionIntent] = []
    private(set) var reads = 0
    private(set) var savedDrafts: [OnboardingDraft] = []
    private(set) var keptDrafts: [OnboardingDraft] = []
    func beginCompletionIntent(for userID: String, preparationID: UUID) async throws -> OnboardingCompletionIntent {
        begins.append(preparationID)
        let result = try beginResults.isEmpty ? .success(IntentFlowFixture.receipt(preparationID)) : beginResults.removeFirst()
        if let gate = gates.removeValue(forKey: .begin) { await gate.pause() }
        return try result.get()
    }
    func resolveCompletionIntent(for userID: String, preparationID: UUID) async throws -> OnboardingCompletionIntent? {
        resolves.append(preparationID)
        let result = try resolveResults.isEmpty ? .success(IntentFlowFixture.receipt(preparationID)) : resolveResults.removeFirst()
        if let gate = gates.removeValue(forKey: .resolve) { await gate.pause() }
        return try result.get()
    }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String,
        completionIntent: OnboardingCompletionIntent) async throws -> OnboardingCompletionAcknowledgement {
        versionedDrafts.append(draft); receipts.append(completionIntent)
        let error = completionErrors.isEmpty ? nil : completionErrors.removeFirst()
        if let gate = gates.removeValue(forKey: .completion) { await gate.pause() }
        if let error { throw error }
        return IntentFlowFixture.ack(draft)
    }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String,
        idempotencyKey: IdempotencyKey) async throws -> OnboardingCompletionAcknowledgement {
        legacyDrafts.append(draft); legacyKeys.append(idempotencyKey)
        if !completionErrors.isEmpty { throw completionErrors.removeFirst() }
        return IntentFlowFixture.ack(draft)
    }
    func loadState(for userID: String) async throws -> OnboardingServerState {
        reads += 1
        guard !states.isEmpty else { throw OnboardingRepositoryError.serviceUnavailable }
        let result = states.removeFirst()
        if let gate = gates.removeValue(forKey: .read) { await gate.pause() }
        return try result.get()
    }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws { savedDrafts.append(draft) }
    func keepDraftOnDevice(_ draft: OnboardingDraft, for userID: String) async { keptDrafts.append(draft) }
    func complete(_ draft: OnboardingDraft, for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func clear(for userID: String) async throws {}
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision { E3Fixtures.choice }
}

private actor IntentFlowGate {
    private var entered = false
    private var finished = false
    private var released = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var entryWaiters: [CheckedContinuation<Bool, Never>] = []
    func pause() async {
        entered = true
        entryWaiters.forEach { $0.resume(returning: true) }; entryWaiters = []
        if released { return }
        await withCheckedContinuation { pauseContinuation = $0 }
    }
    func entryOrFinish() async -> Bool {
        if entered { return true }
        if finished { return false }
        return await withCheckedContinuation { entryWaiters.append($0) }
    }
    func finish() {
        finished = true
        entryWaiters.forEach { $0.resume(returning: entered) }; entryWaiters = []
    }
    func release() {
        released = true
        pauseContinuation?.resume(); pauseContinuation = nil
    }
}

@MainActor
final class OnboardingCompletionIntentRenderingTests: XCTestCase {
    func testPreparationCommandsHaveLocalizedNamesAndTapTargetsAtLargestType() async throws {
        for language in SupportedAppLanguage.allCases {
            for dark in [false, true] {
                let repository = IntentFlowRepository()
                repository.beginResults = [.failure(.serviceUnavailable)]
                let model = await OnboardingCompletionIntentFlowTests().makeModel(repository)
                await model.complete()
                let host = SignUpRenderingProbe.host(
                    OnboardingCompletionCommands(model: model, onComplete: {})
                        .environment(\.locale, language.formattingLocale),
                    width: 375, height: 800, size: .accessibility5, dark: dark)
                defer { host.detach() }
                let buttons = host.nodes().filter { $0.isElement && $0.isButton }
                let check = try XCTUnwrap(buttons.first { $0.identifier == "onboarding.go-to-today" })
                let review = try XCTUnwrap(buttons.first { $0.identifier == "onboarding.completion.review-before-retry" })
                XCTAssertEqual(check.label, language == .portugueseBrazil ? "Conferir novamente" : "Check again")
                XCTAssertEqual(review.label, language == .portugueseBrazil ? "Revisar cadastro" : "Review sign-up")
                for command in [check, review] {
                    XCTAssertTrue(command.isEnabled)
                    XCTAssertGreaterThanOrEqual(command.frame.height, 44)
                    XCTAssertGreaterThanOrEqual(command.frame.width, 44)
                    XCTAssertGreaterThanOrEqual(command.frame.minX, -0.5)
                    XCTAssertLessThanOrEqual(command.frame.maxX, 375.5)
                }
            }
        }
    }

    func testUncertainCompletionHasNoDiscardCommand() async throws {
        let repository = IntentFlowRepository()
        repository.completionErrors = [.serviceUnavailable]
        let model = await OnboardingCompletionIntentFlowTests().makeModel(repository)
        await model.complete()
        let host = SignUpRenderingProbe.host(OnboardingCompletionCommands(model: model, onComplete: {}), width: 375)
        defer { host.detach() }
        let buttons = host.nodes().filter { $0.isElement && $0.isButton }
        XCTAssertNotNil(buttons.first { $0.identifier == "onboarding.go-to-today" && $0.isEnabled })
        XCTAssertNil(buttons.first { $0.identifier == "onboarding.completion.review-before-retry" })
    }
}
