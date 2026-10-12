#if DEBUG
import Foundation
@testable import BodyFlow

// Parameterized argument type is internal, not private.
enum CleanupModelSignal: CaseIterable, Sendable {
    case unknown, notRequired, mismatch, missing
    var scope: OnboardingBodyPhotoCleanupScope? {
        switch self {
        case .unknown: .init(generation: CleanupProcessorHarness.g1, state: .unknown)
        case .notRequired: .init(generation: CleanupProcessorHarness.g1, state: .notRequired)
        case .mismatch: .init(generation: CleanupProcessorHarness.g2, state: .pending)
        case .missing: nil
        }
    }
}

struct CleanupModelAuthentication: AuthenticationService {
    let session: AuthSession?
    let signOutFails: Bool
    init(session: AuthSession?, signOutFails: Bool = false) {
        self.session = session
        self.signOutFails = signOutFails
    }
    func restoreSession() async throws -> AuthSession? { session }
    func signIn(email: String, password: String) async throws -> AuthSession { throw AuthenticationError.operationUnavailable }
    func signUp(email: String, password: String) async throws -> AuthSignUpResult { throw AuthenticationError.operationUnavailable }
    func confirmEmailForDevelopment() async throws -> AuthSession { throw AuthenticationError.operationUnavailable }
    func requestPasswordRecovery(email: String) async throws { throw AuthenticationError.operationUnavailable }
    func signOut() async throws { if signOutFails { throw AuthenticationError.serviceUnavailable } }
}

struct CleanupModelPersona: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws { throw CoachPersonaRepositoryError.serviceUnavailable }
}

struct CleanupModelRepositorySnapshot: Sendable {
    let stateReads: Int
    let technicalReads: Int
    let completionPosts: Int
    let scopedUsers: [String]
}

// Full protocol surface, explicit errors for mutations: these tests receive
// normal metadata and never synthesize an acknowledgement or fallback POST.
actor CleanupModelRepository: OnboardingRepository {
    let state: OnboardingServerState
    private var stateReads = 0
    private var technicalReads = 0
    private var completionPosts = 0
    private var scopedUsers: [String] = []

    init(completed: Bool, scope: OnboardingBodyPhotoCleanupScope? = nil) {
        state = OnboardingServerState(locale: "pt-BR",
            completion: .init(completed: completed, completedAt: completed ? CleanupProcessorHarness.g1 : nil),
            requirements: .unavailable, acceptedActions: [],
            draft: completed ? nil : BodyFlowTestFixtures.onboardingDraft(currentStep: .objective),
            bodyPhotoCleanup: scope)
    }
    func snapshot() -> CleanupModelRepositorySnapshot {
        .init(stateReads: stateReads, technicalReads: technicalReads,
            completionPosts: completionPosts, scopedUsers: scopedUsers)
    }
    func scoped(for userID: String) async throws -> any OnboardingRepository { scopedUsers.append(userID); return self }
    func loadState(for userID: String) async throws -> OnboardingServerState { stateReads += 1; return state }
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
        idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        throw OnboardingRepositoryError.serviceUnavailable
    }
    func clear(for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func keepDraftOnDevice(_ draft: OnboardingDraft, for userID: String) async {}
}

func cleanupModelSession(confirmed: Bool = true) -> AuthSession {
    .init(userID: CleanupProcessorHarness.a, email: "synthetic@example.invalid",
        isEmailConfirmed: confirmed, isOnboardingCompleted: false)
}

// The only added hold is before the real protected observe RMW. All authority,
// store, session gate and registry behavior delegates to the existing scope.
func cleanupModelScope(_ base: SignupBodyPhotoCleanupScope,
    observationGate: CleanupProcessorBarrier) -> SignupBodyPhotoCleanupScope {
    .init(userID: base.userID, validateSession: base.validateSession, loadQueue: base.loadQueue,
        observePending: { generation, authorization in
            await observationGate.enter()
            try await base.observePending(generation, authorization)
        }, prepareRepair: base.prepareRepair, acknowledge: base.acknowledge,
        resolveNotRequired: base.resolveNotRequired, readScope: base.readScope,
        repair: base.repair, performWork: base.performWork)
}
#endif
