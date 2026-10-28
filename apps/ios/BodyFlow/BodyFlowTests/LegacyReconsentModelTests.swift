import Foundation
import Testing
@testable import BodyFlow

@MainActor @Suite("Existing accounts accept documents without another signup")
struct LegacyReconsentModelTests {
    @Test(arguments: [false, true])
    func uncertainResultRetainsTheExactCommandAndBlocksEditing(cancelled: Bool) async throws {
        let state = try LegacyDocumentsFixtures.state()
        let repo = LegacyDocumentsRepository(states: [.success(state)], uncertain: cancelled ? .cancelled : .network)
        let owner = LegacyDocumentsOwner()
        let model = try make(repo, state, owner)
        for document in state.requirements.documents { model.update(document.explicitAction, selected: true) }
        await model.submit()
        let original = try #require(model.pending)
        #expect(model.hasError && !model.isBusy && !model.allowsEditing && model.canSubmit)
        for document in state.requirements.documents { model.update(document.explicitAction, selected: false) }
        #expect(model.pending == original && model.selectedActions.count == state.requirements.documents.count)
        await model.submit()
        #expect(model.acknowledgement != nil && !model.canSubmit && owner.reconciliations == 1)
        await model.submit()
        let requests = await repo.commands
        #expect(requests.count == 2 && requests.allSatisfy { $0 == original })
        #expect(await repo.signupWrites == 0)
    }

    @Test(arguments: [false, true])
    func aLateReplyCannotReconcileAnotherAccountOrReturnedA(failure: Bool) async throws {
        let state = try LegacyDocumentsFixtures.state()
        let gate = LegacyDocumentsGate()
        let repo = LegacyDocumentsRepository(states: [.success(state)], uncertain: failure ? .network : nil, gate: gate)
        let owner = LegacyDocumentsOwner()
        let model = try make(repo, state, owner)
        for document in state.requirements.documents { model.update(document.explicitAction, selected: true) }
        let work = Task { await model.submit() }
        await gate.waitForEntry()
        model.invalidate()
        owner.current = .init(userID: "auth-B", restoreGeneration: 2)
        owner.current = .init(userID: "auth-A", restoreGeneration: 3)
        await gate.release(); await work.value
        #expect(!model.isActive && model.acknowledgement == nil && owner.reconciliations == 0)
        await model.submit()
        #expect(await repo.commands.count == 1)
    }

    @Test func onlyActualMatchingRecordedActionsAreSelectedAndNoNewActionIsInferred() throws {
        let plain = try LegacyDocumentsFixtures.state()
        let first = plain.requirements.documents[0].explicitAction
        let accepted = OnboardingAcceptedAction(documentKey: first.documentKey, version: first.version,
            locale: first.locale, contentHash: first.contentHash, purpose: "synthetic_notice", action: first.action,
            actedAt: "2026-10-27T12:00:00.000001Z")
        let state = try LegacyDocumentsFixtures.state(accepted: [accepted])
        let owner = LegacyDocumentsOwner()
        let model = try make(LegacyDocumentsRepository(states: []), state, owner)
        #expect(model.selectedActions == [first] && !model.canSubmit)
        model.update(first, selected: false)
        #expect(model.selectedActions == [first])
        let obsolete = OnboardingAcceptedAction(documentKey: first.documentKey, version: "old", locale: first.locale,
            contentHash: first.contentHash, purpose: accepted.purpose, action: first.action, actedAt: accepted.actedAt)
        let other = try LegacyDocumentsFixtures.state(accepted: [obsolete])
        let fresh = try make(LegacyDocumentsRepository(states: []), other, owner)
        #expect(fresh.selectedActions.isEmpty && !fresh.canSubmit)
    }

    @Test func rootRetainsOneDocumentsModelAndNeverConstructsSignupOrPhotoModels() throws {
        let state = try LegacyDocumentsFixtures.state()
        let presentation = try OnboardingLegacyDocumentsPresentation(state: state)
        let repo = LegacyDocumentsRepository(states: [])
        let owner = LegacyDocumentsOwner()
        var root = OnboardingRootCoordinator()
        synchronize(&root, owner, presentation, repo)
        let first = try #require(root.legacyDocumentsModel)
        #expect(root.canRender(ownerToken: owner.current) && !root.loadFailed)
        #expect(root.flowModel == nil && root.photosModel == nil)
        #expect(root.claimInitialPhotoLoad(ownerToken: owner.current) == nil)
        first.update(state.requirements.documents[0].explicitAction, selected: true)
        synchronize(&root, owner, presentation, repo)
        #expect(root.legacyDocumentsModel === first && first.selectedActions.count == 1)
        owner.current = .init(userID: "auth-B", restoreGeneration: 2)
        synchronize(&root, owner, presentation, repo)
        #expect(!first.isActive && root.legacyDocumentsModel !== first)
        owner.current = .init(userID: "auth-A", restoreGeneration: 3)
        synchronize(&root, owner, presentation, repo)
        #expect(!root.canRender(ownerToken: first.ownerToken) && !first.isActive)
        root.synchronize(activeUserID: nil, restoredDraft: nil, onboarding: repo, persona: E3Persona(),
            developmentConsentAvailability: .unavailable, telemetry: DisabledTelemetryClient(),
            onStepChanged: { _ in }, onCompleted: {})
        #expect(root.legacyDocumentsModel == nil && root.ownerToken == nil)
    }

    @Test func acceptedPostThenFailedGetCanOnlyRetryTheOfficialGet() async throws {
        let initial = try LegacyDocumentsFixtures.state()
        let completed = OnboardingServerState(locale: initial.locale, completion: .init(completed: true, completedAt: nil),
            requirements: initial.requirements, acceptedActions: [], clinicalSignup: .current,
            clinicalPolicy: initial.clinicalPolicy, legacyReconsent: .documentsOnly)
        let repo = LegacyDocumentsRepository(states: [.success(initial), .failure(.serviceUnavailable), .success(completed)])
        let session = AuthSession(userID: "auth-A", email: "legacy@example.invalid", isEmailConfirmed: true, isOnboardingCompleted: true)
        let app = AppFlowModel(authentication: CleanupModelAuthentication(session: session), onboarding: repo,
            persona: E3Persona(), telemetry: DisabledTelemetryClient())
        await app.start()
        let originalOwner = try #require(app.onboardingOwnerToken)
        let presentation = try #require(app.restoredLegacyDocuments)
        let continuation = LegacyDocumentsContinuation()
        let documents = LegacyReconsentModel(ownerToken: originalOwner, presentation: presentation,
            repository: app.onboardingRepositoryForCurrentOwner, keys: LegacyDocumentsKeys(),
            isCurrentOwner: { app.onboardingOwnerToken == $0 }, onReconcile: {
                continuation.task = Task { await app.reconcileLegacyDocuments(ownerToken: originalOwner) }
            })
        for document in initial.requirements.documents { documents.update(document.explicitAction, selected: true) }
        await documents.submit()
        await continuation.task?.value
        #expect(documents.acknowledgement != nil && app.onboardingLoadFailure != nil)
        #expect(app.currentSession?.isOnboardingCompleted == false && app.restoredLegacyDocuments == nil)
        await documents.submit()
        await app.reconcileLegacyDocuments(ownerToken: originalOwner)
        let failedReads = await repo.reads
        let failedCommands = await repo.commands.count
        #expect(failedReads == 2 && failedCommands == 1)
        await app.retryOnboardingRestore()
        #expect(app.state == .authenticated(userID: "auth-A"))
        let finalReads = await repo.reads
        let finalCommands = await repo.commands.count
        let signupWrites = await repo.signupWrites
        #expect(finalReads == 3 && finalCommands == 1 && signupWrites == 0)
    }

    private func make(_ repository: LegacyDocumentsRepository, _ state: OnboardingServerState,
                      _ owner: LegacyDocumentsOwner) throws -> LegacyReconsentModel {
        LegacyReconsentModel(ownerToken: owner.current, presentation: try .init(state: state), repository: repository,
            keys: LegacyDocumentsKeys(), isCurrentOwner: { owner.current == $0 }, onReconcile: { owner.reconciliations += 1 })
    }
    private func synchronize(_ root: inout OnboardingRootCoordinator, _ owner: LegacyDocumentsOwner,
                             _ presentation: OnboardingLegacyDocumentsPresentation, _ repo: LegacyDocumentsRepository) {
        root.synchronize(activeUserID: owner.current.userID, restoredDraft: nil, legacyDocuments: presentation,
            restoreGeneration: owner.current.restoreGeneration, onboarding: repo, persona: E3Persona(),
            developmentConsentAvailability: .unavailable, idempotencyKeyProvider: LegacyDocumentsKeys(),
            telemetry: DisabledTelemetryClient(), onStepChanged: { _ in }, onCompleted: {},
            isCurrentPhotoOwner: { owner.current == $0 }, onLegacyReconcile: { owner.reconciliations += 1 })
    }
}

enum LegacyDocumentsFixtures {
    static func state(locale: String = "pt-BR", accepted: [OnboardingAcceptedAction] = []) throws -> OnboardingServerState {
        let actions: [OnboardingLegalAction] = [.acceptance, .acknowledgement, .consent]
        let keys = ["terms_of_service", "medical_disclaimer", "privacy_policy"]
        let documents = zip(keys, actions).map { key, action in
            OnboardingLegalDocument(documentKey: key, version: "qa-v1", locale: locale,
                body: locale == "pt-BR" ? "Texto oficial sintético: \(key)" : "Synthetic official text: \(key)",
                contentURL: nil, contentHash: String(repeating: "a", count: 64), purpose: "synthetic_notice",
                action: action, required: true, effectiveAt: "2026-10-27T12:00:00.000001Z")
        }
        return .init(locale: locale, completion: .init(completed: false, completedAt: nil),
            requirements: .init(available: true, blockingReason: nil, documents: documents), acceptedActions: accepted,
            signupCompletion: .osc1, clinicalSignup: .current, clinicalPolicy: try OnboardingCurrentPresentationTests.policy(),
            legacyReconsent: .documentsOnly)
    }
}
private struct LegacyDocumentsKeys: IdempotencyKeyProviding {
    func nextKey() throws -> IdempotencyKey { try .init(validating: "b3b01000-0000-4000-8000-000000007301") }
}
@MainActor private final class LegacyDocumentsOwner {
    var current = OnboardingOwnerToken(userID: "auth-A", restoreGeneration: 1)
    var reconciliations = 0
}
@MainActor private final class LegacyDocumentsContinuation { var task: Task<Void, Never>? }
private actor LegacyDocumentsGate {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var work: CheckedContinuation<Void, Never>?
    func waitForEntry() async { if entered { return }; await withCheckedContinuation { entry = $0 } }
    func hold() async {
        entered = true
        await withCheckedContinuation { work = $0; entry?.resume(); entry = nil }
    }
    func release() { work?.resume(); work = nil }
}
private actor LegacyDocumentsRepository: OnboardingRepository {
    enum Uncertain: Sendable { case network, cancelled }
    var states: [Result<OnboardingServerState, OnboardingRepositoryError>]
    let uncertain: Uncertain?
    let gate: LegacyDocumentsGate?
    private(set) var commands: [LegacyReconsentModel.Pending] = []
    private(set) var reads = 0
    private(set) var signupWrites = 0
    init(states: [Result<OnboardingServerState, OnboardingRepositoryError>], uncertain: Uncertain? = nil,
         gate: LegacyDocumentsGate? = nil) { self.states = states; self.uncertain = uncertain; self.gate = gate }
    func loadState(for userID: String) async throws -> OnboardingServerState {
        reads += 1
        guard !states.isEmpty else { throw OnboardingRepositoryError.serviceUnavailable }
        return try states.removeFirst().get()
    }
    func acceptLegacyDocuments(_ input: OnboardingLegacyDocumentInput, for userID: String,
                               key: IdempotencyKey) async throws -> OnboardingLegacyDocumentAcknowledgement {
        commands.append(.init(input: input, key: key))
        if let gate { await gate.hold() }
        if commands.count == 1, let uncertain {
            if uncertain == .cancelled { throw CancellationError() }
            throw OnboardingRepositoryError.serviceUnavailable
        }
        let actions = input.documentActions.map { action in
            ["document_key": action.documentKey, "version": action.version, "locale": action.locale,
             "content_hash": action.contentHash, "action": action.action.rawValue,
             "purpose": "synthetic_notice", "acted_at": "2026-10-27T12:00:00.000001Z"]
        }
        let object: [String: Any] = ["version": 1, "operation_key": key.value,
            "receipt": ["id": "b3b01000-0000-4000-8000-000000007302", "locale": input.locale,
                "accepted_at": "2026-10-28T01:00:00.000001Z", "document_actions": actions]]
        return try JSONDecoder().decode(OnboardingLegacyDocumentAcknowledgement.self,
            from: JSONSerialization.data(withJSONObject: object))
    }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { throw OnboardingRepositoryError.serviceUnavailable }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws { signupWrites += 1; throw OnboardingRepositoryError.serviceUnavailable }
    func complete(_ draft: OnboardingDraft, for userID: String) async throws { signupWrites += 1; throw OnboardingRepositoryError.serviceUnavailable }
    func clear(for userID: String) async throws { signupWrites += 1; throw OnboardingRepositoryError.serviceUnavailable }
}
