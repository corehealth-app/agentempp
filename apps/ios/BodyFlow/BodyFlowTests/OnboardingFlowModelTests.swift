import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Onboarding flow model")
struct OnboardingFlowModelTests {
    @Test("The initial routine can advance without reporting a habitual water intake")
    func routineDoesNotRequireHabitualWaterIntake() async {
        let repository = RecordingOnboardingRepository()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        draft.waterIntake = nil
        let model = await makeModel(draft: draft, repository: repository)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step != .routine)
    }
    @Test("welcome requires a name, ISO country and IANA timezone")
    func validatesWelcome() async {
        let repository = RecordingOnboardingRepository()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome)
        draft.displayName = "  "
        draft.countryCode = "br"
        draft.timeZoneIdentifier = "Brazil/East/Invalid"
        let model = await makeModel(draft: draft, repository: repository)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [
            .displayNameRequired,
            .countryInvalid,
            .timeZoneInvalid,
        ])
        #expect(model.step == .welcome)
        #expect(await repository.savedDrafts.isEmpty)
    }

    // "001" (the world) and "EU" are regions the system names, not countries.
    @Test(arguments: ["B", "BRA", "br", "1R", "ZZ", "001", "EU"])
    func rejectsInvalidCountryCodes(_ countryCode: String) async {
        let repository = RecordingOnboardingRepository()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome)
        draft.countryCode = countryCode
        let model = await makeModel(draft: draft, repository: repository)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.countryInvalid])
        #expect(await repository.savedDrafts.isEmpty)
    }

    @Test("uppercase ISO country and known timezone pass welcome validation")
    func acceptsCountryAndTimezone() async {
        let repository = RecordingOnboardingRepository()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome)
        draft.countryCode = "BR"
        draft.timeZoneIdentifier = "America/Sao_Paulo"
        let model = await makeModel(draft: draft, repository: repository)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step == .bodyData)
    }

    @Test("changing timezone preserves the selected civil birth date")
    func changingTimeZonePreservesCivilBirthDate() async throws {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .welcome)
        draft.timeZoneIdentifier = "Pacific/Kiritimati"
        draft.birthDate = try #require(OnboardingCivilDate.date(
            from: "1990-01-01",
            timeZoneIdentifier: draft.timeZoneIdentifier
        ))
        let model = await makeModel(draft: draft)

        model.updateTimeZoneIdentifier("Etc/GMT+12")

        let rebasedBirthDate = try #require(model.draft.birthDate)
        #expect(model.draft.timeZoneIdentifier == "Etc/GMT+12")
        #expect(OnboardingCivilDate.string(
            from: rebasedBirthDate,
            timeZoneIdentifier: model.draft.timeZoneIdentifier
        ) == "1990-01-01")
    }

    @Test("body data reports every missing required field")
    func validatesRequiredBodyData() async {
        let repository = RecordingOnboardingRepository()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.biologicalSex = nil
        draft.birthDate = nil
        draft.heightCM = nil
        draft.weightKG = nil
        let model = await makeModel(draft: draft, repository: repository)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [
            .biologicalSexRequired,
            .birthDateRequired,
            .heightOutOfRange,
            .weightOutOfRange,
        ])
        #expect(model.step == .bodyData)
    }

    @Test("birth date cannot be in the future")
    func rejectsFutureBirthDate() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.birthDate = now.addingTimeInterval(1)
        let model = await makeModel(draft: draft, now: now)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.birthDateInFuture])
        #expect(model.step == .bodyData)
    }

    @Test(arguments: [99.99, 250.01])
    func rejectsHeightOutsideContract(_ height: Double) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.heightCM = height
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.heightOutOfRange])
    }

    @Test(arguments: [100.0, 250.0])
    func acceptsHeightContractBounds(_ height: Double) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.heightCM = height
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step == .routine)
    }

    @Test(arguments: [29.99, 300.01])
    func rejectsWeightOutsideContract(_ weight: Double) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.weightKG = weight
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.weightOutOfRange])
    }

    @Test(arguments: [30.0, 300.0])
    func acceptsWeightContractBounds(_ weight: Double) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.weightKG = weight
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step == .routine)
    }

    @Test(arguments: [2.99, 60.01])
    func rejectsBodyFatOutsideContract(_ bodyFat: Double) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.bodyFatPercent = bodyFat
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.bodyFatOutOfRange])
    }

    @Test(arguments: [3.0, 60.0])
    func acceptsBodyFatContractBounds(_ bodyFat: Double) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.bodyFatPercent = bodyFat
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step == .routine)
    }

    @Test("body fat is optional")
    func acceptsMissingBodyFat() async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.bodyFatPercent = nil
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step == .routine)
    }

    @Test("objective is required only on the objective step")
    func validatesObjective() async {
        let repository = RecordingOnboardingRepository()
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .objective)
        draft.objective = nil
        let model = await makeModel(draft: draft, repository: repository)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.objectiveRequired])
        #expect(model.step == .objective)
        #expect(await repository.savedDrafts.isEmpty)
    }

    @Test("routine reports all required selections")
    func validatesRoutineRequiredFields() async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        draft.activityLevel = nil
        draft.trainingFrequency = nil
        draft.waterIntake = nil
        draft.hungerLevel = nil
        draft.wakeTime = nil
        draft.bedtime = nil
        draft.foodOrganization = nil
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [
            .activityLevelRequired,
            .trainingFrequencyOutOfRange,
            .hungerLevelRequired,
            .wakeTimeRequired,
            .bedtimeRequired,
            .foodOrganizationRequired,
        ])
        #expect(model.step == .routine)
    }

    @Test(arguments: [-1, 8])
    func rejectsTrainingFrequencyOutsideContract(_ frequency: Int) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        draft.trainingFrequency = frequency
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.trainingFrequencyOutOfRange])
    }

    @Test(arguments: [0, 7])
    func acceptsTrainingFrequencyContractBounds(_ frequency: Int) async {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .routine)
        draft.trainingFrequency = frequency
        let model = await makeModel(draft: draft)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step == .persona)
    }

    @Test("persona and consent validate only on their own steps")
    func validatesFinalChoicesByStep() async {
        var personaDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .persona)
        personaDraft.persona = nil
        personaDraft.consent = nil
        let personaModel = await makeModel(draft: personaDraft)

        await personaModel.continueFromCurrentStep()

        #expect(personaModel.validationIssues == [.personaRequired])

        var consentDraft = BodyFlowTestFixtures.onboardingDraft(currentStep: .consent)
        consentDraft.consent = nil
        consentDraft.persona = nil
        let consentModel = await makeModel(
            draft: consentDraft,
            requirements: officialRequirements
        )

        await consentModel.continueFromCurrentStep()

        #expect(consentModel.validationIssues == [.consentRequired])
    }

    @Test("unavailable synthetic consent is neither presented nor advanced")
    func unavailableSyntheticConsentDoesNotAdvance() async {
        let repository = RecordingOnboardingRepository()
        let model = await makeModel(
            draft: .fixture(step: .consent),
            repository: repository,
            developmentConsentAvailability: .unavailable
        )

        #expect(model.stepPresentation == .developmentConsentUnavailable)

        await model.continueFromCurrentStep()

        #expect(model.validationIssues == [.developmentConsentUnavailable])
        #expect(model.step == .consent)
        #expect(model.draft.currentStep == .consent)
        #expect(await repository.savedDrafts.isEmpty)
    }

    @Test("unavailable synthetic consent hides a stale completion presentation")
    func unavailableSyntheticConsentHidesStaleCompletion() async {
        let model = await makeModel(
            draft: .fixture(step: .completion),
            developmentConsentAvailability: .unavailable
        )

        #expect(model.stepPresentation == .developmentConsentUnavailable)
    }

    #if DEBUG
    @Test("synthetic development consent retains the debug journey")
    func syntheticDevelopmentConsentAdvances() async {
        let repository = RecordingOnboardingRepository()
        let model = await makeModel(
            draft: .fixture(step: .consent),
            repository: repository,
            developmentConsentAvailability: .syntheticDevelopment
        )

        #expect(model.stepPresentation == .step(.consent))

        await model.continueFromCurrentStep()

        #expect(model.validationIssues.isEmpty)
        #expect(model.step == .objective)
        #expect(await repository.savedDrafts.map(\.currentStep) == [.objective])
    }
    #endif

    @Test("continue saves the advanced draft before publishing the step")
    func savesBeforeAdvance() async {
        let events = LockedEventRecorder()
        let repository = RecordingOnboardingRepository(onSave: {
            events.append("save")
        })
        let model = await makeModel(draft: .fixture(step: .welcome), repository: repository) { step in
            events.append("callback-\(step)")
        }

        await model.continueFromCurrentStep()

        #expect(model.step == .bodyData)
        #expect(model.draft.currentStep == .bodyData)
        #expect(await repository.savedDrafts.map(\.currentStep) == [.bodyData])
        #expect(events.values == ["save", "callback-bodyData"])
    }

    @Test("back preserves typed field updates")
    func backPreservesDraft() async {
        var changedSteps: [OnboardingStep] = []
        let model = await makeModel(draft: .fixture(step: .objective)) {
            changedSteps.append($0)
        }
        model.updateDisplayName("Nome preservado")
        model.updateObjective(.muscleGain)
        model.updateHeightCM(181.5)

        await model.back()

        #expect(model.step == .consent)
        #expect(model.draft.currentStep == .consent)
        #expect(model.draft.displayName == "Nome preservado")
        #expect(model.draft.heightCM == 181.5)
        #expect(model.draft.objective == .muscleGain)
        #expect(changedSteps == [.consent])
    }

    @Test("save failure keeps the step visible and retry can advance")
    func retriesAfterSaveFailure() async {
        let repository = RecordingOnboardingRepository(
            saveResults: [.failure(.serviceUnavailable), .success(())]
        )
        var changedSteps: [OnboardingStep] = []
        let model = await makeModel(draft: .fixture(step: .welcome), repository: repository) {
            changedSteps.append($0)
        }

        await model.continueFromCurrentStep()

        #expect(model.step == .welcome)
        #expect(model.draft.currentStep == .welcome)
        #expect(model.operationState == .failed(.serviceUnavailable))
        #expect(changedSteps.isEmpty)

        await model.continueFromCurrentStep()

        #expect(model.step == .bodyData)
        #expect(model.operationState == .idle)
        #expect(changedSteps == [.bodyData])
        #expect(await repository.savedDrafts.count == 2)
    }

    @Test("concurrent continue calls produce one save and one transition")
    func suppressesConcurrentSubmission() async {
        let repository = SuspendedOnboardingRepository()
        var changedSteps: [OnboardingStep] = []
        let model = await makeModel(draft: .fixture(step: .welcome), repository: repository) {
            changedSteps.append($0)
        }
        let first = Task { await model.continueFromCurrentStep() }
        await repository.waitUntilSaveSuspends()

        await model.continueFromCurrentStep()

        #expect(model.operationState == .saving)
        #expect(await repository.saveCount == 1)

        await repository.resumeSave()
        await first.value

        #expect(model.step == .bodyData)
        #expect(changedSteps == [.bodyData])
    }

    @Test("cancellation after persistence prevents a late transition")
    func cancellationPreventsLateTransition() async {
        let repository = CancellationIgnoringOnboardingRepository()
        var changedSteps: [OnboardingStep] = []
        let model = await makeModel(draft: .fixture(step: .welcome), repository: repository) {
            changedSteps.append($0)
        }
        let submission = Task { await model.continueFromCurrentStep() }
        await repository.waitUntilSaveSuspends()

        submission.cancel()
        await repository.resumeSave()
        await submission.value

        #expect(model.step == .welcome)
        #expect(model.draft.currentStep == .welcome)
        #expect(model.operationState == .idle)
        #expect(changedSteps.isEmpty)
    }

    @Test("a cancelled failing save does not publish a late error")
    func cancellationPreventsLateFailure() async {
        let repository = CancellationIgnoringFailingOnboardingRepository()
        let model = await makeModel(draft: .fixture(step: .welcome), repository: repository)
        let submission = Task { await model.continueFromCurrentStep() }
        await repository.waitUntilSaveSuspends()

        submission.cancel()
        await repository.resumeSave()
        await submission.value

        #expect(model.step == .welcome)
        #expect(model.operationState == .idle)
    }

    @Test("regular Continue cannot bypass the dedicated final command")
    func regularContinueDoesNotComplete() async {
        let repository = RecordingOnboardingRepository()
        var completionCount = 0
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: .fixture(step: .completion),
            repository: repository,
            personaRepository: OnboardingPersonaRepository(),
            developmentConsentAvailability: .syntheticDevelopment,
            onStepChanged: { _ in },
            onCompleted: { completionCount += 1 }
        )

        await model.continueFromCurrentStep()

        #expect(completionCount == 0)
        #expect(await repository.completeCount == 0)
        #expect(await repository.savedDrafts.isEmpty)
    }

    private func makeModel(
        draft: OnboardingDraft = .fixture(step: .welcome),
        repository: any OnboardingRepository = RecordingOnboardingRepository(),
        developmentConsentAvailability: DevelopmentConsentAvailability = .syntheticDevelopment,
        requirements: OnboardingRequirements = .unavailable,
        now: Date = Date(timeIntervalSince1970: 2_000_000_000),
        onStepChanged: @escaping @MainActor (OnboardingStep) -> Void = { _ in }
    ) async -> OnboardingFlowModel {
        let model = OnboardingFlowModel(
            userID: "fixture-user",
            initialDraft: draft,
            repository: repository,
            personaRepository: OnboardingPersonaRepository(),
            developmentConsentAvailability: developmentConsentAvailability,
            requirements: requirements,
            onStepChanged: onStepChanged,
            onCompleted: {},
            now: { now }
        )
        if model.step == .objective { await model.prepareObjectiveIfNeeded() }
        return model
    }

    private var officialRequirements: OnboardingRequirements {
        let document = OnboardingLegalDocument(
            documentKey: "terms_of_service",
            version: "2026-09-15.1",
            locale: "pt-BR",
            body: "Synthetic terms for tests only",
            contentURL: nil,
            contentHash: String(repeating: "a", count: 64),
            purpose: "synthetic_terms_test",
            action: .acceptance,
            required: true,
            effectiveAt: "2026-09-15T15:00:00.000Z"
        )
        return OnboardingRequirements(
            available: true,
            blockingReason: nil,
            documents: [document]
        )
    }
}

private extension OnboardingDraft {
    static func fixture(step: OnboardingStep) -> OnboardingDraft {
        BodyFlowTestFixtures.onboardingDraft(currentStep: step)
    }
}

private actor RecordingOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision { E3Fixtures.choice }

    private(set) var savedDrafts: [OnboardingDraft] = []
    private(set) var completeCount = 0
    private var saveResults: [Result<Void, OnboardingRepositoryError>]
    private let onSave: @Sendable () async -> Void

    init(
        saveResults: [Result<Void, OnboardingRepositoryError>] = [],
        onSave: @escaping @Sendable () async -> Void = {}
    ) {
        self.saveResults = saveResults
        self.onSave = onSave
    }

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        savedDrafts.append(draft)
        await onSave()
        guard !saveResults.isEmpty else { return }
        try saveResults.removeFirst().get()
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        completeCount += 1
    }

    func clear(for userID: String) async throws {}
}

private actor OnboardingPersonaRepository: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}

private actor SuspendedOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision { E3Fixtures.choice }

    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var saveCount = 0

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        saveCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}

    func waitUntilSaveSuspends() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeSave() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CancellationIgnoringOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision { E3Fixtures.choice }

    private var continuation: CheckedContinuation<Void, Never>?

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}

    func waitUntilSaveSuspends() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeSave() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CancellationIgnoringFailingOnboardingRepository: OnboardingRepository {
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
                          idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision { E3Fixtures.choice }

    private var continuation: CheckedContinuation<Void, Never>?

    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }

    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw OnboardingRepositoryError.serviceUnavailable
    }

    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func clear(for userID: String) async throws {}

    func waitUntilSaveSuspends() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeSave() {
        continuation?.resume()
        continuation = nil
    }
}

private final class LockedEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
