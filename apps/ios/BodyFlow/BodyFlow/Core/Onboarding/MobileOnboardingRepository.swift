import Foundation

struct MobileOnboardingRepository: OnboardingRepository {
    let transport: any MobileAPIExecuting

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        try await loadState(for: userID).draft
    }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        do {
            return try await transport.execute(MobileAPIRequest(
                method: .get,
                path: "/api/mobile/v1/onboarding"
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MobileAPITransportError {
            throw mapLoad(error)
        } catch {
            throw OnboardingRepositoryError.serviceUnavailable
        }
    }

    func checkEligibility(
        _ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingEligibilityDecision {
        do {
            let result: OnboardingEligibilityDecision = try await transport.execute(MobileAPIRequest(
                method: .post, path: "/api/mobile/v1/onboarding/eligibility",
                body: try JSONEncoder().encode(input), idempotencyKey: idempotencyKey
            ))
            return try result.validated()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OnboardingRepositoryError {
            throw error
        } catch let error as MobileAPITransportError {
            throw map(error)
        } catch {
            throw OnboardingRepositoryError.serviceUnavailable
        }
    }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        try Task.checkCancellation()
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        let submission = try OnboardingCompletionSubmission(draft: draft)
        let body: Data
        do {
            body = try JSONEncoder().encode(submission)
        } catch {
            throw OnboardingRepositoryError.invalidDraft
        }

        do {
            let acknowledgement: OnboardingCompletionAcknowledgement = try await transport.execute(
                MobileAPIRequest(
                    method: .post,
                    path: "/api/mobile/v1/onboarding",
                    body: body,
                    idempotencyKey: idempotencyKey
                )
            )
            guard acknowledgement.matches(draft) else {
                throw OnboardingRepositoryError.serviceUnavailable
            }
            return acknowledgement
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OnboardingRepositoryError {
            throw error
        } catch let error as MobileAPITransportError {
            throw map(error)
        } catch {
            throw OnboardingRepositoryError.serviceUnavailable
        }
    }

    func clear(for userID: String) async throws {
        try Task.checkCancellation()
    }

    /// The read of the sign-up is the request the root screen waits on, so
    /// it alone tells the team-panel conflict apart (reported on 2026-10-10):
    /// HTTP 403 with this code means the e-mail administers the team's panel.
    /// Every other refusal keeps the meaning it had.
    private func mapLoad(_ error: MobileAPITransportError) -> OnboardingRepositoryError {
        if case .forbidden(let code, _) = error, code == "patient_admin_account_conflict" {
            return .adminAccountConflict
        }
        return map(error)
    }

    private func map(_ error: MobileAPITransportError) -> OnboardingRepositoryError {
        switch error {
        case .conflict(let code, _)
            where code == "onboarding_requirements_changed":
            .requirementsChanged
        case .conflict(let code, _)
            where code == "onboarding_already_completed":
            .alreadyCompleted
        case .server(_, let code, _)
            where code == "onboarding_documents_unavailable":
            .documentsUnavailable
        case .validation(let code, _) where code == "onboarding_objective_not_eligible":
            .objectiveNotEligible
        case .validation:
            .invalidDraft
        default:
            .serviceUnavailable
        }
    }
}

private struct OnboardingCompletionSubmission: Encodable, Sendable {
    let name: String
    let locale: String
    let country: String
    let timezone: String
    let sex: BiologicalSex
    let birthDate: String
    let heightCM: Double
    let weightKG: Double
    let bodyFatPercent: Double?
    let objective: BodyFlowObjective
    let activityLevel: ActivityLevel
    let trainingFrequency: Int
    let waterIntake: WaterIntake
    let hungerLevel: HungerLevel
    let wakeTime: String
    let bedtime: String
    let foodOrganization: FoodOrganization
    let persona: String
    let documentActions: [OnboardingDocumentAction]

    init(draft: OnboardingDraft) throws {
        guard let name = draft.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let sex = draft.biologicalSex,
              let birthDate = draft.birthDate,
              let heightCM = draft.heightCM,
              let weightKG = draft.weightKG,
              let objective = draft.objective,
              let activityLevel = draft.activityLevel,
              let trainingFrequency = draft.trainingFrequency,
              let waterIntake = draft.waterIntake,
              let hungerLevel = draft.hungerLevel,
              let wakeTime = draft.wakeTime,
              let bedtime = draft.bedtime,
              let foodOrganization = draft.foodOrganization,
              let persona = draft.persona,
              let documentActions = draft.documentActions,
              !documentActions.isEmpty,
              documentActions.allSatisfy({
                  !$0.documentKey.hasPrefix("dev.") && !$0.documentKey.hasPrefix("dev_")
              }),
              let birthDateString = OnboardingCivilDate.string(
                  from: birthDate,
                  timeZoneIdentifier: draft.timeZoneIdentifier
              ) else {
            throw OnboardingRepositoryError.invalidDraft
        }

        self.name = name
        locale = draft.localeIdentifier
        country = draft.countryCode
        timezone = draft.timeZoneIdentifier
        self.sex = sex
        self.birthDate = birthDateString
        self.heightCM = heightCM
        self.weightKG = weightKG
        bodyFatPercent = draft.bodyFatPercent
        self.objective = objective
        self.activityLevel = activityLevel
        self.trainingFrequency = trainingFrequency
        self.waterIntake = waterIntake
        self.hungerLevel = hungerLevel
        self.wakeTime = Self.timeString(wakeTime)
        self.bedtime = Self.timeString(bedtime)
        self.foodOrganization = foodOrganization
        self.persona = switch persona {
        case .focus: "focus"
        case .impulse: "impulse"
        case .zen: "zen"
        }
        self.documentActions = documentActions
    }

    private static func timeString(_ time: LocalTime) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case locale
        case country
        case timezone
        case sex
        case birthDate = "birth_date"
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bodyFatPercent = "body_fat_percent"
        case objective
        case activityLevel = "activity_level"
        case trainingFrequency = "training_frequency"
        case waterIntake = "water_intake"
        case hungerLevel = "hunger_level"
        case wakeTime = "wake_time"
        case bedtime
        case foodOrganization = "food_organization"
        case persona
        case documentActions = "document_actions"
    }
}
