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
        try rejectDevelopmentConsentIfNeeded(draft)
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
        try rejectDevelopmentConsentIfNeeded(draft)

        let consentIDs = Set(draft.consent?.documentIDs ?? [])
        let developmentIDs = Set(DevelopmentConsentDocumentID.allCases)
        let hasIdentity = !(draft.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && OnboardingLocalePolicy.isSupported(draft.localeIdentifier)
            && isValidCountryCode(draft.countryCode)
            && TimeZone(identifier: draft.timeZoneIdentifier) != nil
        let hasBody = draft.biologicalSex != nil
            && isValidBirthDate(draft.birthDate)
            && isInRange(draft.heightCM, range: 100...250)
            && isInRange(draft.weightKG, range: 30...300)
            && isOptionalBodyFatValid(draft.bodyFatPercent)
        let hasObjective = draft.objective != nil
        let hasRoutine = draft.activityLevel != nil
            && (0...7).contains(draft.trainingFrequency ?? -1)
            && draft.waterIntake != nil
            && draft.hungerLevel != nil
            && valid(draft.wakeTime)
            && valid(draft.bedtime)
            && draft.foodOrganization != nil
        let hasFinalChoices = draft.persona != nil
            && developmentIDs.isSubset(of: consentIDs)
        let isAtCompletion = draft.currentStep == .completion

        guard hasIdentity,
              hasBody,
              hasObjective,
              hasRoutine,
              hasFinalChoices,
              isAtCompletion else {
            throw OnboardingRepositoryError.invalidDraft
        }
    }

    private func rejectDevelopmentConsentIfNeeded(
        _ draft: OnboardingDraft
    ) throws {
        let consentIDs = Set(draft.consent?.documentIDs ?? [])
        let developmentIDs = Set(DevelopmentConsentDocumentID.allCases)
        if buildFlavor == .release,
           !consentIDs.isDisjoint(with: developmentIDs) {
            throw OnboardingRepositoryError.developmentConsentForbidden
        }
    }

    private func isValidCountryCode(_ countryCode: String) -> Bool {
        countryCode.count == 2
            && countryCode == countryCode.uppercased()
            && countryCode.unicodeScalars.allSatisfy { (65...90).contains($0.value) }
            && Locale.Region.isoRegions.map(\.identifier).contains(countryCode)
    }

    private func isValidBirthDate(_ birthDate: Date?) -> Bool {
        guard let birthDate else { return false }
        return birthDate <= Date()
    }

    private func isInRange(
        _ value: Double?,
        range: ClosedRange<Double>
    ) -> Bool {
        guard let value else { return false }
        return range.contains(value)
    }

    private func isOptionalBodyFatValid(_ value: Double?) -> Bool {
        guard let value else { return true }
        return (3...60).contains(value)
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
