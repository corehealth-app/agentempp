#if DEBUG
import CryptoKit
import Foundation

/// Local QA simulation of the existing server-owned protocol, never a legal publication.
actor OnboardingPreviewRepository: OnboardingRepository {
    private let stateStore: DemoStateStore
    private let drafts: DemoOnboardingRepository
    private let buildFlavor: AppBuildFlavor
    private let eligibilityScenario: OnboardingEligibilityPreviewScenario
    private let preloadsCompletedFixture: Bool
    let receiptNamespace: String
    private let persistsReceipts: Bool
    private let resetsReceipts: Bool
    private var didSimulateUncertainCompletion = false
    private var resetTasks: [String: Task<Void, Error>] = [:]

    init(
        stateStore: DemoStateStore,
        buildFlavor: AppBuildFlavor,
        preloadsSyntheticOnboardingValues: Bool,
        preloadsCompletedFixture: Bool = false,
        receiptNamespace: String = DemoStorageService.development,
        persistsReceipts: Bool = false,
        resetsReceipts: Bool = false,
        eligibilityScenario: OnboardingEligibilityPreviewScenario = .choice
    ) {
        self.stateStore = stateStore
        self.buildFlavor = buildFlavor
        self.eligibilityScenario = eligibilityScenario
        self.preloadsCompletedFixture = preloadsCompletedFixture
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
        return localizedFreshDraft(try await drafts.loadDraft(for: userID))
    }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        try await requireActiveLocalUser(userID)
        // The two load-failure fixtures answer like the real repository does.
        if eligibilityScenario == .adminAccountConflict { throw OnboardingRepositoryError.adminAccountConflict }
        if eligibilityScenario == .loadFailure { throw OnboardingRepositoryError.serviceUnavailable }
        let stored = try await receipt(for: userID)
        let draft: OnboardingDraft?
        if let stored { draft = stored.draft }
        else { draft = localizedFreshDraft(try await drafts.loadDraft(for: userID)) }
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

    private func localizedFreshDraft(_ source: OnboardingDraft?) -> OnboardingDraft? {
        guard var draft = source, draft.currentStep == .welcome, draft.displayName == nil else { return source }
        draft.localeIdentifier = DemoOnboardingSuggestions.currentDevice.localeIdentifier
        return draft
    }

    func checkEligibility(
        _ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingEligibilityDecision {
        guard buildFlavor == .debug else { throw OnboardingRepositoryError.serviceUnavailable }
        try await requireActiveLocalUser(userID)
        if eligibilityScenario == .failure { throw OnboardingRepositoryError.serviceUnavailable }
        let assigned = eligibilityScenario == .assigned
        let blocked = assigned || eligibilityScenario == .gainBlocked
        let portuguese = input.locale == "pt-BR"
        return OnboardingEligibilityDecision(
            decision: assigned ? .assigned : .choice, basis: .bodyFat,
            objective: assigned ? .bodyRecomposition : nil,
            notice: assigned ? [portuguese ? "Nesta simulação local, seu objetivo inicial é recomposição corporal." : "In this local simulation, your starting objective is body recomposition."] : nil,
            options: [
                .init(objective: .bodyRecomposition, status: .available, reasons: [], message: []),
                .init(objective: .muscleGain, status: blocked ? .blocked : .available,
                    reasons: blocked ? [.composition] : [],
                    message: blocked ? [portuguese ? "O ganho de massa está indisponível nesta simulação local." : "Muscle gain is unavailable in this local simulation."] : []),
                .init(objective: .maintenance, status: assigned ? .notOffered : .available, reasons: [], message: [])
            ])
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
                },
            protocolWelcome: eligibilityScenario == .welcome
                ? ProtocolWelcome(protocol: objective, paragraphs: Self.welcomeParagraphs(locale: draft.localeIdentifier))
                : nil
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
        if eligibilityScenario == .completionUncertain && !didSimulateUncertainCompletion {
            didSimulateUncertainCompletion = true
            throw OnboardingRepositoryError.serviceUnavailable
        }
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
        try await preloadCompletedReceiptIfNeeded(for: userID)
    }

    private func preloadCompletedReceiptIfNeeded(for userID: String) async throws {
        guard preloadsCompletedFixture,
              try await receipt(for: userID) == nil else { return }

        let locale = "pt-BR"
        let requirements = Self.requirements(locale: locale)
        let actions = requirements.documents.map(\.explicitAction)
        let draft = OnboardingDraft(
            displayName: "Fixture User",
            localeIdentifier: locale,
            countryCode: "BR",
            timeZoneIdentifier: "America/Sao_Paulo",
            biologicalSex: .feminine,
            birthDate: Date(timeIntervalSince1970: 946_684_800),
            heightCM: 170,
            weightKG: 65,
            bodyFatPercent: 25,
            objective: .bodyRecomposition,
            activityLevel: .moderate,
            trainingFrequency: 3,
            waterIntake: .moderate,
            hungerLevel: .moderate,
            wakeTime: LocalTime(hour: 7, minute: 0),
            bedtime: LocalTime(hour: 23, minute: 0),
            foodOrganization: .yes,
            persona: .focus,
            consent: nil,
            documentActions: actions,
            currentStep: .completion
        )
        let timestamp = "2026-09-17T00:00:00.000Z"
        let acknowledgement = OnboardingCompletionAcknowledgement(
            onboardingCompleted: true,
            completedAt: timestamp,
            objective: .bodyRecomposition,
            persona: .focus,
            documentActions: requirements.documents.map { document in
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
            throw OnboardingRepositoryError.storageUnavailable
        }
        _ = try await OnboardingPreviewReceiptCache.shared.commit(
            OnboardingPreviewReceipt(
                key: "qa-completed-fixture-v1",
                draft: draft,
                acknowledgement: acknowledgement
            ),
            namespace: receiptNamespace,
            persistent: persistsReceipts,
            userID: userID
        )
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

    static func welcomeParagraphs(locale: String) -> [String] {
        let pt = locale == "pt-BR"
        let first = pt ? "Esta é uma mensagem sintética do Flow para testar a entrada no objetivo." : "This is a synthetic Flow message for testing entry into an objective."
        let body = pt
            ? "Este parágrafo sintético verifica a leitura completa da mensagem recebida. O texto permanece integral, com os espaços e a ordem originais, para que você consiga ler cada orientação até o fim. A demonstração local não altera informações clínicas nem publica dados. Leia bem."
            : "This synthetic paragraph checks complete reading of the received message. The text remains intact, with its original spacing and order, so you can read every instruction through to the end. This local demonstration changes no clinical information and publishes no data..."
        let last = pt ? "Fim da mensagem sintética. A próxima tela será Hoje." : "End of the synthetic message. The next screen will be Today."
        return [first] + Array(repeating: body, count: 10) + [last]
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
