#if DEBUG
import Foundation
@testable import BodyFlow

// Captures each normal GET answer before the adverse suspension. Full protocol
// surface rejects mutations and technical reads; no default ACK or fake POST.
actor CleanupModelReplyRepository: OnboardingRepository {
    let firstReadBarrier: CleanupProcessorBarrier
    private let holdFirstRead: Bool
    private let replies: [Result<OnboardingServerState, OnboardingRepositoryError>]
    private var stateReads = 0
    private var technicalReads = 0
    private var completionPosts = 0
    private var scopedUsers: [String] = []
    init(replies: [Result<OnboardingServerState, OnboardingRepositoryError>], holdFirstRead: Bool = false) {
        self.replies = replies
        self.holdFirstRead = holdFirstRead
        firstReadBarrier = CleanupProcessorBarrier(holds: holdFirstRead)
    }
    func snapshot() -> CleanupModelRepositorySnapshot {
        .init(stateReads: stateReads, technicalReads: technicalReads, completionPosts: completionPosts, scopedUsers: scopedUsers)
    }
    func scoped(for userID: String) async throws -> any OnboardingRepository { scopedUsers.append(userID); return self }
    func loadState(for userID: String) async throws -> OnboardingServerState {
        stateReads += 1
        let call = stateReads
        let captured: Result<OnboardingServerState, OnboardingRepositoryError> =
            replies.indices.contains(call - 1) ? replies[call - 1] : .failure(.serviceUnavailable)
        if holdFirstRead && call == 1 { await firstReadBarrier.enter() }
        return try captured.get()
    }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { throw OnboardingRepositoryError.serviceUnavailable }
    func loadBodyPhotoCleanupScope(generation: String?) async throws -> OnboardingBodyPhotoCleanupScope? {
        technicalReads += 1; throw OnboardingRepositoryError.serviceUnavailable
    }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        completionPosts += 1; throw OnboardingRepositoryError.serviceUnavailable
    }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String, idempotencyKey: IdempotencyKey)
        async throws -> OnboardingCompletionAcknowledgement {
        completionPosts += 1; throw OnboardingRepositoryError.serviceUnavailable
    }
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision { throw OnboardingRepositoryError.serviceUnavailable }
    func clear(for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func keepDraftOnDevice(_ draft: OnboardingDraft, for userID: String) async {}
}

func cleanupModelEdgeState(_ generation: String) -> OnboardingServerState {
    .init(locale: "pt-BR", completion: .init(completed: true, completedAt: generation),
        requirements: .unavailable, acceptedActions: [],
        bodyPhotoCleanup: .init(generation: generation, state: .pending))
}

// The initial bind fails; the first retry's bind then ignores cancellation.
// A newer retry binds immediately. This isolates Model restore identity from
// the Root binding identity while the real session lease remains valid.
actor CleanupModelRetryBindingFactory {
    let heldRetryBindingBarrier = CleanupProcessorBarrier(holds: true)
    private let scope: SignupBodyPhotoCleanupScope
    private var users: [String] = []
    init(scope: SignupBodyPhotoCleanupScope) { self.scope = scope }
    func bind(_ userID: String) async throws -> SignupBodyPhotoCleanupScope {
        users.append(userID)
        let call = users.count
        let captured = scope
        if call == 1 { throw SignupBodyPhotoFailure.unavailable }
        if call == 2 { await heldRetryBindingBarrier.enter() }
        return captured
    }
    func snapshot() -> [String] { users }
    nonisolated var capability: SignupBodyPhotoCleanupCapability {
        SignupBodyPhotoCleanupCapability { userID in try await self.bind(userID) }
    }
}

// First confirmed activation binds successfully. The next one is held while
// the UI still shows the first onboarding snapshot. No session switch is used:
// a still-valid lease deliberately isolates the missing Flow identity fence.
actor CleanupModelNextActivationFactory {
    let newActivationBindingBarrier = CleanupProcessorBarrier(holds: true)
    private let scope: SignupBodyPhotoCleanupScope
    private var users: [String] = []
    init(scope: SignupBodyPhotoCleanupScope) { self.scope = scope }
    func bind(_ userID: String) async throws -> SignupBodyPhotoCleanupScope {
        users.append(userID)
        let call = users.count
        let captured = scope
        if call == 2 { await newActivationBindingBarrier.enter() }
        return captured
    }
    func snapshot() -> [String] { users }
    nonisolated var capability: SignupBodyPhotoCleanupCapability {
        SignupBodyPhotoCleanupCapability { userID in try await self.bind(userID) }
    }
}
#endif
