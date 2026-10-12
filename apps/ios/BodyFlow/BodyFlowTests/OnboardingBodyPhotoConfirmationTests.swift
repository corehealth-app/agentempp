import Foundation
import Testing

@testable import BodyFlow

@MainActor
@Suite("Onboarding photo confirmation and local provenance")
struct OnboardingBodyPhotoConfirmationTests {
    private let ids = SignupBodyPhotoSourceIDs(
        front: "00000000-0000-4000-8000-000000000001",
        side: "00000000-0000-4000-8000-000000000002",
        back: "00000000-0000-4000-8000-000000000003"
    )
    private var value: Decimal { Decimal(string: "24.13")! }
    private var fingerprint: String { String(repeating: "a", count: 64) }
    private var confirmation: OnboardingBodyPhotoConfirmation {
        .init(value: value, sex: .masculine, sourceIDs: ids, fingerprint: fingerprint)
    }

    private func state(fingerprint: String? = nil, accepted: Bool = true) -> SignupBodyPhotoState {
        let date = APITimestamp(value: Date(timeIntervalSince1970: 1_791_849_600))
        let decision = SignupBodyPhotoEstimate.Decision(usable: true, bodyFatPercent: value, reason: nil)
        return .init(available: true, unavailableReason: nil,
            consent: .init(documentKey: "body_photo_estimate_consent", version: "test-v1", locale: "pt-BR",
                body: "synthetic only", bodyHash: String(repeating: "b", count: 64), acceptedAt: accepted ? date : nil),
            minimumAge: 18,
            poses: zip(SignupBodyPhotoPose.allCases, [ids.front, ids.side, ids.back]).map { pose, id in
                .init(pose: pose, photo: .init(id: id, status: "read", createdAt: date))
            },
            estimate: .init(isEstimate: true, bySex: .init(masculine: decision, feminine: decision), sourceIDs: ids,
                fingerprint: fingerprint ?? self.fingerprint,
                readings: [.init(pose: .front, bodyFatPercent: Decimal(string: "18.125")!),
                    .init(pose: .side, bodyFatPercent: Decimal(string: "24.125")!),
                    .init(pose: .back, bodyFatPercent: Decimal(string: "30.125")!)]),
            remainingUploads: 6)
    }

    private func draftWithPhotos(step: OnboardingStep = .bodyData) -> OnboardingDraft {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: step)
        draft.biologicalSex = .masculine
        draft.bodyFatPercent = 24.13
        draft.bodyFatOrigin = .photos
        draft.bodyPhotoConfirmation = confirmation
        return draft
    }

    private func model(_ draft: OnboardingDraft, repository: PhotoConfirmationRepository = .init()) -> OnboardingFlowModel {
        OnboardingFlowModel(userID: "synthetic-owner", initialDraft: draft, repository: repository,
            personaRepository: PhotoConfirmationPersonaRepository(), developmentConsentAvailability: .syntheticDevelopment,
            onStepChanged: { _ in }, onCompleted: {}, now: { Date(timeIntervalSince1970: 2_000_000_000) })
    }

    @Test("Old drafts without provenance decode without inventing photo confirmation")
    func oldDraftCompatibility() throws {
        let draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        let data = try JSONEncoder().encode(draft)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["bodyFatOrigin"] == nil)
        #expect(object["bodyPhotoConfirmation"] == nil)
        let decoded = try JSONDecoder().decode(OnboardingDraft.self, from: data)
        #expect(decoded == draft)
        #expect(decoded.bodyPhotoConfirmation == nil)
    }

    @Test("Only explicit confirmation applies the server canonical mean")
    func explicitConfirmation() throws {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.biologicalSex = .masculine
        draft.bodyFatPercent = nil
        let flow = model(draft)
        flow.reconcileBodyPhotoState(state())
        #expect(flow.draft.bodyFatPercent == nil)
        #expect(flow.draft.bodyPhotoConfirmation == nil)
        #expect(flow.confirmBodyPhotoEstimate(state()))
        #expect(flow.draft.bodyFatPercent == 24.13)
        #expect(flow.draft.bodyFatOrigin == .photos)
        #expect(flow.draft.bodyPhotoConfirmation == confirmation)
        #expect(!flow.requiresBodyPhotoRevalidation)
        let roundTrip = try JSONDecoder().decode(OnboardingDraft.self, from: JSONEncoder().encode(flow.draft))
        #expect(roundTrip.bodyPhotoConfirmation == confirmation)
    }

    @Test("Typing the same 24.13 clears the photo intent")
    func manualSameValueInvalidates() {
        let flow = model(draftWithPhotos())
        flow.updateBodyFatPercent(24.13)
        #expect(flow.draft.bodyFatPercent == 24.13)
        #expect(flow.draft.bodyFatOrigin == .typed)
        #expect(flow.draft.bodyPhotoConfirmation == nil)
        #expect(!flow.requiresBodyPhotoRevalidation)
    }

    @Test("A changed fingerprint invalidates the photo value even with the same mean")
    func changedProofSameMean() {
        let flow = model(draftWithPhotos())
        flow.reconcileBodyPhotoState(state())
        #expect(!flow.requiresBodyPhotoRevalidation)
        flow.reconcileBodyPhotoState(state(fingerprint: String(repeating: "c", count: 64)))
        #expect(flow.draft.bodyFatPercent == nil)
        #expect(flow.draft.bodyFatOrigin == nil)
        #expect(flow.draft.bodyPhotoConfirmation == nil)
    }

    @Test("Unavailable state clears only photo-derived values", arguments: [OnboardingBodyFatOrigin.photos, .typed])
    func unavailableState(_ origin: OnboardingBodyFatOrigin) {
        var draft = draftWithPhotos()
        draft.bodyFatOrigin = origin
        if origin == .typed { draft.bodyPhotoConfirmation = nil }
        let flow = model(draft)
        flow.reconcileBodyPhotoState(nil)
        #expect(flow.draft.bodyFatPercent == (origin == .photos ? nil : 24.13))
        #expect(flow.draft.bodyFatOrigin == (origin == .photos ? nil : .typed))
        #expect(flow.draft.bodyPhotoConfirmation == nil)
    }

    @Test("A restored photo draft cannot request eligibility before official revalidation")
    func restoredDraftWaitsForRead() async {
        let repository = PhotoConfirmationRepository()
        let flow = model(draftWithPhotos(step: .objective), repository: repository)
        #expect(flow.requiresBodyPhotoRevalidation)
        await flow.prepareObjectiveIfNeeded()
        #expect(await repository.eligibilityInputs.isEmpty)
        #expect(flow.eligibilityDecision == nil)
        flow.reconcileBodyPhotoState(state())
        await flow.prepareObjectiveIfNeeded()
        #expect(!flow.requiresBodyPhotoRevalidation)
        #expect(await repository.eligibilityInputs.count == 1)
        #expect(await repository.eligibilityInputs.first?.bodyFatPercent == 24.13)
    }

    @Test("No accepted consent and an inactive owner cannot confirm")
    func confirmationGates() {
        let flow = model(draftWithPhotos())
        #expect(!flow.confirmBodyPhotoEstimate(state(accepted: false)))
        flow.invalidate()
        #expect(!flow.confirmBodyPhotoEstimate(state()))
    }

    @Test("The protected device draft retains proof without photo bytes or consent text")
    func protectedProofRestoration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("photo-proof-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OnboardingDeviceDraftStore(directory: folder)
        #expect(store.save(draftWithPhotos(), for: "synthetic-owner"))
        let kept = try #require(store.load(for: "synthetic-owner"))
        #expect(kept.bodyFatOrigin == .photos)
        #expect(kept.bodyPhotoConfirmation == confirmation)
        #expect(store.load(for: "another-owner") == nil)
        #expect(model(kept).requiresBodyPhotoRevalidation)
        let content = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!content.contains("synthetic-owner"))
        #expect(!content.contains("synthetic only"))
        #expect(!content.contains("upload"))
        #expect(!content.contains("fileURL"))
    }

    @Test("Removing a manual value or changing the photo sex cannot retain its intent")
    func editsClearPhotoIntent() {
        let flow = model(draftWithPhotos())
        flow.updateBiologicalSex(.feminine)
        #expect(flow.draft.bodyFatPercent == nil)
        #expect(flow.draft.bodyPhotoConfirmation == nil)
        #expect(flow.draft.bodyFatOrigin == nil)
        flow.updateBodyFatPercent(24.13)
        flow.updateBodyFatPercent(nil)
        #expect(flow.draft.bodyFatOrigin == nil)
        #expect(flow.draft.bodyPhotoConfirmation == nil)
    }

    @Test("An uncertain photo completion keeps its exact confirmed draft and retry key")
    func uncertainPhotoCompletionIsImmutable() async throws {
        let repository = PhotoConfirmationRepository()
        var draft = draftWithPhotos(step: .completion)
        draft.consent = .init(documentIDs: [.terms, .privacy], acceptedAt: Date(timeIntervalSince1970: 2_000_000_000))
        let flow = model(draft, repository: repository)
        flow.reconcileBodyPhotoState(state())
        // Establish the official decision before capturing the completion attempt.
        await flow.complete()
        await prepareE3Review(flow)
        let original = flow.draft
        await flow.complete()
        #expect(flow.unresolvedCompletion)
        flow.reconcileBodyPhotoState(nil)
        flow.updateBodyFatPercent(24.13)
        #expect(!flow.confirmBodyPhotoEstimate(state(fingerprint: String(repeating: "c", count: 64))))
        #expect(flow.draft == original)
        await flow.complete()
        #expect(await repository.completionDrafts == [original, original])
        let keys = await repository.completionKeys
        #expect(keys.count == 2)
        #expect(Set(keys).count == 1)
    }
}

private actor PhotoConfirmationRepository: OnboardingRepository {
    private(set) var eligibilityInputs: [OnboardingEligibilityInput] = []
    private(set) var completionDrafts: [OnboardingDraft] = []
    private(set) var completionKeys: [IdempotencyKey] = []
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String, idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        eligibilityInputs.append(input)
        return E3Fixtures.choice
    }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { nil }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {}
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {}
    func completeOfficial(_ draft: OnboardingDraft, for userID: String, idempotencyKey: IdempotencyKey) async throws -> OnboardingCompletionAcknowledgement {
        completionDrafts.append(draft)
        completionKeys.append(idempotencyKey)
        throw OnboardingRepositoryError.serviceUnavailable
    }
    func clear(for userID: String) async throws {}
}

private actor PhotoConfirmationPersonaRepository: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws {}
}
