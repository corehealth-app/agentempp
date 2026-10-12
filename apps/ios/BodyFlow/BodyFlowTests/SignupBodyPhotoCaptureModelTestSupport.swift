#if DEBUG
import Foundation
import Testing
@testable import BodyFlow

// Local model peers only. No real transport/provider or signed Storage URL.
enum CaptureConsentScenario: String, CaseIterable, Equatable, Sendable { case awaitingChoice, declined, unavailable }
enum CaptureFailurePoint: String, CaseIterable, Equatable, Sendable { case consent, create, complete }
enum CaptureReplayScript: Sendable { case none, stored, pendingWithoutTicket }
enum CaptureCallStep: Equatable, Sendable { case state, consent, stage, create, put, complete, delete, repair }
enum CaptureCall: Equatable, Sendable {
    case state
    case consent(MutationAttempt<SignupBodyPhotoConsentRequest>)
    case stage(Int, MealSourceChannel)
    case create(MutationAttempt<SignupBodyPhotoCreateRequest>)
    case put(Int)
    case complete(MutationAttempt<MediaAssetCommand>)
    case delete(MutationAttempt<SignupBodyPhotoDeleteCommand>)
    case repair(MutationAttempt<SignupBodyPhotoRepairCommand>)

    var step: CaptureCallStep {
        switch self {
        case .state: .state
        case .consent: .consent
        case .stage: .stage
        case .create: .create
        case .put: .put
        case .complete: .complete
        case .delete: .delete
        case .repair: .repair
        }
    }
}

struct CapturePeerSnapshot: Sendable {
    let calls: [CaptureCall]
    var consents: [MutationAttempt<SignupBodyPhotoConsentRequest>] {
        calls.compactMap { if case let .consent(a) = $0 { a } else { nil } }
    }
    var creates: [MutationAttempt<SignupBodyPhotoCreateRequest>] {
        calls.compactMap { if case let .create(a) = $0 { a } else { nil } }
    }
    var completes: [MutationAttempt<MediaAssetCommand>] {
        calls.compactMap { if case let .complete(a) = $0 { a } else { nil } }
    }
    var mutationAndStageSteps: [CaptureCallStep] { calls.map(\.step).filter { $0 != .state } }
    func count(_ step: CaptureCallStep) -> Int { calls.filter { $0.step == step }.count }
}

/// Explicit barrier also signals an inert scaffold returning before entry.
/// Tests therefore fail by assertion instead of hanging waiting for a call.
actor CaptureConsentGate {
    private let holds: Bool
    private var entered = false
    private var operationEnded = false
    private var released = false
    private var observers: [CheckedContinuation<Bool, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(holds: Bool = false) { self.holds = holds }
    func enter() async {
        entered = true
        let ready = observers; observers.removeAll()
        for observer in ready { observer.resume(returning: true) }
        if holds && !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func operationFinished() {
        operationEnded = true
        guard !entered else { return }
        let ready = observers; observers.removeAll()
        for observer in ready { observer.resume(returning: false) }
    }
    func entryOrOperationEnd() async -> Bool {
        if entered { return true }
        if operationEnded { return false }
        return await withCheckedContinuation { observers.append($0) }
    }
    func release() {
        released = true
        let ready = waiters; waiters.removeAll()
        for waiter in ready { waiter.resume() }
    }
}

actor CaptureCleanupPeer {
    let gate: CaptureConsentGate
    private var failOnce: Bool
    private(set) var calls = 0
    init(gate: CaptureConsentGate, failOnce: Bool) { self.gate = gate; self.failOnce = failOnce }
    func discard(_ file: URL, staging: MediaStagingStore) async throws {
        calls += 1
        await gate.enter()
        if failOnce { failOnce = false; throw SignupBodyPhotoFailure.unavailable }
        staging.remove(file)
    }
}

// Same lock discipline as existing DeterministicIdempotencyKeyProvider.
// Advancing time makes accidental reconstruction of createdAt detectable.
final class CaptureAttemptTime: @unchecked Sendable, TimeProviding {
    private let lock = NSLock()
    private var tick = 0
    var now: Date {
        lock.withLock {
            defer { tick += 1 }
            return Date(timeIntervalSince1970: 1_790_000_000 + Double(tick))
        }
    }
}

actor CaptureServerPeer: SignupBodyPhotosProviding, StorageUploading {
    let consentGate: CaptureConsentGate
    let stageGate: CaptureConsentGate?
    let stateGate: CaptureConsentGate?
    private let cooperativeStage: Bool
    private let staging: MediaStagingStore
    private let available: Bool
    private let replay: CaptureReplayScript
    private var failOnceAt: CaptureFailurePoint?
    private var readingFailsOnce: Bool
    private var accepted = false
    private var acceptedVersion: String?
    private var documentVersion = "test-v1"
    private var shouldHoldNextState = false
    private var failNextState = false
    private var failStateAfterComplete = false
    private var calls: [CaptureCall] = []
    private var byKey: [String: SignupBodyPhotoOperationPhoto] = [:]
    private var byPose: [SignupBodyPhotoPose: SignupBodyPhotoOperationPhoto] = [:]
    private var nextID = 101
    private let timestamp = APITimestamp(value: Date(timeIntervalSince1970: 1_790_000_000))

    init(staging: MediaStagingStore, consentGate: CaptureConsentGate, available: Bool = true,
         failOnceAt: CaptureFailurePoint? = nil, replay: CaptureReplayScript = .none,
         readingFailsOnce: Bool = false, otherPosesPresent: Bool = false,
         stageGate: CaptureConsentGate? = nil, stateGate: CaptureConsentGate? = nil,
         failStateAfterComplete: Bool = false, cooperativeStage: Bool = false) {
        self.staging = staging; self.consentGate = consentGate; self.available = available
        self.stageGate = stageGate; self.stateGate = stateGate
        self.failStateAfterComplete = failStateAfterComplete
        self.cooperativeStage = cooperativeStage
        self.failOnceAt = failOnceAt; self.replay = replay; self.readingFailsOnce = readingFailsOnce
        if otherPosesPresent {
            byPose[.side] = SignupBodyPhotoOperationPhoto(id: "00000000-0000-4000-8000-000000910002", pose: .side, status: "read", createdAt: timestamp)
            byPose[.back] = SignupBodyPhotoOperationPhoto(id: "00000000-0000-4000-8000-000000910003", pose: .back, status: "read", createdAt: timestamp)
        }
    }
    func snapshot() -> CapturePeerSnapshot { CapturePeerSnapshot(calls: calls) }
    func changeDocument() { documentVersion = "test-v2" }
    func holdNextState(fail: Bool = false) { shouldHoldNextState = true; failNextState = fail }
    func state() async throws -> SignupBodyPhotoState {
        calls.append(.state)
        let shouldFail = failNextState
        failNextState = false
        let result = SignupBodyPhotoState(available: available, unavailableReason: available ? nil : "disabled",
            consent: available ? SignupBodyPhotoConsent(documentKey: "body_photo_estimate_consent", version: documentVersion, locale: "pt-BR", body: "Synthetic model consent only", bodyHash: String(repeating: documentVersion == "test-v1" ? "a" : "b", count: 64), acceptedAt: accepted && acceptedVersion == documentVersion ? timestamp : nil) : nil,
            minimumAge: 18,
            poses: SignupBodyPhotoPose.allCases.map { pose in SignupBodyPhotoSlot(pose: pose, photo: byPose[pose].map { SignupBodyPhoto(id: $0.id, status: $0.status, createdAt: $0.createdAt) }) },
            estimate: nil, remainingUploads: available ? 9 : 0)
        if shouldHoldNextState {
            shouldHoldNextState = false
            await stateGate?.enter()
        }
        if shouldFail { throw SignupBodyPhotoFailure.offline }
        return result
    }
    func consent(_ attempt: MutationAttempt<SignupBodyPhotoConsentRequest>) async throws -> SignupBodyPhotoConsentReceipt {
        calls.append(.consent(attempt))
        await consentGate.enter()
        accepted = true
        acceptedVersion = attempt.payload.version
        try failAfterApply(.consent)
        return SignupBodyPhotoConsentReceipt(documentKey: "body_photo_estimate_consent", version: attempt.payload.version, acceptedAt: timestamp)
    }
    func stage(_ data: Data, channel: MealSourceChannel) async throws -> StagedMedia {
        calls.append(.stage(data.count, channel))
        // Deliberately returns a late file even when its caller was cancelled.
        await stageGate?.enter()
        if cooperativeStage { try Task.checkCancellation() }
        let url = try staging.stage(data, fileExtension: "jpg")
        return StagedMedia(fileURL: url, kind: .signupBodyPhoto, mimeType: "image/jpeg", sizeBytes: data.count, duration: nil, channel: channel)
    }
    func create(_ attempt: MutationAttempt<SignupBodyPhotoCreateRequest>) async throws -> SignupBodyPhotoCreateReceipt {
        calls.append(.create(attempt))
        let wasKnown = byKey[attempt.key.value] != nil
        let created: SignupBodyPhotoOperationPhoto
        if let prior = byKey[attempt.key.value] { created = prior }
        else {
            let id = String(format: "00000000-0000-4000-8000-%012d", nextID); nextID += 1
            let status: String
            switch replay { case .none, .pendingWithoutTicket: status = "pending_upload"; case .stored: status = "read" }
            created = SignupBodyPhotoOperationPhoto(id: id, pose: attempt.payload.pose, status: status, createdAt: timestamp)
            byKey[attempt.key.value] = created; byPose[attempt.payload.pose] = created
        }
        try failAfterApply(.create)
        let ticket: MediaUploadTicket?
        switch replay {
        case .none: ticket = MediaUploadTicket(signedURL: "synthetic-unused", method: "PUT", headers: ["Content-Type": "image/jpeg"], expiresAt: APITimestamp(value: .distantFuture))
        case .stored, .pendingWithoutTicket: ticket = nil
        }
        return SignupBodyPhotoCreateReceipt(photo: created, upload: ticket, replayed: wasKnown || ticket == nil)
    }
    func upload(_ media: StagedMedia, with ticket: MediaUploadTicket) async throws {
        calls.append(.put(media.sizeBytes))
        guard media.kind == .signupBodyPhoto, media.mimeType == "image/jpeg",
              FileManager.default.fileExists(atPath: media.fileURL.path)
        else { throw SignupBodyPhotoFailure.invalidInput }
    }
    func complete(_ attempt: MutationAttempt<MediaAssetCommand>) async throws -> SignupBodyPhotoCompleteReceipt {
        calls.append(.complete(attempt))
        guard let current = byPose.values.first(where: { $0.id == attempt.payload.assetID }) else { throw SignupBodyPhotoFailure.invalidInput }
        let status = readingFailsOnce ? "reading_failed" : "read"
        readingFailsOnce = false
        let photo = SignupBodyPhotoOperationPhoto(id: current.id, pose: current.pose, status: status, createdAt: current.createdAt)
        byPose[current.pose] = photo
        try failAfterApply(.complete)
        if failStateAfterComplete { failStateAfterComplete = false; failNextState = true }
        return SignupBodyPhotoCompleteReceipt(photo: photo)
    }
    func delete(_ attempt: MutationAttempt<SignupBodyPhotoDeleteCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        calls.append(.delete(attempt)); throw SignupBodyPhotoFailure.unavailable
    }
    func repair(_ attempt: MutationAttempt<SignupBodyPhotoRepairCommand>) async throws -> SignupBodyPhotoDeleteReceipt {
        calls.append(.repair(attempt)); throw SignupBodyPhotoFailure.unavailable
    }
    private func failAfterApply(_ point: CaptureFailurePoint) throws {
        guard failOnceAt == point else { return }
        failOnceAt = nil
        throw SignupBodyPhotoFailure.offline
    }
}

@MainActor
struct CaptureModelHarness {
    static let owner = "00000000-0000-4000-8000-000000c70101"
    static let data = Data([0xff, 0xd8, 0xff, 0xd9]) // scripted staged bytes, not normalizer proof
    let model: SignupBodyPhotoCaptureModel
    let peer: CaptureServerPeer
    let gate: CaptureConsentGate
    let stageGate: CaptureConsentGate
    let stateGate: CaptureConsentGate
    let cleanupGate: CaptureConsentGate
    let cleanupPeer: CaptureCleanupPeer
    let staging: MediaStagingStore
    let base: URL

    init(available: Bool = true, failOnceAt: CaptureFailurePoint? = nil, replay: CaptureReplayScript = .none,
         holdConsent: Bool = false, readingFailsOnce: Bool = false, otherPosesPresent: Bool = false,
         holdStage: Bool = false, holdCleanup: Bool = false, failCleanupOnce: Bool = false,
         failStateAfterComplete: Bool = false, cooperativeStage: Bool = false) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("signup-model-\(UUID().uuidString)", isDirectory: true)
        let staging = MediaStagingStore(temporaryDirectory: base)
        let gate = CaptureConsentGate(holds: holdConsent)
        let stageGate = CaptureConsentGate(holds: holdStage)
        let stateGate = CaptureConsentGate(holds: true)
        let cleanupGate = CaptureConsentGate(holds: holdCleanup)
        let cleanupPeer = CaptureCleanupPeer(gate: cleanupGate, failOnce: failCleanupOnce)
        let peer = CaptureServerPeer(staging: staging, consentGate: gate, available: available, failOnceAt: failOnceAt, replay: replay, readingFailsOnce: readingFailsOnce, otherPosesPresent: otherPosesPresent, stageGate: stageGate, stateGate: stateGate, failStateAfterComplete: failStateAfterComplete, cooperativeStage: cooperativeStage)
        let ownerToken = OnboardingOwnerToken(userID: Self.owner, restoreGeneration: 1)
        let scope = SignupBodyPhotoCaptureScope(userID: Self.owner, photos: peer, uploader: peer, staging: staging, camera: .unavailable,
            validateSession: { try Task.checkCancellation() },
            stagePhoto: { data, channel in try await peer.stage(data, channel: channel) },
            performWork: { operation in try await operation() },
            discardStaged: { url in try await cleanupPeer.discard(url, staging: staging) })
        self.base = base; self.staging = staging; self.peer = peer; self.gate = gate
        self.stageGate = stageGate; self.stateGate = stateGate
        self.cleanupGate = cleanupGate; self.cleanupPeer = cleanupPeer
        self.model = SignupBodyPhotoCaptureModel(scope: scope, ownerToken: ownerToken,
            timeProvider: CaptureAttemptTime(), keyProvider: DeterministicIdempotencyKeyProvider(prefix: "signup-model-key"),
            isCurrentOwner: { $0 == ownerToken })
    }
    func clean() { try? FileManager.default.removeItem(at: base) }
}
#endif
