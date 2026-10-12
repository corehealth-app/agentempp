#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

enum SignupCompositionOrigin: String, CaseIterable, Sendable { case typed, photos }
enum SignupCompositionFlowAction: String, CaseIterable, Sendable { case advance, eligibility, completion, saving }
enum SignupCompositionRecovery: String, CaseIterable, Sendable { case cleanup, deleteReply, reload }
enum SignupCompositionOwnerChange: String, CaseIterable, Sendable { case foreign, restore }

struct SignupCompositionPhotoReport: Sendable {
    let attempts: [MutationAttempt<SignupBodyPhotoDeleteCommand>]
    let stateReads: Int
    let postDeleteReads: Int
    let repairs: Int
}

/// Typed server peer below the real models. No observer/manual publication.
actor SignupCompositionPhotos: SignupBodyPhotosProviding {
    let base: PresentationPhotoPeer
    private var attempts: [MutationAttempt<SignupBodyPhotoDeleteCommand>] = []
    private var states = 0, postReads = 0, repairs = 0
    private var applied = false
    private var loseReply = false, failReload = false
    private var readingAfterDelete = false
    private var originalIdentifiers = false
    private var nextDelete: CaptureConsentGate?
    private var nextReload: CaptureConsentGate?
    init(base: PresentationPhotoPeer, loseReply: Bool = false, failReload: Bool = false, readingAfterDelete: Bool = false) {
        self.base = base; self.loseReply = loseReply; self.failReload = failReload
        self.readingAfterDelete = readingAfterDelete
    }
    func restoreOriginalReadIDs() { originalIdentifiers = true }
    func holdDelete(_ gate: CaptureConsentGate) { nextDelete = gate }
    func holdReload(_ gate: CaptureConsentGate) { nextReload = gate }
    func report() -> SignupCompositionPhotoReport {
        .init(attempts: attempts, stateReads: states, postDeleteReads: postReads, repairs: repairs)
    }
    func state() async throws -> SignupBodyPhotoState {
        states += 1
        let after = applied
        if after { postReads += 1 }
        let sequence = postReads
        if after, readingAfterDelete {
            await base.forceReading(sequence == 1)
            if sequence > 1 { await base.replaceReadIDs() }
        }
        let raw = try await base.state()
        let answer: SignupBodyPhotoState
        if after, readingAfterDelete, originalIdentifiers, let estimate = raw.estimate {
            let ids = PresentationPhotoPeer.ids
            let poses = raw.poses.enumerated().map { index, slot in
                SignupBodyPhotoSlot(pose: slot.pose, photo: slot.photo.map {
                    SignupBodyPhoto(id: ids[index], status: $0.status, createdAt: $0.createdAt)
                })
            }
            let changed = SignupBodyPhotoEstimate(isEstimate: estimate.isEstimate, bySex: estimate.bySex,
                sourceIDs: .init(front: ids[0], side: ids[1], back: ids[2]),
                fingerprint: String(repeating: "a", count: 64), readings: estimate.readings)
            answer = .init(available: raw.available, unavailableReason: raw.unavailableReason,
                consent: raw.consent, minimumAge: raw.minimumAge, poses: poses,
                estimate: changed, remainingUploads: raw.remainingUploads)
        } else if !after || readingAfterDelete { answer = raw }
        else {
            answer = .init(available: raw.available, unavailableReason: raw.unavailableReason,
                consent: raw.consent, minimumAge: raw.minimumAge,
                poses: SignupBodyPhotoPose.allCases.map { .init(pose: $0, photo: nil) },
                estimate: nil, remainingUploads: raw.remainingUploads)
        }
        if after {
            let gate = nextReload; nextReload = nil
            await gate?.enter() // snapshot captured above; cancellation deliberately ignored
            if failReload { failReload = false; throw SignupBodyPhotoFailure.offline }
        }
        return answer
    }
    func consent(_ a: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt { try await base.consent(a) }
    func create(_ a: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt { try await base.create(a) }
    func complete(_ a: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt { try await base.complete(a) }
    func delete(_ a: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        attempts.append(a)
        let gate = nextDelete; nextDelete = nil
        await gate?.enter()
        applied = true // server effect can precede a lost response
        if loseReply { loseReply = false; throw SignupBodyPhotoFailure.offline }
        return .init(deleted: 0) // valid counted control; no assertion of Storage absence
    }
    func repair(_ a: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        repairs += 1; throw SignupBodyPhotoFailure.unavailable
    }
}

actor SignupCompositionCleanup {
    private var failOnce: Bool
    private var files: [URL] = []
    init(failOnce: Bool) { self.failOnce = failOnce }
    func beforeRemove(_ file: URL) throws {
        files.append(file)
        if failOnce { failOnce = false; throw SignupBodyPhotoFailure.unavailable }
    }
    func attemptedFiles() -> [URL] { files }
}

struct SignupCompositionFlowReport: Equatable, Sendable {
    let saves: Int
    let eligibility: Int
    let completions: Int
}

/// Boundary counters + exact valid choice response, never a success ACK.
actor SignupCompositionOnboardingPeer: OnboardingRepository {
    private var saves = 0, eligibility = 0, completions = 0
    private var nextSave: CaptureConsentGate?
    func holdSave(_ gate: CaptureConsentGate) { nextSave = gate }
    func report() -> SignupCompositionFlowReport { .init(saves: saves, eligibility: eligibility, completions: completions) }
    nonisolated static var choice: OnboardingEligibilityDecision {
        .init(decision: .choice, basis: .bodyFat, objective: nil, notice: nil,
            options: [BodyFlowObjective.bodyRecomposition, .muscleGain, .maintenance].map {
                .init(objective: $0, status: .available, reasons: [], message: [])
            })
    }
    func scoped(for userID: String) async throws -> any OnboardingRepository { self }
    func loadDraft(for userID: String) async throws -> OnboardingDraft? { throw OnboardingRepositoryError.serviceUnavailable }
    func loadState(for userID: String) async throws -> OnboardingServerState { throw OnboardingRepositoryError.serviceUnavailable }
    func loadBodyPhotoCleanupScope(generation: String?) async throws -> OnboardingBodyPhotoCleanupScope? { throw OnboardingRepositoryError.serviceUnavailable }
    func saveDraft(_ draft: OnboardingDraft, for userID: String) async throws {
        saves += 1
        let gate = nextSave; nextSave = nil
        await gate?.enter()
    }
    func checkEligibility(_ input: OnboardingEligibilityInput, for userID: String,
        idempotencyKey: IdempotencyKey) async throws -> OnboardingEligibilityDecision {
        eligibility += 1
        return try Self.choice.validated()
    }
    func complete(_ draft: OnboardingDraft, for userID: String) async throws {
        completions += 1; throw OnboardingRepositoryError.serviceUnavailable
    }
    func completeOfficial(_ draft: OnboardingDraft, for userID: String,
        idempotencyKey: IdempotencyKey) async throws -> OnboardingCompletionAcknowledgement {
        completions += 1; throw OnboardingRepositoryError.serviceUnavailable
    }
    func clear(for userID: String) async throws { throw OnboardingRepositoryError.serviceUnavailable }
    func keepDraftOnDevice(_ draft: OnboardingDraft, for userID: String) async {}
}

struct SignupCompositionUploader: StorageUploading {
    let peer: PresentationPhotoPeer
    let gate: CaptureConsentGate
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        try await peer.upload(media, with: ticket)
        await gate.enter()
    }
}

@MainActor
struct SignupDeleteCompositionHarness {
    let cleanup: CleanupProcessorHarness
    let base: CaptureServerPeer
    let photoBase: PresentationPhotoPeer
    let photos: SignupCompositionPhotos
    let filePeer: SignupCompositionCleanup
    let factory: PresentationFactoryPeer
    let scope: SignupBodyPhotoCaptureScope
    let flowPeer: SignupCompositionOnboardingPeer
    let flow: OnboardingFlowModel
    let model: SignupBodyPhotoPresentationModel
    let owner: OnboardingOwnerToken
    let ownerBox: PresentationOwnerBox
    let clock: CapturePollingClock
    let staging: MediaStagingStore
    let putGate: CaptureConsentGate

    init(step: OnboardingStep = .bodyData, recovery: SignupCompositionRecovery? = nil,
        holdPUT: Bool = false, readingAfterDelete: Bool = false) async throws {
        let cleanup = try await CleanupProcessorHarness()
        let staging = MediaStagingStore(temporaryDirectory: cleanup.folder.appendingPathComponent("composition-staging"))
        let base = CaptureServerPeer(staging: staging, consentGate: CaptureConsentGate(),
            failOnceAt: recovery == .cleanup ? .create : nil)
        let photoBase = PresentationPhotoPeer(base: base, hasEstimate: true)
        let photos = SignupCompositionPhotos(base: photoBase, loseReply: recovery == .deleteReply,
            failReload: recovery == .reload, readingAfterDelete: readingAfterDelete)
        let filePeer = SignupCompositionCleanup(failOnce: recovery == .cleanup)
        let lifecycle = cleanup.lifecycle, lease = cleanup.lease, store = cleanup.store
        let clock = CapturePollingClock(), put = CaptureConsentGate(holds: holdPUT)
        let scope = SignupBodyPhotoCaptureScope(userID: lease.userID, photos: photos,
            uploader: SignupCompositionUploader(peer: photoBase, gate: put), staging: staging, camera: .unavailable,
            validateSession: { try Task.checkCancellation(); try await lifecycle.validate(lease) },
            stagePhoto: { data, channel in
                try await lifecycle.validate(lease)
                let media = try await base.stage(data, channel: channel)
                try await lifecycle.validate(lease)
                return media
            }, performWork: { operation in
                await clock.workStarted()
                do { try await SignupSessionBoundWork(lifecycle: lifecycle, lease: lease).run(operation) }
                catch { await clock.workEnded(); throw error }
                await clock.workEnded()
            }, discardStaged: { file in
                let task = Task {
                    try await filePeer.beforeRemove(file)
                    try await lifecycle.performPatientStateOperation(lease: lease) { staging.remove(file) }
                }
                try await task.value
            }, rememberUnboundCreate: { id in
                try await lifecycle.performPatientStateOperation(lease: lease) {
                    try store.mutate(for: lease.userID) { current in _ = current.rememberUnbound(id) }
                }
            })
        let owner = OnboardingOwnerToken(userID: lease.userID, restoreGeneration: 1)
        let ownerBox = PresentationOwnerBox(owner), flowPeer = SignupCompositionOnboardingPeer()
        let flow = Self.makeFlow(owner: owner, peer: flowPeer, step: step)
        let factory = PresentationFactoryPeer(scope: scope)
        let model = Self.makeModel(flow: flow, owner: owner, box: ownerBox,
            factory: factory, clock: clock, prefix: "composition-one")
        self.cleanup = cleanup; self.staging = staging; self.base = base; self.photoBase = photoBase
        self.photos = photos; self.filePeer = filePeer; self.scope = scope; self.clock = clock
        self.flowPeer = flowPeer; self.flow = flow; self.factory = factory; self.model = model
        self.owner = owner; self.ownerBox = ownerBox; self.putGate = put
    }
    static func makeFlow(owner: OnboardingOwnerToken, peer: SignupCompositionOnboardingPeer,
        step: OnboardingStep) -> OnboardingFlowModel {
        var draft = BodyFlowTestFixtures.onboardingDraft(currentStep: step)
        draft.localeIdentifier = "pt-BR"; draft.timeZoneIdentifier = "America/Sao_Paulo"
        draft.birthDate = OnboardingCivilDate.date(from: "1990-01-02", timeZoneIdentifier: draft.timeZoneIdentifier)
        draft.biologicalSex = .masculine; draft.bodyFatPercent = 24; draft.bodyFatOrigin = .typed
        draft.bodyPhotoConfirmation = nil
        let flow = OnboardingFlowModel(userID: owner.userID, initialDraft: draft,
            repository: peer, personaRepository: PresentationPersona(),
            developmentConsentAvailability: .syntheticDevelopment,
            onStepChanged: { _ in }, onCompleted: {}, now: { PresentationHarness.now })
        if step == .completion {
            flow.installDecisionForPreview(SignupCompositionOnboardingPeer.choice, requestedStep: .completion)
        }
        return flow
    }
    static func makeModel(flow: OnboardingFlowModel, owner: OnboardingOwnerToken, box: PresentationOwnerBox,
        factory: PresentationFactoryPeer, clock: CapturePollingClock, prefix: String) -> SignupBodyPhotoPresentationModel {
        .init(flow: flow, ownerToken: owner, capability: factory.capability,
            timeProvider: PresentationFixedTime(now: PresentationHarness.now),
            keyProvider: DeterministicIdempotencyKeyProvider(prefix: prefix),
            pollingTiming: .init(elapsed: { await clock.elapsed() }, sleep: { try await clock.sleep($0) }),
            isCurrentOwner: { $0 == box.current })
    }
    func prepare() async throws {
        await model.load()
        let capture = try #require(model.capture, "Prerequisite: U1 real implementation, not composition RED")
        model.select(.photos)
        await model.acceptConsent()
        try #require(capture.hasAcceptedConsent, "Prerequisite: U1/U2 consent implementation must be GREEN")
    }
    func begin(retry: Bool = false, ending gates: [CaptureConsentGate] = []) -> Task<Void, Never> {
        Task {
            if retry { await model.retryDeletion() } else { await model.deletePhotos() }
            for gate in gates { await gate.operationFinished() }
        }
    }
    func drain() async throws {
        model.invalidate()
        await putGate.release()
        if let capture = model.capture {
            await capture.invalidateAndWaitForOwnedCaptureWork()
            try await capture.waitForLocalCleanup()
        }
    }
    func removeFolder() {
        // Failed #require/semantic RED also invalidates the retained D1,
        // including a private replacement that was not adopted by the facade.
        model.invalidate()
        model.deletion?.invalidate()
        cleanup.removeFolder()
    }
}
#endif
