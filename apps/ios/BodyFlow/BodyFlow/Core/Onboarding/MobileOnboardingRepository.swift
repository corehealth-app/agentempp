import Foundation

struct MobileOnboardingRepository: OnboardingRepository {
    let transport: any MobileAPIExecuting
    /// Local persistence requires the immutable session scope below.
    let deviceDraft: OnboardingDeviceDraftStore?
    let sessionLifecycle: (any SessionLifecycleProviding)?
    private let sessionLease: SessionLease?

    init(
        transport: any MobileAPIExecuting,
        deviceDraft: OnboardingDeviceDraftStore? = nil,
        sessionLifecycle: (any SessionLifecycleProviding)? = nil
    ) {
        self.transport = transport
        self.deviceDraft = deviceDraft
        self.sessionLifecycle = sessionLifecycle
        sessionLease = nil
    }

    private init(
        transport: any MobileAPIExecuting,
        deviceDraft: OnboardingDeviceDraftStore?,
        sessionLifecycle: any SessionLifecycleProviding,
        sessionLease: SessionLease
    ) {
        self.transport = transport
        self.deviceDraft = deviceDraft
        self.sessionLifecycle = sessionLifecycle
        self.sessionLease = sessionLease
    }

    /// Bound once by the root before its first read and retained by its model.
    /// Re-scoping an old instance never grants it a newer generation.
    func scoped(for userID: String) async throws -> any OnboardingRepository {
        if let sessionLease {
            guard sessionLease.userID == userID, let sessionLifecycle else {
                throw SessionLifecycleError.sessionSuperseded
            }
            try await sessionLifecycle.validate(sessionLease)
            return self
        }
        guard let sessionLifecycle else {
            // A token-only provider or test transport owns no device state.
            return MobileOnboardingRepository(transport: transport)
        }
        let lease = try await sessionLifecycle.leaseForRequest()
        guard lease.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
        try await sessionLifecycle.validate(lease)
        let scopedTransport: any MobileAPIExecuting =
            if let mobile = transport as? MobileAPITransport { mobile.scoped(to: lease) }
            else { transport }
        return MobileOnboardingRepository(
            transport: scopedTransport, deviceDraft: deviceDraft,
            sessionLifecycle: sessionLifecycle, sessionLease: lease
        )
    }

    private func validateScope(for userID: String) async throws {
        guard let sessionLease else { return }
        guard let sessionLifecycle, sessionLease.userID == userID else {
            throw SessionLifecycleError.sessionSuperseded
        }
        try await sessionLifecycle.validate(sessionLease)
    }

    private func clearDeviceDraft(for userID: String) async throws {
        guard let deviceDraft, let sessionLifecycle, let sessionLease else { return }
        guard sessionLease.userID == userID else { throw SessionLifecycleError.sessionSuperseded }
        try await sessionLifecycle.performPatientStateOperation(lease: sessionLease) {
            deviceDraft.clear(for: userID)
        }
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? {
        try await loadState(for: userID).draft
    }

    func loadState(for userID: String) async throws -> OnboardingServerState {
        try await validateScope(for: userID)
        let state: OnboardingServerState
        do {
            state = try await transport.execute(MobileAPIRequest(
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
        try await validateScope(for: userID)
        guard let deviceDraft, let sessionLifecycle, let sessionLease else { return state }
        return try await sessionLifecycle.performPatientStateOperation(lease: sessionLease) {
            resuming(state, for: userID, deviceDraft: deviceDraft)
        }
    }

    /// The server's answer, completed by what this iPhone kept of an
    /// unfinished sign-up. The server keeps nothing of a sign-up before it is
    /// finished, so without this a person whose app was ended in the middle
    /// came back to a blank first step.
    private func resuming(
        _ state: OnboardingServerState,
        for userID: String,
        deviceDraft: OnboardingDeviceDraftStore
    ) -> OnboardingServerState {
        // A finished sign-up, one whose documents are being accepted again,
        // or any draft the server sends: the server's word, and nothing kept
        // here applies any more.
        guard !state.completion.completed,
              state.completion.completedAt == nil,
              state.draft == nil else {
            deviceDraft.clear(for: userID)
            return state
        }
        guard let kept = deviceDraft.load(for: userID) else { return state }
        return OnboardingServerState(
            locale: state.locale,
            completion: state.completion,
            requirements: state.requirements,
            acceptedActions: state.acceptedActions,
            draft: kept
        )
    }

    func checkEligibility(
        _ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingEligibilityDecision {
        try await validateScope(for: userID)
        do {
            let result: OnboardingEligibilityDecision = try await transport.execute(MobileAPIRequest(
                method: .post, path: "/api/mobile/v1/onboarding/eligibility",
                body: try JSONEncoder().encode(input), idempotencyKey: idempotencyKey
            ))
            try await validateScope(for: userID)
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

    /// Nothing of an unfinished sign-up is sent: the server only receives it
    /// whole, at the end. What waits on this iPhone meanwhile is kept by
    /// `keepDraftOnDevice`.
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        try Task.checkCancellation()
        try await validateScope(for: userID)
    }

    func keepDraftOnDevice(_ draft: OnboardingDraft, for userID: String) async {
        guard let deviceDraft, let sessionLifecycle, let sessionLease,
              sessionLease.userID == userID else { return }
        _ = try? await sessionLifecycle.performPatientStateOperation(lease: sessionLease) {
            deviceDraft.save(draft, for: userID)
        }
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func completeOfficial(
        _ draft: OnboardingDraft,
        for userID: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> OnboardingCompletionAcknowledgement {
        try await validateScope(for: userID)
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
            // The sign-up is the server's now: nothing of it stays here.
            try await validateScope(for: userID)
            try await clearDeviceDraft(for: userID)
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
        try await clearDeviceDraft(for: userID)
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
        case .conflict(let code, _)
            where code == "body_photo_confirmation_stale" || code == "body_photo_confirmation_unavailable":
            .bodyPhotoConfirmationChanged
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
    let bodyPhotoConfirmation: OnboardingBodyPhotoConfirmation.Intent?

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
        if draft.bodyFatOrigin == .photos {
            guard let confirmation = draft.bodyPhotoConfirmation, confirmation.matches(draft) else {
                throw OnboardingRepositoryError.invalidDraft
            }
            bodyPhotoConfirmation = confirmation.intent
        } else {
            bodyPhotoConfirmation = nil
        }
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
        case bodyPhotoConfirmation = "body_photo_confirmation"
    }
}
