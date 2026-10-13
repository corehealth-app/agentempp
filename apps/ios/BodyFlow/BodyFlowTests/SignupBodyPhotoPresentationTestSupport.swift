#if DEBUG
import Foundation
import CryptoKit
@testable import BodyFlow

struct PresentationFixedTime: TimeProviding { let now: Date }
@MainActor final class PresentationOwnerBox {
    var current: OnboardingOwnerToken
    init(_ value: OnboardingOwnerToken) { current = value }
}

// All mutation and uploader stand-ins are the same explicit local peer.
// Current documents have a true body hash; never an approved/legal fallback.
actor PresentationPhotoPeer: SignupBodyPhotosProviding, StorageUploading {
    let base: CaptureServerPeer
    private let locale: String
    private let missingDocument: Bool
    private let hasEstimate: Bool
    private var forcedReading = false
    private var replacementIDs = false
    private var stateProjection: (@Sendable (SignupBodyPhotoState) -> SignupBodyPhotoState)? = nil
    static let ids = ["00000000-0000-4000-8000-000000001001",
        "00000000-0000-4000-8000-000000001002", "00000000-0000-4000-8000-000000001003"]

    init(base: CaptureServerPeer, locale: String = "pt-BR", missingDocument: Bool = false, hasEstimate: Bool = false) {
        self.base = base; self.locale = locale; self.missingDocument = missingDocument; self.hasEstimate = hasEstimate
    }
    func snapshot() async -> CapturePeerSnapshot { await base.snapshot() }
    func changeDocument() async { await base.changeDocument() }
    func holdNextState() async { await base.holdNextState() }
    func forceReading(_ value: Bool) { forcedReading = value }
    func replaceReadIDs() { replacementIDs = true; forcedReading = false }
    // Test-only public DTO script. A held GET keeps its original projection.
    func setStateProjection(_ projection: (@Sendable (SignupBodyPhotoState) -> SignupBodyPhotoState)?) {
        stateProjection = projection
    }
    func state() async throws -> SignupBodyPhotoState {
        let project = stateProjection
        let raw = try await base.state()
        let document: SignupBodyPhotoConsent?
        if let doc = raw.consent, !missingDocument {
            let body = "Synthetic presentation consent only: \(doc.version)"
            let hash = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
            document = .init(documentKey: doc.documentKey, version: doc.version, locale: locale,
                body: body, bodyHash: hash, acceptedAt: doc.acceptedAt)
        } else { document = nil }
        guard hasEstimate else {
            let answer = SignupBodyPhotoState(available: raw.available, unavailableReason: raw.unavailableReason, consent: document,
                minimumAge: raw.minimumAge, poses: raw.poses, estimate: nil, remainingUploads: raw.remainingUploads)
            return project?(answer) ?? answer
        }
        let timestamp = APITimestamp(value: PresentationHarness.now)
        let ids = Self.ids.enumerated().map { index, old in
            replacementIDs ? String(format: "00000000-0000-4000-8000-%012d", 2_001 + index)
                : (raw.poses.first { $0.pose == SignupBodyPhotoPose.allCases[index] }?.photo?.id ?? old)
        }
        let poses = SignupBodyPhotoPose.allCases.enumerated().map { index, pose in
            let status = forcedReading && pose == .front ? "reading"
                : (raw.poses.first { $0.pose == pose }?.photo?.status ?? "read")
            return SignupBodyPhotoSlot(pose: pose, photo: .init(id: ids[index], status: status, createdAt: timestamp))
        }
        let source = SignupBodyPhotoSourceIDs(front: ids[0], side: ids[1], back: ids[2])
        let decision = SignupBodyPhotoEstimate.Decision(usable: true, bodyFatPercent: Decimal(24), reason: nil)
        let fingerprint = ids == Self.ids ? String(repeating: "a", count: 64) : String(repeating: "b", count: 64)
        let estimate = SignupBodyPhotoEstimate(isEstimate: true,
            bySex: .init(masculine: decision, feminine: decision), sourceIDs: source, fingerprint: fingerprint,
            readings: [.init(pose: .front, bodyFatPercent: Decimal(18)),
                .init(pose: .side, bodyFatPercent: Decimal(24)), .init(pose: .back, bodyFatPercent: Decimal(30))])
        let answer = SignupBodyPhotoState(available: raw.available, unavailableReason: raw.unavailableReason, consent: document,
            minimumAge: raw.minimumAge, poses: poses, estimate: estimate, remainingUploads: raw.remainingUploads)
        return project?(answer) ?? answer
    }
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt {
        try await base.consent(attempt)
    }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await base.create(attempt) }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(attempt) }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.delete(attempt) }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt { try await base.repair(attempt) }
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws { try await base.upload(media, with: ticket) }
}

actor PresentationFactoryPeer {
    let scope: SignupBodyPhotoCaptureScope
    let gate: CaptureConsentGate
    private let holdsFirst: Bool
    private var calls: [String] = []
    init(scope: SignupBodyPhotoCaptureScope, holdsFirst: Bool = false) {
        self.scope = scope; self.holdsFirst = holdsFirst; gate = CaptureConsentGate(holds: holdsFirst)
    }
    func bind(_ userID: String) async throws -> SignupBodyPhotoCaptureScope {
        calls.append(userID)
        let captured = scope
        if holdsFirst && calls.count == 1 { await gate.enter() }
        return captured // Deliberately noncooperative; presentation guards result.
    }
    func snapshot() -> [String] { calls }
    nonisolated var capability: SignupBodyPhotoCaptureCapability {
        .init(scoped: { userID in try await self.bind(userID) })
    }
}

struct SignupPhotoPresentationOnboardingRepository: OnboardingRepository {
    func scoped(for userID: String) async throws -> any OnboardingRepository { self }
    func loadState(for userID: String) async throws -> OnboardingServerState { throw OnboardingRepositoryError.serviceUnavailable }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { throw OnboardingRepositoryError.serviceUnavailable }
    func loadBodyPhotoCleanupScope(generation: String?) async throws -> OnboardingBodyPhotoCleanupScope? { throw OnboardingRepositoryError.serviceUnavailable }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func complete(_ draft: OnboardingDraft, for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String, idempotencyKey: IdempotencyKey) async throws -> OnboardingCompletionAcknowledgement {
        throw OnboardingRepositoryError.serviceUnavailable
    }
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String, idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        throw OnboardingRepositoryError.serviceUnavailable
    }
    func clear(for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func keepDraftOnDevice(_ draft: OnboardingDraft, for userID: String) async {}
}
struct PresentationPersona: CoachPersonaRepository {
    func selectedPersona(for userID: String) async throws -> CoachPersona? { nil }
    func setPersona(_ persona: CoachPersona, for userID: String) async throws { throw CoachPersonaRepositoryError.serviceUnavailable }
}

@MainActor
struct PresentationHarness {
    nonisolated static let now = Date(timeIntervalSince1970: 1_791_849_600)
    let cleanup: CleanupProcessorHarness
    let peer: PresentationPhotoPeer
    let consentGate: CaptureConsentGate
    let stateGate: CaptureConsentGate
    let factory: PresentationFactoryPeer
    let scope: SignupBodyPhotoCaptureScope
    let staging: MediaStagingStore
    let owner: OnboardingOwnerToken
    let ownerBox: PresentationOwnerBox
    let flow: OnboardingFlowModel
    let model: SignupBodyPhotoPresentationModel
    let clock: CapturePollingClock

    init(manual: Double? = nil, available: Bool = true, missingDocument: Bool = false,
        documentLocale: String = "pt-BR", hasEstimate: Bool = false, holdConsent: Bool = false,
        holdFactory: Bool = false, installsCapability: Bool = true, birthDate: String = "1990-01-02",
        failOnceAt: CaptureFailurePoint? = nil) async throws {
        let cleanup = try await CleanupProcessorHarness()
        let staging = MediaStagingStore(temporaryDirectory: cleanup.folder.appendingPathComponent("staging"))
        let consentGate = CaptureConsentGate(holds: holdConsent)
        let stateGate = CaptureConsentGate(holds: true)
        let base = CaptureServerPeer(staging: staging, consentGate: consentGate, available: available,
            failOnceAt: failOnceAt, stateGate: stateGate)
        let peer = PresentationPhotoPeer(base: base, locale: documentLocale, missingDocument: missingDocument, hasEstimate: hasEstimate)
        let lifecycle = cleanup.lifecycle, lease = cleanup.lease, store = cleanup.store
        let clock = CapturePollingClock()
        let scope = SignupBodyPhotoCaptureScope(userID: lease.userID, photos: peer, uploader: peer,
            staging: staging, camera: .unavailable,
            validateSession: { try Task.checkCancellation(); try await lifecycle.validate(lease) },
            stagePhoto: { data, channel in
                try await lifecycle.validate(lease)
                let file = try await base.stage(data, channel: channel)
                try await lifecycle.validate(lease)
                return file
            }, performWork: { operation in
                await clock.workStarted()
                do { try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run(operation) }
                catch { await clock.workEnded(); throw error }
                await clock.workEnded()
            }, discardStaged: { file in
                let task = Task { try await lifecycle.performPatientStateOperation(lease: lease) { staging.remove(file) } }
                try await task.value
            }, rememberUnboundCreate: { operationID in
                try await lifecycle.performPatientStateOperation(lease: lease) {
                    try store.mutate(for: lease.userID) { current in _ = current.rememberUnbound(operationID) }
                }
            })
        let factory = PresentationFactoryPeer(scope: scope, holdsFirst: holdFactory)
        let owner = OnboardingOwnerToken(userID: lease.userID, restoreGeneration: 1)
        let ownerBox = PresentationOwnerBox(owner)
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: .bodyData)
        draft.localeIdentifier = "pt-BR"; draft.timeZoneIdentifier = "America/Sao_Paulo"
        draft.birthDate = OnboardingCivilDate.date(from: birthDate, timeZoneIdentifier: draft.timeZoneIdentifier)
        draft.biologicalSex = .masculine
        draft.bodyFatPercent = manual; draft.bodyFatOrigin = manual == nil ? nil : .typed
        draft.bodyPhotoConfirmation = nil
        let flow = OnboardingFlowModel(userID: lease.userID, initialDraft: draft,
            repository: SignupPhotoPresentationOnboardingRepository(), personaRepository: PresentationPersona(),
            developmentConsentAvailability: .syntheticDevelopment,
            onStepChanged: { _ in }, onCompleted: {}, now: { Self.now })
        self.cleanup = cleanup; self.peer = peer; self.consentGate = consentGate; self.stateGate = stateGate
        self.factory = factory; self.scope = scope; self.staging = staging; self.owner = owner; self.ownerBox = ownerBox
        self.flow = flow; self.clock = clock
        model = SignupBodyPhotoPresentationModel(flow: flow, ownerToken: owner,
            capability: installsCapability ? factory.capability : nil,
            timeProvider: PresentationFixedTime(now: Self.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: "presentation-test-key"),
            pollingTiming: .init(elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }),
            isCurrentOwner: { $0 == ownerBox.current })
    }
    func clean() { model.invalidate(); cleanup.removeFolder() }
}
#endif
