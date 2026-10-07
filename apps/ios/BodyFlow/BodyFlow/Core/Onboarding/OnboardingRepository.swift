import Foundation

enum OnboardingRepositoryError: Error, Equatable, Sendable {
    case invalidDraft
    case objectiveNotEligible
    case developmentConsentForbidden
    case documentsUnavailable
    case requirementsChanged
    case alreadyCompleted
    case storageUnavailable
    case serviceUnavailable
}

protocol OnboardingRepository: Sendable {
    func loadDraft(for userID: String) async throws -> OnboardingDraft?
    func loadState(for userID: String) async throws -> OnboardingServerState
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws
    func complete(_ draft: OnboardingDraft, for userID: String) async throws
    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement
    func checkEligibility(
        _ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingEligibilityDecision
    func clear(for userID: String) async throws
}

extension OnboardingRepository {
    func checkEligibility(
        _ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingEligibilityDecision {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        let draft = try await loadDraft(for: userID)
        return OnboardingServerState(
            locale: draft?.localeIdentifier ?? OnboardingDraft.currentDeviceWelcome.localeIdentifier,
            completion: OnboardingCompletionState(completed: false, completedAt: nil),
            requirements: .unavailable,
            acceptedActions: [],
            draft: draft
        )
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        try await complete(draft, for: userID)
        guard let objective = draft.objective,
              let persona = draft.persona else {
            throw OnboardingRepositoryError.invalidDraft
        }
        let actedAt = ISO8601DateFormatter().string(from: Date())
        return OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: actedAt,
            objective: objective,
            persona: persona,
            documentActions: (draft.documentActions ?? []).map { action in
                OnboardingAcceptedAction(
                    documentKey: action.documentKey,
                    version: action.version,
                    locale: action.locale,
                    contentHash: action.contentHash,
                    purpose: "development_fixture",
                    action: action.action,
                    actedAt: actedAt
                )
            }
        )
    }
}

actor UnavailableOnboardingRepository: OnboardingRepository {
    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func clear(for userID: String) async throws {
        throw OnboardingRepositoryError.serviceUnavailable
    }
}
