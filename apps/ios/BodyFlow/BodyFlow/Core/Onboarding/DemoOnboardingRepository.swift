import Foundation

struct DemoOnboardingSuggestions: Sendable {
    let localeIdentifier: String
    let countryCode: String
    let timeZoneIdentifier: String

    static var currentDevice: DemoOnboardingSuggestions {
        let languageCode = Locale.current.language.languageCode?.identifier
        return DemoOnboardingSuggestions(
            localeIdentifier: languageCode == "pt" ? "pt-BR" : "en-US",
            countryCode: Locale.current.region?.identifier ?? "US",
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }
}

actor DemoOnboardingRepository: OnboardingRepository {
    private let stateStore: DemoStateStore
    private let buildFlavor: AppBuildFlavor
    private let preloadsSyntheticOnboardingValues: Bool
    private let suggestions: DemoOnboardingSuggestions
    private let behavior: DemoOperationBehavior<OnboardingRepositoryError>

    init(
        stateStore: DemoStateStore,
        buildFlavor: AppBuildFlavor,
        preloadsSyntheticOnboardingValues: Bool = false,
        suggestions: DemoOnboardingSuggestions = .currentDevice,
        behavior: DemoOperationBehavior<OnboardingRepositoryError> = .succeed(after: nil)
    ) {
        self.stateStore = stateStore
        self.buildFlavor = buildFlavor
        self.preloadsSyntheticOnboardingValues = preloadsSyntheticOnboardingValues
        self.suggestions = suggestions
        self.behavior = behavior
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        try await apply(behavior)
        do {
            if let draft = try await stateStore.loadOnboardingDraft() {
                return draft
            }
            if preloadsSyntheticOnboardingValues,
               let session = try await stateStore.loadSession(),
               session.userID == userID,
               session.isEmailConfirmed {
                return syntheticPreloadedDraft
            }

            guard buildFlavor == .debug else {
                return nil
            }
            return suggestedEmptyDraft
        } catch {
            throw OnboardingRepositoryError.storageUnavailable
        }
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        try await apply(behavior)
        try Task.checkCancellation()
        do {
            try await stateStore.saveOnboardingDraft(draft)
        } catch {
            throw OnboardingRepositoryError.storageUnavailable
        }
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        try await apply(behavior)
        try validate(draft)

        let existingSession: AuthSession
        do {
            guard let session = try await stateStore.loadSession(), session.userID == userID else {
                throw OnboardingRepositoryError.storageUnavailable
            }
            existingSession = session
        } catch let error as OnboardingRepositoryError {
            throw error
        } catch {
            throw OnboardingRepositoryError.storageUnavailable
        }

        try Task.checkCancellation()
        do {
            try await stateStore.saveOnboardingDraft(draft)
        } catch {
            throw OnboardingRepositoryError.storageUnavailable
        }

        let completedSession = AuthSession(
            userID: existingSession.userID,
            email: existingSession.email,
            isEmailConfirmed: existingSession.isEmailConfirmed,
            isOnboardingCompleted: true
        )
        try Task.checkCancellation()
        do {
            try await stateStore.saveSession(completedSession)
        } catch {
            throw OnboardingRepositoryError.storageUnavailable
        }
    }

    func clear(for userID: String) async throws {
        try await apply(behavior)
        try Task.checkCancellation()
        do {
            try await stateStore.clearOnboardingDraft()
        } catch {
            throw OnboardingRepositoryError.storageUnavailable
        }
    }

    private func apply(
        _ behavior: DemoOperationBehavior<OnboardingRepositoryError>
    ) async throws {
        switch behavior {
        case .succeed(let delay):
            if let delay { try await Task.sleep(for: delay) }
        case .fail(let error, let delay):
            if let delay { try await Task.sleep(for: delay) }
            try Task.checkCancellation()
            throw error
        }
    }

    private func validate(_ draft: OnboardingDraft) throws {
        if buildFlavor == .release, draft.consent != nil {
            throw OnboardingRepositoryError.developmentConsentForbidden
        }

        let hasIdentity = !(draft.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && !draft.localeIdentifier.isEmpty
            && !draft.countryCode.isEmpty
            && !draft.timeZoneIdentifier.isEmpty
        let hasBody = draft.biologicalSex != nil
            && draft.birthDate != nil
            && (draft.heightCM ?? 0) > 0
            && (draft.weightKG ?? 0) > 0
            && (draft.bodyFatPercent ?? -1) >= 0
        let hasObjective = draft.objective != nil
        let hasRoutine = draft.activityLevel != nil
            && (1...7).contains(draft.trainingFrequency ?? 0)
            && draft.waterIntake != nil
            && draft.hungerLevel != nil
            && valid(draft.wakeTime)
            && valid(draft.bedtime)
            && draft.foodOrganization != nil
        let hasFinalChoices = draft.persona != nil && draft.consent != nil

        guard hasIdentity, hasBody, hasObjective, hasRoutine, hasFinalChoices else {
            throw OnboardingRepositoryError.invalidDraft
        }
    }

    private func valid(_ time: LocalTime?) -> Bool {
        guard let time else {
            return false
        }
        return (0..<24).contains(time.hour) && (0..<60).contains(time.minute)
    }

    private var syntheticPreloadedDraft: OnboardingDraft {
        OnboardingDraft(
            displayName: nil,
            localeIdentifier: "pt-BR",
            countryCode: "BR",
            timeZoneIdentifier: "America/Sao_Paulo",
            biologicalSex: .feminine,
            birthDate: Date(timeIntervalSince1970: 946_684_800),
            heightCM: 170,
            weightKG: 65,
            bodyFatPercent: 25,
            objective: nil,
            activityLevel: .moderate,
            trainingFrequency: 3,
            waterIntake: .moderate,
            hungerLevel: .moderate,
            wakeTime: LocalTime(hour: 7, minute: 0),
            bedtime: LocalTime(hour: 23, minute: 0),
            foodOrganization: .yes,
            persona: nil,
            consent: nil,
            currentStep: .bodyData
        )
    }

    private var suggestedEmptyDraft: OnboardingDraft {
        OnboardingDraft(
            displayName: nil,
            localeIdentifier: suggestions.localeIdentifier,
            countryCode: suggestions.countryCode,
            timeZoneIdentifier: suggestions.timeZoneIdentifier,
            biologicalSex: nil,
            birthDate: nil,
            heightCM: nil,
            weightKG: nil,
            bodyFatPercent: nil,
            objective: nil,
            activityLevel: nil,
            trainingFrequency: nil,
            waterIntake: nil,
            hungerLevel: nil,
            wakeTime: nil,
            bedtime: nil,
            foodOrganization: nil,
            persona: nil,
            consent: nil,
            currentStep: .welcome
        )
    }
}
