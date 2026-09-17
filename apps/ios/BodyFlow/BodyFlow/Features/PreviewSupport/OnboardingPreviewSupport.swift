#if DEBUG
import CryptoKit
import Foundation

/// Local QA simulation of the existing server-owned protocol, never a legal publication.
actor OnboardingPreviewRepository: OnboardingRepository {
    private let stateStore: DemoStateStore
    private let drafts: DemoOnboardingRepository
    let receiptNamespace: String
    private let persistsReceipts: Bool
    private let resetsReceipts: Bool
    private var resetTasks: [String: Task<Void, Error>] = [:]

    init(
        stateStore: DemoStateStore,
        buildFlavor: AppBuildFlavor,
        preloadsSyntheticOnboardingValues: Bool,
        receiptNamespace: String = DemoStorageService.development,
        persistsReceipts: Bool = false,
        resetsReceipts: Bool = false
    ) {
        self.stateStore = stateStore
        self.receiptNamespace = receiptNamespace
        self.persistsReceipts = persistsReceipts
        self.resetsReceipts = resetsReceipts
        drafts = DemoOnboardingRepository(
            stateStore: stateStore,
            buildFlavor: buildFlavor,
            preloadsSyntheticOnboardingValues: preloadsSyntheticOnboardingValues
        )
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        try await requireActiveLocalUser(userID)
        if let receipt = try await receipt(for: userID) { return receipt.draft }
        return try await drafts.loadDraft(for: userID)
    }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        try await requireActiveLocalUser(userID)
        let stored = try await receipt(for: userID)
        let draft: OnboardingDraft?
        if let stored { draft = stored.draft }
        else { draft = try await drafts.loadDraft(for: userID) }
        let receipt = stored?.acknowledgement
        return OnboardingServerState(
            locale: draft?.localeIdentifier ?? "pt-BR",
            completion: OnboardingCompletionState(
                completed: receipt != nil,
                completedAt: receipt?.completedAt
            ),
            requirements: Self.requirements(locale: draft?.localeIdentifier ?? "pt-BR"),
            acceptedActions: receipt?.documentActions ?? [],
            draft: draft
        )
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        try await requireActiveLocalUser(userID)
        try await drafts.saveDraft(draft, for: userID)
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        // Match MobileOnboardingRepository: legacy completion is not an official finish.
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        try await requireActiveLocalUser(userID)
        if let receipt = try await receipt(for: userID) {
            guard receipt.key == idempotencyKey.value, receipt.draft == draft else {
                throw OnboardingRepositoryError.alreadyCompleted
            }
            return receipt.acknowledgement
        }
        let requirements = Self.requirements(locale: draft.localeIdentifier)
        guard requirements.available,
              draft.currentStep == .completion,
              OnboardingStepValidator.completionIssues(
                draft: draft,
                developmentConsentAvailability: .unavailable,
                requirements: requirements,
                now: Date()
              ).isEmpty,
              let objective = draft.objective,
              let persona = draft.persona else {
            throw OnboardingRepositoryError.invalidDraft
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let selected = Set(draft.documentActions ?? [])
        let acknowledgement = OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: timestamp,
            objective: objective,
            persona: persona,
            documentActions: requirements.documents
                .filter { selected.contains($0.explicitAction) }
                .map { document in
                    OnboardingAcceptedAction(
                        documentKey: document.documentKey,
                        version: document.version,
                        locale: document.locale,
                        contentHash: document.contentHash,
                        purpose: document.purpose,
                        action: document.action,
                        actedAt: timestamp
                    )
                }
        )
        guard acknowledgement.matches(draft) else {
            throw OnboardingRepositoryError.invalidDraft
        }
        try Task.checkCancellation()
        // Commit arbitration is atomic in the shared local cache. Do not await a
        // legacy draft write between checking and recording the official receipt.
        let committed = try await OnboardingPreviewReceiptCache.shared.commit(
            OnboardingPreviewReceipt(
                key: idempotencyKey.value, draft: draft,
                acknowledgement: acknowledgement
            ),
            namespace: receiptNamespace, persistent: persistsReceipts, userID: userID
        )
        return committed.acknowledgement
    }

    func clear(for userID: String) async throws {
        try Task.checkCancellation()
        if let session = try await stateStore.loadSession(), session.userID != userID {
            throw OnboardingRepositoryError.invalidDraft
        }
        try await prepareReceipts(for: userID)
        try await drafts.clear(for: userID)
        // Clearing a local draft cannot undo an acknowledged server-shaped receipt.
    }

    private func receipt(for userID: String) async throws -> OnboardingPreviewReceipt? {
        try await OnboardingPreviewReceiptCache.shared.load(
            namespace: receiptNamespace, persistent: persistsReceipts, userID: userID
        )
    }

    private func requireActiveLocalUser(_ userID: String) async throws {
        try Task.checkCancellation()
        guard try await stateStore.loadSession()?.userID == userID else {
            throw OnboardingRepositoryError.invalidDraft
        }
        try await prepareReceipts(for: userID)
    }

    private func prepareReceipts(for userID: String) async throws {
        guard resetsReceipts else { return }
        if let task = resetTasks[userID] {
            try await task.value
        } else {
            let namespace = receiptNamespace
            let persistent = persistsReceipts
            let task = Task {
                try await OnboardingPreviewReceiptCache.shared.reset(
                    namespace: namespace, persistent: persistent, userID: userID
                )
            }
            // Record before suspension: concurrent calls share one initial reset
            // rather than a late reset erasing an explicitly acknowledged finish.
            resetTasks[userID] = task
            try await task.value
        }
        try Task.checkCancellation()
    }

    private static func requirements(locale: String) -> OnboardingRequirements {
        guard OnboardingLocalePolicy.isSupported(locale) else { return .unavailable }
        let paragraph = locale == "pt-BR"
            ? "Documento sintético de QA para validar o fluxo de consentimento. Não é um documento jurídico nem uma publicação real."
            : "Synthetic QA document for validating the consent flow. This is not a legal document or a real publication."
        let body = Array(repeating: paragraph, count: 12).joined(separator: "\n\n")
        let hash = SHA256.hash(data: Data(body.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let definitions: [(String, OnboardingLegalAction)] = [
            ("qa_onboarding_required", .acceptance),
            ("qa_onboarding_notice", .acknowledgement),
            ("qa_onboarding_consent", .consent),
        ]
        return OnboardingRequirements(
            available: true,
            blockingReason: nil,
            documents: definitions.map { key, action in
                OnboardingLegalDocument(
                    documentKey: key,
                    version: "qa-local-v1",
                    locale: locale,
                    body: body,
                    contentURL: nil,
                    contentHash: hash,
                    purpose: "qa_local_consent_validation",
                    action: action,
                    required: true,
                    effectiveAt: "2026-09-17T00:00:00.000Z"
                )
            }
        )
    }
}

/// A private QA cache envelope, not a new consent DTO or server contract.
private struct OnboardingPreviewReceipt: Codable, Sendable {
    let key: String
    let draft: OnboardingDraft
    let acknowledgement: OnboardingCompletionAcknowledgement
}

private actor OnboardingPreviewReceiptCache {
    static let shared = OnboardingPreviewReceiptCache()
    private var records: [String: [String: OnboardingPreviewReceipt]] = [:]

    func reset(namespace: String, persistent: Bool, userID: String) throws {
        if persistent {
            guard let defaults = UserDefaults(suiteName: suiteName(namespace)) else {
                throw OnboardingRepositoryError.storageUnavailable
            }
            defaults.removeObject(forKey: userID)
        }
        records[namespace]?[userID] = nil
    }

    func load(
        namespace: String, persistent: Bool, userID: String
    ) throws -> OnboardingPreviewReceipt? {
        if let receipt = records[namespace]?[userID] { return receipt }
        guard persistent else { return nil }
        guard let defaults = UserDefaults(suiteName: suiteName(namespace)) else {
            throw OnboardingRepositoryError.storageUnavailable
        }
        guard let data = defaults.data(forKey: userID) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let receipt = try decoder.decode(OnboardingPreviewReceipt.self, from: data)
            guard receipt.acknowledgement.matches(receipt.draft) else {
                throw OnboardingRepositoryError.storageUnavailable
            }
            records[namespace, default: [:]][userID] = receipt
            return receipt
        } catch {
            throw OnboardingRepositoryError.storageUnavailable
        }
    }

    func commit(
        _ candidate: OnboardingPreviewReceipt,
        namespace: String, persistent: Bool, userID: String
    ) throws -> OnboardingPreviewReceipt {
        // No suspension in this method: concurrent provider instances cannot
        // acknowledge conflicting snapshots or overwrite the winning receipt.
        if let existing = try load(
            namespace: namespace, persistent: persistent, userID: userID
        ) {
            guard existing.key == candidate.key, existing.draft == candidate.draft else {
                throw OnboardingRepositoryError.alreadyCompleted
            }
            return existing
        }
        if persistent {
            guard let defaults = UserDefaults(suiteName: suiteName(namespace)) else {
                throw OnboardingRepositoryError.storageUnavailable
            }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(candidate)
                defaults.set(data, forKey: userID)
            } catch {
                throw OnboardingRepositoryError.storageUnavailable
            }
        }
        records[namespace, default: [:]][userID] = candidate
        return candidate
    }

    private func suiteName(_ namespace: String) -> String {
        "bodyflow.qa.onboarding-receipts.v1.\(namespace)"
    }
}
#endif
